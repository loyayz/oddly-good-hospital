extends RefCounted

# Diagnostics keep their own derived data. They never write hospital facts or
# consult a route, fit, occupancy cache, quote, reservation or random stream.
static var _active: bool = false
static var _species: Dictionary = {}
static var _bindings: Dictionary = {}
static var _shapes: Dictionary = {}
static var _events: Array = []
static var _phases: Dictionary = {}
static var _motion: Dictionary = {}
static var _cancel_sites: Dictionary = {}
static var _attempts: Dictionary = {}
static var _counts: Dictionary = {}
static var _costs: Dictionary = {}
static var _errors: Array = []
static var _sequence_boundary: Dictionary = {}
static var _boundary_before: Dictionary = {}
static var _started_tick: int = -1
static var _movement_steps: int = 0

static func prepare(world: WorldState, content: HospitalContent) -> void:
	var start: int=Time.get_ticks_usec()
	_active=true
	_species={}; _bindings={}; _shapes={}; _events=[]; _phases={}; _motion={}; _cancel_sites={}; _attempts={}; _counts={}; _costs={}; _errors=[]; _sequence_boundary={}; _boundary_before={}
	_started_tick=world.sim_tick; _movement_steps=0
	for row: Dictionary in content.catalog.species: _species[str(row.id)]=row
	for row: Dictionary in content.catalog.treatment_bindings: _bindings[str(row.id)]=row
	for id: String in world.facts.connectors:
		_phases[id]={"phase":world.facts.connectors[id].phase,"entered_tick":-1,"observed_from_tick":world.sim_tick}
	for id: String in world.facts.actors: _motion[id]=_new_motion(world.sim_tick)
	_record(world,"trace_initialized",{"existing_phase_entry_times_known":false})
	_cost("prepare_outside_steps",start)

static func _new_motion(tick: int) -> Dictionary:
	return {"observed_from_tick":tick,"last_actual_floor_displacement_tick":-1,"last_location_change_tick":-1,"floor_displacement_steps":0,"last_floor_displacement":{}}

static func _cost(name: String, started: int) -> void:
	var elapsed: int=Time.get_ticks_usec()-started
	var row: Dictionary=_costs.get_or_add(name,{"calls":0,"inclusive_us":0,"max_us":0})
	row.calls+=1; row.inclusive_us+=elapsed; row.max_us=maxi(int(row.max_us),elapsed)

static func _record(world: WorldState, kind: String, details: Dictionary) -> void:
	_events.append({"tick":world.sim_tick,"kind":kind,"details":details})
	_counts[kind]=int(_counts.get(kind,0))+1

static func _connection(connection: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for key: String in ["id","phase","floor_id","from","to","remaining_ticks","trip_sequence","ticket_next","primary_actor_id","riders","assigned_actor_id","anchor","failed","pending_failure"]:
		if connection.has(key): result[key]=connection[key].duplicate(true) if connection[key] is Array or connection[key] is Dictionary else connection[key]
	return result

static func _actor(world: WorldState, id: String) -> Dictionary:
	var actor: Dictionary=world.facts.actors.get(id,{})
	if actor.is_empty(): return {"id":id,"present":false,"motion":_motion.get(id,{}).duplicate(true)}
	var movement: Dictionary=world.facts.moves.get(id,{})
	var result: Dictionary={"id":id,"present":true,"location":actor.get("location",{}).duplicate(true),"posture":actor.get("posture","standing"),"facing":actor.get("facing",0.0),"species_id":actor.get("species_id",""),"body_binding_id":actor.get("body_binding_id",""),"service_role":actor.get("service_role",""),"staff_role":world.facts.staff.get(id,{}).get("role",""),"motion":_motion.get(id,{}).duplicate(true)}
	var trip: Dictionary={}
	for key: String in ["request_sequence","cursor","route_pending","target_floor","target_cell","local_move","route_waypoint","transit_ticket","replan_after_transit","waiting_reason","owner_job_id","members"]:
		if movement.has(key): trip[key]=movement[key].duplicate(true) if movement[key] is Array or movement[key] is Dictionary else movement[key]
	if movement.has("path") and int(movement.get("cursor",0))<movement.path.size(): trip.segment=movement.path[int(movement.cursor)].duplicate(true)
	result.move=trip
	return result

static func phase_entered(world: WorldState, connection: Dictionary, source: String) -> void:
	if not _active: return
	var start: int=Time.get_ticks_usec()
	var id: String=str(connection.id)
	var prior: Dictionary=_phases.get(id,{})
	var details: Dictionary={"connector_id":id,"phase":connection.phase,"source":source,"previous_phase":prior.get("phase",""),"previous_entered_tick":prior.get("entered_tick",-1),"previous_duration_ticks":world.sim_tick-int(prior.entered_tick) if int(prior.get("entered_tick",-1))>=0 else -1}
	_phases[id]={"phase":connection.phase,"entered_tick":world.sim_tick,"observed_from_tick":world.sim_tick}
	_record(world,"phase_entered",details)
	_cost("phase_entered",start)

static func before_movement(world: WorldState) -> Dictionary:
	if not _active: return {}
	var start: int=Time.get_ticks_usec()
	var locations: Dictionary={}
	for id: String in world.facts.actors: locations[id]=world.facts.actors[id].location.duplicate(true)
	_cost("before_movement",start)
	return locations

static func after_movement(world: WorldState, before: Dictionary) -> void:
	if not _active: return
	var start: int=Time.get_ticks_usec()
	_movement_steps+=1
	for id: String in world.facts.actors:
		var now: Dictionary=world.facts.actors[id].location
		var prior: Dictionary=before.get(id,{})
		var state: Dictionary=_motion.get_or_add(id,_new_motion(world.sim_tick))
		if prior.is_empty(): continue
		if prior!=now: state.last_location_change_tick=world.sim_tick
		if prior.get("kind","")=="floor" and now.get("kind","")=="floor" and prior.get("floor_id") == now.get("floor_id") and prior.get("cell")!=now.get("cell"):
			state.last_actual_floor_displacement_tick=world.sim_tick
			state.floor_displacement_steps+=1
			state.last_floor_displacement={"tick":world.sim_tick,"from":prior.duplicate(true),"to":now.duplicate(true)}
	_cost("after_movement",start)

static func ticket_created(world: WorldState, movement: Dictionary, source: String) -> void:
	if not _active: return
	var start: int=Time.get_ticks_usec()
	_record(world,"ticket_created",{"actor":_actor(world,movement.actor_id),"ticket":movement.transit_ticket.duplicate(true),"source":source})
	_cost("ticket_created",start)

static func cancel_site(world: WorldState, movement: Dictionary, source: String) -> void:
	if _active and movement.has("transit_ticket"): _cancel_sites[str(movement.actor_id)]={"tick":world.sim_tick,"source":source}

static func before_cancel(world: WorldState, movement: Dictionary) -> Dictionary:
	if not _active or not movement.has("transit_ticket"): return {}
	var start: int=Time.get_ticks_usec()
	var token: Dictionary={"actor":_actor(world,movement.actor_id),"ticket":movement.transit_ticket.duplicate(true),"existing_waiting_reason":movement.get("waiting_reason",""),"source":_cancel_sites.get(str(movement.actor_id),{}).duplicate(true)}
	_cancel_sites.erase(str(movement.actor_id))
	token.caller_frames=get_stack()
	_cost("before_cancel",start)
	return token

static func after_cancel(world: WorldState, movement: Dictionary, token: Dictionary) -> void:
	if not _active or token.is_empty(): return
	var start: int=Time.get_ticks_usec()
	token.ticket_removed=not movement.has("transit_ticket")
	_record(world,"ticket_cancelled",token)
	_cost("after_cancel",start)

static func ticket_consumed(world: WorldState, movement: Dictionary, source: String) -> void:
	if not _active: return
	var start: int=Time.get_ticks_usec()
	_record(world,"ticket_consumed_for_boarding",{"actor_id":movement.actor_id,"ticket":movement.get("transit_ticket",{}).duplicate(true),"source":source})
	_cost("ticket_consumed",start)

static func _point(cell: Array) -> Vector2:
	return Vector2(float(cell[0]),float(cell[1]))

static func _shape(actor: Dictionary) -> Dictionary:
	var key: String=JSON.stringify([actor.get("species_id",""),actor.get("body_binding_id",""),actor.get("posture","standing"),actor.get("facing",0.0)])
	if _shapes.has(key): return _shapes[key]
	var body: Dictionary=_species[str(actor.species_id)].body
	var symptom: Dictionary=_bindings.get(str(actor.get("body_binding_id","")),{}).get("symptom_envelope",{})
	var width: float=maxf(float(body.width_m),float(symptom.get("width_m",0)))
	var depth: float=maxf(float(body.depth_m),float(symptom.get("depth_m",0)))
	var height: float=maxf(float(body.height_m),float(symptom.get("height_m",0)))
	var cells: int=ceili(maxf(width,depth)/1.5)
	var facing: float=float(actor.get("facing",0.0))
	var result: Dictionary={}
	if actor.get("posture","standing")=="lying":
		var low: Vector2=Vector2(INF,INF)
		var high: Vector2=Vector2(-INF,-INF)
		for x: float in [-width*0.5,width*0.5]:
			for z: float in [-height,0.0]:
				var point: Vector2=Vector2(x*cos(facing)+z*sin(facing),-x*sin(facing)+z*cos(facing))/1.5
				low=low.min(point); high=high.max(point)
		result={"lying":true,"center":Vector2.ONE*cells*0.5,"offset":-low,"size":high-low}
	else:
		var cosine: float=absf(cos(facing)); var sine: float=absf(sin(facing))
		var dimensions: Vector2=Vector2(width,depth)/1.5
		var size: Vector2=Vector2(dimensions.x*cosine+dimensions.y*sine,dimensions.x*sine+dimensions.y*cosine)
		result={"offset":(Vector2.ONE*cells-size)*0.5,"size":size}
	_shapes[key]=result
	return result

static func _rect(actor: Dictionary, at: Vector2) -> Rect2:
	var shape: Dictionary=_shape(actor)
	if shape.get("lying",false): return Rect2(at+Vector2(shape.center)-Vector2(shape.offset),Vector2(shape.size))
	return Rect2(at+Vector2(shape.offset),Vector2(shape.size))

static func _raw_rect(rect: Rect2) -> Array:
	return [rect.position.x,rect.position.y,rect.size.x,rect.size.y]

static func _convoy_regions(world: WorldState, movement: Dictionary) -> Array[Rect2]:
	var convoy: Dictionary=movement.convoy
	var result: Array[Rect2]=[]
	var shift: Vector2=Vector2.ONE*float(convoy.shift)
	var size: Vector2=Vector2.ONE*float(convoy.size)
	var points: Array=convoy.points
	if points.size()==1: result.append(Rect2(_point(points[0])+shift,size))
	for index: int in range(1,points.size()): result.append(Rect2(_point(points[index-1])+shift,size).merge(Rect2(_point(points[index])+shift,size)))
	var actor: Dictionary=world.facts.actors[movement.actor_id]
	if actor.location.kind!="transit": return result
	var connection: Dictionary=world.facts.connectors[actor.location.connector_id]
	if connection.phase=="riding": return []
	if not convoy.has("portal"): return result
	var cabin: Rect2=Rect2(_point(connection.cell),_point(connection.footprint))
	var ground: Array[Rect2]=[]
	for region: Rect2 in result:
		var cut: Rect2=region.intersection(cabin)
		if not cut.has_area(): ground.append(region); continue
		for part: Rect2 in [Rect2(region.position,Vector2(region.size.x,cut.position.y-region.position.y)),Rect2(Vector2(region.position.x,cut.end.y),Vector2(region.size.x,region.end.y-cut.end.y)),Rect2(Vector2(region.position.x,cut.position.y),Vector2(cut.position.x-region.position.x,cut.size.y)),Rect2(Vector2(cut.end.x,cut.position.y),Vector2(region.end.x-cut.end.x,cut.size.y))]:
			if part.has_area(): ground.append(part)
	return ground

static func _body_blockers(world: WorldState, floor_id: int, targets: Array[Rect2], ignored: Array) -> Array:
	var result: Array=[]
	var convoy_members: Dictionary={}
	for movement: Dictionary in world.facts.moves.values():
		if not movement.has("convoy"): continue
		for id: String in movement.members: convoy_members[id]=true
		if movement.actor_id in ignored or int(movement.convoy.floor_id)!=floor_id: continue
		var hits: Array=[]
		for region: Rect2 in _convoy_regions(world,movement):
			for target: Rect2 in targets:
				if region.intersects(target,false): hits.append(_raw_rect(region)); break
		if not hits.is_empty(): result.append({"owner_id":movement.actor_id,"members":movement.members.duplicate(),"regions":hits,"actor":_actor(world,movement.actor_id),"geometry":"saved convoy ground envelope"})
	for id: String in world.facts.actors:
		if id in ignored or convoy_members.has(id): continue
		var actor: Dictionary=world.facts.actors[id]
		if actor.location.kind!="floor" or int(actor.location.floor_id)!=floor_id: continue
		var rectangle: Rect2=_rect(actor,_point(actor.location.cell))
		for target: Rect2 in targets:
			if rectangle.intersects(target,false):
				result.append({"owner_id":id,"members":[id],"regions":[_raw_rect(rectangle)],"actor":_actor(world,id),"geometry":"independent complete Actor body"})
				break
	return result

static func alight_attempt(world: WorldState, connection: Dictionary) -> Dictionary:
	if not _active: return {}
	var start: int=Time.get_ticks_usec()
	var members: Array=connection.riders.duplicate()
	var primary: String=str(connection.get("primary_actor_id",members[0]))
	var movement: Dictionary=world.facts.moves[primary]
	var targets: Array[Rect2]=[]
	var raw: Array=[]
	for id: String in members:
		var rectangle: Rect2=_rect(world.facts.actors[id],_point(connection.anchor)+_point(movement.get("offsets",{}).get(id,[0,0])))
		targets.append(rectangle); raw.append(_raw_rect(rectangle))
	var blockers: Array=_body_blockers(world,int(connection.to),targets,members)
	var ids: Array=[]
	for blocker: Dictionary in blockers: ids.append(blocker.owner_id)
	var attempt: Dictionary={"attempt_id":int(_counts.get("alight_attempt",0))+1,"connection":_connection(connection),"actor":_actor(world,primary),"target_regions":raw,"body_blocker_ids":ids,"body_blockers":blockers,"body_geometry_is_independent":true,"reservation_or_static_failure_inferred":false}
	_attempts[str(connection.id)]=attempt
	_record(world,"alight_attempt",attempt)
	_cost("alight_attempt_geometry",start)
	return {"attempt_id":attempt.attempt_id,"primary_actor_id":primary,"connector_id":connection.id,"riders":members}

static func alight_rejected(world: WorldState, connection: Dictionary, branch: String) -> void:
	if not _active: return
	var start: int=Time.get_ticks_usec()
	_record(world,"alight_rejected",{"connector_id":connection.id,"attempt_id":_attempts.get(str(connection.id),{}).get("attempt_id",-1),"actual_branch":branch,"connection":_connection(connection)})
	_cost("alight_rejected",start)

static func alight_finished(world: WorldState, connection: Dictionary, token: Dictionary) -> void:
	if not _active or token.is_empty(): return
	var start: int=Time.get_ticks_usec()
	_record(world,"alight_attempt_returned",{"attempt_id":token.attempt_id,"connection":_connection(connection),"primary_actor":_actor(world,token.primary_actor_id)})
	_attempts.erase(str(connection.id))
	_cost("alight_finished",start)

static func alight_committed(world: WorldState, connection: Dictionary, movement: Dictionary, source: String) -> void:
	if not _active: return
	var start: int=Time.get_ticks_usec()
	var actors: Array=[]
	for id: String in connection.riders: actors.append(_actor(world,id))
	_record(world,"alight_succeeded",{"attempt_id":_attempts.get(str(connection.id),{}).get("attempt_id",-1),"connection":_connection(connection),"actors":actors,"source":source,"actual_move_request_sequence":movement.request_sequence})
	_cost("alight_committed",start)

static func aside_begin(world: WorldState, connection: Dictionary, movement: Dictionary, source: String) -> Dictionary:
	if not _active: return {}
	var start: int=Time.get_ticks_usec()
	var token: Dictionary={"source":source,"request_sequence":movement.request_sequence,"actor_id":movement.actor_id,"location":world.facts.actors[movement.actor_id].location.duplicate(true)}
	_record(world,"stand_aside_called",{"connection":_connection(connection),"before":token.duplicate(true)})
	_cost("aside_begin",start)
	return token

static func aside_end(world: WorldState, connection: Dictionary, movement: Dictionary, token: Dictionary) -> void:
	if not _active or token.is_empty(): return
	var start: int=Time.get_ticks_usec()
	_record(world,"stand_aside_returned",{"connection":_connection(connection),"before":token,"after_actor":_actor(world,movement.actor_id),"request_sequence_changed":int(token.request_sequence)!=int(movement.request_sequence)})
	_cost("aside_end",start)

static func before_aside_commit(world: WorldState, connection: Dictionary, movement: Dictionary, source: String) -> void:
	if not _active: return
	var start: int=Time.get_ticks_usec()
	if _sequence_boundary.is_empty() and _boundary_before.is_empty():
		_boundary_before={"tick":world.sim_tick,"actor_id":movement.actor_id,"source":source,"request_sequence":movement.request_sequence,"facts":world.freeze()}
	_record(world,"stand_aside_commit_before",{"connection":_connection(connection),"actor":_actor(world,movement.actor_id),"source":source})
	_cost("aside_commit_before_includes_first_full_fact_copy",start)

static func after_aside_commit(world: WorldState, connection: Dictionary, movement: Dictionary, source: String) -> void:
	if not _active: return
	var start: int=Time.get_ticks_usec()
	if not _boundary_before.is_empty() and _boundary_before.actor_id==movement.actor_id:
		_sequence_boundary={"before":_boundary_before,"after":{"tick":world.sim_tick,"actor_id":movement.actor_id,"source":source,"request_sequence":movement.request_sequence,"facts":world.freeze()},"request_sequence_changed":int(_boundary_before.request_sequence)!=int(movement.request_sequence)}
		_boundary_before={}
	_record(world,"stand_aside_commit_after",{"connection":_connection(connection),"actor":_actor(world,movement.actor_id),"source":source})
	_cost("aside_commit_after_includes_first_full_fact_copy",start)

static func portal_begin(world: WorldState, movement: Dictionary, connector_id: String, floor_id: int) -> Dictionary:
	if not _active: return {}
	var start: int=Time.get_ticks_usec()
	var token: Dictionary={"connector_id":connector_id,"floor_id":floor_id,"phase":world.facts.connectors[connector_id].phase,"actor_id":movement.actor_id,"cursor":movement.convoy.portal.cursor,"last_point":movement.convoy.points[-1].duplicate()}
	_cost("portal_begin",start)
	return token

static func portal_end(world: WorldState, movement: Dictionary, token: Dictionary, result: Variant) -> void:
	if not _active or token.is_empty(): return
	var start: int=Time.get_ticks_usec()
	var blockers: Array=[]
	for id: String in result.blocker_actor_ids: blockers.append(_actor(world,id))
	_record(world,"actual_convoy_portal_step",{"before":token,"after_actor":_actor(world,movement.actor_id),"cursor":movement.convoy.portal.cursor,"last_point":movement.convoy.points[-1].duplicate(),"blocked":result.blocked,"static_reason":result.static_reason,"reservation_ids":result.reservation_ids.duplicate(),"door_id":result.door_id,"body_blocker_ids":result.blocker_actor_ids.duplicate(),"body_blockers":blockers,"requested_motion":[result.requested_motion.x,result.requested_motion.y],"actual_motion":[result.actual_motion.x,result.actual_motion.y]})
	_cost("portal_end",start)

static func finish(path: String, world: WorldState) -> void:
	if not _active: return
	var started: int=Time.get_ticks_usec()
	var actors: Dictionary={}
	for id: String in _motion: actors[id]=_actor(world,id)
	var open_phases: Dictionary={}
	for id: String in _phases:
		var phase: Dictionary=_phases[id].duplicate(true)
		phase.elapsed_ticks=world.sim_tick-int(phase.entered_tick) if int(phase.entered_tick)>=0 else -1
		phase.connection=_connection(world.facts.connectors.get(id,{}))
		open_phases[id]=phase
	var report: Dictionary={"diagnostic_only":true,"speed_conclusion_allowed":false,"observed_from_tick":_started_tick,"final_tick":world.sim_tick,"movement_steps":_movement_steps,"event_rows":_events.size(),"counts":_counts,"hook_costs":_costs,"events":_events,"open_phases":open_phases,"actors":actors,"first_stand_aside_commit_boundary":_sequence_boundary,"errors":_errors,"scope":"True phase assignments and alight calls, actual rejection branches, ticket creation/cancellation/consumption, complete independently derived body blocker identities, movement-boundary actual floor displacement. Missing pre-observation entry/last-move times remain -1. No remaining_ticks=1 inference. Full boundary snapshots and all hook costs perturb diagnostic steps; the source timing is not performance qualification.","cost_accounting":"inclusive_us is trace-owned elapsed only; never sum nested measurements as exclusive simulation time"}
	report.finish_prepare_us=Time.get_ticks_usec()-started
	var file: FileAccess=FileAccess.open(path,FileAccess.WRITE)
	if file==null: push_error("Could not write transport diagnostic sidecar: "+path); return
	file.store_string(JSON.stringify(report,"\t")); file.close()
	_active=false
