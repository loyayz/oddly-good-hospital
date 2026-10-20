extends RefCounted

const TRAVELLER: String = "static_version_traveller"
const OWNER: String = "static_version_owner"
const FACILITY: String = "static_version_facility"
const BED: String = "static_version_nursing_bed"
const BED_USER: String = "static_version_bed_user"

func run() -> Dictionary:
	var content: HospitalContent = HospitalContent.new()
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"静态路线版本",false,content)
	var footprint: Array = content.facility_definition("M37").footprint.duplicate()
	HospitalFactory._add_facility(world,{"id":FACILITY,"definition_id":"M37","anchor":[44,76],"size":footprint,"room_id":null},content)
	HospitalFactory._add_room(world,{"id":"static_version_ward","type":"ward","anchor":[50,66],"size":[12,12],"door":{"definition_id":"DR01","offset":4}},content)
	HospitalFactory._add_facility(world,{"id":BED,"definition_id":"EQ05","anchor":[54,69],"size":content.facility_definition("EQ05").footprint.duplicate(),"room_id":"static_version_ward"},content)
	var goal: Array = world.facts.facilities[FACILITY].patient_cell.duplicate()
	world.facts.actors[OWNER] = _actor(OWNER,[35,86])
	world.facts.actors[TRAVELLER] = _actor(TRAVELLER,[int(goal[0])-1,int(goal[1])])
	world.facts.actors[BED_USER] = _actor(BED_USER,[56,88])
	world.touch()
	var space: HospitalSpace = HospitalSpace.new(content)
	var navigation: NavigationCache = space._navigation
	var actor: Dictionary = world.facts.actors[TRAVELLER]
	space._ensure_actor_index(world)
	var route: Dictionary = space.route(world,TRAVELLER,1,goal)
	if not route.ok: return {"ok":false,"route":route}
	var movement: Dictionary = {"request_sequence":1,"cursor":0,"path":route.path,"members":[TRAVELLER],"offsets":{}}
	var checks: Dictionary = {}
	checks.initial_route = space.movement._active_route_clear(world,actor,movement,{})
	var initial: int = navigation.floor_static_version(space,world,1)
	var full_before: int = navigation.floor_version(space,world,1)
	var counted: int = int(space.query_counts.route_revalidations)
	var reserved: String = space.reserve_facility(world,FACILITY,OWNER,OWNER)
	if not reserved.is_empty(): return {"ok":false,"reservation":reserved}
	checks.occupancy_tag_unchanged = navigation.floor_static_version(space,world,1)==initial and navigation.floor_version(space,world,1)!=full_before
	checks.occupancy_does_not_rescan_path = space.movement._active_route_clear(world,actor,movement,{}) and int(space.query_counts.route_revalidations)==counted
	checks.new_reservation_blocks_actual_sweep = not _local_clear(space,world,goal)
	space.grant_facility_access(world,FACILITY,TRAVELLER)
	checks.permission_tag_unchanged = navigation.floor_static_version(space,world,1)==initial
	checks.permission_does_not_rescan_path = space.movement._active_route_clear(world,actor,movement,{}) and int(space.query_counts.route_revalidations)==counted
	checks.permission_opens_actual_sweep = _local_clear(space,world,goal)
	# Region edits are dynamic. They still update the local spatial index.
	world.facts.adaptations[FACILITY].staff_ids.erase(TRAVELLER)
	space.reservation_changed(world,FACILITY)
	navigation.invalidate(world,1)
	checks.revoked_permission_immediate = navigation.floor_static_version(space,world,1)==initial and not _local_clear(space,world,goal)
	space.grant_facility_access(world,FACILITY,TRAVELLER)
	var projection_checks: Dictionary = _projections(space,world,goal,initial)
	checks.merge(projection_checks)
	# A real structural obstruction must invalidate the active route before it
	# can advance. Restoring geometry must agree with a cold clearance query.
	world.facts.floors.overrides["1"].blocked.append(goal.duplicate())
	world.touch()
	checks.blocked_invalidates = navigation.floor_static_version(space,world,1)!=initial and not space.movement._active_route_clear(world,actor,movement,{}) and int(space.query_counts.route_revalidations)>counted
	world.facts.floors.overrides["1"].blocked.erase(goal)
	world.touch()
	checks.blocked_restore_safe = space.movement._active_route_clear(world,actor,movement,{}) and _cold_goal_clear(content,world,goal)
	var before_wall: int = navigation.floor_static_version(space,world,1)
	HospitalFactory._add_room(world,{"id":"static_version_room","type":"gp","anchor":[35,66],"size":[4,4],"door":{"definition_id":"DR01","offset":1}},content)
	world.touch()
	checks.wall_invalidates = navigation.floor_static_version(space,world,1)!=before_wall and space.movement._active_route_clear(world,actor,movement,{}) and _cold_goal_clear(content,world,goal)
	# A quoted nursing-bed expansion is a real change to solid geometry. Its
	# body compatibility and complete fit are supplied by the actual game quote.
	var before_footprint: int = navigation.floor_static_version(space,world,1)
	var expanded_bed: Dictionary = _expanded_bed(space,world)
	checks.legal_expanded_bed_quote = not expanded_bed.is_empty()
	if not expanded_bed.is_empty():
		world.facts.adaptations[BED] = expanded_bed
		space.reservation_changed(world,BED)
	world.touch()
	checks.footprint_invalidates = navigation.floor_static_version(space,world,1)!=before_footprint
	checks.footprint_cold_equal = space.navigation.structural_clearance(world,actor,1).reason(Vector2i(int(goal[0]),int(goal[1])))==RouteClearance.new(HospitalSpace.new(content),world,actor,1,[],{},false).reason(Vector2i(int(goal[0]),int(goal[1])))
	# Graph eviction may give the source a fresh tag; it must never keep a
	# stale clearance result. No permanent floor-snapshot cache is required.
	navigation._trim(0)
	checks.graphs_evicted = navigation._entries.is_empty()
	var rebuilt: int = navigation.floor_static_version(space,world,1)
	checks.evicted_rebuild_safe = rebuilt>0 and space.movement._active_route_clear(world,actor,movement,{})==_cold_path_clear(content,world,actor,movement.path)
	var restored: WorldState = WorldState.new(world.freeze())
	var restored_actor: Dictionary = restored.facts.actors[TRAVELLER]
	var restored_source: Dictionary = navigation.floor_source(space,restored,1)
	var expected: Dictionary = RouteClearance.capture_source(HospitalSpace.new(content),restored,1)
	checks.restored_world_source = restored_source==expected and navigation.floor_static_version(space,restored,1)>0
	checks.restored_cold_equal = space.navigation.structural_clearance(restored,restored_actor,1).reason(Vector2i(int(goal[0]),int(goal[1])))==RouteClearance.new(HospitalSpace.new(content),restored,restored_actor,1,[],{},false).reason(Vector2i(int(goal[0]),int(goal[1])))
	var temporary: WorldState = WorldState.new(world.freeze())
	navigation.floor_static_version(space,temporary,1)
	var temporary_key: String = str(temporary.get_instance_id())+":1"
	var weak: WeakRef = weakref(temporary)
	temporary = null
	navigation._prune_sources(1)
	checks.dead_world_pruned = weak.get_ref()==null and not navigation._sources.has(temporary_key)
	checks.merge(_body_identity_checks(content))
	var passed: bool = true
	for accepted: bool in checks.values(): passed = passed and accepted
	return {"ok":passed,"checks":checks,"route_checks":space.query_counts.route_checks,"route_revalidations":space.query_counts.route_revalidations}

func _body_identity_checks(content: HospitalContent) -> Dictionary:
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"路线身体依据",false,content)
	HospitalFactory._add_room(world,{"id":"identity_ward","type":"ward","anchor":[50,66],"size":[12,12],"door":{"definition_id":"DR01","offset":4}},content)
	HospitalFactory._add_facility(world,{"id":BED,"definition_id":"EQ05","anchor":[54,69],"size":content.facility_definition("EQ05").footprint.duplicate(),"room_id":"identity_ward"},content)
	world.facts.actors[TRAVELLER] = _actor(TRAVELLER,[40,86])
	world.facts.actors[OWNER] = _actor(OWNER,[40,87])
	world.touch()
	var space: HospitalSpace = HospitalSpace.new(content)
	var actor: Dictionary = world.facts.actors[TRAVELLER]
	var route: Dictionary = space.route(world,TRAVELLER,1,[44,86])
	if not route.ok: return {"body_identity_route_legal":false}
	var movement: Dictionary = {"request_sequence":1,"cursor":0,"path":route.path,"members":[TRAVELLER],"offsets":{}}
	space.sync_actor(world,TRAVELLER)
	var checks: Dictionary = {}
	checks.body_identity_initial_proof = space.movement._active_route_clear(world,actor,movement,{}) and int(space.query_counts.get("route_revalidation_unvalidated",0))==1 and int(space.query_counts.get("route_revalidation_body",0))==0
	var counted: int = int(space.query_counts.route_revalidations)
	var roundtrips: bool = true
	for attempt: int in 4:
		var projected: WorldState = WorldState.new(world.freeze())
		# Real quotation projections may also carry a different proposed body.
		# Both the unchanged and altered projection rebuild disposable shapes.
		if attempt%2==1: projected.facts.actors[TRAVELLER].species_id = "S13"
		space.prepare_projection(world,projected,[],[1])
		space.sync_actor(projected,TRAVELLER)
		roundtrips = roundtrips and space._indexed_world==projected
		space.sync_actor(world,TRAVELLER)
		var clear: bool = space.movement._active_route_clear(world,actor,movement,{})
		roundtrips = roundtrips and clear and space._indexed_world==world and int(space.query_counts.route_revalidations)==counted
	checks.actual_projection_roundtrips_reuse_body_proof = roundtrips
	var before_turn: Rect2 = space.body_rectangle(actor)
	actor.facing = PI*0.25
	space.sync_actor(world,TRAVELLER)
	checks.facing_keeps_static_proof = space.movement._active_route_clear(world,actor,movement,{}) and int(space.query_counts.route_revalidations)==counted
	checks.facing_still_changes_exact_collision_shape = space.body_rectangle(actor)!=before_turn
	actor.species_id = "S13"
	space.sync_actor(world,TRAVELLER)
	checks.real_species_revalidates = _revalidation_matches_cold(space,world,actor,movement,"body")
	actor.body_binding_id = "B_S13_D09_M09"
	space.sync_actor(world,TRAVELLER)
	checks.real_binding_revalidates = _revalidation_matches_cold(space,world,actor,movement,"body")
	actor.species_id = "S08"
	actor.erase("body_binding_id")
	space.sync_actor(world,TRAVELLER)
	checks.larger_species_revalidates = _revalidation_matches_cold(space,world,actor,movement,"body")
	actor.body_binding_id = "B_S08_D04_M04"
	space.sync_actor(world,TRAVELLER)
	checks.symptom_dimensions_revalidate = _revalidation_matches_cold(space,world,actor,movement,"body")
	actor.species_id = "S49"
	actor.erase("body_binding_id")
	space.sync_actor(world,TRAVELLER)
	checks.original_body_revalidates = _revalidation_matches_cold(space,world,actor,movement,"body")
	movement.members = [TRAVELLER,OWNER]
	movement.offsets = {TRAVELLER:[0,0],OWNER:[0,1]}
	checks.real_members_revalidate = _revalidation_matches_cold(space,world,actor,movement,"formation")
	world.facts.actors[OWNER].species_id = "S13"
	space.sync_actor(world,OWNER)
	checks.member_body_revalidates = _revalidation_matches_cold(space,world,actor,movement,"body")
	movement.offsets[OWNER] = [0,2]
	world.facts.actors[OWNER].location.cell = [40,88]
	space.sync_actor(world,OWNER)
	checks.real_offsets_revalidate = _revalidation_matches_cold(space,world,actor,movement,"formation")
	# This is a supported-pose boundary input for checking an existing proof,
	# not a simulated arrival. A stale path must agree with a cold rejection.
	var reservation: String = space.reserve_facility(world,BED,TRAVELLER,TRAVELLER)
	var original_location: Dictionary = actor.location.duplicate(true)
	actor.posture = "lying"
	actor.support_facility_id = BED
	actor.location = space.support_location(world,actor,world.facts.facilities[BED])
	world.touch()
	space.sync_actor(world,TRAVELLER)
	checks.real_supported_posture_revalidates = reservation.is_empty() and _revalidation_matches_cold(space,world,actor,movement,"body")
	# Restore the independent boundary input before checking geometry changes.
	actor.posture = "standing"
	actor.erase("support_facility_id")
	actor.location = original_location
	world.touch()
	space.sync_actor(world,TRAVELLER)
	space.movement._active_route_clear(world,actor,movement,{})
	world.facts.floors.overrides["1"].blocked.append([42,86])
	world.touch()
	checks.real_geometry_revalidates = _revalidation_matches_cold(space,world,actor,movement,"floor")
	return checks

func _revalidation_matches_cold(space: HospitalSpace, world: WorldState, actor: Dictionary, movement: Dictionary, reason: String) -> bool:
	var count: int = int(space.query_counts.route_revalidations)
	var key: String = "route_revalidation_"+reason
	var causes: int = int(space.query_counts.get(key,0))
	var actual: bool = space.movement._active_route_clear(world,actor,movement,{})
	var expected: bool = _cold_path_clear(space.content,world,actor,movement.path,movement.members,movement.offsets)
	return actual==expected and int(space.query_counts.route_revalidations)==count+1 and int(space.query_counts.get(key,0))==causes+1

func _projections(space: HospitalSpace, world: WorldState, goal: Array, original_version: int) -> Dictionary:
	var navigation: NavigationCache = space._navigation
	# Keep the original static graph resident so inheritance can borrow it.
	navigation.graph(space,world,1,world.facts.actors[TRAVELLER],[],{})
	var facts: Dictionary = world.freeze()
	facts.adaptations[FACILITY].staff_ids.erase(TRAVELLER)
	var projected: WorldState = WorldState.new(facts)
	navigation.inherit_projection(space,world,projected,[FACILITY])
	var same_tag: bool = navigation.floor_static_version(space,projected,1)==original_version
	var original_query: RouteClearance = navigation.clearance(space,world,1,world.facts.actors[TRAVELLER])
	var projected_query: RouteClearance = navigation.clearance(space,projected,1,projected.facts.actors[TRAVELLER])
	var point: Vector2i = Vector2i(int(goal[0]),int(goal[1]))
	var isolated: bool = original_query.reservation_reason(point).is_empty() and not projected_query.reservation_reason(point).is_empty() and world.facts.adaptations[FACILITY].staff_ids.has(TRAVELLER)
	var expanded: WorldState = WorldState.new(projected.freeze())
	var quote: Dictionary = _expanded_bed(space,expanded)
	if not quote.is_empty(): expanded.facts.adaptations[BED] = quote
	expanded.touch()
	navigation.inherit_projection(space,projected,expanded,[BED])
	var expanded_source: Dictionary = navigation.floor_source(space,expanded,1)
	return {"permission_projection_shares_static_tag":same_tag,"projection_permissions_isolated":isolated,"expanded_projection_changes_tag":not quote.is_empty() and navigation.floor_static_version(space,expanded,1)!=original_version and expanded_source.facilities[BED].footprint==quote.footprint,"original_static_tag_preserved":navigation.floor_static_version(space,world,1)==original_version}

func _expanded_bed(space: HospitalSpace, world: WorldState) -> Dictionary:
	for species: Dictionary in space.content.catalog.species:
		world.facts.actors[BED_USER].species_id = species.id
		var quote: Dictionary = space.facility_geometry_quote(world,BED,BED_USER)
		if quote.ok and quote.get("footprint",[])!=world.facts.facilities[BED].footprint:
			quote.erase("ok")
			quote.owner_id = BED_USER
			return quote
	return {}

func _local_clear(space: HospitalSpace, world: WorldState, goal: Array) -> bool:
	space._ensure_actor_index(world)
	var actor: Dictionary = world.facts.actors[TRAVELLER]
	var sweep: BodyIndex.Record = space._actor_index.record(TRAVELLER)
	sweep.sweep_from = sweep.rect
	sweep.sweep_to = space._actor_rect(actor,Vector2(float(goal[0]),float(goal[1])))
	var records: Array[BodyIndex.Record] = [sweep]
	return space.movement._movement_clear(world,TRAVELLER,1,sweep.sweep_from.merge(sweep.sweep_to),records,[TRAVELLER])

func _cold_goal_clear(content: HospitalContent, world: WorldState, goal: Array) -> bool:
	return RouteClearance.new(HospitalSpace.new(content),world,world.facts.actors[TRAVELLER],1,[],{},false).reason(Vector2i(int(goal[0]),int(goal[1]))).is_empty()

func _cold_path_clear(content: HospitalContent, world: WorldState, actor: Dictionary, path: Array, members: Array = [], offsets: Dictionary = {}) -> bool:
	var clearance: RouteClearance = RouteClearance.new(HospitalSpace.new(content),world,actor,1,members,offsets,false)
	var current: Vector2 = Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))
	for segment: Dictionary in path:
		var target: Vector2 = Vector2(float(segment.cell[0]),float(segment.cell[1]))
		if not clearance.sweep_reason(current,target).is_empty(): return false
		current = target
	return true

func _actor(id: String, cell: Array) -> Dictionary:
	return {"id":id,"name":id,"species_id":"S49","location":{"kind":"floor","floor_id":1,"cell":cell.duplicate(),"height_m":0.0},"facing":0.0,"posture":"standing"}
