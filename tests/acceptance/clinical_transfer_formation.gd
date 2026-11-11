extends SceneTree
var content: HospitalContent
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()<3:
		push_error("Expected result.json, selected cases (geometry,journey,restore), and a real transfer boundary .bin")
		quit(2)
		return
	content=HospitalContent.new()
	var saved: Dictionary=FileAccess.open(args[2],FileAccess.READ).get_var()
	var rows: Array=[]
	for name: String in ["geometry","journey","restore"]:
		if not name in args[1].split(","): continue
		var result: Dictionary=_geometry(saved) if name=="geometry" else _continue(saved,name=="restore")
		result.case=name
		rows.append(result)
		print(JSON.stringify({"case":name,"ok":result.ok,"checks":result.get("checks",{}),"ticks":result.get("ticks",0)}))
	var ok: bool=not rows.is_empty()
	for row: Dictionary in rows: ok=ok and row.ok
	FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify({"ok":ok,"rows":rows,"engine":Engine.get_version_info().string},"  "))
	quit(0 if ok else 1)

func _geometry(saved: Dictionary) -> Dictionary:
	var world: WorldState=WorldState.new(saved.facts.duplicate(true))
	var sim: HospitalSimulation=HospitalSimulation.new(world,content)
	sim.clinic.experience=null
	var stay: Dictionary=world.facts.ward_stays.values()[0]
	var visit: Dictionary=world.facts.visits[world.facts.attempts[stay.attempt_id].visit_id]
	var bed: Dictionary=sim.space.facility_layout(world,stay.bed_id)
	var before: Dictionary=world.freeze()
	var failed: Dictionary=sim.clinic._escort_formation_candidate(world,visit.actor_id,stay.escort_id,int(bed.floor_id),bed.patient_cell,Vector2.RIGHT)
	var actual: Dictionary=sim.clinic._escort_formation(world,visit.actor_id,stay.escort_id,int(bed.floor_id),bed.patient_cell)
	var checks: Dictionary={"original_east_tail_rejected":not failed.ok,"legal_alternative_found":actual.ok,"actual_west_facing_queue":actual.get("direction",[])==[-1.0,0.0],"nurse_gathering_is_reachable":actual.get("gathering",{}).get("ok",false),"both_queries_readonly":before==world.freeze(),"world_valid":world.validate(content).is_empty()}
	var ok: bool=true
	for check: bool in checks.values(): ok=ok and check
	sim.dispose()
	return {"ok":ok,"checks":checks,"rejected":failed,"formation":actual}

func _continue(saved: Dictionary, restore: bool) -> Dictionary:
	var world: WorldState=WorldState.new(saved.facts.duplicate(true))
	var sim: HospitalSimulation=HospitalSimulation.new(world,content)
	sim.clinic.experience=null
	var stay_id: String=world.facts.ward_stays.keys()[0]
	var stay: Dictionary=world.facts.ward_stays[stay_id]
	var visit: Dictionary=world.facts.visits[world.facts.attempts[stay.attempt_id].visit_id]
	var patient_id: String=visit.actor_id
	var escort_id: String=stay.escort_id
	var initial_remaining: int=int(stay.remaining_ticks)
	var initial_facts: Dictionary=world.freeze()
	var bed: Dictionary=sim.space.facility_layout(world,stay.bed_id)
	var formation: Dictionary=sim.clinic._escort_formation(world,patient_id,escort_id,int(bed.floor_id),bed.patient_cell)
	var readonly: bool=initial_facts==world.freeze()
	var legal_input: String=world.validate(content)
	var errors: Array=[]
	var saw_group: bool=false
	var arrived: bool=false
	var nurse_gathered: bool=false
	var bounded: bool=true
	var first_group: Dictionary={}
	var restored: bool=false
	var ticks: int=0
	var trace: Array=[]
	for index: int in 800:
		var before: Vector2=ConvoyTrail.point(world.facts.actors[patient_id].location.cell)
		var had_group: bool=world.facts.moves.get(patient_id,{}).has("convoy")
		if not had_group and sim.space.at(world,escort_id,int(bed.floor_id),formation.targets[escort_id]): nurse_gathered=true
		sim.step()
		ticks+=1
		var movement: Dictionary=world.facts.moves.get(patient_id,{})
		if movement.has("convoy"):
			saw_group=true
			if first_group.is_empty():
				first_group=movement.convoy.duplicate(true)
		if had_group or movement.has("convoy"):
			bounded=bounded and before.distance_to(ConvoyTrail.point(world.facts.actors[patient_id].location.cell))<=sim.space.walking_speed(world.facts.actors[patient_id])*WorldState.TICK_SECONDS+0.001
		var valid: String=world.validate(content)
		if not valid.is_empty(): errors.append(valid);break
		var actors: Array=world.facts.actors.values()
		for a: int in actors.size():
			if actors[a].location.kind!="floor": continue
			for b: int in range(a+1,actors.size()):
				if actors[b].location.kind=="floor" and actors[a].location.floor_id==actors[b].location.floor_id and sim.space.body_rectangle(actors[a]).intersects(sim.space.body_rectangle(actors[b]),false): errors.append("body overlap: "+actors[a].id+" / "+actors[b].id)
		if index%25==0:trace.append({"tick":world.sim_tick,"stay":stay.phase,"patient":world.facts.actors[patient_id].location.duplicate(true),"escort":world.facts.actors[escort_id].location.duplicate(true),"waiting":visit.get("waiting_reason",""),"movement":movement.duplicate(true)})
		if restore and not restored and movement.has("convoy"):
			var frozen: Dictionary=world.freeze()
			sim.dispose()
			world=WorldState.new(frozen)
			sim=HospitalSimulation.new(world,content)
			sim.clinic.experience=null
			stay=world.facts.ward_stays[stay_id]
			visit=world.facts.visits[world.facts.attempts[stay.attempt_id].visit_id]
			restored=world.validate(content).is_empty() and world.freeze()==frozen
		if stay.phase=="recovery": arrived=true;break
		if not errors.is_empty():break
	var checks: Dictionary={"legal_input":legal_input.is_empty(),"readonly_formation":readonly,"legal_formation":formation.ok,"nurse_actually_gathered":nurse_gathered,"real_queue_seen":saw_group,"safe":errors.is_empty(),"bounded":bounded,"actual_bed_handoff":arrived,"no_recovery_work_while_transferring":int(stay.remaining_ticks)>=initial_remaining-1,"care_completed_kept":stay.care_completed,"restore_preserved_state":not restore or restored}
	var ok: bool=true
	for check: bool in checks.values():ok=ok and check
	var result: Dictionary={"ok":ok,"checks":checks,"ticks":ticks,"errors":errors,"formation":formation,"first_group":first_group,"stay":stay,"trace":trace,"final_validation":world.validate(content)}
	sim.dispose()
	return result
