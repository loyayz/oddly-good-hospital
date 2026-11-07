extends SceneTree
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var content: HospitalContent = HospitalContent.new()
	var payload: Dictionary = FileAccess.open(args[0],FileAccess.READ).get_var()
	var world: WorldState = WorldState.new(payload.facts.duplicate(true))
	var sim: HospitalSimulation = HospitalSimulation.new(world,content)
	var initial: String = world.validate(content)
	var origin_tick: int = world.sim_tick
	var first: Dictionary = {}
	var bad: Array = []
	var errors: Array = []
	var steps: int = int(args[2]) if args.size()>2 else 120
	for n: int in steps:
		var result: TickResult = sim.step()
		if result==null: errors.append("Incomplete step");break
		if n==0:
			var id: String = "bench_staff_0019"
			first = {"tick":world.sim_tick,"actor":world.facts.actors[id].location.duplicate(true),"phase":world.facts.staff[id].life_task.phase,"has_move":world.facts.moves.has(id)}
		for id: String in world.facts.moves:
			if world.facts.actors[id].location.kind=="outside": bad.append({"tick":world.sim_tick,"actor_id":id})
		if not bad.is_empty(): break
	var validation: String = world.validate(content)
	var report: Dictionary = {"passed":initial.is_empty() and validation.is_empty() and errors.is_empty() and bad.is_empty() and world.sim_tick==origin_tick+steps,"input_sha256":FileAccess.get_sha256(args[0]),"initial_validation":initial,"first_boundary":first,"bad":bad,"errors":errors,"final_validation":validation,"initial_tick":origin_tick,"final_tick":world.sim_tick,"requested_steps":steps}
	FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("STAFF_EXIT_SNAPSHOT "+JSON.stringify(report))
	sim.dispose();quit(0 if report.passed else 1)
