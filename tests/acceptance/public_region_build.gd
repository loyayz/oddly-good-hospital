extends "res://tests/acceptance/public_area_use.gd"

const BED: String = "region_build_bed"
const BED_USER: String = "region_build_bed_user"
const STORED: String = "region_build_stored"
const NONBLOCKING: String = "region_build_nonblocking"

class LayoutCounts extends HospitalSpace:
	var layouts: int = 0
	func facility_layout(world: WorldState, facility_id: String) -> Dictionary:
		layouts += 1
		return super.facility_layout(world,facility_id)

# Frozen 284efc9 traversal is a compatibility oracle for derived identity and
# order, not a definition of gameplay. The independent assertions below also
# check fixed obstacles, stored/nonblocking facilities and a real bed quote.
class ReferenceAreas extends HospitalPublicAreas:
	func _ensure(world: WorldState, requested_floor: int = 0) -> void:
		var current: bool = _world!=null and _world.get_ref()==world and _revision==world.geometry_revision
		if current and (requested_floor==0 or _derived_floors.has(requested_floor)): return
		var floors: Dictionary = {}
		if not current:
			_world = weakref(world)
			_revision = world.geometry_revision
			_regions.clear()
			_by_cell.clear()
			_by_facility.clear()
			_derived_floors.clear()
			_wait_geometry = {}
			_geometry_fits.clear()
			_entry_geometry.clear()
			for floor_key: String in world.facts.floors.overrides: floors[int(floor_key)] = true
			for room: Dictionary in world.facts.rooms.values(): floors[int(room.floor_id)] = true
			for facility: Dictionary in world.facts.facilities.values(): floors[int(facility.floor_id)] = true
		if requested_floor>0: floors[requested_floor] = true
		for floor_id: int in floors:
			if _derived_floors.has(floor_id) or HospitalSpace.floor_plots(world,floor_id).is_empty(): continue
			_derived_floors[floor_id] = true
			_wait_geometry = {}
			var zones: Dictionary = {}
			for plot: Array in HospitalSpace.floor_plots(world,floor_id):
				for y: int in range(int(plot[1])*32,(int(plot[1])+1)*32):
					for x: int in range(int(plot[0])*32,(int(plot[0])+1)*32): zones[Vector2i(x,y)] = ""
			for room_id: String in world.ids("rooms"):
				var room: Dictionary = world.facts.rooms[room_id]
				if int(room.floor_id)!=floor_id: continue
				for cell: Array in BuildGeometry.cells(room): zones[Vector2i(int(cell[0]),int(cell[1]))] = room_id
			var free: Dictionary = zones.duplicate()
			for cell: Array in HospitalSpace.floor_layout(world,floor_id).get("blocked",[]): free.erase(Vector2i(int(cell[0]),int(cell[1])))
			for collection: String in ["facilities","connectors"]:
				for record: Dictionary in world.facts[collection].values():
					if (int(record.floor_id)!=floor_id if collection=="facilities" else not HospitalTransit.has_stop(record,floor_id)) or record.get("stored",false): continue
					if collection=="facilities" and not space.content.facility_definition(record.definition_id).get("blocks_movement",true): continue
					var layout: Dictionary = space.facility_layout(world,record.id) if collection=="facilities" else record
					for y: int in range(int(layout.cell[1]),int(layout.cell[1])+int(layout.footprint[1])):
						for x: int in range(int(layout.cell[0]),int(layout.cell[0])+int(layout.footprint[0])): free.erase(Vector2i(x,y))
			var ordered: Array = free.keys()
			ordered.sort_custom(func(a: Vector2i,b: Vector2i)->bool: return a.y<b.y or a.y==b.y and a.x<b.x)
			var seen: Dictionary = {}
			for start: Vector2i in ordered:
				if seen.has(start): continue
				var cells: Dictionary = {start:true}
				var bounds: Rect2i = Rect2i(start,Vector2i.ONE)
				var pending: Array[Vector2i] = [start]
				seen[start] = true
				var cursor: int = 0
				while cursor<pending.size():
					var point: Vector2i = pending[cursor]
					cursor += 1
					for direction: Vector2i in BuildGeometry.DIRECTIONS:
						var next: Vector2i = point+direction
						if seen.has(next) or not free.has(next) or zones[next]!=zones[start]: continue
						seen[next] = true
						cells[next] = true
						bounds = bounds.merge(Rect2i(next,Vector2i.ONE))
						pending.append(next)
				var geometry: String = JSON.stringify(pending,"",true,true).sha256_text()
				var region: Dictionary = {"ref":{"floor_id":floor_id,"room_id":zones[start],"anchor":[start.x,start.y]},"cells":cells,"facilities":[],"bounds":bounds,"geometry":geometry}
				_regions.append(region)
				for point: Vector2i in cells: _by_cell[_key(floor_id,point)] = region
			for id: String in world.ids("facilities"):
				var facility: Dictionary = world.facts.facilities[id]
				if int(facility.floor_id)!=floor_id or facility.get("stored",false): continue
				var layout: Dictionary = space.facility_layout(world,id)
				var point: Vector2i = Vector2i(int(layout.patient_cell[0]),int(layout.patient_cell[1]))
				var region: Dictionary = _by_cell.get(_key(floor_id,point),{})
				if not region.is_empty():
					region.facilities.append(id)
					_by_facility[id] = region

func run_case(database: HospitalContent) -> Dictionary:
	_content = database
	var x: Dictionary = _build_fixture()
	var validation: String = x.world.validate(_content)
	var actual_space: LayoutCounts = LayoutCounts.new(_content)
	var reference_space: LayoutCounts = LayoutCounts.new(_content)
	var actual: HospitalPublicAreas = HospitalPublicAreas.new(actual_space)
	var reference: ReferenceAreas = ReferenceAreas.new(reference_space)
	var observations: Array = [_compare_build("cold",x.world,actual,reference)]
	var expected_layouts: int = 0
	for facility: Dictionary in x.world.facts.facilities.values():
		if not facility.get("stored",false): expected_layouts += 1
	var checks: Dictionary = {}
	checks.valid_input = validation.is_empty()
	checks.region_reads_only_actual_geometry_without_full_layout_copy = actual_space.layouts==0 and expected_layouts>0 and reference_space.layouts>actual_space.layouts
	var cold_calls: int = actual_space.layouts
	var reference_cold_calls: int = reference_space.layouts
	actual._ensure(x.world)
	checks.current_build_reused = actual_space.layouts==cold_calls
	checks.full_grid_boundaries = actual._by_cell.has("1:0:0") and actual._by_cell.has("1:95:95")
	checks.stored_excluded = not actual._by_facility.has(STORED) and actual._by_cell.has("1:41:70")
	checks.nonblocking_still_associated = actual._by_cell.has("1:40:70") and actual._by_facility.get(NONBLOCKING,{}).get("ref",{}).get("room_id","")=="west"
	checks.fixed_chair_blocks_its_cell = not actual._by_cell.has("1:36:68")
	checks.floors_isolated = actual._by_facility.get("upper_west_chair",{}).get("ref",{}).get("floor_id",0)==2 and actual._by_facility.get("west_chair",{}).get("ref",{}).get("floor_id",0)==1
	checks.upper_floor_starts_lazy = not actual._derived_floors.has(3)
	observations.append(_compare_build("lazy_empty_upper_floor",x.world,actual,reference,3))
	checks.empty_upper_floor_built = actual._derived_floors.has(3) and actual._by_cell.has("3:32:64") and not actual._by_cell.has("3:0:0")
	var initial: Dictionary = _snapshot(actual)
	var tick: int = x.world.sim_tick
	var quote: Dictionary = _bed_expansion(x)
	checks.real_bed_expansion_quoted = not quote.is_empty()
	if not quote.is_empty():
		x.world.facts.adaptations[BED] = quote
		x.space.reservation_changed(x.world,BED)
	x.world.facts.floors.overrides["1"].blocked.append([37,70])
	x.world.touch()
	var expanded_validation: String = x.world.validate(_content)
	observations.append(_compare_build("same_tick_geometry_and_bed_change",x.world,actual,reference))
	checks.same_tick_geometry_rebuilt = x.world.sim_tick==tick and initial!=_snapshot(actual) and not actual._by_cell.has("1:37:70")
	checks.expanded_input_valid = expanded_validation.is_empty()
	if not quote.is_empty():
		checks.expanded_bed_cells_excluded = _footprint_excluded(actual,1,x.world.facts.facilities[BED].cell,quote.footprint)
		var patient_key: String = HospitalPublicAreas._key(1,Vector2i(int(quote.patient_cell[0]),int(quote.patient_cell[1])))
		checks.adapted_patient_cell_used = quote.patient_cell!=x.world.facts.facilities[BED].patient_cell and actual._by_facility.get(BED,{}).get("ref",{})==actual._by_cell.get(patient_key,{}).get("ref",{}) and actual._by_facility.has(BED)
		checks.other_floor_keeps_base_bed = actual._by_cell.has("2:51:72")
	var restored: WorldState = WorldState.new(x.world.freeze())
	observations.append(_compare_build("restored_world_identity",restored,actual,reference,3))
	var ok: bool = true
	for passed: bool in checks.values(): ok = ok and passed
	for observation: Dictionary in observations: ok = ok and observation.ok
	var result: Dictionary = {"ok":ok,"validation":validation,"expanded_validation":expanded_validation,"checks":checks,"cold_facility_layout_calls":{"optimized":cold_calls,"reference":reference_cold_calls},"observations":observations,"scope":"Complete derived region compatibility; no gameplay movement or arrival is simulated by this calculation fixture."}
	x.a.dispose()
	x.p.waiting_life = null
	x.p.environment = null
	x.e.waiting_life = null
	x.l.environment = null
	x.l.visitors = null
	x.c.recruitment = null
	x.clear()
	return result

func _build_fixture() -> Dictionary:
	var x: Dictionary = _areas()
	x.world.facts.rooms.east.kind = "ward"
	x.world.facts.rooms.east.room_type_id = "ward"
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
		facility.room_id = "upper_"+str(facility.room_id)
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
	return {"ok":equal and before==world.freeze(),"boundary":label,"all_regions_anchors_cell_order_geometry_and_facility_maps_equal":equal,"regions":actual._regions.size(),"cells":actual._by_cell.size(),"facilities":actual._by_facility.size(),"world_and_rng_unchanged":before==world.freeze(),"first_difference":first_difference}

func _snapshot(areas: HospitalPublicAreas) -> Dictionary:
	var regions: Array = []
	for region: Dictionary in areas._regions:
		regions.append({"ref":region.ref.duplicate(true),"cells":region.cells.keys(),"facilities":region.facilities.duplicate(),"bounds":region.bounds,"geometry":region.geometry})
	var cells: Array = []
	for key: String in areas._by_cell: cells.append([key,areas._by_cell[key].ref.duplicate(true)])
	var facilities: Array = []
	for id: String in areas._by_facility: facilities.append([id,areas._by_facility[id].ref.duplicate(true)])
	return {"regions":regions,"cells":cells,"facilities":facilities,"derived_floors":areas._derived_floors.keys()}

func _footprint_excluded(areas: HospitalPublicAreas, floor_id: int, cell: Array, footprint: Array) -> bool:
	for y: int in range(int(cell[1]),int(cell[1])+int(footprint[1])):
		for x: int in range(int(cell[0]),int(cell[0])+int(footprint[0])):
			if areas._by_cell.has(HospitalPublicAreas._key(floor_id,Vector2i(x,y))): return false
	return true
