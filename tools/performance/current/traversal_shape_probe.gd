extends SceneTree

# Local shape calls only: actual complete mixed-world actors and actual four
# floor sources. Counter and timing modes run in separate processes. No Sim,
# graph build, gameplay draw, actor relocation or population reduction.
# Original method: 6d8cd78caab614be60d7f544960aaa86489a40ad, verbatim
# with one enclosing-class indent. The performance runtime is otherwise common.
class OriginalNavigation extends NavigationCache:
	func _traversal_shape(space: HospitalSpace, actor: Dictionary, offset: Array, source: Dictionary) -> Array:
		# Floor nodes/sweeps use the integer clearance; door expansion adds its
		# actual 0.1m margin. Heights enter only these two ceiling predicates.
		# Facility fits and actual body collisions still use complete dimensions.
		var body: Dictionary = space.body(actor)
		var height: float = float(body.depth_m if actor.get("posture","standing")=="lying" else body.height_m)
		return [space.clearance(actor),ceili((maxf(float(body.width_m),float(body.depth_m))+0.1)/HospitalSpace.CELL_METERS),height<=float(source.height),float(body.height_m)+0.1<=float(source.door_height),offset]

class CountSpace extends HospitalSpace:
	var body_calls: int = 0
	var clearance_calls: int = 0
	func body(actor: Dictionary) -> Dictionary:
		body_calls += 1
		return super.body(actor)
	func clearance(actor: Dictionary) -> int:
		clearance_calls += 1
		return super.clearance(actor)

func _initialize() -> void: call_deferred("_run")

func _hash(value: Variant) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(value))
	return context.finish().hex_encode()

func _run() -> void:
	var input: String = ""
	var expected_sha: String = ""
	var output: String = ""
	var mode: String = ""
	var iterations: int = 256
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--input="): input=argument.trim_prefix("--input=")
		if argument.begins_with("--expected-sha="): expected_sha=argument.trim_prefix("--expected-sha=")
		if argument.begins_with("--output="): output=argument.trim_prefix("--output=")
		if argument.begins_with("--mode="): mode=argument.trim_prefix("--mode=")
		if argument.begins_with("--iterations="): iterations=argument.trim_prefix("--iterations=").to_int()
	if input.is_empty() or expected_sha.is_empty() or output.is_empty() or FileAccess.file_exists(output) or not mode in ["counts","timing"] or iterations<1:
		push_error("Use complete mixed input/expected SHA, a new output, explicit counts|timing and positive iterations");quit(2);return
	if FileAccess.get_sha256(input)!=expected_sha:
		push_error("Complete mixed input SHA differs");quit(2);return
	var preparation: int = Time.get_ticks_usec()
	var file: FileAccess = FileAccess.open(input,FileAccess.READ)
	if file==null: push_error("Cannot open complete mixed input");quit(2);return
	var envelope: Dictionary = file.get_var(false)
	file.close()
	var content := HospitalContent.new()
	var world := WorldState.new(envelope.facts)
	var validation: String = world.validate(content)
	if envelope.get("content_fingerprint","")!=content.content_fingerprint or not validation.is_empty():
		push_error("Invalid complete mixed input: "+validation);quit(2);return
	var frozen: PackedByteArray = var_to_bytes(world.facts)
	var floor_ids: Array[int] = []
	for key: String in world.facts.floors.overrides: floor_ids.append(int(key))
	floor_ids.sort()
	if floor_ids.size()!=4:
		push_error("This local probe requires the actual complete four-floor mixed input");quit(2);return
	var policy: Dictionary = ClassDB.class_call_static("PlatformThreadPolicy","apply_main_thread")
	var space: HospitalSpace = CountSpace.new(content) if mode=="counts" else HospitalSpace.new(content)
	var before := OriginalNavigation.new()
	var candidate := NavigationCache.new()
	var sources: Dictionary = {}
	var source_hashes: Dictionary = {}
	for floor_id: int in floor_ids:
		sources[floor_id] = space._navigation.floor_source(space,world,floor_id)
		source_hashes[str(floor_id)] = _hash(sources[floor_id])
	var actors: Array = []
	var actor_ids: Array = world.ids("actors")
	for id: String in actor_ids: actors.append({"kind":"actor","id":id,"actor":world.facts.actors[id]})
	var convoy_ids: Array = []
	for id: String in world.ids("moves"):
		var movement: Dictionary = world.facts.moves[id]
		if movement.get("convoy",{}).is_empty(): continue
		actors.append({"kind":"actual_convoy_proxy","id":id,"actor":ConvoyTrail.proxy(world,movement)})
		convoy_ids.append(id)
	var requests: Array = []
	var observed: Array = []
	var errors: Array = []
	var no_size_override: int = 0
	for actor: Dictionary in actors:
		for floor_id: int in floor_ids:
			var request: Dictionary = {"kind":actor.kind,"id":actor.id,"actor":actor.actor,"floor":floor_id,"offset":[0,0],"source":sources[floor_id]}
			requests.append(request)
			if not actor.actor.has("_convoy_size"): no_size_override += 1
			# Full comparison also warms only the existing content body lookup.
			# It does not build any floor/body navigation graph.
			var original: Array = before._traversal_shape(space,request.actor,request.offset,request.source)
			var actual: Array = candidate._traversal_shape(space,request.actor,request.offset,request.source)
			if var_to_bytes(original)!=var_to_bytes(actual) or JSON.stringify([original],"",true,true)!=JSON.stringify([actual],"",true,true):
				errors.append({"actor":actor.id,"floor":floor_id,"original":original,"actual":actual})
			observed.append({"kind":actor.kind,"id":actor.id,"floor":floor_id,"offset":request.offset,"shape":actual})
	if requests.is_empty(): push_error("Complete input has no actors");quit(2);return
	var preparation_usec: int = Time.get_ticks_usec()-preparation
	var pairs: Array = []
	var counts: Dictionary = {}
	if errors.is_empty() and mode=="counts":
		var counted: CountSpace = space as CountSpace
		for label: String in ["reference","candidate"]:
			counted.body_calls=0
			counted.clearance_calls=0
			var cache: NavigationCache = before if label=="reference" else candidate
			for request: Dictionary in requests: cache._traversal_shape(counted,request.actor,request.offset,request.source)
			counts[label] = {"requests":requests.size(),"body_calls":counted.body_calls,"clearance_calls":counted.clearance_calls}
		if counts.reference.body_calls-counts.candidate.body_calls!=no_size_override or counts.candidate.body_calls!=requests.size() or counts.reference.clearance_calls!=requests.size() or counts.candidate.clearance_calls!=0:
			errors.append({"work_count_mismatch":counts,"requests_without_size_override":no_size_override})
	elif errors.is_empty():
		for repeat: int in 3:
			var pair: Dictionary = {"repeat":repeat+1,"operations_per_variant":requests.size()*iterations,"order":["reference","candidate"] if repeat%2==0 else ["candidate","reference"]}
			for label: String in pair.order:
				var cache: NavigationCache = before if label=="reference" else candidate
				var last: Array = []
				var started: int = Time.get_ticks_usec()
				for _iteration: int in iterations:
					for request: Dictionary in requests: last=cache._traversal_shape(space,request.actor,request.offset,request.source)
				pair[label+"_usec"] = Time.get_ticks_usec()-started
				pair[label+"_last_shape_sha256"] = _hash(last)
			if pair.reference_last_shape_sha256!=pair.candidate_last_shape_sha256: errors.append({"pair_last_shape":pair})
			pairs.append(pair)
	var unchanged: bool = frozen==var_to_bytes(world.facts)
	for floor_id: int in floor_ids:
		unchanged = unchanged and source_hashes[str(floor_id)]==_hash(sources[floor_id])
	var native: Dictionary = {}
	for name: String in ["oddly_good_platform.windows.x86_64.dll","libgcc_s_seh-1.dll","libgmp-10.dll","libmpfr-6.dll","libwinpthread-1.dll"]:
		native[name] = FileAccess.get_sha256("res://game/platform/windows/bin/"+name)
	var report: Dictionary = {"complete":true,"ok":errors.is_empty() and unchanged,"mode":mode,"input":input,"input_sha256":expected_sha,"sim_tick":world.sim_tick,"actors":actor_ids.size(),"present_actors":world.present_actor_count(),"all_actor_ids":actor_ids,"actual_convoy_ids":convoy_ids,"floor_ids":floor_ids,"source_sha256":source_hashes,"requests":requests.size(),"requests_without_size_override":no_size_override,"complete_typed_shapes_and_json_equal":errors.is_empty(),"request_shapes":observed,"request_shapes_sha256":_hash(observed),"world_rng_and_source_unchanged":unchanged,"main_thread_policy":policy,"engine_version":Engine.get_version_info(),"engine_executable":OS.get_executable_path(),"engine_sha256":FileAccess.get_sha256(OS.get_executable_path()),"native":native,"OMP_NUM_THREADS":OS.get_environment("OMP_NUM_THREADS"),"reference_method_commit":"6d8cd78caab614be60d7f544960aaa86489a40ad","iterations_per_pair":iterations if mode=="timing" else 1,"preparation_usec":preparation_usec,"pairs":pairs,"counts":counts,"errors":errors,"runtime_source_sha256":{"navigation_cache":FileAccess.get_sha256("res://game/building/navigation_cache.gd"),"hospital_space":FileAccess.get_sha256("res://game/building/hospital_space.gd"),"probe":FileAccess.get_sha256(get_script().resource_path)},"scope":"Every actor in the complete mixed input and each actual floor source, plus any actual saved convoy proxies. Local shape calls only; input, sources and RNG stay unchanged. Counter mode has no elapsed claim; plain timing uses no CountSpace and no per-call instrumentation. Not Simulation.step or game CPU acceptance."}
	file=FileAccess.open(output,FileAccess.WRITE)
	if file==null: push_error("Cannot write local shape result");quit(2);return
	file.store_string(JSON.stringify(report,"\t",true,true))
	file.close()
	print("TRAVERSAL_SHAPE_PROBE="+JSON.stringify({"mode":mode,"ok":report.ok,"actors":actor_ids.size(),"requests":requests.size(),"output":output}))
	quit(0 if report.ok else 1)
