extends SceneTree
class OriginalSearch extends HospitalNavigation:
	func _dynamic_goal_has_entry(_graph: FloorNavigation, _goal: Vector2i, _people: Callable) -> bool: return true
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var suite=load("res://tests/acceptance/space.gd").new();suite.content=HospitalContent.new()
	var rows: Array=[]
	for mode: String in ["sealed","one_open","goal_occupied","fractional_start","same_start_goal","proxy_direction"]:
		var sim: HospitalSimulation=suite._fixture()
		suite._add_actor(sim,"walker","S49",[35.25,80] if mode=="fractional_start" else [35,80])
		var offsets: Array=[[44,80],[46,80],[45,79],[45,81]]
		for i: int in offsets.size():
			if mode=="one_open" and i==3: continue
			suite._add_actor(sim,"blocker_"+str(i),"S49",offsets[i])
		if mode=="goal_occupied": suite._add_actor(sim,"goal_owner","S49",[45,80])
		var world: WorldState=sim.world
		if mode=="same_start_goal": world.facts.actors.walker.location.cell=[45,80]
		if mode=="proxy_direction": world.facts.actors.walker._convoy_goal_direction=Vector2.ZERO
		var start: Vector2i=Vector2i(45,80) if mode=="same_start_goal" else Vector2i(35,80)
		var actual:=HospitalSpace.new(suite.content)
		var original:=HospitalSpace.new(suite.content)
		var original_navigation:=OriginalSearch.new(original)
		var before: Dictionary=world.freeze()
		var a: Dictionary=actual.navigation._floor_route(world,world.facts.actors.walker,1,start,Vector2i(45,80))
		var b: Dictionary=original_navigation._floor_route(world,world.facts.actors.walker,1,start,Vector2i(45,80))
		var pruned: int=int(actual.query_counts.get("dynamic_goal_entry_prunes",0))
		var expected: bool=pruned==1 if mode in ["sealed","fractional_start"] else pruned==0
		rows.append({"mode":mode,"passed":a==b and expected and before==world.freeze() and world.validate(suite.content).is_empty(),"exact_route_equal":a==b,"pruned":pruned,"status":a.get("status",""),"candidate_projections":actual.query_counts.get("dynamic_route_projections",0),"original_projections":original.query_counts.get("dynamic_route_projections",0)})
		sim.dispose()
	var passed: bool=rows.all(func(x: Dictionary)->bool:return x.passed)
	var f=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE);f.store_string(JSON.stringify({"passed":passed,"rows":rows},"\t"));f.close();quit(0 if passed else 1)
