extends "res://tests/acceptance/environment_source_intersection.gd"

class CustomEnvironment extends HospitalEnvironment:
	pass
class CustomSpace extends HospitalSpace:
	pass

func _outside(bounds: Dictionary, cell: Array) -> bool:
	var regions: Variant = bounds.get(1,[])
	if not regions is Array: return false
	for region: Rect2i in regions:
		if region.has_point(Vector2i(int(cell[0]),int(cell[1]))): return false
	return true

func _sample(x: Dictionary, name: String, cell: Array, excluded: bool, value: Variant = null) -> Dictionary:
	var before: Dictionary = x.world.freeze()
	# The no-scope path retains the complete propagation/scoring calculation.
	var expected: Dictionary = x.e._observe_at(x.world,1,cell,"",false,false)
	x.e.begin_query(x.world)
	var actual: Dictionary = x.e.sample_at(x.world,1,cell)
	var bounds: Variant = x.e._query.get("observation_bounds")
	var proof: bool = bounds is Dictionary and bounds.is_read_only() and _outside(bounds,cell)==excluded
	if bounds is Dictionary:
		for regions: Variant in bounds.values():
			if regions is Array: proof = proof and regions.is_read_only()
	x.e.end_query()
	return {"name":name,"cell":cell,"ok":proof and actual==expected and (value==null or actual.value==value) and before==x.world.freeze() and x.e._query.is_empty(),"excluded":excluded,"proof":proof,"expected":expected,"actual":actual,"world_readonly":before==x.world.freeze()}

func run(database: HospitalContent) -> Dictionary:
	_content = database
	var x: Dictionary = _fixture()
	# Legal calculation input: built empty rooms may have no optional furniture.
	x.world.facts.facilities.clear()
	x.world.facts.floors.completed_top_floor = {}
	for plot: Array in x.world.facts.floors.overrides["1"].plots: x.world.facts.floors.completed_top_floor["%d:%d" % plot] = 1
	x.world.touch()
	var validation: String = x.world.validate(_content)
	if not validation.is_empty(): return {"ok":false,"failure_kind":"fixture","validation":validation}
	var rules: Dictionary = _content.balance.environment
	var plain: int = clampi(int(rules.base)+int(rules.clean_bonus),0,100)
	var rows: Array = [_sample(x,"empty_floor",[44,80],true,plain)]
	_facility(x,"bounds_plant","FUR25",[44,80])
	x.world.touch()
	var radius: int = int(rules.range_cells)
	for direction: Array in [[1,0],[-1,0],[0,1],[0,-1]]:
		for distance: int in [radius,radius+1]:
			var cell: Array = [44+int(direction[0])*distance,80+int(direction[1])*distance]
			rows.append(_sample(x,"positive_inclusive_edge",cell,distance>radius,plain if distance>radius else null))
	rows.append(_sample(x,"conservative_corner_keeps_full_path",[44+radius,80+radius],false,plain))
	x.world.facts.research.append("R15")
	var upgraded: int = int(rules.upgraded_range_cells)
	rows.append(_sample(x,"research_positive_outer_edge",[44+upgraded,80],false))
	rows.append(_sample(x,"outside_research_positive_range",[45+upgraded,80],true,plain))
	x.world.facts.facilities.bounds_plant.cell = [55,80]
	x.world.touch()
	rows.append(_sample(x,"next_query_reads_moved_source",[44,80],true,plain))
	x.world.facts.facilities.clear()
	x.world.touch()
	_surface(x,[44,80],"","MAT01")
	var material: Dictionary = _content.definition("renovation_materials","MAT01")
	rows.append(_sample(x,"floor_finish_keeps_full_scoring",[44,80],true,clampi(plain+mini(int(rules.floor_cap),int(material.environment_value)),0,100)))
	x.world.facts.environment.surfaces.clear()
	var before: Dictionary = x.world.freeze()
	# Source-index arithmetic only: these records do not claim live machinery,
	# construction or dirt. OPS-18 and OPS-11 exercise their real business sources.
	for kind: String in ["dirt","machines","construction"]:
		x.e.begin_query(x.world)
		x.e._prepare_facility_sources(x.world)
		x.e._prepare_sample_sources(x.world)
		x.e._query.samples[kind][1] = {Vector2i(44,80):[]}
		var bounds: Dictionary = x.e._prepare_observation_bounds(x.world)
		rows.append({"name":kind+"_base_range_with_R15","ok":not _outside(bounds,[44+radius,80]) and _outside(bounds,[45+radius,80]) and x.world.freeze()==before})
		x.e.end_query()
	for key: String in ["4294967340:80","44.5:80"]:
		x.e.begin_query(x.world)
		x.e._prepare_facility_sources(x.world)
		x.e._prepare_sample_sources(x.world)
		x.e._query.facilities[1] = {key:[]}
		var bounds: Dictionary = x.e._prepare_observation_bounds(x.world)
		rows.append({"name":"unsupported_source_key_keeps_full_path","ok":bounds.has(1) and bounds[1]==null and x.world.freeze()==before})
		x.e.end_query()
	for service: HospitalEnvironment in [CustomEnvironment.new(_content,x.space),HospitalEnvironment.new(_content,CustomSpace.new(_content))]:
		service.begin_query(x.world)
		rows.append({"name":"custom_implementation_has_no_bounds_proof","ok":service._prepare_observation_bounds(x.world)==null})
		service.end_query()
	var legacy: WorldState = WorldState.new(x.world.freeze())
	legacy.facts.floors.erase("completed_top_floor")
	x.e.begin_query(legacy)
	rows.append({"name":"legacy_floor_model_keeps_full_path","ok":x.e._prepare_observation_bounds(legacy)==null})
	x.e.end_query()
	return {"ok":rows.all(func(row: Dictionary)->bool:return row.ok) and x.world.freeze()==before and x.world.validate(_content).is_empty(),"rows":rows,"scope":"Environment calculation and conservative rectangle boundaries only. No travel, work completion or seat acquisition is synthesized."}
