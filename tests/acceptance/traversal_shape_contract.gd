extends RefCounted

var _comparisons: int = 0
var _failures: int = 0
var _differences: Array = []
var _coverage: Dictionary = {}

# The original public clearance operation is the independent first-field oracle.
# No implementation of the candidate's inlined clearance formula lives here.
func _expected(space: HospitalSpace, actor: Dictionary, offset: Array, source: Dictionary) -> Array:
	var dimensions: Dictionary = space.body(actor)
	var height: float = float(dimensions.depth_m if actor.get("posture","standing")=="lying" else dimensions.height_m)
	return [space.clearance(actor),ceili((maxf(float(dimensions.width_m),float(dimensions.depth_m))+0.1)/HospitalSpace.CELL_METERS),height<=float(source.height),float(dimensions.height_m)+0.1<=float(source.door_height),offset]

func _compare(space: HospitalSpace, cache: NavigationCache, actor: Dictionary, offset: Array, source: Dictionary, label: String) -> void:
	_comparisons += 1
	var before: PackedByteArray = var_to_bytes([actor,offset,source])
	var expected: Array = _expected(space,actor,offset,source)
	var actual: Array = cache._traversal_shape(space,actor,offset,source)
	var expected_json: String = JSON.stringify([expected],"",true,true)
	var actual_json: String = JSON.stringify([actual],"",true,true)
	var equal: bool = actual.size()==5 and var_to_bytes(actual)==var_to_bytes(expected) and actual_json.to_utf8_buffer()==expected_json.to_utf8_buffer() and is_same(actual[4],offset) and before==var_to_bytes([actor,offset,source])
	if equal: return
	_failures += 1
	if _differences.size()<8:
		_differences.append({"label":label,"actor":actor,"source":source,"offset":offset,"expected":expected,"actual":actual,"expected_json":expected_json,"actual_json":actual_json})

func _corpus(space: HospitalSpace, cache: NavigationCache, actor: Dictionary, label: String) -> void:
	var offsets: Array = [[0,0],[1,0],[-0.25,0.5],[1.0000000001,-2.125]]
	for posture: String in ["standing","lying"]:
		var subject: Dictionary = actor.duplicate(true)
		subject.posture = posture
		var dimensions: Dictionary = space.body(subject)
		var height: float = float(dimensions.depth_m if posture=="lying" else dimensions.height_m)
		var door_height: float = float(dimensions.height_m)+0.1
		# These tiny differences collapse in float32; both original float64
		# ceiling predicates must distinguish their exact, inclusive boundaries.
		for source: Dictionary in [
			{"height":height,"door_height":door_height},
			{"height":height-0.0000000001,"door_height":door_height},
			{"height":height,"door_height":door_height-0.0000000001},
			{"height":height-0.0000000001,"door_height":door_height-0.0000000001},
			{"height":height+0.0000000001,"door_height":door_height+0.0000000001}]:
			for offset: Array in offsets:
				_compare(space,cache,subject,offset,source,label+":"+posture)
		_coverage[posture] = int(_coverage.get(posture,0))+1

func run_case(content: HospitalContent) -> Dictionary:
	_comparisons = 0
	_failures = 0
	_differences.clear()
	_coverage.clear()
	var space := HospitalSpace.new(content)
	var cache := NavigationCache.new()
	var originals: Array = []
	var species_count: int = 0
	var binding_count: int = 0
	for species: Dictionary in content.catalog.species:
		originals.append({"id":"shape_species_"+str(species.id),"species_id":species.id,"body_binding_id":"","posture":"standing","facing":0.0})
		species_count += 1
	for binding: Dictionary in content.catalog.treatment_bindings:
		originals.append({"id":"shape_binding_"+str(binding.id),"species_id":binding.species_id,"body_binding_id":binding.id,"posture":"standing","facing":0.0})
		binding_count += 1
	for original: Dictionary in originals:
		_corpus(space,cache,original,"content")
		var dimensions: Dictionary = space.body(original).duplicate(true)
		dimensions.width_m = float(dimensions.width_m)+HospitalSpace.CELL_METERS*0.25
		dimensions.depth_m = float(dimensions.depth_m)+HospitalSpace.CELL_METERS*0.5
		dimensions.height_m = float(dimensions.height_m)+0.1
		var body_only: Dictionary = original.duplicate(true)
		body_only._convoy_body = dimensions
		_corpus(space,cache,body_only,"convoy_body_only")
		var size_only: Dictionary = original.duplicate(true)
		size_only._convoy_size = space.clearance(original)+2
		_corpus(space,cache,size_only,"convoy_size_only")
		var both: Dictionary = body_only.duplicate(true)
		both._convoy_size = space.clearance(original)+3
		_corpus(space,cache,both,"convoy_body_and_size")
		for name: String in ["content","convoy_body_only","convoy_size_only","convoy_body_and_size"]:
			_coverage[name] = int(_coverage.get(name,0))+1
	# Independent dimension inputs exercise integer clearance and the distinct
	# doorway margin on either side of their exact metre/cell thresholds.
	var boundary_inputs: int = 0
	if not originals.is_empty():
		for cells: int in [1,2,3]:
			for threshold: float in [float(cells)*HospitalSpace.CELL_METERS,float(cells)*HospitalSpace.CELL_METERS-0.1]:
				for delta: float in [-0.0000000001,0.0,0.0000000001]:
					var subject: Dictionary = originals[0].duplicate(true)
					subject._convoy_body = {"width_m":threshold+delta,"depth_m":0.1,"height_m":1.5}
					_corpus(space,cache,subject,"clearance_and_door_ceil_boundary")
					boundary_inputs += 1
	var checks: Dictionary = {
		"all_content_species_and_bindings":species_count==content.catalog.species.size() and binding_count==content.catalog.treatment_bindings.size() and species_count>0 and binding_count>0,
		"every_body_normal_lying_and_convoy_variants":_coverage.get("content",0)==originals.size() and _coverage.get("convoy_body_only",0)==originals.size() and _coverage.get("convoy_size_only",0)==originals.size() and _coverage.get("convoy_body_and_size",0)==originals.size(),
		"ceil_threshold_corpus_complete":boundary_inputs==18,
		"typed_shapes_original_json_bytes_and_inputs_equal":_failures==0 and _comparisons>0
	}
	return {"checks":checks,"species":species_count,"bindings":binding_count,"coverage":_coverage.duplicate(),"boundary_inputs":boundary_inputs,"comparisons":_comparisons,"failure_count":_failures,"first_differences":_differences.duplicate(true),"scope":"Calculation-only body/source/offset contract; original public clearance supplies the independent oracle. Synthetic convoy overrides are local arguments, never injected into a simulation or a performance world."}
