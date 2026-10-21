extends "res://tests/acceptance/staff_fixtures.gd"

# The pre-change full coverage scan supplies independent record ordering and
# existence answers. It deliberately ignores the new unordered-consumer hint.
class FullScan extends HospitalEnvironment:
	func _sample_records(kind: String, floor_id: int, coverage: Dictionary, _preserve_order: bool = true) -> Array:
		_prepare_sample_sources(_query.world)
		var cells: Dictionary = _query.samples[kind].get(floor_id,{})
		var result: Array = []
		if cells.is_empty(): return result
		for key: String in coverage: result.append_array(cells.get(key,[]))
		return result
	func _has_sample(kind: String, floor_id: int, coverage: Dictionary) -> bool:
		_prepare_sample_sources(_query.world)
		var cells: Dictionary = _query.samples[kind].get(floor_id,{})
		if cells.is_empty(): return false
		for key: String in coverage:
			if cells.has(key) and not cells[key].is_empty(): return true
		return false

func _compare(x: Dictionary, original: HospitalEnvironment, cells: Array) -> Dictionary:
	var before: Dictionary = x.world.freeze()
	x.e.begin_query(x.world)
	original.begin_query(x.world)
	var ok: bool = true
	var observations: Array = []
	for cell: Array in cells:
		var brief: Dictionary = x.e.sample_at(x.world,1,cell,"subject")
		var expected_brief: Dictionary = original.sample_at(x.world,1,cell,"subject")
		var detailed: Dictionary = x.e.environment_at(x.world,1,cell,"subject",true)
		var expected_detailed: Dictionary = original.environment_at(x.world,1,cell,"subject",true)
		# Dictionary equality preserves value types, and Array equality preserves
		# the complete original explanatory-source sequence without sorting it.
		var equal: bool = brief==expected_brief and detailed==expected_detailed
		ok = ok and equal
		observations.append({"cell":cell,"complete_brief_equal":brief==expected_brief,"complete_explanation_and_order_equal":detailed==expected_detailed,"brief":brief,"detailed":detailed})
	x.e.end_query()
	original.end_query()
	return {"ok":ok and before==x.world.freeze(),"readonly":before==x.world.freeze(),"observations":observations}

func _surface(x: Dictionary, cell: Array, edge: String, material: String) -> String:
	var definition: Dictionary = _content.definition("renovation_materials",material)
	var key: String = x.e._surface_key(1,cell,str(definition.surface),edge)
	x.world.facts.environment.surfaces[key] = {"floor_id":1,"cell":cell.duplicate(),"surface":definition.surface,"edge":edge,"material_id":material,"paid_cost":int(definition.unit_price),"order_id":""}
	return key

func _same_records(actual: Array, expected: Array) -> bool:
	if actual.size()!=expected.size(): return false
	for record: Dictionary in expected:
		if actual.count(record)!=expected.count(record): return false
	return true

func _joins(x: Dictionary, original: HospitalEnvironment) -> Dictionary:
	x.e.begin_query(x.world)
	original.begin_query(x.world)
	x.e._prepare_sample_sources(x.world)
	original._prepare_sample_sources(x.world)
	var first: Dictionary = {"id":"first","value":4}
	var second: Dictionary = {"id":"second","value":10}
	var coverage: Dictionary = {"44:79":0,"43:79":1,"45:79":1,"42:79":2}
	# These are legal already-indexed calculation inputs. Duplicate source
	# records and multiple records at one cell must retain their multiplicity.
	var cases: Array = [
		{"name":"sparse_reverse_order","coverage":coverage,"cells":{"45:79":[second],"44:79":[first,second],"80:80":[first]}},
		{"name":"dense_sources","coverage":{"44:79":0},"cells":{"80:80":[second],"44:79":[first],"45:79":[second]}},
		{"name":"empty_matching_bucket","coverage":coverage,"cells":{"44:79":[],"80:80":[first]}},
		{"name":"no_coverage","coverage":{},"cells":{"44:79":[first]}},
		{"name":"no_sources","coverage":coverage,"cells":{}}
	]
	var ok: bool = true
	var rows: Array = []
	for kind: String in ["walls","dirt","machines","construction"]:
		for input: Dictionary in cases:
			x.e._query.samples[kind] = {1:input.cells}
			original._query.samples[kind] = {1:input.cells}
			var expected: Array = original._sample_records(kind,1,input.coverage)
			var ordered: Array = x.e._sample_records(kind,1,input.coverage)
			var unordered: Array = x.e._sample_records(kind,1,input.coverage,false)
			var equal: bool = ordered==expected and _same_records(unordered,expected) and x.e._has_sample(kind,1,input.coverage)==original._has_sample(kind,1,input.coverage) and not x.e._has_sample(kind,2,input.coverage)
			ok = ok and equal
			rows.append({"kind":kind,"input":input.name,"default_order_and_record_multiplicity":equal})
	x.e.end_query()
	original.end_query()
	return {"ok":ok,"observations":rows}

func run(database: HospitalContent) -> Dictionary:
	_content = database
	var x: Dictionary = _fixture({"subject":"doctor","neighbor":"nurse"})
	_facility(x,"join_plant","FUR25",[40,80])
	_facility(x,"join_light","FUR19",[42,82])
	_facility(x,"join_water","FUR17",[50,80])
	_position(x,"subject",[44,79])
	_position(x,"neighbor",[45,80])
	x.e.waiting_life = x.l
	var original: HospitalEnvironment = FullScan.new(_content,x.space)
	original.waiting_life = x.l
	# Installed legal wall surfaces at equal distance have different values and
	# reverse source insertion order, so distance/key selection is observable.
	x.world.facts.floors.overrides["1"].blocked.append_array([[43,77],[45,77]])
	var later_key: String = _surface(x,[45,78],"north","MAT08")
	var earlier_key: String = _surface(x,[43,78],"north","MAT05")
	_surface(x,[44,79],"","MAT01")
	var dirt: Array = []
	for index: int in 3: dirt.append(x.e.spawn_dirt(x.world,"CL01","intersection_%d"%index,"intersection:%d"%index,1,[[44,81],[46,80],[42,80]][index]))
	x.world.touch()
	var validation: String = x.world.validate(_content)
	var first: Dictionary = _compare(x,original,[[44,79],[45,78],[44.25,79.5],[48,80]])
	var walls: Dictionary = {later_key:x.world.facts.environment.surfaces[later_key],earlier_key:x.world.facts.environment.surfaces[earlier_key]}
	for key: String in walls: x.world.facts.environment.surfaces.erase(key)
	var bare: Dictionary = _compare(x,original,[[44,79],[45,78]])
	x.world.facts.environment.surfaces.merge(walls)
	var rules: Dictionary = _content.balance.environment
	var wall_ties: bool = int(first.observations[0].brief.value)-int(bare.observations[0].brief.value)==mini(int(rules.wall_cap),4) and int(first.observations[1].brief.value)-int(bare.observations[1].brief.value)==mini(int(rules.wall_cap),10)
	var joins: Dictionary = _joins(x,original)
	var changes: Array = []
	x.world.facts.research.append("R15")
	changes.append(_compare(x,original,[[44,79],[44,85],[48,80]]))
	x.world.facts.facilities.join_light.failed = true
	changes.append(_compare(x,original,[[44,79]]))
	if not dirt[0].is_empty(): x.world.facts.environment.dirt.erase(dirt[0])
	changes.append(_compare(x,original,[[44,79]]))
	_position(x,"neighbor",x.space.facility_layout(x.world,"join_water").patient_cell)
	changes.append(_compare(x,original,[[48,80]]))
	var changed_ok: bool = true
	for row: Dictionary in changes: changed_ok = changed_ok and row.ok
	var final_validation: String = x.world.validate(_content)
	var result: Dictionary = {"ok":validation.is_empty() and final_validation.is_empty() and not dirt.has("") and first.ok and bare.ok and wall_ties and joins.ok and changed_ok,"validation":validation,"final_validation":final_validation,"complete_original_observations":first,"wall_distance_then_key_ties_with_integer_values":wall_ties,"direct_join_default_order_and_unordered_multiset":joins,"same_tick_new_scope_changes":changes}
	x.e.waiting_life = null
	original.waiting_life = null
	x.l.environment = null
	return result
