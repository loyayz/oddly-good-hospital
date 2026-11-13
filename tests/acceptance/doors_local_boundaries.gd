extends "res://tests/acceptance/ordinary_door_passage.gd"
var rows: Array=[]
func _ids(values: Array) -> Array:
	var result: Array=[]
	for value: Dictionary in values: result.append(value.id)
	return result
func _cache(space: HospitalSpace) -> Dictionary:
	var nav: NavigationCache=space._navigation
	var sources: Array=[]
	for key: String in nav._sources:
		var entry: Dictionary=nav._sources[key]
		sources.append({"key":key,"revision":entry.revision,"used":entry.used,"version":entry.static_version,"floor":entry.floor_id})
	var geometries: Array=[]
	for key: String in nav._floor_geometries:
		var entry: Dictionary=nav._floor_geometries[key]
		geometries.append({"key":key,"used":entry.used,"charge":entry.charge})
	return {"used":nav._used,"charged":nav._charged,"query_charged":nav._query_charged,"source_charged":nav._source_charged,"floor_charged":nav._floor_charged,"source_key":nav._source_key,"source_key_world":nav._source_key_world_id,"source_key_floor":nav._source_key_floor_id,"sources":sources,"geometries":geometries,"query_counts":space.query_counts.duplicate(true)}
func _compare(world: WorldState, actor: Dictionary, swept: Rect2, members: Array, label: String) -> bool:
	var original: HospitalSpace=preload("res://tests/acceptance/doors_original_space.gd").new(suite.content)
	var candidate: HospitalSpace=HospitalSpace.new(suite.content)
	var before: Dictionary=world.freeze()
	var passed: bool=true
	for phase: String in ["cold","warm","borrowed"]:
		var ga: FloorStaticGeometry=null
		var gb: FloorStaticGeometry=null
		if phase=="borrowed":
			ga=original._navigation.floor_geometry(original,world,int(actor.location.floor_id))
			gb=candidate._navigation.floor_geometry(candidate,world,int(actor.location.floor_id))
		var cache_before_a: Dictionary=_cache(original)
		var cache_before_b: Dictionary=_cache(candidate)
		var a: Array[Dictionary]=original.movement_doors(world,actor,swept,members,0,ga)
		var b: Array[Dictionary]=candidate.movement_doors(world,actor,swept,members,0,gb)
		var identities: bool=a==b and a.size()==b.size()
		if identities:
			for i: int in a.size(): identities=identities and is_same(a[i],b[i])
		var ca: Dictionary=_cache(original)
		var cb: Dictionary=_cache(candidate)
		var valid: bool=identities and ca==cb and cache_before_a==cache_before_b and before==world.freeze()
		if phase=="borrowed": valid=valid and ca.used==cache_before_a.used and cb.used==cache_before_b.used
		rows.append({"case":label,"phase":phase,"ok":valid,"ids":_ids(a),"same_values_order_and_identity":identities,"same_cache_counts_charge_keys_lru":ca==cb,"borrowed_no_nav_touch":ca.used==cache_before_a.used if phase=="borrowed" else null,"world_unchanged":before==world.freeze(),"cache":ca})
		passed=passed and valid
	return passed
func run_boundaries(content: HospitalContent) -> Dictionary:
	suite.content=content
	var f: Dictionary=_setup(true)
	var sim: HospitalSimulation=f.sim
	if not f.built or f.door.is_empty(): sim.dispose();return {"ok":false,"reason":"fixture room build failed"}
	var world: WorldState=sim.world
	var build: CommandResult=suite._command(sim,"build_room",suite._room("reach_second",[34,70],[8,8]))
	suite._add_actor(sim,"reach_big","S59",[56,84])
	suite._add_actor(sim,"reach_small","S49",[40,84])
	var big: Dictionary=world.facts.actors.reach_big
	var small: Dictionary=world.facts.actors.reach_small
	var checks: Dictionary={"second_room":build.accepted,"valid_world":world.validate(content).is_empty(),"different_clearance":sim.space.clearance(big)>sim.space.clearance(small)}
	var expected: Array=_ids(world.facts.floors.overrides["1"].doors)
	checks.multiple_doors=expected.size()>=2
	checks.all_doors_order=_compare(world,small,Rect2(0,0,96,96),[small.id,big.id],"multi_door_order")
	var actual_order: Array=_ids(sim.space.movement_doors(world,small,Rect2(0,0,96,96),[small.id,big.id]))
	checks.original_build_order=actual_order==expected
	var geometry: FloorStaticGeometry=sim.space._navigation.floor_geometry(sim.space,world,1)
	var found: bool=false
	for dx: int in range(-9,10):
		if found: break
		for dy: int in range(-9,10):
			var rect: Rect2=Rect2(float(f.door.cell[0])+dx,float(f.door.cell[1])+dy,0.25,0.25)
			var narrow: Array=geometry.door_index.candidates(1,rect.grow(float(sim.space.clearance(small))+1.0))
			var broad: Array=geometry.door_index.candidates(1,rect.grow(float(sim.space.clearance(big))+1.0))
			if narrow.has(f.door.id) or not broad.has(f.door.id): continue
			found=true
			checks.member_reach=_compare(world,small,rect,[small.id,big.id],"multi_member_reach") and _compare(world,small,rect,[big.id,small.id],"reversed_members")
			checks.member_actual_effect=not _ids(sim.space.movement_doors(world,small,rect,[small.id])).has(f.door.id) and _ids(sim.space.movement_doors(world,small,rect,[small.id,big.id])).has(f.door.id)
			break
	checks.member_boundary_found=found
	sim.dispose()
	var reservation: Dictionary=_reservation_only()
	checks.reservation_only=reservation.ok
	return {"ok":not checks.values().has(false),"checks":checks,"rows":rows,"reservation":reservation,"scope":"Existing ordinary_door_passage/door_reach_same_instance fixture construction; calculated candidate-query boundaries, NOT actual movement/clinical crossing. Live reservation acquired through production _reserve_doors; no reservation facts injected. Cache snapshots compare independent services on same world, ordered scalar resident/LRU metadata plus query counts; not byte-identity of separate cache objects."}
func _reservation_only() -> Dictionary:
	# Copy the existing giant convoy_door_lifecycle journey setup exactly;
	# advance its actual requested movement until production acquires the door.
	var sim: HospitalSimulation=suite._fixture()
	var world: WorldState=sim.world
	var land: CommandResult=suite._command(sim,"build_land",{"plot":[1,1],"floor_id":1})
	var build: CommandResult=suite._command(sim,"build_room",suite._room("room",[42,62],[18,16]))
	suite._add_actor(sim,"head","S49",[45,81])
	suite._add_actor(sim,"tail","S59",[44,90])
	var doors: Array=suite._doors(world,"room")
	if not land.accepted or not build.accepted or doors.is_empty():
		sim.dispose();return {"ok":false,"reason":"giant fixture build failed"}
	var door: Dictionary=doors[0]
	var actor: Dictionary=world.facts.actors.head
	var pos: Vector2=Vector2(float(door.cell[0]),float(door.cell[1]))
	var reason: String=sim.space.request_group_move(world,"head",["head","tail"],{},1,[45,65])
	var validation: String=world.validate(suite.content)
	var acquired: bool=false
	var elapsed_steps: int=0
	if reason.is_empty() and validation.is_empty():
		for step: int in 700:
			suite._movement_tick(sim)
			elapsed_steps+=1
			validation=world.validate(suite.content)
			if not validation.is_empty(): break
			if world.facts.adaptations.has(door.id): acquired=true;break
	var reservation: Dictionary=world.facts.adaptations.get(door.id,{}).duplicate(true)
	var geometry: FloorStaticGeometry=sim.space._navigation.floor_geometry(sim.space,world,1)
	var found: bool=false
	var passed: bool=false
	var query: String=""
	if acquired:
		for dx: int in range(-48,49):
			if found: break
			for dy: int in range(-48,49):
				var rect: Rect2=Rect2(pos+Vector2(dx,dy)*0.25,Vector2(0.1,0.1))
				var indexed: Array=geometry.door_index.candidates(1,rect.grow(float(sim.space.clearance(actor))+1.0))
				if indexed.has(door.id): continue
				var reserved: bool=false
				for region: Dictionary in sim.space._reservation_regions(world,1,rect):
					if region.reservation.kind=="door" and region.reservation_id==door.id: reserved=true
				if not reserved: continue
				found=true;query=str(rect)
				passed=_compare(world,actor,rect,[actor.id],"live_reservation_only_added_id") and _ids(sim.space.movement_doors(world,actor,rect,[actor.id])).has(door.id)
				break
	var result: Dictionary={"ok":reason.is_empty() and validation.is_empty() and acquired and found and passed,"request_reason":reason,"validation":validation,"real_movement_ticks":elapsed_steps,"production_acquired":acquired,"actual_reservation_only_boundary_found":found,"differential_passed":passed,"query":query,"door":door.id,"reservation":reservation,"missing":[] if found else ["reservation_only_new_id"],"scope":"Existing giant convoy fixture natural request_group_move and movement_tick to production reservation; subsequent query rectangle is a calculation input, not actor crossing proof."}
	sim.dispose();return result
