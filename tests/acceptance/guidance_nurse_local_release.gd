extends "res://tests/acceptance/rooms_areas_guidance.gd"

const NURSE: String="release_nurse"
const DESK: String="remote_guide"
const LIFT: String="release_lift"

func run_case(database: HospitalContent) -> Dictionary:
	content=database
	var rows: Array=[_departure("public"),_departure("landing"),_departure("ride"),_blocked()]
	return {"ok":rows.all(func(row:Dictionary)->bool:return row.ok),"runs":rows,"scope":"Already-prepared current work segment before an unstarted remote desk approach. Initial locations and desk assignment are input, not attendance or preparation evidence. Every tested exit, ride, water use and return uses real production steps; the original LIFE-04 covers preparation and six-second desk work."}

func _input(mode: String) -> Dictionary:
	var x: Dictionary=_base()
	var plots: Array=HospitalSpace.floor_plots(x.world,1).duplicate(true)
	for plot: Array in plots: x.world.facts.floors.completed_top_floor[HospitalSpace.plot_key(plot)]=2
	x.world.facts.floors.height_intervals=[{"first":1,"last":2,"height_m":float(content.balance.floors.clear_height_m)}]
	x.world.facts.floors.overrides["2"]={"plots":plots.duplicate(true),"blocked":[],"wall_edges":[],"doors":[],"paths":[]}
	x.world.facts.connectors[LIFT]={"id":LIFT,"definition_id":"VC02","first_floor":1,"last_floor":2,"cell":[58,70],"footprint":[4,4],"rotation":0,"anchor":[59,74],"repair_cell":[57,71],"floor_id":1,"phase":"idle","riders":[],"remaining_ticks":0,"condition":100.0,"failed":false,"pending_failure":false,"use_receipts":{},"paid_cost":3200,"used":false}
	x.world.touch()
	x.sim.services.maintenance.ensure(x.world)
	x.checks.water_downstairs=_facility(x,"water_downstairs","FUR17",[37,82])
	x.checks.water_upstairs=_command(x,"build_facility",{"id":"water_upstairs","definition_id":"FUR17","floor_id":2,"cell":[37,82]}).accepted
	x.checks.remote_desk=_command(x,"build_facility",{"id":DESK,"definition_id":"SE01","floor_id":2,"cell":[47,83]}).accepted
	_staff(x,NURSE,"nurse",[59,74] if mode in ["landing","blocked"] else [43,88])
	var staff: Dictionary=x.world.facts.staff[NURSE]
	staff.base_prepared=true
	staff.active_job_id="floor_desk:"+DESK
	x.world.facts.floor_guidance.desks[DESK]={"id":DESK,"nurse_id":NURSE,"reason":"","queue":[]}
	if mode=="blocked":
		# The actual connector occupies the fourth side of this legal landing.
		# No body is inside a pillar, and no path or completed arrival is supplied.
		x.world.facts.floors.overrides["1"].blocked.append_array([[58,74],[60,74],[59,75]])
	x.world.touch()
	x.sim.space.sync_actor(x.world,NURSE)
	x.checks.legal_input=x.world.validate(content).is_empty()
	x.before_entries=x.world.facts.ledger.entries.duplicate(true)
	x.before_units=int(x.world.facts.inventory.units)
	x.before_issues=x.world.facts.inventory.issues.duplicate(true)
	x.before_rest=int(staff.last_rest_end_tick)
	return x

func _departure(mode: String) -> Dictionary:
	var x: Dictionary=_input(mode)
	if not x.checks.values().all(func(value:Variant)->bool:return value==true): return _finish(x,{"mode":mode,"reason":"Initial built hospital or legal boundary failed"})
	var observations: Dictionary={"mode":mode,"input_tick":x.world.sim_tick,"initial_actor":x.world.facts.actors[NURSE].duplicate(true),"transit_phases":[],"release_walk_steps":0,"water_work_ticks":0,"release_point":{},"restores":[],"errors":[]}
	x.checks.original_transit_protected=true
	x.checks.in_transit_request_rejected=true
	if mode=="ride" and not _actual_ride(x,observations):
		x.checks.actual_ride=false
		return _finish(x,{"mode":mode,"observed":observations})
	var actor: Dictionary=x.world.facts.actors[NURSE]
	var start: Dictionary=actor.location.duplicate(true)
	var floor_id: int=int(actor.location.floor_id)
	var safe_before: bool=x.sim.space.public_areas.safe_wait(x.world,NURSE,floor_id,actor.location.cell)
	x.checks.expected_initial_safety=safe_before if mode=="public" else not safe_before
	x.checks.need_accepted=x.sim.services.wellbeing.begin_amenity(x.world,NURSE,"water")
	var guidance: HospitalFloorGuidance=x.sim.services.floor_guidance
	guidance._assign_desks(x.world)
	x.checks.original_release_created=x.world.facts.floor_guidance.releases.has(NURSE) and x.world.facts.staff[NURSE].active_job_id=="floor_desk_release:"+DESK
	observations.original_release=x.world.facts.floor_guidance.releases.get(NURSE,{}).duplicate(true)
	guidance._release_nurses(x.world)
	x.checks.owner_did_not_move_body=actor.location==start
	if mode=="public":
		x.checks.safe_public_released_directly=not x.world.facts.floor_guidance.releases.has(NURSE) and x.world.facts.staff[NURSE].active_job_id=="" and not x.world.facts.moves.has(NURSE)
		observations.release_point=actor.location.duplicate(true)
	else:
		var move: Dictionary=x.world.facts.moves.get(NURSE,{})
		x.checks.real_local_evacuation_requested=not move.is_empty() and int(move.target_floor)==floor_id and move.get("floor_only",false) and x.world.facts.staff[NURSE].life_task.phase=="wait_safe"
		if mode=="landing":
			var restored: Dictionary=_restore_release(x)
			observations.restores.append(restored)
			x.checks.pending_release_cold_restore=restored.ok
	x.checks.release_only_at_safe_point=true
	x.checks.original_work_segment_preserved=true
	x.checks.water_work_at_real_facility=true
	x.checks.local_exit_stays_on_floor=true
	var finished: bool=false
	for index: int in 1700:
		var before: Dictionary=x.world.facts.staff[NURSE].life_task.duplicate(true)
		var previous: Dictionary=x.world.facts.actors[NURSE].location.duplicate(true)
		var releasing: bool=x.world.facts.staff[NURSE].get("active_job_id","")=="floor_desk_release:"+DESK
		_step(x)
		actor=x.world.facts.actors[NURSE]
		var staff: Dictionary=x.world.facts.staff[NURSE]
		var task: Dictionary=staff.life_task
		var validation: String=x.world.validate(content)
		if not validation.is_empty(): observations.errors.append({"tick":x.world.sim_tick,"validation":validation});break
		x.checks.original_work_segment_preserved=x.checks.original_work_segment_preserved and staff.get("base_prepared",false) and staff.get("base_task",{}).is_empty() and int(staff.last_rest_end_tick)==int(x.before_rest)
		if releasing:
			x.checks.local_exit_stays_on_floor=x.checks.local_exit_stays_on_floor and actor.location.kind=="floor" and previous.kind=="floor" and int(actor.location.floor_id)==int(previous.floor_id)
			if actor.location!=previous: observations.release_walk_steps+=1
			if staff.get("active_job_id","")!="floor_desk_release:"+DESK:
				x.checks.release_only_at_safe_point=x.checks.release_only_at_safe_point and x.sim.space.public_areas.safe_wait(x.world,NURSE,int(actor.location.floor_id),actor.location.cell)
				observations.release_point=actor.location.duplicate(true)
		var worked: int=0
		if before.get("phase","")=="using": worked=int(before.remaining_ticks)-int(task.get("remaining_ticks",0))
		elif task.get("phase","")=="using": worked=80-int(task.remaining_ticks)
		if worked>0:
			observations.water_work_ticks+=worked
			var facility_id: String=str(before.get("facility_id",task.get("facility_id","")))
			if facility_id.is_empty(): facility_id=str(task.get("facility_id",""))
			var facility: Dictionary=x.sim.space.facility_layout(x.world,facility_id)
			x.checks.water_work_at_real_facility=x.checks.water_work_at_real_facility and worked==1 and not facility.is_empty() and x.sim.space.at(x.world,NURSE,int(facility.get("floor_id",0)),facility.get("patient_cell",[]))
		if task.has("completed_tick"): observations.water_completed_tick=int(task.completed_tick)
		if int(observations.water_work_ticks)==80 and task.phase=="idle" and staff.get("active_job_id","")=="floor_desk:"+DESK and not x.world.facts.moves.has(NURSE) and x.sim.space.at(x.world,NURSE,2,x.sim.space.guidance_operator_cell(x.world,DESK,NURSE)):
			finished=true;break
	x.checks.full_eight_seconds=int(observations.water_work_ticks)==80 and observations.has("water_completed_tick")
	x.checks.real_landing_departure=mode=="public" or int(observations.release_walk_steps)>0
	x.checks.released_and_actually_reposted=finished and not x.world.facts.floor_guidance.releases.has(NURSE) and not observations.release_point.is_empty()
	x.checks.no_extra_clinical_work=x.world.facts.preparations.is_empty() and x.world.facts.sessions.is_empty() and x.world.facts.attempts.is_empty()
	x.checks.no_extra_charges_or_supplies=_accounts_unchanged(x)
	return _finish(x,{"mode":mode,"observed":observations})

func _actual_ride(x: Dictionary, observations: Dictionary) -> bool:
	x.sim.services.floor_guidance._assign_desks(x.world)
	var move: Dictionary=x.world.facts.moves.get(NURSE,{})
	x.checks.actual_remote_approach=not move.is_empty() and move.get("guidance_nurse_desk","")==DESK and int(move.target_floor)==2
	var rejected: bool=false
	var boarded: bool=false
	for index: int in 700:
		var actor: Dictionary=x.world.facts.actors[NURSE]
		var connection: Dictionary=x.world.facts.connectors[LIFT]
		if actor.location.kind=="transit":
			boarded=true
			if not connection.phase in observations.transit_phases: observations.transit_phases.append(connection.phase)
			if not rejected:
				var frozen: Dictionary=x.world.freeze()
				x.checks.in_transit_request_rejected=not x.sim.services.wellbeing.begin_amenity(x.world,NURSE,"water") and frozen==x.world.freeze()
				var restored: Dictionary=_restore_release(x)
				observations.restores.append(restored)
				x.checks.original_transit_protected=x.checks.original_transit_protected and restored.ok and x.world.freeze()==frozen
				rejected=true
		if boarded and actor.location.kind=="floor" and int(actor.location.floor_id)==2:
			x.checks.actual_ride=rejected and observations.transit_phases.has("boarding") and observations.transit_phases.has("riding") and observations.transit_phases.has("alighting")
			return x.checks.actual_ride
		_step(x)
		var validation: String=x.world.validate(content)
		if not validation.is_empty(): observations.errors.append({"tick":x.world.sim_tick,"validation":validation});return false
	return false

func _blocked() -> Dictionary:
	var x: Dictionary=_input("blocked")
	if not x.checks.values().all(func(value:Variant)->bool:return value==true): return _finish(x,{"mode":"blocked","reason":"Initial built hospital or legal boundary failed"})
	var actor: Dictionary=x.world.facts.actors[NURSE]
	var original: Dictionary=actor.location.duplicate(true)
	x.checks.landing_is_not_safe=not x.sim.space.public_areas.safe_wait(x.world,NURSE,1,actor.location.cell)
	x.checks.need_accepted=x.sim.services.wellbeing.begin_amenity(x.world,NURSE,"water")
	x.sim.services.floor_guidance._assign_desks(x.world)
	var release: Dictionary=x.world.facts.floor_guidance.releases.get(NURSE,{}).duplicate(true)
	var frozen: Dictionary=x.world.freeze()
	var point: Dictionary=x.sim.services.floor_guidance._nurse_local_release_point(x.world,NURSE)
	x.checks.no_safe_point_is_real=point.is_empty() and frozen==x.world.freeze()
	x.sim.services.floor_guidance._release_nurses(x.world)
	var restored: Dictionary=_restore_release(x)
	x.checks.blocked_cold_restore=restored.ok
	x.checks.responsibility_retained=true
	for index: int in 3:
		_step(x)
		var staff: Dictionary=x.world.facts.staff[NURSE]
		x.checks.responsibility_retained=x.checks.responsibility_retained and x.world.facts.actors[NURSE].location==original and staff.active_job_id=="floor_desk_release:"+DESK and staff.life_task.phase=="wait_safe" and x.world.facts.floor_guidance.releases.get(NURSE,{})==release and not x.world.facts.moves.has(NURSE)
	x.checks.no_fake_service_or_charge=x.world.facts.sessions.is_empty() and x.world.facts.attempts.is_empty() and _accounts_unchanged(x)
	return _finish(x,{"mode":"blocked","restore":restored,"reason":x.world.facts.staff[NURSE].life_reason,"blocked_cells":x.world.facts.floors.overrides["1"].blocked.duplicate(true)})

func _accounts_unchanged(x: Dictionary) -> bool:
	return x.world.facts.ledger.entries==x.before_entries and int(x.world.facts.inventory.units)==int(x.before_units) and x.world.facts.inventory.issues==x.before_issues

func _restore_release(x: Dictionary) -> Dictionary:
	var original: Dictionary=x.world.freeze()
	var chunks: Array=[]
	var encoder:=HospitalJsonStream.new()
	if not encoder.encode_to(original,func(_bytes:int)->bool:return true,func(chunk:PackedByteArray)->Dictionary:
		chunks.append(chunk.duplicate())
		return {"ok":true}):
		return {"ok":false,"error":encoder.error}
	var cursor: Dictionary={"index":0}
	var decoder:=HospitalJsonStream.new()
	var decoded: Dictionary=decoder.decode_from(encoder.bytes,encoder.digest,func(_bytes:int)->bool:return true,func()->Dictionary:
		if int(cursor.index)>=chunks.size(): return {"ok":true,"data":PackedByteArray()}
		var chunk: PackedByteArray=chunks[int(cursor.index)]
		cursor.index=int(cursor.index)+1
		return {"ok":true,"data":chunk})
	if not decoded.ok: return {"ok":false,"error":decoded.error}
	var world:=WorldState.new(decoded.value)
	var validation: String=world.validate(content)
	if not validation.is_empty() or world.freeze()!=original: return {"ok":false,"error":validation,"facts_equal":world.freeze()==original}
	x.sim.dispose()
	x.world=world;x.sim=HospitalSimulation.new(world,content)
	return {"ok":x.world.freeze()==original,"bytes":encoder.bytes,"sha256":encoder.digest}
