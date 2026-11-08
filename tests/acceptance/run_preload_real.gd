extends SceneTree
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var args=OS.get_cmdline_user_args()
	var f=FileAccess.open(args[0],FileAccess.READ)
	var e: Dictionary=f.get_var(false);f.close()
	var content=HospitalContent.new()
	var world=WorldState.new(e.facts)
	var sim=HospitalSimulation.new(world,content)
	var before: Dictionary=world.freeze()
	var first: Dictionary=sim.prepare_floor_static(1)
	var second: Dictionary=sim.prepare_floor_static(1)
	var passed: bool=before==world.freeze() and sim.space._route_queries.is_empty() and second.guidance_routes.path_builds==0
	var out=FileAccess.open(args[1],FileAccess.WRITE);out.store_string(JSON.stringify({"passed":passed,"first":first,"second":second,"facts_unchanged":before==world.freeze()},"\t"));out.close();sim.dispose();quit(0 if passed else 1)
