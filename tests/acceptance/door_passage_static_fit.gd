extends "res://tests/acceptance/ordinary_door_passage.gd"
func run_static_fit(content: HospitalContent) -> Dictionary:
	suite.content=content
	var f: Dictionary=_setup(true)
	var sim: HospitalSimulation=f.sim
	if f.door.is_empty():sim.dispose();return {"ok":false,"error":"fixture door missing"}
	var world: WorldState=sim.world
	var space: HospitalSpace=sim.space
	var door: Dictionary=f.door
	suite._add_actor(sim,"fit_probe","S49",[40,85])
	var actor: Dictionary=world.facts.actors.fit_probe
	var checks: Dictionary={}
	checks.cold_equal=space.door_passage_quote(world,actor,1,door)==space.door_quote(world,actor,1,door)
	space._navigation.query_graphs(space,world,1,actor,[],{})
	var geometry: RouteClearance=space._navigation.cached_static_geometry(space,world,1,actor)
	checks.hot_geometry=geometry!=null
	checks.hot_equal=space.door_passage_quote(world,actor,1,door)==space.door_quote(world,actor,1,door)
	if geometry!=null:
		var scalar: Dictionary=geometry.door_static_fit(str(door.id))
		var saved: Dictionary=scalar.duplicate(true)
		scalar.ok=false;scalar.span=-99;scalar.reason="mutated caller copy"
		checks.scalar_not_alias=geometry.door_static_fit(str(door.id))==saved
		checks.missing_door=geometry.door_static_fit("not_a_door").is_empty()
	# Two explicit proxy bodies deliberately share integer width/height flags.
	# Their exact height requirements must never be borrowed from one another.
	var definition: Dictionary=content.definition("doors",door.definition_id)
	var a: Dictionary=actor.duplicate(true)
	a._convoy_body={"width_m":0.8,"depth_m":0.8,"height_m":float(definition.clear_height_m)+0.05}
	var b: Dictionary=a.duplicate(true)
	b._convoy_body.height_m=float(definition.clear_height_m)+0.15
	var source: Dictionary=space._navigation.floor_source(space,world,1)
	checks.same_graph_key=space._navigation._graph_key(space,world,1,a,[],{},source)==space._navigation._graph_key(space,world,1,b,[],{},source)
	space._navigation.query_graphs(space,world,1,a,[],{})
	var qa: Dictionary=space.door_passage_quote(world,a,1,door)
	var qb: Dictionary=space.door_passage_quote(world,b,1,door)
	checks.exact_proxy_quotes=qa==space.door_quote(world,a,1,door) and qb==space.door_quote(world,b,1,door)
	checks.distinct_exact_heights=qa.get("ok",false) and qb.get("ok",false) and qa.clear_height_m!=qb.clear_height_m
	# Permission calls below do not move bodies or prove actual traversal.
	var doors: Array[Dictionary]=[door]
	var swept: Rect2=space._door_rect(door,int(qa.get("span",door.span)))
	var move: Dictionary={"members":[actor.id]}
	var initial_location: Dictionary=actor.location.duplicate(true)
	var initial_used: bool=bool(door.get("used",false))
	if qa.get("ok",false) and qb.get("ok",false):
		var own: Dictionary={"kind":"door","owner_id":actor.id,"actor_id":actor.id,"staff_ids":[actor.id],"floor_id":1,"span":qa.span,"clear_height_m":qa.clear_height_m,"clear_width_m":qa.clear_width_m,"regions":[[swept.position.x,swept.position.y,swept.size.x,swept.size.y]]}
		world.facts.adaptations[door.id]=own
		space.reservation_changed(world,str(door.id))
		var larger:=HospitalMovement.MotionResult.new()
		checks.larger_exact_height_rejected=not space.movement._reserve_doors(world,b,move,swept,doors,larger) and larger.reservation_ids.has(str(door.id)) and world.facts.adaptations[door.id]==own
		var same:=HospitalMovement.MotionResult.new()
		checks.same_exact_owner_allowed=space.movement._reserve_doors(world,a,move,swept,doors,same)
		var foreign: Dictionary=own.duplicate(true)
		foreign.owner_id="foreign_owner";foreign.actor_id="foreign_owner";foreign.staff_ids=["foreign_owner"]
		world.facts.adaptations[door.id]=foreign
		space.reservation_changed(world,str(door.id))
		var denied:=HospitalMovement.MotionResult.new()
		checks.same_size_foreign_owner_rejected=not space.movement._reserve_doors(world,a,move,swept,doors,denied) and denied.reservation_ids.has(str(door.id)) and world.facts.adaptations[door.id]==foreign
		world.facts.adaptations.erase(door.id)
		space.reservation_changed(world,str(door.id))
		var released:=HospitalMovement.MotionResult.new()
		checks.released_permission_restored=space.movement._reserve_doors(world,a,move,swept,doors,released) and world.facts.adaptations.get(door.id,{}).get("actor_id","")==actor.id
		world.facts.adaptations.erase(door.id)
		space.reservation_changed(world,str(door.id))
	else:
		checks.permission_fixture_valid=false
	checks.permission_only_no_motion=actor.location==initial_location and bool(door.get("used",false))==initial_used
	# Same numerical revision on another WorldState must not borrow ownership
	# or stale geometry. Use the same space to exercise its world boundary.
	var projected:=WorldState.new(world.freeze())
	var projected_actor: Dictionary=projected.facts.actors[actor.id]
	checks.cross_world_equal=space.door_passage_quote(projected,projected_actor,1,door)==space.door_quote(projected,projected_actor,1,door)
	space._navigation.query_graphs(space,projected,1,projected_actor,[],{})
	checks.cross_world_hot_equal=space.door_passage_quote(projected,projected_actor,1,door)==space.door_quote(projected,projected_actor,1,door)
	checks.return_original_world_equal=space.door_passage_quote(world,actor,1,door)==space.door_quote(world,actor,1,door)
	space._navigation.query_graphs(space,world,1,actor,[],{})
	var before_blocks: Array=world.facts.floors.overrides["1"].blocked.duplicate(true)
	var side: Vector2=swept.position-(Vector2(0,1) if door.axis=="x" else Vector2(1,0))
	world.facts.floors.overrides["1"].blocked.append([int(side.x),int(side.y)])
	world.touch()
	var blocked_quote: Dictionary=space.door_passage_quote(world,actor,1,door)
	checks.changed_blocked_side_fails=not blocked_quote.ok and blocked_quote==space.door_quote(world,actor,1,door)
	world.facts.floors.overrides["1"].blocked=before_blocks
	world.touch()
	checks.removed_block_equal=space.door_passage_quote(world,actor,1,door)==space.door_quote(world,actor,1,door)
	world.facts.floors.height_intervals=[{"first":1,"last":1,"height_m":0.3}]
	world.touch()
	checks.changed_ceiling_fails=not space.door_passage_quote(world,actor,1,door).ok and space.door_passage_quote(world,actor,1,door)==space.door_quote(world,actor,1,door)
	space._navigation._entries.clear()
	checks.evicted_equal=space.door_passage_quote(world,actor,1,door)==space.door_quote(world,actor,1,door)
	var result: Dictionary={"ok":checks.values().all(func(value: Variant)->bool:return value==true),"checks":checks,"proxy_a":qa,"proxy_b":qb,"scope":"static fit and live reservation permission; no actual displacement tested"}
	sim.dispose()
	return result
