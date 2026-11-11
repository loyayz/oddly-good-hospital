extends RefCounted

# Diagnostic state lives in this helper only. Geometry uses a separate space
# instance and raw room cells; no move, quote, reservation or random draw runs.
static var _geometry: HospitalSpace
static var _output: String=""
static var _stream: FileAccess
static var _seen: Dictionary={}
static var _decrements: Dictionary={}
static var _terminal_clears: Dictionary={}
static var _first_error: Dictionary={}
static var _hook_us: int=0
static var _observer_capture_us: int=0

static func _begin(content: HospitalContent) -> void:
	if _geometry==null: _geometry=HospitalSpace.new(content)
	if _stream!=null: return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): _output=argument.trim_prefix("--output=")
	var path: String=_output+".visitor-branches.ndjson"
	if _output.is_empty() or FileAccess.file_exists(path): push_error("Expected a new visitor diagnostic output");return
	_stream=FileAccess.open(path,FileAccess.WRITE)
	if _stream==null: push_error("Cannot open visitor diagnostic output")

static func _write(path: String, record: Dictionary) -> void:
	if FileAccess.file_exists(path): push_error("Preserve existing visitor diagnostic: "+path);return
	var file: FileAccess=FileAccess.open(path,FileAccess.WRITE)
	if file==null: push_error("Cannot write visitor diagnostic: "+path);return
	file.store_string(JSON.stringify(record,"\t"));file.close()

static func _rect(actor: Dictionary) -> Array:
	if actor.get("location",{}).get("kind","")!="floor": return []
	var rect: Rect2=_geometry.body_rectangle(actor)
	return [rect.position.x,rect.position.y,rect.size.x,rect.size.y]

static func _contains(world: WorldState, actor_id: String, room: Dictionary) -> bool:
	var actor: Dictionary=world.facts.actors.get(actor_id,{})
	if actor.get("location",{}).get("kind","")!="floor" or int(actor.location.floor_id)!=int(room.get("floor_id",-1)): return false
	var rect: Rect2=_geometry.body_rectangle(actor)
	if not room.has("cells"):
		return Rect2(float(room.origin[0]),float(room.origin[1]),float(room.size[0]),float(room.size[1])).encloses(rect)
	for x: int in range(floori(rect.position.x),ceili(rect.end.x)):
		for y: int in range(floori(rect.position.y),ceili(rect.end.y)):
			if not [x,y] in room.cells: return false
	return true

static func _context(world: WorldState, family: Dictionary, ward: Dictionary, visit: Dictionary) -> Dictionary:
	var bed: Dictionary=world.facts.facilities.get(str(ward.get("bed_id","")),{})
	var room: Dictionary=world.facts.rooms.get(str(bed.get("room_id","")),{})
	var medical: Array=[]
	var sessions: Dictionary={}
	var actor_ids: Dictionary={}
	for actor_id: String in [str(family.get("actor_id","")),str(visit.get("actor_id","")),str(ward.get("nurse_id","")),str(ward.get("escort_id",""))]:
		if world.facts.actors.has(actor_id): actor_ids[actor_id]=true
	for id: String in world.facts.sessions:
		var session: Dictionary=world.facts.sessions[id]
		if session.get("visit_id","")!=family.get("visit_id",""): continue
		sessions[id]=session.duplicate(true)
		for actor_id: String in session.get("staff_ids",[]): actor_ids[actor_id]=true
		var facility: Dictionary=world.facts.facilities.get(str(session.get("facility_id","")),{})
		if session.kind in ["care","outpatient"] and int(facility.get("floor_id",-1))==int(bed.get("floor_id",-2)) and facility.get("room_id","")==bed.get("room_id",""): medical.append(id)
	var yields: Dictionary={}
	var active_yields: Array=[]
	for id: String in world.facts.visitors.stays:
		var other: Dictionary=world.facts.visitors.stays[id]
		if other.visit_id!=family.get("visit_id",""): continue
		yields[id]={"yielding":other.get("yielding",false),"yield_requested_tick":other.get("yield_requested_tick",-2),"phase":other.phase,"purpose":other.purpose}
		if other.get("yielding",false) and int(other.get("yield_requested_tick",-2))>=world.sim_tick-1: active_yields.append(id)
	var actors: Dictionary={}
	var movements: Dictionary={}
	for actor_id: String in actor_ids:
		var actor: Dictionary=world.facts.actors.get(actor_id,{})
		if actor.is_empty(): continue
		actors[actor_id]={"actor":actor.duplicate(true),"body_dimensions":_geometry.body(actor).duplicate(true),"body_rectangle_cells":_rect(actor)}
		if world.facts.moves.has(actor_id): movements[actor_id]=world.facts.moves[actor_id].duplicate(true)
	var family_inside: bool=not room.is_empty() and _contains(world,str(family.get("actor_id","")),room)
	var patient_inside: bool=not room.is_empty() and _contains(world,str(visit.get("actor_id","")),room)
	var terminal: bool=ward.is_empty() or visit.get("phase","") in ["leaving","departed","ward_referral"]
	var away: bool=ward.get("phase","") in ["to_surgery","reserved","transfer","return_preop"]
	return {"tick":world.sim_tick,"family":family.duplicate(true),"ward":ward.duplicate(true),"visit":visit.duplicate(true),"bed":bed.duplicate(true),"room":room.duplicate(true),"actors":actors,"moves":movements,"sessions":sessions,"yield_facts":yields,"independent_conditions":{"terminal":terminal,"away_phase":away,"family_inside_ward":family_inside,"patient_inside_ward":patient_inside,"medical_sessions":medical,"active_yield_requests":active_yields,"life_task_empty":family.get("life_task",{}).is_empty(),"legal_effective_tick":not terminal and not away and family_inside and patient_inside and medical.is_empty() and active_yields.is_empty() and not family.get("yielding",false) and family.purpose=="ward_visit" and not family.phase in ["outside","leaving"] and family.get("life_task",{}).is_empty()}}

static func capture(world: WorldState, content: HospitalContent) -> Dictionary:
	var started: int=Time.get_ticks_usec()
	_begin(content)
	var result: Dictionary={"tick":world.sim_tick,"families":{}}
	for id: String in world.facts.visitors.stays:
		var family: Dictionary=world.facts.visitors.stays[id]
		_seen[id]=true
		var ward: Dictionary={}
		for candidate: Dictionary in world.facts.ward_stays.values():
			if candidate.get("visit_id","")==family.visit_id: ward=candidate;break
		result.families[id]=_context(world,family,ward,world.facts.visits[family.visit_id])
	_observer_capture_us+=Time.get_ticks_usec()-started
	return result

static func _branch(kind: String, world: WorldState, family: Dictionary, ward: Dictionary, visit: Dictionary, content: HospitalContent) -> void:
	var started: int=Time.get_ticks_usec()
	_begin(content)
	_seen[family.id]=true
	var record: Dictionary={"kind":kind,"tick":world.sim_tick,"stay_id":family.id,"remaining_before":int(family.remaining_ticks),"context":_context(world,family,ward,visit)}
	if _stream!=null: _stream.store_line(JSON.stringify(record));_stream.flush()
	_hook_us+=Time.get_ticks_usec()-started

static func before_decrement(world: WorldState, family: Dictionary, ward: Dictionary, visit: Dictionary, content: HospitalContent) -> void:
	var actual: bool=int(family.remaining_ticks)>0
	if actual: _decrements[family.id]=int(_decrements.get(family.id,0))+1
	_branch("actual_effective_decrement" if actual else "zero_remaining_branch",world,family,ward,visit,content)

static func before_terminal_clear(world: WorldState, family: Dictionary, ward: Dictionary, visit: Dictionary, content: HospitalContent) -> void:
	if family.purpose!="ward_visit" or int(family.remaining_ticks)<=0: return
	_terminal_clears[family.id]=int(_terminal_clears.get(family.id,0))+1
	_branch("terminal_remaining_clear",world,family,ward,visit,content)

static func observer_failure(world: WorldState, id: String, before: Dictionary, after: Dictionary, content: HospitalContent) -> void:
	if not _first_error.is_empty(): return
	_begin(content)
	_first_error={"stay_id":id,"before_tick":before.tick,"after_tick":after.tick,"old_family":before.families.get(id,{}).duplicate(true),"new_family":after.families.get(id,{}).duplicate(true),"before_context":before.get("clinical_diagnostic",{}).get("families",{}).get(id,{}).duplicate(true),"after_context":after.get("clinical_diagnostic",{}).get("families",{}).get(id,{}).duplicate(true),"actual_decrements_seen_for_stay":int(_decrements.get(id,0)),"terminal_clears_seen_for_stay":int(_terminal_clears.get(id,0)),"source":"Original effective-visit observer predicate, unchanged"}
	_write(_output+".visitor-first-error.json",_first_error)

static func finish(world: WorldState, content: HospitalContent) -> void:
	_begin(content)
	if _stream!=null: _stream.flush();_stream.close()
	_write(_output+".visitor-summary.json",{"final_tick":world.sim_tick,"seen_stays":_seen.keys(),"actual_effective_decrements":_decrements,"terminal_remaining_clears":_terminal_clears,"first_observer_error":_first_error,"in_step_hook_elapsed_us":_hook_us,"outside_step_context_capture_us":_observer_capture_us,"scope":"Read-only branch and geometry diagnosis. In-step hook time perturbs clinic phase spans; it is reported separately. Diagnostic whole-step timings are not performance qualification."})
