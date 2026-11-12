extends SceneTree

# The two original query methods from HospitalSpace SHA 10b28f9dad002dd14fea805b0cb8a791d99134cbb2652e5c443d947b27690971.
# Only these operations are compared; constructors and validation are untimed.
class BeforeSpace extends HospitalSpace:
	func _init(database: HospitalContent) -> void: super(database)
	func body(actor: Dictionary) -> Dictionary:
		if actor.has("_convoy_body"): return actor._convoy_body
		var key: String = str(actor.species_id)+":"+str(actor.get("body_binding_id",""))
		if not _bodies.has(key):
			_bodies[key] = content.actor_body(actor)
		return _bodies[key]
	func walking_speed(actor: Dictionary) -> float:
		var k: int = ceili(maxf(float(content.actor_body(actor).width_m),float(content.actor_body(actor).depth_m))/CELL_METERS)
		return float(content.balance.movement_speeds[str(k)])

class CountedContent extends HospitalContent:
	var actor_body_calls: int = 0
	func actor_body(actor: Dictionary) -> Dictionary:
		actor_body_calls+=1
		return super.actor_body(actor)

func _initialize() -> void: call_deferred("run")

func _hash(value: Variant) -> String:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256); context.update(var_to_bytes(value))
	return context.finish().hex_encode()

func _results(geometry: HospitalSpace, actors: Array[Dictionary], operation: String) -> Array:
	var result: Array = []
	for actor: Dictionary in actors:
		result.append({"actor_id":actor.id,"value":geometry.walking_speed(actor) if operation=="walking_speed" else geometry.body(actor).duplicate()})
	return result

func _measure(geometry: HospitalSpace, actors: Array[Dictionary], operation: String, iterations: int) -> Dictionary:
	var speed_sum: float = 0.0
	var last_body: Dictionary = {}
	var started: int = Time.get_ticks_usec()
	if operation=="walking_speed":
		for repeat: int in iterations:
			for actor: Dictionary in actors: speed_sum+=geometry.walking_speed(actor)
	else:
		for repeat: int in iterations:
			for actor: Dictionary in actors: last_body=geometry.body(actor)
	return {"elapsed_us":Time.get_ticks_usec()-started,"derived_requests":actors.size()*iterations,"speed_sum":speed_sum,"last_body":last_body}

func _counts(actors: Array[Dictionary], operation: String, before: bool) -> Dictionary:
	var database: CountedContent = CountedContent.new()
	var geometry: HospitalSpace = BeforeSpace.new(database) if before else HospitalSpace.new(database)
	var setup_calls: int = database.actor_body_calls
	var first: Array = _results(geometry,actors,operation)
	var cold_calls: int = database.actor_body_calls-setup_calls
	var second: Array = _results(geometry,actors,operation)
	return {"cold_pass_requests":actors.size(),"cold_pass_actor_body_calls":cold_calls,"warm_pass_requests":actors.size(),"warm_pass_actor_body_calls":database.actor_body_calls-setup_calls-cold_calls,"cached_individual_bodies":geometry._bodies.size(),"repeated_complete_results_equal":var_to_bytes(first)==var_to_bytes(second),"timed":false}

func run() -> void:
	var input: String = ""
	var output: String = ""
	var expected_sha: String = ""
	var iterations: int = 1000
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--input="): input=arg.trim_prefix("--input=")
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
		if arg.begins_with("--expected-sha="): expected_sha=arg.trim_prefix("--expected-sha=")
		if arg.begins_with("--iterations="): iterations=arg.trim_prefix("--iterations=").to_int()
	if input.is_empty() or output.is_empty() or expected_sha.is_empty() or iterations<=0 or FileAccess.file_exists(output): quit(2); return
	if FileAccess.get_sha256(input)!=expected_sha: push_error("Input identity differs from the fixed boundary"); quit(2); return
	var file: FileAccess = FileAccess.open(input,FileAccess.READ)
	if file==null: quit(2); return
	var envelope: Dictionary = file.get_var(false); file.close()
	var database: HospitalContent = HospitalContent.new()
	if envelope.get("content_fingerprint","")!=database.content_fingerprint: quit(2); return
	var world: WorldState = WorldState.new(envelope.facts)
	var snapshot: Dictionary = world.freeze()
	var validation: String = world.validate(database)
	var policy: Dictionary = ClassDB.class_call_static("PlatformThreadPolicy","apply_main_thread") if ClassDB.class_exists("PlatformThreadPolicy") else {"applied":false}
	var errors: Array = []
	if not validation.is_empty(): errors.append(validation)
	if not policy.get("applied",false): errors.append("Application main-thread policy failed")
	var actors: Array[Dictionary] = []
	var actor_ids: Array = world.ids("actors")
	var individual_keys: Dictionary = {}
	var ordinary_keys: Dictionary = {}
	var proxy_actors: int = 0
	for id: String in actor_ids:
		var actor: Dictionary = world.facts.actors[id]
		actors.append(actor)
		var key: String = str(actor.species_id)+":"+str(actor.get("body_binding_id",""))
		individual_keys[key]=true
		if actor.has("_convoy_body"): proxy_actors+=1
		else: ordinary_keys[key]=true
	if actors.is_empty(): errors.append("The complete real boundary has no actor records")
	var counted: Dictionary = {}
	var timings: Array = []
	var result_hashes: Dictionary = {}
	for operation: String in ["walking_speed","body"]:
		counted[operation]={"before":_counts(actors,operation,true),"after":_counts(actors,operation,false)}
		var old_counts: Dictionary = counted[operation].before
		var new_counts: Dictionary = counted[operation].after
		var expected_old_cold: int = actors.size()*2 if operation=="walking_speed" else ordinary_keys.size()
		var expected_new_cold: int = ordinary_keys.size()+proxy_actors if operation=="walking_speed" else ordinary_keys.size()
		var expected_old_warm: int = actors.size()*2 if operation=="walking_speed" else 0
		var expected_new_warm: int = proxy_actors if operation=="walking_speed" else 0
		if int(old_counts.cold_pass_actor_body_calls)!=expected_old_cold or int(old_counts.warm_pass_actor_body_calls)!=expected_old_warm or int(new_counts.cold_pass_actor_body_calls)!=expected_new_cold or int(new_counts.warm_pass_actor_body_calls)!=expected_new_warm: errors.append("Counted content-build contract differs: "+operation)
		if not old_counts.repeated_complete_results_equal or not new_counts.repeated_complete_results_equal: errors.append("Counted repeated results differ: "+operation)
		for pair: int in 3:
			var old: HospitalSpace = BeforeSpace.new(database)
			var current: HospitalSpace = HospitalSpace.new(database)
			# Each fresh runtime receives the same complete corpus once. These
			# natural warm queries also compare every typed result before timing.
			var expected: Array = _results(old,actors,operation)
			var actual: Array = _results(current,actors,operation)
			if var_to_bytes(actual)!=var_to_bytes(expected): errors.append("Complete typed results differ: "+operation+" pair "+str(pair+1))
			result_hashes[operation]={"before":_hash(expected),"after":_hash(actual)}
			var order: Array[String] = ["before","after"]
			if pair%2!=0: order.reverse()
			var measured: Dictionary = {"operation":operation,"pair":pair+1,"order":order,"warm_queries_per_runtime":actors.size()}
			if errors.is_empty():
				for name: String in order: measured[name]=_measure(old if name=="before" else current,actors,operation,iterations)
			if var_to_bytes(_results(old,actors,operation))!=var_to_bytes(expected) or var_to_bytes(_results(current,actors,operation))!=var_to_bytes(expected): errors.append("Repeated results differ: "+operation)
			timings.append(measured)
	if snapshot!=world.freeze(): errors.append("Read-only queries changed complete world facts")
	if not world.validate(database).is_empty(): errors.append("World validation failed after queries")
	var result: Dictionary = {"ok":errors.is_empty(),"errors":errors,"input":input,"input_sha256":expected_sha,"world_sha256":_hash(snapshot),"whole_world_readonly":snapshot==world.freeze(),"world_validation":validation,"tick":world.sim_tick,"actor_ids":actor_ids,"actor_records":actors.size(),"present":world.present_actor_count(),"moves":world.facts.moves.size(),"individual_body_keys":individual_keys.size(),"iterations":iterations,"pairs_per_operation":3,"timings":timings,"untimed_counts":counted,"complete_result_hashes":result_hashes,"policy":policy,"engine":OS.get_executable_path(),"engine_sha256":FileAccess.get_sha256(OS.get_executable_path()),"space_sha256":FileAccess.get_sha256("res://game/building/hospital_space.gd"),"content_sha256":FileAccess.get_sha256("res://game/content/content_db.gd"),"probe_sha256":FileAccess.get_sha256("res://tools/performance/current/individual_body_probe.gd"),"scope":"Read-only individual body and walking-speed operations over every actor record of the fixed real boundary, including outside/transit identities. Each operation is measured separately after one complete natural warm pass, in three alternating A/B pairs. CountedContent runs only separate cold/warm correctness passes; timed queries use plain HospitalContent. Requests are derived loop counts; actor_body calls are directly counted. No combined workload ratio, simulation step, gameplay change or full160 speedup is inferred."}
	result.proxy_actor_records=proxy_actors
	result.ordinary_body_keys=ordinary_keys.size()
	var report: FileAccess = FileAccess.open(output,FileAccess.WRITE)
	if report==null: quit(2); return
	report.store_string(JSON.stringify(result,"\t")); report.close()
	print(JSON.stringify({"ok":result.ok,"actor_records":actors.size(),"timings":timings,"errors":errors}))
	quit(0 if result.ok else 1)
