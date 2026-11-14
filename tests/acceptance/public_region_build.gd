extends "res://tests/acceptance/public_area_use.gd"

const BED: String = "region_build_bed"
const BED_USER: String = "region_build_bed_user"
const STORED: String = "region_build_stored"
const NONBLOCKING: String = "region_build_nonblocking"

# Independent current-design oracle. Each fixture owns a flood limited to
# three orthogonal steps; no shared component, cache, or runtime region is used.
class ReferenceAreas extends HospitalPublicAreas:
	var by_floor: Dictionary = {}

	func _candidate_regions(_definitions: Array) -> Array:
		return _regions

	func _ensure(world: WorldState, _floor: int = 0) -> void:
		_world = weakref(world)
		_revision = world.geometry_revision
		_regions.clear()
		_by_facility.clear()
		by_floor.clear()
		var allowed: Array = ["FUR06","FUR07","FUR09","FUR10","FUR11","FUR12","FUR13","FUR14","FUR15","FUR16","FUR17","FUR49","FUR50","FUR51","FUR52","AE01","AE02","AE03","RC01","RC02","RC03"]
		for id: String in world.ids("facilities"):
			var facility: Dictionary = world.facts.facilities[id]
			if facility.get("stored",false) or not facility.definition_id in allowed: continue
			var floor: int = int(facility.floor_id)
			var origin: Vector2i = Vector2i(facility.cell[0],facility.cell[1])
			var room: String = _room_at(world,floor,origin)
			if not room.is_empty() and not world.facts.rooms[room].kind in ["rest","toilet"]: continue
			var footprint: Rect2i = Rect2i(origin,Vector2i(facility.footprint[0],facility.footprint[1]))
			var visited: Dictionary = {}
			var layer: Array[Vector2i] = []
			for y: int in range(footprint.position.y,footprint.end.y):
				for x: int in range(footprint.position.x,footprint.end.x):
					var cell := Vector2i(x,y)
					visited[cell] = true
					layer.append(cell)
			var layout: Dictionary = HospitalSpace.floor_layout(world,floor)
			for _distance: int in 3:
				var next: Array[Vector2i] = []
				for source: Vector2i in layer:
					for step: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
						var target: Vector2i = source+step
						if visited.has(target) or not space.owned(world,floor,target) or room!=_room_at(world,floor,target): continue
						if _edge_blocked(layout,source,target) or _object_blocked(world,floor,target,id,layout): continue
						visited[target] = true
						next.append(target)
				layer = next
			var area: Dictionary = {"ref":{"floor_id":floor,"room_id":room,"facility_id":id,"anchor":[origin.x,origin.y]},"cells":visited,"bounds":footprint.grow(3),"facilities":[]}
			_regions.append(area)
			_by_facility[id] = area
			var index: Dictionary = by_floor.get_or_add(floor,{})
			for point: Vector2i in visited: index.get_or_add(point,[]).append(area)
		for area: Dictionary in _regions:
			for id: String in _by_facility:
				var facility: Dictionary = world.facts.facilities[id]
				if facility.floor_id!=area.ref.floor_id: continue
				if id==area.ref.facility_id or area.cells.has(Vector2i(facility.patient_cell[0],facility.patient_cell[1])):
					area.facilities.append(id)

	func _room_at(world: WorldState, floor: int, point: Vector2i) -> String:
		for room: Dictionary in world.facts.rooms.values():
			if int(room.floor_id)==floor and room.get("structure_valid",true) and [point.x,point.y] in BuildGeometry.cells(room):
				return room.id
		return ""

	func _edge_blocked(layout: Dictionary, source: Vector2i, target: Vector2i) -> bool:
		var axis: String = "x" if source.y!=target.y else "y"
		var line: int = maxi(source.y,target.y) if axis=="x" else maxi(source.x,target.x)
		var side: int = source.x if axis=="x" else source.y
		for wall: Dictionary in layout.get("wall_edges",[]):
			if axis==wall.axis and line==int(wall.line) and int(wall.low)<=side and side<int(wall.high): return true
		for door: Dictionary in layout.get("doors",[]):
			if axis!=door.axis: continue
			var door_line: int = int(door.cell[1] if axis=="x" else door.cell[0])
			var low: int = int(door.cell[0] if axis=="x" else door.cell[1])
			if line==door_line and low<=side and side<low+int(door.span): return true
		return false

	func _object_blocked(world: WorldState, floor: int, point: Vector2i, own: String, layout: Dictionary) -> bool:
		if [point.x,point.y] in layout.get("blocked",[]): return true
		for facility: Dictionary in world.facts.facilities.values():
			if facility.id==own or int(facility.floor_id)!=floor or facility.get("stored",false) or not space.content.facility_definition(facility.definition_id).get("blocks_movement",true): continue
			if BuildGeometry.rectangle(space.facility_layout(world,facility.id)).has_point(Vector2(point)): return true
		for connector: Dictionary in world.facts.connectors.values():
			if not connector.get("stored",false) and HospitalTransit.has_stop(connector,floor) and BuildGeometry.rectangle(connector).has_point(Vector2(point)): return true
		return false

func run_case(database: HospitalContent) -> Dictionary:
	_content = database
	var x: Dictionary = _build_fixture()
	var validation: String = x.world.validate(_content)
	var actual_space: HospitalSpace = HospitalSpace.new(_content)
	var reference_space: HospitalSpace = HospitalSpace.new(_content)
	var actual: HospitalPublicAreas = HospitalPublicAreas.new(actual_space)
	var reference: ReferenceAreas = ReferenceAreas.new(reference_space)
	var observations: Array = [_compare_build("cold",x.world,actual,reference)]
	var west: Dictionary = actual._by_facility.get("west_chair",{})
	var upper: Dictionary = actual._by_facility.get("upper_west_chair",{})
	var checks: Dictionary = {"valid_input":validation.is_empty()}
	checks.stored_and_private_excluded = not actual._by_facility.has(STORED) and not actual._by_facility.has(BED)
	checks.non_amenity_does_not_create_area = not actual._by_facility.has(NONBLOCKING)
	checks.distant_ground_has_no_synthetic_area = actual._cell_region(1,Vector2i(0,0)).is_empty() and actual._cell_region(1,Vector2i(95,95)).is_empty()
	checks.floors_isolated = not west.is_empty() and not upper.is_empty() and west.ref.floor_id==1 and upper.ref.floor_id==2
	observations.append(_compare_build("completed_floor_without_facilities",x.world,actual,reference,3))
	checks.empty_upper_floor_has_no_area = actual._cell_region(3,Vector2i(32,64)).is_empty() and not actual._floor_regions.has(3)
	var tick: int = x.world.sim_tick
	var quote: Dictionary = _bed_expansion(x)
	checks.real_bed_expansion_quoted = not quote.is_empty()
	if not quote.is_empty():
		x.world.facts.adaptations[BED] = quote
		x.space.reservation_changed(x.world,BED)
	var cell := Vector2i(37,70)
	checks.block_target_in_original_west_area = west.get("cells",{}).has(cell)
	x.world.facts.floors.overrides["1"].blocked.append([cell.x,cell.y])
	x.world.touch()
	observations.append(_compare_build("same_tick_geometry_and_bed_change",x.world,actual,reference))
	checks.same_tick_geometry_rebuilt = x.world.sim_tick==tick and not is_same(west,actual._by_facility.get("west_chair",{})) and actual._cell_region(1,cell).is_empty()
	checks.unaffected_floor_retains_its_projection = is_same(upper,actual._by_facility.get("upper_west_chair",{}))
	checks.expanded_input_valid = x.world.validate(_content).is_empty()
	if not quote.is_empty():
		checks.private_bed_remains_excluded_after_expansion = not actual._by_facility.has(BED) and _footprint_excluded(actual,1,x.world.facts.facilities[BED].cell,quote.footprint)
	var frozen: Dictionary = x.world.freeze()
	var restored: WorldState = WorldState.new(frozen.duplicate(true))
	var before_restore: Dictionary = actual._by_facility.get("west_chair",{})
	observations.append(_compare_build("restored_world_identity",restored,actual,reference,3))
	checks.restored_uses_exact_detached_geometry = before_restore==actual._by_facility.get("west_chair",{}) and not is_same(before_restore,actual._by_facility.get("west_chair",{}))
	checks.restoration_readonly = restored.freeze()==frozen and x.world.freeze()==frozen
	var components: Dictionary = preload("res://tests/acceptance/public_region_components.gd").new().run_case(_content)
	var ok: bool = components.ok and not checks.values().has(false) and observations.all(func(row: Dictionary)->bool:return row.ok)
	x.a.dispose()
	x.p.waiting_life = null
	x.p.environment = null
	x.e.waiting_life = null
	x.l.environment = null
	x.l.visitors = null
	x.c.recruitment = null
	return {"ok":ok,"validation":validation,"checks":checks,"observations":observations,"canonical_component_calculations":components}

func _build_fixture() -> Dictionary:
	var x: Dictionary = _fixture()
	HospitalFactory._add_room(x.world,{"id":"west","type":"rest","anchor":[34,66],"size":[10,12],"door":{"definition_id":"DR04","offset":3}},_content)
	HospitalFactory._add_room(x.world,{"id":"east","type":"ward","anchor":[48,66],"size":[10,12],"door":{"definition_id":"DR04","offset":3}},_content)
	_facility(x,"west_chair","FUR06",[36,68],"west")
	_facility(x,"east_chair","FUR09",[49,82])
	_facility(x,BED,"EQ05",[51,69],"east")
	_facility(x,STORED,"FUR09",[41,70],"west")
	x.world.facts.facilities[STORED].stored = true
	_facility(x,NONBLOCKING,"FUR23",[40,70],"west")
	x.world.facts.actors[BED_USER] = {"id":BED_USER,"name":BED_USER,"species_id":"S49","location":{"kind":"floor","floor_id":1,"cell":[58,88],"height_m":0.0},"facing":0.0,"posture":"standing"}
	# Legal calculation boundary: all ground plots are owned, while completed
	# upper modules exist only above the original plot. No movement is skipped.
	x.world.facts.floors.overrides["1"].plots.clear()
	for y: int in 3:
		for column: int in 3: x.world.facts.floors.overrides["1"].plots.append([column,y])
	HospitalFloors.new(_content,x.space).ensure(x.world)
	x.world.facts.floors.completed_top_floor["1:2"] = 3
	var upper: Dictionary = x.world.facts.floors.overrides["1"].duplicate(true)
	upper.erase("plots")
	for door: Dictionary in upper.doors:
		door.id = "upper_"+str(door.id)
		door.room_id = "upper_"+str(door.room_id)
	x.world.facts.floors.overrides["2"] = upper
	for id: String in x.world.ids("rooms"):
		var room: Dictionary = x.world.facts.rooms[id].duplicate(true)
		room.id = "upper_"+id
		room.floor_id = 2
		x.world.facts.rooms[room.id] = room
	for id: String in x.world.ids("facilities"):
		var facility: Dictionary = x.world.facts.facilities[id].duplicate(true)
		facility.id = "upper_"+id
		facility.floor_id = 2
		if not str(facility.get("room_id","")).is_empty(): facility.room_id = "upper_"+str(facility.room_id)
		x.world.facts.facilities[facility.id] = facility
	x.m.ensure(x.world)
	x.world.touch()
	return x

func _bed_expansion(x: Dictionary) -> Dictionary:
	for species: Dictionary in _content.catalog.species:
		x.world.facts.actors[BED_USER].species_id = species.id
		var quote: Dictionary = x.space.facility_geometry_quote(x.world,BED,BED_USER)
		if not quote.ok or quote.footprint==x.world.facts.facilities[BED].footprint: continue
		quote.erase("ok")
		quote.owner_id = BED_USER
		return quote
	return {}

func _compare_build(label: String, world: WorldState, actual: HospitalPublicAreas, reference: HospitalPublicAreas, requested_floor: int = 0) -> Dictionary:
	var before: Dictionary = world.freeze()
	actual._ensure(world,requested_floor)
	reference._ensure(world,requested_floor)
	var expected: Dictionary = _snapshot(reference)
	var observed: Dictionary = _snapshot(actual)
	var equal: bool = observed==expected
	var first_difference: Dictionary = {}
	if not equal:
		for field: String in expected:
			if expected[field]!=observed.get(field): first_difference = {"field":field}; break
	return {"ok":equal and before==world.freeze(),"boundary":label,"all_region_cells_anchors_bounds_and_facility_maps_equal":equal,"regions":actual._regions.size(),"cells":observed.cells.size(),"facilities":actual._by_facility.size(),"world_and_rng_unchanged":before==world.freeze(),"first_difference":first_difference,"internal_representation":"Cell order and private fingerprints are not public semantics; exact full region memberships and live cell identity are checked separately."}

func _snapshot(areas: HospitalPublicAreas) -> Dictionary:
	var regions: Dictionary = {}
	for region: Dictionary in areas._regions:
		var occupied: Array = region.cells.keys()
		occupied.sort_custom(func(a: Vector2i,b: Vector2i)->bool:return a.y<b.y or a.y==b.y and a.x<b.x)
		var members: Array = region.facilities.duplicate()
		members.sort()
		regions[region.ref.facility_id] = {"ref":region.ref.duplicate(true),"cells":occupied,"facilities":members,"bounds":region.bounds}
	var cells: Dictionary = {}
	var indexed: Dictionary = (areas as ReferenceAreas).by_floor if areas is ReferenceAreas else areas._facility_areas.by_floor
	for floor: int in indexed:
		for point: Vector2i in indexed[floor]:
			var rows: Array = indexed[floor][point]
			var ids: Array = rows.map(func(area: Dictionary)->String:return str(area.ref.facility_id))
			ids.sort()
			cells[Vector3i(point.x,point.y,floor)] = ids
			if not areas is ReferenceAreas and not is_same(areas._cell_region(floor,point),rows[0]):
				cells[Vector3i(point.x,point.y,floor)] = ["invalid current area"]
	var facilities: Dictionary = {}
	for id: String in areas._by_facility: facilities[id] = areas._by_facility[id].ref.duplicate(true)
	return {"regions":regions,"cells":cells,"facilities":facilities}

func _footprint_excluded(areas: HospitalPublicAreas, floor_id: int, cell: Array, footprint: Array) -> bool:
	for y: int in range(int(cell[1]),int(cell[1])+int(footprint[1])):
		for x: int in range(int(cell[0]),int(cell[0])+int(footprint[0])):
			if not areas._cell_region(floor_id,Vector2i(x,y)).is_empty(): return false
	return true
