extends "res://tests/acceptance/clinical_fixtures.gd"

func run(t, content: HospitalContent) -> void:
	_content = content
	_cache = t.checkpoints(content,"res://tests/acceptance/clinical_fixtures.gd",self)
	var started: int = Time.get_ticks_msec()
	var ready: bool = await _ensure_boundary(t,"gp_started") and await _ensure_boundary(t,"outpatient_started")
	t.preparation_elapsed(started)
	if not ready:
		t.check("CORE-48",false,{"fixture_prerequisites":_fixture_failures})
		_dispose_simulations()
		return
	var view: HospitalView = HospitalView.new(content)
	var valid: bool = true
	var observations: Array = []
	for boundary: String in ["gp_started","outpatient_started"]:
		var c: Dictionary = _copy(boundary)
		view.world = c.world
		var validation: String = c.world.validate(content)
		var before: Dictionary = c.world.freeze()
		var equivalent: bool = _all_poses_equal(view)
		# The real outpatient boundary has a seated patient: display the actual
		# posture while treatment proceeds, rather than forcing a standing work pose.
		var expected_patient_pose: String = "sit" if boundary=="outpatient_started" else "symptom"
		var seated_outpatient: bool = boundary!="outpatient_started" or c.world.facts.actors[_visit(c).actor_id].posture=="seated"
		var actual_patient_pose: String = str(view._pose(_visit(c).actor_id).name)
		view.low_motion = true
		var low_motion: bool = _all_poses_equal(view)
		for actor_id: String in c.world.facts.actors:
			low_motion = low_motion and view._pose(actor_id).name=="low_motion"
		view.low_motion = false
		var readonly: bool = c.world.freeze()==before
		for tick: int in 13: _tick(c)
		var after_validation: String = c.world.validate(content)
		before = c.world.freeze()
		var fresh: bool = _all_poses_equal(view)
		readonly = readonly and c.world.freeze()==before
		valid = valid and validation.is_empty() and after_validation.is_empty() and equivalent and fresh and low_motion and readonly and seated_outpatient and actual_patient_pose==expected_patient_pose
		observations.append({"boundary":boundary,"validation":validation,"after13ticks_validation":after_validation,"actors":c.world.facts.actors.size(),"all_pose_results_equal":equivalent,"fresh_after13actualticks":fresh,"low_motion":low_motion,"readonly":readonly,"seated_outpatient":seated_outpatient,"expected_patient_pose":expected_patient_pose,"actual_patient_pose":actual_patient_pose})
	view.free()
	_dispose_simulations()
	t.check("CORE-48",valid,{"observations":observations,"scope":"validated actual GP/outpatient states, every actor, low motion, fresh projection after real progression and world replacement; actual node/resource rebind remains CORE31/32"})

func _all_poses_equal(view: HospitalView) -> bool:
	var presentation: Dictionary = view._presentation_index()
	for actor_id: String in view.world.facts.actors:
		if view._pose(actor_id,presentation)!=_original_pose(view,actor_id): return false
	return true

# Frozen 83cc36a pose observation, used only as a compatibility comparator.
# Clinical boundary inputs and the patient expectations above own correctness.
func _original_pose(view: HospitalView, actor_id: String) -> Dictionary:
	var world: WorldState = view.world
	if view.low_motion:
		return {"name":"low_motion","time":0.5}
	if world.facts.moves.has(actor_id):
		return {"name":"walk","time":fmod(float(world.facts.sim_tick)*0.1,1.0)}
	for movement: Dictionary in world.facts.moves.values():
		if actor_id in movement.get("members",[]):
			return {"name":"walk","time":fmod(float(world.facts.sim_tick)*0.1,1.0)}
	for session: Dictionary in world.facts.sessions.values():
		if (actor_id==world.facts.visits.get(session.get("visit_id",""),{}).get("actor_id","") or actor_id in session.get("staff_ids",[])) and world.facts.facilities.get(session.get("facility_id",""),{}).get("failed",false) and session.kind!="wake":
			return {"name":"pause","time":0.5}
	if world.facts.staff.has(actor_id):
		var phase: String = str(world.facts.staff[actor_id].get("life_task",{}).get("phase","idle"))
		if phase in ["sleep","rest","recreation"]:
			return {"name":phase,"time":0.5 if phase!="recreation" else fmod(float(world.sim_tick)*0.1,1.0)}
	if world.facts.actors[actor_id].get("posture","standing") == "seated":
		return {"name":"sit","time":0.5}
	for visit: Dictionary in world.facts.visits.values():
		if visit.actor_id != actor_id:
			continue
		if visit.final_result == "cured":
			return {"name":"recover","time":fmod(float(world.facts.sim_tick)*0.1,1.0)}
		if visit.phase in ["outpatient","surgery"]:
			return {"name":"work","time":fmod(float(world.facts.sim_tick)*0.1,1.0)}
		if visit.phase in ["wake","transfer","recovery","round_wait","round"]:
			return {"name":"pause","time":0.5}
		return {"name":"symptom","time":fmod(float(world.facts.sim_tick)*0.1,1.0)}
	for session: Dictionary in world.facts.sessions.values():
		if actor_id in session.staff_ids:
			return {"name":"work","time":fmod(float(world.facts.sim_tick)*0.1,1.0)}
	for patch: Dictionary in world.facts.get("environment",{}).get("dirt",{}).values():
		if patch.get("worker_id","")==actor_id and patch.get("phase","")=="working":
			return {"name":"work","time":fmod(float(world.sim_tick)*0.1,1.0)}
	for order: Dictionary in world.facts.get("environment",{}).get("orders",{}).values():
		for unit: Dictionary in order.units:
			if unit.get("worker_id","")==actor_id and unit.phase=="working":
				return {"name":"work","time":fmod(float(world.sim_tick)*0.1,1.0)}
	for collection: String in ["jobs","upgrades"]:
		for job: Dictionary in world.facts.get("maintenance",{}).get(collection,{}).values():
			if job.get("worker_id","")==actor_id and job.phase=="working":
				return {"name":"work","time":fmod(float(world.sim_tick)*0.1,1.0)}
	return {"name":"idle","time":fmod(float(world.facts.sim_tick)*0.1,1.0)}
