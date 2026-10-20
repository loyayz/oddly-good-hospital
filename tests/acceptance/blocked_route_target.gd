extends RefCounted

class CountedSpace extends HospitalSpace:
	var checks: int = 0
	var goal_checks: int = 0
	func _unit_step_dynamic_clear(world: WorldState, actor: Dictionary, floor_id: int, from: Vector2i, to: Vector2i, members: Array, offsets: Dictionary) -> bool:
		checks += 1
		if from==to: goal_checks += 1
		return super._unit_step_dynamic_clear(world,actor,floor_id,from,to,members,offsets)

# Independent reference keeps the complete original dynamic fallback. It does
# not call the optimized _floor_route or use its destination condition.
class OriginalSpace extends CountedSpace:
	func _floor_route(world: WorldState, actor: Dictionary, floor_id: int, start: Vector2i, goal: Vector2i, members: Array = [], offsets: Dictionary = {}, ignore_people: bool = false, navigation: Dictionary = {}, _cost_only: bool = false) -> Dictionary:
		var routes: Dictionary = {}
		var key: String = ""
		if ignore_people and navigation.is_empty() and not _route_queries.is_empty() and _route_queries.back().world==world:
			routes = _route_queries.back().routes
			var identity: Variant = actor.id
			if not _route_queries.back().reference.is_empty() and members.is_empty() and offsets.is_empty():
				identity = [body(actor),RouteClearance.reservation_exemptions(world,actor.id,floor_id)]
			key = JSON.stringify([identity,floor_id,start.x,start.y,goal.x,goal.y,members,offsets,_route_envelope(world,actor,members,offsets)])
			if routes.has(key): return routes[key].duplicate(true)
		if navigation.is_empty(): navigation = _navigation.query_graphs(self,world,floor_id,actor,members,offsets)
		var graph: FloorNavigation = navigation.graph
		var query: RouteClearance
		if navigation.has("query"): query = navigation.query
		else: query = _navigation.clearance(self,world,floor_id,actor) if members.is_empty() else RouteClearance.new(self,world,actor,floor_id,members,offsets,true,graph.geometry.source)
		var people: Callable = Callable()
		if not ignore_people:
			people = func(from_cell: Vector2i,to_cell: Vector2i) -> bool:
				return _unit_step_dynamic_clear(world,actor,floor_id,from_cell,to_cell,members,offsets)
		var result: Dictionary = graph.find_path(start,goal,query,Callable(),false,navigation.bases,navigation.shifts,bool(navigation.get("overlay",false)))
		if result.ok and people.is_valid():
			var low: Vector2 = Vector2(start)
			var high: Vector2 = low
			for cell: Array in result.cells:
				low = low.min(Vector2(float(cell[0]),float(cell[1])))
				high = high.max(Vector2(float(cell[0]),float(cell[1])))
			var shape: Rect2 = _unit_rect(world,actor,Vector2.ZERO,members,offsets)
			var broad: Rect2 = Rect2(low+shape.position,high-low+shape.size)
			if not _dynamic_clear(world,actor.id,floor_id,broad,members):
				var blocked: bool = false
				var previous: Vector2i = start
				for cell: Array in result.cells:
					var next: Vector2i = Vector2i(int(cell[0]),int(cell[1]))
					if not bool(people.call(previous,next)):
						blocked = true
						break
					previous = next
				if blocked:
					var alternative: Dictionary = graph.find_path(start,goal,query,people,false,navigation.bases,navigation.shifts,bool(navigation.get("overlay",false)))
					if alternative.ok: result = alternative
					else: result.status = "contention"
		if result.ok:
			var path: Array = []
			for cell: Array in result.cells: path.append({"kind":"floor","floor_id":floor_id,"cell":cell})
			result.path = path
			result.erase("cells")
		if not key.is_empty(): routes[key] = result.duplicate(true)
		return result

func run_case(sim: HospitalSimulation, content: HospitalContent) -> Dictionary:
	var original_facts: Dictionary = sim.world.freeze()
	var baseline: Dictionary = original_facts.duplicate(true)
	baseline.actors["subject"] = _actor("subject",[38,80])
	baseline.actors["peer"] = _actor("peer",[54,90])
	baseline.actors["blocker"] = _actor("blocker",[50,90])
	var observations: Array = []
	var ok: bool = true
	for variant: String in ["goal_body","middle_detour","group_member_goal","group_gap","actual_fractional_start","zero_path","accepted_sweep"]:
		var facts: Dictionary = baseline.duplicate(true)
		var start: Vector2i = Vector2i(38,80)
		var goal: Vector2i = Vector2i(42,80)
		var members: Array = []
		var offsets: Dictionary = {}
		match variant:
			"goal_body": facts.actors.blocker.location.cell = [42,80]
			"middle_detour": facts.actors.blocker.location.cell = [40,80]
			"group_member_goal":
				members = ["subject","peer"]
				offsets = {"peer":[2,0]}
				facts.actors.peer.location.cell = [40,80]
				facts.actors.blocker.location.cell = [44,80]
			"group_gap":
				members = ["subject","peer"]
				offsets = {"peer":[2,0]}
				facts.actors.peer.location.cell = [40,80]
				facts.actors.blocker.location.cell = [43,80]
			"actual_fractional_start":
				facts.actors.subject.location.cell = [42.35,80]
				facts.actors.blocker.location.cell = [40,80]
			"zero_path":
				facts.actors.subject.location.cell = [42.35,80]
				start = goal
			"accepted_sweep":
				var geometry: HospitalSpace = HospitalSpace.new(content)
				var subject: Rect2 = geometry._actor_rect(facts.actors.subject,Vector2(goal))
				var blocker: Rect2 = geometry._actor_rect(facts.actors.blocker,Vector2.ZERO)
				facts.actors.blocker.location.cell = [subject.end.x-blocker.position.x+0.01,80]
		var actual_world: WorldState = WorldState.new(facts.duplicate(true))
		var original_world: WorldState = WorldState.new(facts.duplicate(true))
		var actual: CountedSpace = CountedSpace.new(content)
		var original: OriginalSpace = OriginalSpace.new(content)
		for geometry: HospitalSpace in [actual,original]:
			var world: WorldState = actual_world if geometry==actual else original_world
			geometry._ensure_actor_index(world)
			if variant=="accepted_sweep":
				# A legal calculation boundary: a preceding 0.1-cell accepted move
				# has left its endpoint clear but its sweep remains this phase.
				var actor: Dictionary = world.facts.actors.blocker
				var current: Vector2 = Vector2(actor.location.cell[0],actor.location.cell[1])
				geometry.movement._sweep_index.begin_boundary(world.facts.actors)
				geometry.movement._sweep_index.update(actor.id,1,geometry._actor_rect(actor,current-Vector2(0.1,0)).merge(geometry._actor_rect(actor,current)))
		var validation: String = actual_world.validate(content)
		var original_validation: String = original_world.validate(content)
		var valid: bool = validation.is_empty() and original_validation.is_empty()
		var before: Dictionary = actual_world.freeze()
		var expected: Dictionary = original._floor_route(original_world,original_world.facts.actors.subject,1,start,goal,members,offsets)
		var result: Dictionary = actual._floor_route(actual_world,actual_world.facts.actors.subject,1,start,goal,members,offsets)
		var equal: bool = valid and result==expected and actual_world.freeze()==before and original_world.freeze()==before
		var behavior: bool = result.get("ok",false)
		if variant in ["goal_body","group_member_goal","accepted_sweep"]:
			behavior = behavior and result.get("status")=="contention" and actual.goal_checks==1 and original.checks>actual.checks+10
		elif variant=="middle_detour":
			behavior = behavior and result.get("status")=="complete" and result.get("path",[]).size()>4 and actual.checks>5
		elif variant in ["actual_fractional_start","zero_path"]:
			behavior = behavior and actual.goal_checks==0
		observations.append({"variant":variant,"valid":valid,"validation":validation,"original_validation":original_validation,"complete_cold_equal":equal,"expected_behavior":behavior,"checks":actual.checks,"original_checks":original.checks,"goal_checks":actual.goal_checks,"result":result})
		ok = ok and equal and behavior
		if variant=="goal_body":
			# No stale negative proof survives an actual endpoint release.
			actual_world.facts.actors.blocker.location.cell = [50,90]
			original_world.facts.actors.blocker.location.cell = [50,90]
			actual_world.touch(false)
			original_world.touch(false)
			var released: Dictionary = actual._floor_route(actual_world,actual_world.facts.actors.subject,1,start,goal)
			var cold: Dictionary = OriginalSpace.new(content)._floor_route(original_world,original_world.facts.actors.subject,1,start,goal)
			var restored: bool = released==cold and released.get("ok",false) and released.get("status")=="complete"
			observations.append({"variant":"goal_released","complete_cold_equal":released==cold,"expected_behavior":restored})
			ok = ok and restored
	return {"ok":ok and sim.world.freeze()==original_facts,"details":{"observations":observations,"scope":"exact original complete dynamic A* comparison; computation only; real transport lifecycle covered separately"}}

func _actor(id: String, cell: Array) -> Dictionary:
	return {"id":id,"name":id,"species_id":"S49","location":{"kind":"floor","floor_id":1,"cell":cell.duplicate(),"height_m":0.0},"facing":0.0,"posture":"standing"}
