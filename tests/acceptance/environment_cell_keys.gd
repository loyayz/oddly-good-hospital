extends RefCounted

const Fixtures = preload("res://tests/acceptance/staff_fixtures.gd")
const ORIGINS: Array = [[44,80],[4294967340,80],[-4294967252,80]]
var _contexts: Array = []

class FootprintInput extends HospitalSpace:
	func facility_layout(_world: WorldState, _facility_id: String) -> Dictionary:
		return {"footprint":[3,2]}

func _fixture(builder: RefCounted, facts: Dictionary = {}) -> Dictionary:
	var x: Dictionary
	if facts.is_empty():
		x = builder._fixture({"domain_actor":"cleaner"})
		builder._facility(x,"domain_water","FUR17",[44,80])
		builder._facility(x,"domain_water_other","FUR17",[46,78])
		builder._facility(x,"domain_bin","FUR18",[48,80])
		x.world.touch()
	else:
		x = builder._bind(WorldState.new(facts.duplicate(true)))
	_contexts.append(x)
	return x

func _dispose_all() -> void:
	for x: Dictionary in _contexts:
		x.a.dispose()
		x.e.waiting_life = null
		x.p.waiting_life = null
		x.p.environment = null
		x.l.environment = null
		x.l.visitors = null
		x.c.recruitment = null
		x.clear()
	_contexts.clear()

func _coordinate_view(coverage: Dictionary) -> Dictionary:
	var cells: Array = []
	var key_types: Array = []
	var valid: bool = true
	for key: Variant in coverage:
		var point: Array = []
		if key is Vector2i:
			point = [int(key.x),int(key.y)]
		elif key is String:
			var parts: PackedStringArray = key.split(":")
			if parts.size()==2 and parts[0].is_valid_int() and parts[1].is_valid_int(): point = [parts[0].to_int(),parts[1].to_int()]
		if point.is_empty(): valid = false
		var kind: String = type_string(typeof(key))
		if not key_types.has(kind): key_types.append(kind)
		cells.append({"cell":point,"distance":coverage[key]})
	return {"valid_coordinate_keys":valid,"key_types":key_types,"cells":cells}

func _coverage_rows(x: Dictionary) -> Array:
	var rows: Array = []
	var before: Dictionary = x.world.freeze()
	var edges: Dictionary = x.e._coverage_edges(x.world,1)
	for noise: bool in [false,true]:
		for origin: Array in ORIGINS:
			var radii: Array = [0,1] if origin==ORIGINS[0] else [0]
			for radius: int in radii:
				# Radius zero retains the exact raw root. The normal radius-one
				# input has four open, owned neighbours and no wall or screen.
				var expected: Array = [{"cell":origin.duplicate(),"distance":0}]
				if radius==1:
					for offset: Array in [[-1,0],[0,-1],[0,1],[1,0]]:
						expected.append({"cell":[int(origin[0])+offset[0],int(origin[1])+offset[1]],"distance":1})
				var native_before: int = int(x.space.query_counts.get("environment_coverage_native_calls",0))
				var fallback_before: int = int(x.space.query_counts.get("environment_coverage_fallbacks",0))
				var actual: Dictionary = x.e._coverage(x.world,1,origin,radius,noise,edges)
				var view: Dictionary = _coordinate_view(actual)
				var normal: bool = origin==ORIGINS[0]
				var membership: bool = x.e._facility_in_coverage(x.world,x.world.facts.facilities.domain_water,actual)
				var readonly: bool = x.world.freeze()==before
				rows.append({"origin":origin,"radius":radius,"noise":noise,"input_scope":"normal hospital coordinate" if normal else "private helper coordinate boundary; original world remains legal",
					"expected_raw_coordinates":expected,"actual":view,"normal_fixture_facility_hit":membership,"expected_fixture_hit":normal,
					"world_readonly":readonly,"native_calls":int(x.space.query_counts.get("environment_coverage_native_calls",0))-native_before,
					"fallback_calls":int(x.space.query_counts.get("environment_coverage_fallbacks",0))-fallback_before,
					"passed":view.valid_coordinate_keys and view.cells==expected and membership==normal and readonly})
	return rows

func _membership_rows(x: Dictionary, content: HospitalContent) -> Array:
	# Only the unchanged layout boundary is adapted. These are calculation
	# inputs, not a placed facility, a working noise source or actual travel.
	var geometry: HospitalSpace = FootprintInput.new(content)
	var environment: HospitalEnvironment = HospitalEnvironment.new(content,geometry)
	var coordinate_key: Variant = environment.call("_cell_key",[44,80])
	var integer_keys: bool = coordinate_key is Vector2i
	var facility: Dictionary = {"id":"domain_membership","cell":[44,80],"footprint":[99,99]}
	var before: Dictionary = x.world.freeze()
	var rows: Array = []
	for input: Array in [[[44,80],true],[[46,81],true],[[47,81],false],[[43,80],false]]:
		var point: Array = input[0]
		var key: Variant = Vector2i(int(point[0]),int(point[1])) if integer_keys else "%d:%d" % point
		var coverage: Dictionary = {key:false}
		var original: Dictionary = facility.duplicate(true)
		var actual: bool = environment._facility_in_coverage(x.world,facility,coverage)
		rows.append({"cell":point,"coverage_value":false,"layout_footprint":[3,2],"raw_footprint":[99,99],"expected":input[1],"actual":actual,
			"passed":actual==input[1] and facility==original and x.world.freeze()==before,"input_scope":"private adapted-footprint membership calculation"})
	for origin: Array in [ORIGINS[1],ORIGINS[2]]:
		var large_facility: Dictionary = {"id":"domain_large_membership","cell":origin.duplicate(),"footprint":[99,99]}
		var ordinary_coverage: Dictionary = {Vector2i(44,80):0}
		var raw_coverage: Dictionary = {"%d:%d" % origin:0}
		var alias_hit: bool = environment._facility_in_coverage(x.world,large_facility,ordinary_coverage)
		var exact_hit: bool = environment._facility_in_coverage(x.world,large_facility,raw_coverage)
		rows.append({"origin":origin,"ordinary_alias_hit":alias_hit,"raw_exact_hit":exact_hit,"passed":not alias_hit and exact_hit and x.world.freeze()==before,"input_scope":"private 64-bit footprint membership calculation; no placement or movement"})
	var empty_hit: bool = environment._facility_in_coverage(x.world,facility,{})
	rows.append({"empty_coverage":true,"expected":false,"actual":empty_hit,"passed":not empty_hit and x.world.freeze()==before})
	return rows

func _bin_rows(builder: RefCounted, facts: Dictionary, content: HospitalContent) -> Array:
	var rows: Array = []
	for origin: Array in ORIGINS:
		var x: Dictionary = _fixture(builder,facts)
		var validation: String = x.world.validate(content)
		var normal: bool = origin==ORIGINS[0]
		var id: String = x.e.spawn_dirt(x.world,"CL02","domain_water","domain:source",1,origin)
		var patch: Dictionary = x.world.facts.environment.dirt.get(id,{})
		var collected: bool = patch.get("bin_id","")=="domain_bin"
		var merge: Variant = null
		if normal and collected:
			var first: Dictionary = x.world.freeze()
			var second: String = x.e.spawn_dirt(x.world,"CL02","domain_water_other","domain:other",1,[46,78])
			merge = second==id and x.world.freeze()==first
		rows.append({"origin":origin,"input_world_validation":validation,"input_scope":"legal source-creation boundary; drinking completion is not exercised" if normal else "private helper origin differs from the legal source facility; no normal-flow claim",
			"created_id":id,"actual_cell":patch.get("cell",[]),"actual_bin_id":patch.get("bin_id",""),"expected_normal_bin_collection":normal,
			"normal_second_source_merges_without_fact_changes":merge,"post_call_validation":x.world.validate(content),
			"passed":validation.is_empty() and collected==normal and (not normal or not id.is_empty() and merge==true)})
	return rows

func _validation_rows(facts: Dictionary, content: HospitalContent) -> Array:
	var rows: Array = []
	for origin: Array in ORIGINS:
		for kind: String in ["actor","facility"]:
			var source: Dictionary = facts.duplicate(true)
			var target: Array = [origin[0],86] if kind=="actor" else origin.duplicate()
			if kind=="actor":
				source.actors.domain_actor.location.cell = target.duplicate()
			else:
				var facility: Dictionary = source.facilities.domain_water
				var delta: int = int(origin[0])-44
				for field: String in ["cell","patient_cell","repair_cell"]: facility[field][0] = int(facility[field][0])+delta
				for point: Array in facility.operator_cells: point[0] = int(point[0])+delta
			var world: WorldState = WorldState.new(source)
			var before: Dictionary = world.freeze()
			var reason: String = world.validate(content)
			rows.append({"kind":kind,"target":target,"accepted":reason.is_empty(),"reason":reason,"validation_readonly":world.freeze()==before,
				"actual_save_load_executed":false,"input_scope":"cloned fact validation probe only; acceptance is recorded, not assumed"})
	return rows

func run(content: HospitalContent) -> Dictionary:
	var builder: RefCounted = Fixtures.new()
	builder._content = content
	var x: Dictionary = _fixture(builder)
	var validation: String = x.world.validate(content)
	var facts: Dictionary = x.world.freeze()
	var groups: Dictionary = {"coverage":_coverage_rows(x),"membership":_membership_rows(x,content),"bins":_bin_rows(builder,facts,content),"validation":_validation_rows(facts,content)}
	var passed: bool = validation.is_empty()
	for group: String in ["coverage","membership","bins"]:
		for row: Dictionary in groups[group]: passed = passed and bool(row.get("passed",false))
	_dispose_all()
	return {"ok":passed,"input_world_validation":validation,"groups":groups,
		"scope":"Finite raw-coordinate and ownership boundaries. Legal source-creation inputs and private calculation/clone-validation probes are separate; no actual save/load, noise work, drinking, travel or normal-flow reproduction is claimed."}
