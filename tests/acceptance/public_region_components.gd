extends RefCounted

# Calculation projections exercise domain boundaries independently of gameplay
# arrival. The real-world region/ownership cases remain in public_region_build.
func run_case(content: HospitalContent) -> Dictionary:
	# HospitalPublicAreas borrows its space, so keep this owner for every query.
	var space: HospitalSpace = HospitalSpace.new(content)
	var areas: HospitalPublicAreas = HospitalPublicAreas.new(space)
	var base: Dictionary = _input()
	var baseline: Dictionary = _one(areas,base,"overlapping_and_irregular_rooms",true)
	var observations: Array = [baseline.observation]
	var equivalent: Dictionary = base.duplicate(true)
	equivalent.layout.plots.reverse()
	equivalent.layout.blocked.reverse()
	equivalent.rooms[3].cells.reverse()
	var reordered: Dictionary = _one(areas,equivalent,"same_geometry_different_source_cell_order",true)
	observations.append(reordered.observation)
	var changed: Dictionary = base.duplicate(true)
	changed.layout.blocked.append([1,1])
	var modified: Dictionary = _one(areas,changed,"real_membership_change_same_anchor",true)
	observations.append(modified.observation)
	var fallback_equivalent: Dictionary = base.duplicate(true)
	fallback_equivalent.rooms[0][StringName("unconsumed_field")] = true
	var fallback: Dictionary = _one(areas,fallback_equivalent,"special_field_key_complete_fallback",false)
	observations.append(fallback.observation)
	var full: Dictionary = {"layout":{"plots":[],"blocked":[[0,0],[95,95]]},"rooms":[],"facilities":[],"connectors":[]}
	for y: int in 3:
		for x: int in 3: full.layout.plots.append([x,y])
	observations.append(_one(areas,full,"all_nine_plots_and_exact_grid_edges",true).observation)
	observations.append(_one(areas,{"layout":{"plots":[],"blocked":[]},"rooms":[],"facilities":[],"connectors":[]},"empty_floor_has_no_component",true).observation)
	for mode: String in ["outside_plot","fractional_blocked","fractional_room","fractional_obstacle","unicode_replacement_room_id"]:
		var input: Dictionary = base.duplicate(true)
		match mode:
			"outside_plot": input.layout.plots.append([3,2])
			"fractional_blocked": input.layout.blocked.append([3.25,3.75])
			"fractional_room": input.rooms[3].cells[0] = [14.25,2.0]
			"fractional_obstacle": input.facilities[0].layout.cell = [4.25,3.75]
			"unicode_replacement_room_id": input.rooms[0].id = "a"+String.chr(0xfffd)+"suffix"
		var computed: Dictionary = _one(areas,input,mode,mode=="unicode_replacement_room_id")
		if mode=="unicode_replacement_room_id":
			var complete_id: bool = str(computed.result.by_cell[Vector2i(2,2)].ref.room_id)==str(input.rooms[0].id) and str(input.rooms[0].id).unicode_at(1)==0xfffd
			computed.observation.complete_actual_unicode_room_id_preserved = complete_id
			computed.observation.ok = computed.observation.ok and complete_id
		observations.append(computed.observation)
	var checks: Dictionary = {
		"later_overlapping_room_keeps_original_assignment_precedence":baseline.result.by_cell[Vector2i(6,2)].ref.room_id=="b" and baseline.result.by_cell[Vector2i(2,2)].ref.room_id=="a",
		"explicit_empty_and_irregular_cells_override_rectangular_shorthand":baseline.result.by_cell[Vector2i(1,1)].ref.room_id=="" and baseline.result.by_cell[Vector2i(14,2)].ref.room_id=="irregular" and baseline.result.by_cell[Vector2i(14,3)].ref.room_id=="",
		"blocking_nonblocking_and_partial_outside_obstacle_rules":not baseline.result.by_cell.has(Vector2i(4,3)) and baseline.result.by_cell.has(Vector2i(8,3)) and not baseline.result.by_cell.has(Vector2i(10,10)) and not baseline.result.by_cell.has(Vector2i(0,31)) and baseline.result.by_cell.has(Vector2i(2,31)),
		"nonpositive_obstacles_retain_empty_deletion":baseline.result.by_cell.has(Vector2i(1,1)) and baseline.result.by_cell.has(Vector2i(1,2)),
		"equivalent_source_order_keeps_canonical_identity":_digests(baseline.result)==_digests(reordered.result),
		"native_and_complete_script_fallback_keep_same_identity":_digests(baseline.result)==_digests(fallback.result),
		"actual_membership_changes_fingerprint_without_changing_public_anchor":baseline.result.regions[0].ref==modified.result.regions[0].ref and baseline.result.regions[0].geometry!=modified.result.regions[0].geometry,
		"full_grid_is_not_truncated":full.layout.plots.size()==9 and observations[4].indexed_cells==9214,
	}
	return {"ok":not checks.values().has(false) and observations.all(func(row: Dictionary)->bool:return row.ok),"checks":checks,"observations":observations,"scope":"Complete connected sets, canonical cell representation and identity; unsupported-domain projections use the full original script geometry calculation."}

func _input() -> Dictionary:
	var blocked: Array = [[3,3],[3,3],[100,3]]
	for y: int in 32: blocked.append([20,y])
	return {"layout":{"plots":[[0,0],[0,0]],"blocked":blocked},"rooms":[
		{"id":"a","origin":[2,2],"size":[6,4]},
		{"id":"b","origin":[6,2],"size":[6,4]},
		{"id":"empty","origin":[1,1],"size":[5,5],"cells":[]},
		{"id":"irregular","origin":[14,2],"size":[3,2],"cells":[[14,2],[15,2],[15,3],[16,3]]},
	],"facilities":[
		{"id":"chair","definition":"FUR09","blocks":true,"layout":{"cell":[4,3],"footprint":[1,1],"patient_cell":[4,4]}},
		{"id":"nonblocking","definition":"FUR19","blocks":false,"layout":{"cell":[8,3],"footprint":[1,1],"patient_cell":[8,3]}},
		{"id":"outside_part","definition":"FUR09","blocks":true,"layout":{"cell":[-2,30],"footprint":[4,3],"patient_cell":[2,30]}},
		{"id":"zero_extent","definition":"FUR09","blocks":true,"layout":{"cell":[1,1],"footprint":[0,2],"patient_cell":[1,1]}},
		{"id":"negative_extent","definition":"FUR09","blocks":true,"layout":{"cell":[1,2],"footprint":[-1,2],"patient_cell":[1,2]}},
	],"connectors":[{"cell":[10,10],"footprint":[2,3]}]}

func _one(areas: HospitalPublicAreas, input: Dictionary, label: String, supported: bool) -> Dictionary:
	var before: Dictionary = input.duplicate(true)
	var blocking: Array = []
	for facility: Dictionary in input.facilities:
		if facility.blocks: blocking.append(facility.layout)
	blocking.append_array(input.connectors)
	var expected: Array = _original_components(input.layout,input.rooms,blocking)
	var native: Dictionary = PlatformArrivalMath.public_region_components({"plots":input.layout.plots,"blocked":input.layout.blocked,"rooms":input.rooms,"obstacles":blocking})
	var native_before: int = int(areas.space.query_counts.get("public_region_native_builds",0))
	var script_before: int = int(areas.space.query_counts.get("public_region_script_builds",0))
	var result: Dictionary = areas._derive_floor(2147483649,input.layout,input.rooms,input.facilities,input.connectors)
	var canonical: bool = result.regions.size()==expected.size()
	var facilities: bool = true
	var cells: int = 0
	var members: int = 0
	for index: int in mini(result.regions.size(),expected.size()):
		var region: Dictionary = result.regions[index]
		var component: Dictionary = expected[index]
		var coordinates: PackedInt64Array = component.cells
		var points: Array = []
		for position: int in range(0,coordinates.size(),2): points.append(Vector2i(coordinates[position],coordinates[position+1]))
		canonical = canonical and region.cells.keys()==points and region.ref=={"floor_id":2147483649,"room_id":component.room_id,"anchor":[coordinates[0],coordinates[1]]} and region.bounds==Rect2i(component.bounds[0],component.bounds[1],component.bounds[2],component.bounds[3]) and str(region.geometry).length()==64
		for point: Vector2i in points: canonical = canonical and is_same(result.by_cell.get(point,{}),region)
		cells += points.size()
		var expected_ids: Array = []
		var definitions: Dictionary = {}
		for facility: Dictionary in input.facilities:
			var patient: Vector2i = Vector2i(int(facility.layout.patient_cell[0]),int(facility.layout.patient_cell[1]))
			if not patient in points: continue
			var indices: PackedInt32Array = definitions.get(facility.definition,PackedInt32Array())
			indices.append(expected_ids.size())
			definitions[facility.definition] = indices
			expected_ids.append(facility.id)
			facilities = facilities and is_same(result.by_facility.get(facility.id,{}),region)
		facilities = facilities and region.facilities==expected_ids and region.facility_definitions==definitions
		members += expected_ids.size()
	canonical = canonical and result.by_cell.size()==cells
	facilities = facilities and result.by_facility.size()==members
	var dispatch: bool = int(areas.space.query_counts.get("public_region_native_builds",0))-native_before==(1 if supported else 0) and int(areas.space.query_counts.get("public_region_script_builds",0))-script_before==(0 if supported else 1)
	var native_contract: bool = not native.has("error") and bool(native.get("ready",false))==supported and (native.get("components",[])==expected if supported else not native.has("components"))
	return {"result":result,"observation":{"ok":canonical and facilities and dispatch and native_contract and before==input,"variant":label,"native_ready":native.get("ready",false),"native_fallback_reason":native.get("reason",""),"native_or_complete_fallback_used_as_expected":dispatch and native_contract,"complete_canonical_cells_anchors_bounds_and_index_equal":canonical,"full_facility_order_and_definition_membership_equal":facilities,"input_unchanged":before==input,"components":result.regions.size(),"indexed_cells":result.by_cell.size()}}

func _original_components(layout: Dictionary, rooms: Array, obstacles: Array) -> Array:
	# Independent original four-neighbour BFS; only the completed sets are
	# normalized for comparison with the canonical representation under test.
	var zones: Dictionary = {}
	for plot: Array in layout.plots:
		for y: int in range(int(plot[1])*32,(int(plot[1])+1)*32):
			for x: int in range(int(plot[0])*32,(int(plot[0])+1)*32): zones[Vector2i(x,y)] = ""
	for room: Dictionary in rooms:
		for cell: Array in BuildGeometry.cells(room): zones[Vector2i(int(cell[0]),int(cell[1]))] = str(room.id)
	var free: Dictionary = zones.duplicate()
	for cell: Array in layout.blocked: free.erase(Vector2i(int(cell[0]),int(cell[1])))
	for obstacle: Dictionary in obstacles:
		for y: int in range(int(obstacle.cell[1]),int(obstacle.cell[1])+int(obstacle.footprint[1])):
			for x: int in range(int(obstacle.cell[0]),int(obstacle.cell[0])+int(obstacle.footprint[0])): free.erase(Vector2i(x,y))
	var ordered: Array = free.keys()
	ordered.sort_custom(func(a: Vector2i,b: Vector2i)->bool:return a.y<b.y or a.y==b.y and a.x<b.x)
	var seen: Dictionary = {}
	var result: Array = []
	for start: Vector2i in ordered:
		if seen.has(start): continue
		var pending: Array[Vector2i] = [start]
		var bounds: Rect2i = Rect2i(start,Vector2i.ONE)
		seen[start] = true
		var cursor: int = 0
		while cursor<pending.size():
			var point: Vector2i = pending[cursor]
			cursor += 1
			for direction: Vector2i in [Vector2i.LEFT,Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN]:
				var next: Vector2i = point+direction
				if seen.has(next) or not free.has(next) or zones[next]!=zones[start]: continue
				seen[next] = true
				bounds = bounds.merge(Rect2i(next,Vector2i.ONE))
				pending.append(next)
		pending.sort_custom(func(a: Vector2i,b: Vector2i)->bool:return a.y<b.y or a.y==b.y and a.x<b.x)
		var coordinates: PackedInt64Array = PackedInt64Array()
		for point: Vector2i in pending:
			coordinates.append(point.x)
			coordinates.append(point.y)
		result.append({"room_id":zones[start],"cells":coordinates,"bounds":[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y]})
	return result

func _digests(result: Dictionary) -> Array:
	var values: Array = []
	for region: Dictionary in result.regions: values.append([region.ref,region.geometry])
	return values
