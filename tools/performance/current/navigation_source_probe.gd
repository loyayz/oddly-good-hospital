extends SceneTree

# Local operations only. No Simulation, movement, gameplay draw or budget edit.
# --input=<complete-final.bin> --expected-sha=<sha256> --output=<new.json>
# --iterations=10000. Three pairs per workload: AB, BA, AB.
# BeforeCache methods are verbatim, with one enclosing class indent, from
# a4766fb101e80cf649773ef60093203c76bc1060 / 7b2a7352f9e0c5af54024521a106a307e97fbd22.
# Original navigation_cache.gd SHA256:
# 7ac97237286da27410d840a93588fe78a975d4cf452989ac6228c89e3df57ea7
class BeforeCache extends NavigationCache:
	func _source_record(space: HospitalSpace, world: WorldState, floor_id: int) -> Dictionary:
		var key: String = str(world.get_instance_id())+":"+str(floor_id)
		var entry: Dictionary = _sources.get(key,{})
		if not entry.is_empty() and entry.world.get_ref()!=world: entry = {}
		if not entry.is_empty() and entry.revision==world.geometry_revision:
			_used += 1
			entry.used = _used
			return entry
		if entry.is_empty() or entry.revision!=world.geometry_revision:
			var current: Dictionary = RouteClearance.capture_source(space,world,floor_id)
			if entry.is_empty() or entry.source!=current:
				var identity: Dictionary = _static_identity(world,floor_id,current)
				var graphs: Dictionary = entry.graphs if not entry.is_empty() and entry.static_version==identity.version else {}
				entry = {"source":current,"world":weakref(world),"floor_id":floor_id,"version":_identity(floor_id,current),"static_source":identity.source,"static_version":identity.version,"graphs":graphs}
			entry.revision = world.geometry_revision
		_store_source(key,entry)
		if _defer_trim==0: _trim_source_payloads(int(space.content.balance.pathfinding.graph_cache_target_bytes),space.query_counts)
		return entry

	func inherit_projection(space: HospitalSpace, world: WorldState, projected: WorldState, facility_ids: Array = []) -> void:
		_prune_sources()
		for original: Dictionary in _sources.values():
			if original.world.get_ref()!=world or original.revision!=world.geometry_revision: continue
			var floor_id: int = int(original.floor_id)
			var current: Dictionary = original.source.duplicate()
			for id: String in facility_ids:
				if not current.facilities.has(id): continue
				var facility: Dictionary = projected.facts.facilities[id]
				var footprint: Array = projected.facts.adaptations.get(id,{}).get("footprint",facility.footprint)
				if current.facilities[id].footprint==footprint: continue
				if is_same(current.facilities,original.source.facilities): current.facilities = current.facilities.duplicate()
				current.facilities[id] = {"cell":facility.cell.duplicate(),"footprint":footprint.duplicate()}
			current.occupancy = RouteClearance.capture_occupancy(projected,floor_id)
			var identical: bool = current==original.source
			var identity: Dictionary = _static_identity(projected,floor_id,current)
			var same_static: bool = identity.version==original.static_version
			var entry: Dictionary = {"source":original.source if identical else current,"world":weakref(projected),"floor_id":floor_id,"revision":projected.geometry_revision,"version":original.version if identical else _identity(floor_id,current),"static_source":identity.source,"static_version":identity.version,"graphs":original.graphs.duplicate() if same_static else {}}
			_store_source(str(projected.get_instance_id())+":"+str(floor_id),entry)
		if _defer_trim==0: _trim_source_payloads(int(space.content.balance.pathfinding.graph_cache_target_bytes),space.query_counts)

class CountedBefore extends BeforeCache:
	var static_identity_calls: int=0
	func _static_identity(world: WorldState, floor_id: int, current: Dictionary) -> Dictionary:
		static_identity_calls+=1
		return super._static_identity(world,floor_id,current)

class CountedCurrent extends NavigationCache:
	var static_identity_calls: int=0
	func _static_identity(world: WorldState, floor_id: int, current: Dictionary) -> Dictionary:
		static_identity_calls+=1
		return super._static_identity(world,floor_id,current)

var _errors: Array[String]=[]

func _initialize() -> void: call_deferred("run")

func _check(passed: bool, message: String) -> void:
	if not passed: _errors.append(message)

func _hash(value: Variant) -> String:
	var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(value));return context.finish().hex_encode()

func _runtime(content: HospitalContent, before: bool, counted: bool = false) -> Dictionary:
	var space:=HospitalSpace.new(content)
	var cache: NavigationCache
	if counted: cache=CountedBefore.new() if before else CountedCurrent.new()
	else: cache=BeforeCache.new() if before else NavigationCache.new()
	space._navigation=cache
	return {"space":space,"cache":cache,"before":before,"counted":counted}

func _semantic(record: Dictionary) -> Dictionary:
	return {"source":record.source.duplicate(true),"static_source":record.static_source.duplicate(true),"version":record.version,"static_version":record.static_version,"floor_id":record.floor_id,"revision":record.revision,"graphs":record.graphs.duplicate(true)}

func _budget(runtime: Dictionary) -> Dictionary:
	var cache: NavigationCache=runtime.cache
	var recorded: int=0
	for entry: Dictionary in cache._sources.values(): recorded+=int(entry.charge)
	var target: int=int(runtime.space.content.balance.pathfinding.graph_cache_target_bytes)
	var total: int=cache.total_charge()
	_check(recorded==cache._source_charged and total<=target and cache._source_charged<=target/4,"Original cache accounting/allowance differs")
	return {"target_bytes":target,"source_charged":cache._source_charged,"source_charge_sum":recorded,"total_charged":total,"resident_sources":cache._sources.size(),"used":cache._used}

func _warm(runtime: Dictionary, requests: Array) -> Array:
	var values: Array=[]
	for request: Dictionary in requests:
		var world: WorldState=request.world
		var record: Dictionary=runtime.cache._source_record(runtime.space,world,int(request.floor_id))
		_check(record.world.get_ref()==world and int(record.revision)==world.geometry_revision,"Source record has another owner/revision")
		values.append(_semantic(record))
	# Do not label a rebuild/eviction workload as a resident-hit measurement.
	for request: Dictionary in requests:
		var world: WorldState=request.world
		var key: String=str(world.get_instance_id())+":"+str(request.floor_id)
		_check(runtime.cache._sources.has(key),"Complete requested source set does not fit the unchanged cache allowance")
	return values

func _measure_source(runtime: Dictionary, requests: Array, iterations: int) -> Dictionary:
	var cache: NavigationCache=runtime.cache
	var space: HospitalSpace=runtime.space
	var last: Dictionary={}
	var used: int=cache._used
	var started: int=Time.get_ticks_usec()
	for repeat: int in iterations:
		for request: Dictionary in requests: last=cache._source_record(space,request.world,int(request.floor_id))
	var elapsed: int=Time.get_ticks_usec()-started
	return {"elapsed_us":elapsed,"derived_requests":requests.size()*iterations,"used_delta":cache._used-used,"last_version":last.version,"last_static_version":last.static_version}

func _source_cases(content: HospitalContent, world: WorldState, other: WorldState, iterations: int) -> Array:
	var modes: Dictionary={"same_world_floor1":[{"world":world,"floor_id":1}],"same_world_four_floors":[{"world":world,"floor_id":1},{"world":world,"floor_id":2},{"world":world,"floor_id":3},{"world":world,"floor_id":4}],"two_complete_worlds_floor1":[{"world":world,"floor_id":1},{"world":other,"floor_id":1}]}
	var results: Array=[]
	for mode: String in modes:
		var requests: Array=modes[mode]
		for pair: int in 3:
			var runtimes: Dictionary={"before":_runtime(content,true),"after":_runtime(content,false)}
			var expected: Array=_warm(runtimes.before,requests)
			var actual: Array=_warm(runtimes.after,requests)
			_check(var_to_bytes(expected)==var_to_bytes(actual),"Complete cold source/static/version results differ: "+mode)
			var order: Array=["before","after"] if pair%2==0 else ["after","before"]
			var row: Dictionary={"operation":"_source_record","mode":mode,"pair":pair+1,"order":order,"warm_requests_per_runtime":requests.size(),"complete_semantic_sha256":_hash(expected)}
			if _errors.is_empty():
				for name: String in order: row[name]=_measure_source(runtimes[name],requests,iterations)
			for name: String in ["before","after"]:
				_check(var_to_bytes(_warm(runtimes[name],requests))==var_to_bytes(expected),"Complete source results changed after timing: "+mode)
				if row.has(name): _check(int(row[name].used_delta)==requests.size()*iterations,"Resident hit did not advance the original LRU once per request: "+mode)
				row[name+"_budget"]=_budget(runtimes[name])
			results.append(row)
	return results

func _projection_pass(runtime: Dictionary, world: WorldState, projections: Array, timed: bool) -> Dictionary:
	var requests: Array=[]
	for floor_id: int in [1,2,3,4]: requests.append({"world":world,"floor_id":floor_id})
	var cache: NavigationCache=runtime.cache
	var space: HospitalSpace=runtime.space
	var facility_ids: Array=[]
	var elapsed: Array=[]
	var total: int=0
	var counted_inside: int=0
	var semantic_hashes: Array=[]
	for projected: WorldState in projections:
		# Natural parent queries are outside the timer. They keep all four
		# original sources live under the unchanged LRU; no cache is copied.
		var parent_values: Array=_warm(runtime,requests)
		var count_before: int=int(cache.get("static_identity_calls")) if runtime.counted else 0
		var started: int=Time.get_ticks_usec() if timed else 0
		cache.inherit_projection(space,world,projected,facility_ids)
		var duration: int=Time.get_ticks_usec()-started if timed else 0
		if timed: elapsed.append(duration);total+=duration
		if runtime.counted: counted_inside+=int(cache.get("static_identity_calls"))-count_before
		var values: Array=[]
		for index: int in 4:
			var key: String=str(projected.get_instance_id())+":"+str(index+1)
			var record: Dictionary=cache._sources.get(key,{})
			_check(not record.is_empty(),"Inheritance did not retain the complete four-floor result under the original allowance")
			if record.is_empty(): continue
			_check(record.world.get_ref()==projected,"Inherited source has the wrong weak owner")
			values.append(_semantic(record))
			_check(record.source.is_read_only() and record.static_source.is_read_only(),"Inherited source payload is not sealed")
			if not runtime.before:
				var parent_key: String=str(world.get_instance_id())+":"+str(index+1)
				var parent: Dictionary=cache._sources.get(parent_key,{})
				_check(not parent.is_empty() and is_same(record.static_source,parent.static_source),"Unchanged sealed static source was not reused")
		_check(var_to_bytes(values)==var_to_bytes(parent_values),"Complete inherited source/static/version/graph payload differs from the identity projection")
		semantic_hashes.append(_hash(values))
		_budget(runtime)
	return {"timed":timed,"elapsed_us":total if timed else null,"per_call_us":elapsed,"derived_requests":projections.size(),"complete_floors_per_request":4,"untimed_parent_queries":projections.size()*4,"semantic_sha256":_hash(semantic_hashes),"static_identity_calls_inside_inherit":counted_inside if runtime.counted else null,"budget":_budget(runtime)}

func _projection_cases(content: HospitalContent, world: WorldState, projections: Array) -> Dictionary:
	var timings: Array=[]
	for pair: int in 3:
		var runtimes: Dictionary={"before":_runtime(content,true),"after":_runtime(content,false)}
		var order: Array=["before","after"] if pair%2==0 else ["after","before"]
		var row: Dictionary={"operation":"inherit_projection","pair":pair+1,"order":order}
		for name: String in order: row[name]=_projection_pass(runtimes[name],world,projections,true)
		_check(row.before.semantic_sha256==row.after.semantic_sha256,"Complete A/B projection results differ")
		timings.append(row)
	var counts: Dictionary={}
	for before: bool in [true,false]:
		var name: String="before" if before else "after"
		counts[name]=_projection_pass(_runtime(content,before,true),world,projections,false)
	_check(int(counts.before.static_identity_calls_inside_inherit)==projections.size()*4 and int(counts.after.static_identity_calls_inside_inherit)==0,"Selected static-identity method-call counts differ")
	_check(counts.before.semantic_sha256==counts.after.semantic_sha256,"Counted A/B complete projection results differ")
	return {"timings":timings,"untimed_counts":counts,"projection_kind":"Twenty independent complete identity Worlds; no Actor or reservation is edited. All worlds remain alive across A/B; cache budgets and pruning run normally."}

func run() -> void:
	var input: String="";var output: String="";var expected_sha: String="";var iterations: int=10000
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--input="): input=arg.trim_prefix("--input=")
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
		if arg.begins_with("--expected-sha="): expected_sha=arg.trim_prefix("--expected-sha=")
		if arg.begins_with("--iterations="): iterations=arg.trim_prefix("--iterations=").to_int()
	if input.is_empty() or output.is_empty() or expected_sha.is_empty() or iterations<=0 or FileAccess.file_exists(output): quit(2);return
	if FileAccess.get_sha256(input)!=expected_sha: push_error("Fixed complete input identity differs");quit(2);return
	var file: FileAccess=FileAccess.open(input,FileAccess.READ)
	if file==null: quit(2);return
	var envelope: Dictionary=file.get_var(false);file.close()
	var content:=HospitalContent.new()
	if not content.error.is_empty() or envelope.get("content_fingerprint","")!=content.content_fingerprint: quit(2);return
	var world:=WorldState.new(envelope.facts)
	var snapshot: Dictionary=world.freeze()
	var other:=WorldState.new(snapshot.duplicate(true))
	var originals: Array=[world,other]
	var projections: Array=[]
	for index: int in 20: projections.append(WorldState.new(snapshot.duplicate(true)))
	var policy: Dictionary=ClassDB.class_call_static("PlatformThreadPolicy","apply_main_thread") if ClassDB.class_exists("PlatformThreadPolicy") else {"applied":false}
	_check(policy.get("applied",false),"Application main-thread policy failed")
	_check(envelope.get("floors",[])==[1,2,3,4],"Expected the complete original four-floor input")
	var all_worlds: Array=originals+projections
	var original_sha: String=_hash(snapshot)
	var rng_sha: String=_hash(snapshot.rng)
	for owner: WorldState in all_worlds:
		_check(owner.validate(content).is_empty(),"Complete input World validation failed")
		_check(_hash(owner.freeze())==original_sha and _hash(owner.facts.rng)==rng_sha,"Independent complete-world copy differs")
	var sources: Array=[];var inheritance: Dictionary={}
	if _errors.is_empty():
		sources=_source_cases(content,world,other,iterations)
		if _errors.is_empty(): inheritance=_projection_cases(content,world,projections)
	var readonly: bool=true
	var final_validations: Array=[]
	for owner: WorldState in all_worlds:
		var validation: String=owner.validate(content)
		final_validations.append(validation)
		_check(validation.is_empty(),"Readonly World validation failed after queries")
		var same: bool=_hash(owner.freeze())==original_sha and _hash(owner.facts.rng)==rng_sha
		readonly=readonly and same
		_check(same,"Readonly queries changed complete World facts/RNG")
	var result: Dictionary={"ok":_errors.is_empty(),"errors":_errors,"input":input,"input_sha256":expected_sha,"whole_world_sha256":original_sha,"rng_sha256":rng_sha,"whole_world_readonly":readonly,"world_validation_after":final_validations,"tick":world.sim_tick,"actor_records":world.facts.actors.size(),"present":world.present_actor_count(),"rooms":world.facts.rooms.size(),"facilities":world.facts.facilities.size(),"moves":world.facts.moves.size(),"complete_world_owners":all_worlds.size(),"source_iterations":iterations,"pairs_per_operation":3,"source_timings":sources,"inheritance":inheritance,"policy":policy,"engine":OS.get_executable_path(),"engine_sha256":FileAccess.get_sha256(OS.get_executable_path()),"navigation_cache_sha256":FileAccess.get_sha256("res://game/building/navigation_cache.gd"),"space_sha256":FileAccess.get_sha256("res://game/building/hospital_space.gd"),"probe_sha256":FileAccess.get_sha256("res://tools/performance/current/navigation_source_probe.gd"),"baseline":{"commit":"a4766fb101e80cf649773ef60093203c76bc1060","also_identical_at":"7b2a7352f9e0c5af54024521a106a307e97fbd22","file_sha256":"7ac97237286da27410d840a93588fe78a975d4cf452989ac6228c89e3df57ea7","source_record_method_sha256":"edd5f9f2d109e9288b45074957104d5eb2095dc5ced4ce6dd38106234100d700","inherit_projection_method_sha256":"c3ab0db5eb1e865a8d38ec6f9f8736b529f4058bbc8fadfa24d436b97e267ae3"},"scope":"Specific plain read-only source-record hits/alternation and identity-projection inheritance, not a complete simulation or an observed game call sequence. Before methods are verbatim original bodies; both use the current unchanged common cache machinery and allowance. Initialization, full-result checks, World validation and static-identity counters are outside timers. Source timings include loop/dispatch overhead; projection timings sum only individual inherit calls. Counter runs never supply elapsed measurements. Derived requests describe these loops, not game frequency or allocations. No combined workload weighting, full160 speedup, changed-occupancy/facility projection coverage or performance compliance is inferred."}
	var report: FileAccess=FileAccess.open(output,FileAccess.WRITE)
	if report==null: quit(2);return
	report.store_string(JSON.stringify(result,"\t"));report.close()
	print(JSON.stringify({"ok":result.ok,"actor_records":result.actor_records,"source_pairs":sources.size(),"errors":_errors}))
	quit(0 if result.ok else 1)
