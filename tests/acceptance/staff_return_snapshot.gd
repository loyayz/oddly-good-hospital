extends SceneTree
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var content: HospitalContent = HospitalContent.new()
	var input: Dictionary = FileAccess.open(args[0],FileAccess.READ).get_var()
	var world: WorldState = WorldState.new(input.facts.duplicate(true))
	var sim: HospitalSimulation = HospitalSimulation.new(world,content)
	var initial: String = world.validate(content)
	var origin_tick: int = world.sim_tick
	var replacement: Dictionary = world.facts.actors.clin_or_nurse.location.duplicate(true)
	var schedule: Array = world.facts.staff.clin_cover.schedule.duplicate(true)
	var first_idle: Dictionary = {}
	var ready_tick: int = -1
	var errors: Array = []
	for n: int in 1200:
		sim.step()
		var staff: Dictionary = world.facts.staff.clin_cover
		if first_idle.is_empty() and staff.life_task.phase=="idle":
			first_idle = {"tick":world.sim_tick,"location":world.facts.actors.clin_cover.location.duplicate(true),"replacement_unchanged":world.facts.actors.clin_or_nurse.location==replacement,"leave_cleared":staff.leave_plan.is_empty()}
		if ready_tick<0 and staff.life_task.phase=="idle" and staff.on_shift and not staff.block_new_work and staff.base_prepared: ready_tick = world.sim_tick
		var bodies: Array = []
		for actor: Dictionary in world.facts.actors.values():
			if actor.location.kind=="floor": bodies.append({"id":actor.id,"floor":actor.location.floor_id,"rect":sim.space.body_rectangle(actor)})
		for a: int in bodies.size():
			for b: int in range(a+1,bodies.size()):
				if bodies[a].floor==bodies[b].floor and bodies[a].rect.intersects(bodies[b].rect,false): errors.append({"tick":world.sim_tick,"overlap":[bodies[a].id,bodies[b].id]})
		for id: String in world.facts.moves:
			if world.facts.actors[id].location.kind=="outside": errors.append({"tick":world.sim_tick,"outside_move":id})
		if n%100==0:
			var validation: String = world.validate(content)
			if not validation.is_empty(): errors.append({"tick":world.sim_tick,"validation":validation})
	var final_validation: String = world.validate(content)
	var report: Dictionary = {"passed":input.content_fingerprint==content.content_fingerprint and initial.is_empty() and final_validation.is_empty() and errors.is_empty() and not first_idle.is_empty() and first_idle.replacement_unchanged and first_idle.leave_cleared and ready_tick>=0 and world.facts.staff.clin_cover.schedule==schedule,"input_sha256":FileAccess.get_sha256(args[0]),"initial_tick":origin_tick,"final_tick":world.sim_tick,"initial_validation":initial,"first_idle":first_idle,"ready_tick":ready_tick,"checks":1200,"errors":errors,"final_validation":final_validation,"final_staff":world.facts.staff.clin_cover.duplicate(true),"final_location":world.facts.actors.clin_cover.location.duplicate(true)}
	FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("STAFF_RETURN_SNAPSHOT "+JSON.stringify({"passed":report.passed,"first_idle":first_idle,"ready_tick":ready_tick,"initial_tick":origin_tick,"final_tick":world.sim_tick,"errors":errors,"validation":final_validation}))
	sim.dispose();quit(0 if report.passed else 1)
