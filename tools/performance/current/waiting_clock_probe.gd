extends SceneTree

# One complete real mixed boundary, three main-thread AB/BA/AB local pairs.
# --input=<0daf-final.bin> --expected-sha=<0daf...> --output=<new.json>
# --iterations=1000. No Simulation, movement, clock fabrication or gameplay draw.
const INPUT_SHA256: String = "0daf82b82da618af8818aed962d5ef2bf9bad1b00be01c4f5a7ce71efb52662e"
const BASELINE_COMMIT: String = "9368fc68cb67760dd8200c60edb0fcacbee395c6"
const BASELINE_ALSO_IDENTICAL_AT: String = "6d8cd78caab614be60d7f544960aaa86489a40ad"
const BASELINE_BLOB: String = "c99ef187d5520c9b9af94478b233e35296a2217f"
const BASELINE_FILE_SHA256: String = "02788e12469664abadb8d6da487150316fdb6742f4ca07381a6de7d20f0cc5d7"
const BASELINE_METHOD_SHA256: String = "740a82ede400d6cb6e538ecf5971717758479f23bb9c704382d4d77de9db400c"
const LIFE_SOURCE: String = "res://game/life/waiting_life.gd"
const PROBE_SOURCE: String = "res://tools/performance/current/waiting_clock_probe.gd"

# Verbatim Git method; only one enclosing class indent is added.
class BeforeLife extends HospitalWaitingLife:
	func ensure(world: WorldState) -> void:
		if not world.facts.has("waiting_life"):
			world.facts.waiting_life = {"seats":{},"needs":{},"clocks":{}}
		toilets.ensure(world)
		for visit_id: String in world.active_visit_ids():
			var visit: Dictionary = world.facts.visits[visit_id]
			if _admitted(world,visit_id): continue
			if not world.facts.waiting_life.clocks.has(visit_id):
				world.facts.waiting_life.clocks[visit_id] = {"sequence":0,"next_purpose":"toilet",
					"next_need_tick":int(visit.get("arrival_tick",world.sim_tick))+_ticks(content.balance.amenity_flow.first_need_seconds)}

# BASELINE_ENSURE_END

class CountedBefore extends BeforeLife:
	var admission_queries: int = 0
	func _admitted(world: WorldState, visit_id: String) -> bool:
		admission_queries+=1
		return super._admitted(world,visit_id)

class CountedAfter extends HospitalWaitingLife:
	var admission_queries: int = 0
	func _admitted(world: WorldState, visit_id: String) -> bool:
		admission_queries+=1
		return super._admitted(world,visit_id)

var _errors: Array[String] = []
var _input_world_sha: String = ""

func _initialize() -> void: call_deferred("run")

func _check(passed: bool, message: String) -> void:
	if not passed: _errors.append(message)

func _hash(value: Variant) -> String:
	var context: HashingContext=HashingContext.new()
	context.start(HashingContext.HASH_SHA256);context.update(var_to_bytes(value))
	return context.finish().hex_encode()

func _embedded_method(source: String) -> String:
	var begin: int=source.find("\tfunc ensure(world: WorldState) -> void:\n")
	var end: int=source.find("# BASELINE_ENSURE_END",begin)
	if begin<0 or end<begin: return ""
	var lines: PackedStringArray=source.substr(begin,end-begin).split("\n")
	for index: int in lines.size():
		if lines[index].is_empty(): continue
		if not lines[index].begins_with("\t"): return ""
		lines[index]=lines[index].substr(1)
	return "\n".join(lines)

func _current_method(source: String) -> String:
	var begin: int=source.find("func ensure(world: WorldState) -> void:\n")
	var end: int=source.find("\nfunc dispatch(",begin)
	return source.substr(begin,end-begin+1) if begin>=0 and end>begin else ""

func _proof() -> Dictionary:
	var embedded: String=_embedded_method(FileAccess.get_file_as_string(PROBE_SOURCE))
	var current: String=FileAccess.get_file_as_string(LIFE_SOURCE)
	var method: String=_current_method(current)
	var exact: bool=not embedded.is_empty() and embedded.sha256_text()==BASELINE_METHOD_SHA256
	var only_ensure: bool=not method.is_empty() and current.count(method)==1 and current.replace(method,embedded).sha256_text()==BASELINE_FILE_SHA256
	_check(exact,"Embedded baseline ensure differs byte-for-byte from its pinned Git method")
	_check(only_ensure,"Production source differs from the pinned Git file outside ensure")
	return {"commit":BASELINE_COMMIT,"also_identical_at":BASELINE_ALSO_IDENTICAL_AT,
		"git_blob_object_id":BASELINE_BLOB,"git_file_sha256":BASELINE_FILE_SHA256,
		"git_method_sha256":BASELINE_METHOD_SHA256,"embedded_method_sha256":embedded.sha256_text(),
		"embedded_method_byte_exact":exact,"only_ensure_changed":only_ensure,
		"current_method_sha256":method.sha256_text(),
		"scope":"Pinned Git values were verified offline using git show/rev-parse and the Git blob header. Runtime verifies the exact embedded bytes and full-file reverse replacement; no Git command runs here."}

func _references(world: WorldState) -> Dictionary:
	var state: Dictionary=world.facts.waiting_life
	return {"state":state,"clocks":state.clocks,"entries":state.clocks.duplicate()}

func _same_references(world: WorldState, refs: Dictionary) -> bool:
	if not is_same(world.facts.waiting_life,refs.state) or not is_same(world.facts.waiting_life.clocks,refs.clocks): return false
	for id: String in refs.entries:
		if not refs.clocks.has(id) or not is_same(refs.clocks[id],refs.entries[id]): return false
	return true

func _readonly(world: WorldState, snapshot: Dictionary, rng_sha: String, refs: Dictionary, label: String) -> Dictionary:
	var frozen: Dictionary=world.freeze()
	var full_sha: String=_hash(frozen)
	var result: Dictionary={"facts_equal":frozen==snapshot and full_sha==_input_world_sha,"rng_equal":_hash(world.facts.rng)==rng_sha,
		"complete_world_sha256":full_sha,
		"container_identity_equal":_same_references(world,refs)}
	_check(result.facts_equal and result.rng_equal and result.container_identity_equal,"Read-only clock boundary changed: "+label)
	return result

func _workload(world: WorldState) -> Dictionary:
	var active: Array=world.active_visit_ids()
	var with_clock: Array=[]
	var without_clock: Array=[]
	var admitted_missing: Array=[]
	var eligible_missing: Array=[]
	var admitted: Dictionary={}
	for stay: Dictionary in world.facts.ward_stays.values():
		if stay.has("admitted_tick"): admitted[str(stay.visit_id)]=true
	for id: String in active:
		if world.facts.waiting_life.clocks.has(id): with_clock.append(id)
		else:
			without_clock.append(id)
			if admitted.has(id): admitted_missing.append(id)
			else: eligible_missing.append(id)
	return {"active_visit_ids":active,"active_count":active.size(),"clock_records":world.facts.waiting_life.clocks.size(),
		"active_with_clock_ids":with_clock,"active_with_clock_count":with_clock.size(),
		"active_missing_clock_ids":without_clock,"active_missing_clock_count":without_clock.size(),
		"admitted_missing_clock_ids":admitted_missing,"missing_eligible_clock_ids":eligible_missing}

func _life(content: HospitalContent, before: bool, counted: bool = false) -> HospitalWaitingLife:
	var space: HospitalSpace=HospitalSpace.new(content)
	if counted:
		if before: return CountedBefore.new(content,space)
		return CountedAfter.new(content,space)
	if before: return BeforeLife.new(content,space)
	return HospitalWaitingLife.new(content,space)

func _counts(life: HospitalWaitingLife, world: WorldState, iterations: int, expected: int) -> Dictionary:
	var before: int=int(life.get("admission_queries"))
	for _repeat: int in iterations: life.ensure(world)
	var actual: int=int(life.get("admission_queries"))-before
	_check(actual==expected,"Actual admission-query count differs from the complete input-derived expectation")
	return {"timed":false,"ensure_calls":iterations,"admission_queries":actual,"expected_admission_queries":expected}

func _measure(life: HospitalWaitingLife, world: WorldState, iterations: int) -> Dictionary:
	var started: int=Time.get_ticks_usec()
	for _repeat: int in iterations: life.ensure(world)
	return {"elapsed_us":Time.get_ticks_usec()-started,"derived_ensure_calls":iterations,"counter_enabled":false}

func run() -> void:
	var input: String=""
	var output: String=""
	var expected_sha: String=""
	var iterations: int=1000
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--input="): input=arg.trim_prefix("--input=")
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
		if arg.begins_with("--expected-sha="): expected_sha=arg.trim_prefix("--expected-sha=")
		if arg.begins_with("--iterations="): iterations=arg.trim_prefix("--iterations=").to_int()
	if input.is_empty() or output.is_empty() or expected_sha!=INPUT_SHA256 or iterations!=1000 or FileAccess.file_exists(output): quit(2);return
	if FileAccess.get_sha256(input)!=INPUT_SHA256: push_error("Fixed complete mixed input identity differs");quit(2);return
	var file: FileAccess=FileAccess.open(input,FileAccess.READ)
	if file==null: quit(2);return
	var envelope: Dictionary=file.get_var(false);file.close()
	var content: HospitalContent=HospitalContent.new()
	if not content.error.is_empty() or envelope.get("content_fingerprint","")!=content.content_fingerprint: quit(2);return
	var world: WorldState=WorldState.new(envelope.facts)
	var snapshot: Dictionary=world.freeze()
	_input_world_sha=_hash(snapshot)
	var rng_sha: String=_hash(world.facts.rng)
	var validation_before: String=world.validate(content)
	_check(validation_before.is_empty(),"Invalid complete input World: "+validation_before)
	_check(OS.get_thread_caller_id()==OS.get_main_thread_id(),"The probe must run on the main thread")
	var policy: Dictionary=ClassDB.class_call_static("PlatformThreadPolicy","apply_main_thread") if ClassDB.class_exists("PlatformThreadPolicy") else {"applied":false}
	_check(policy.get("applied",false),"Application main-thread policy failed")
	var proof: Dictionary=_proof()
	var input_ready: bool=world.facts.get("waiting_life") is Dictionary and world.facts.waiting_life.get("clocks") is Dictionary and world.facts.waiting_life.get("toilet_queues") is Dictionary
	_check(input_ready,"The real boundary lacks initialized clock/toilet collections; do not fabricate a warm input")
	var workload: Dictionary=_workload(world) if input_ready else {}
	if input_ready: _check(workload.missing_eligible_clock_ids.is_empty(),"The real input requires legitimate clock initialization and is not a read-only ensure boundary")
	var references: Dictionary=_references(world) if input_ready else {}
	var counted: Dictionary={}
	var timings: Array=[]
	var expected_before: int=int(workload.get("active_count",0))*iterations
	var expected_after: int=int(workload.get("active_missing_clock_count",0))*iterations
	if _errors.is_empty():
		for before: bool in [true,false]:
			var name: String="before" if before else "after"
			counted[name]=_counts(_life(content,before,true),world,iterations,expected_before if before else expected_after)
			counted[name].readonly=_readonly(world,snapshot,rng_sha,references,"counted "+name)
		for pair: int in 3:
			if not _errors.is_empty(): break
			var lives: Dictionary={"before":_life(content,true),"after":_life(content,false)}
			var warm: Dictionary={}
			for name: String in ["before","after"]:
				lives[name].ensure(world)
				warm[name]=_readonly(world,snapshot,rng_sha,references,"warm "+name)
			var order: Array[String]=["before","after"]
			if pair%2!=0: order.reverse()
			var row: Dictionary={"operation":"ensure","pair":pair+1,"order":order,
				"active_count":workload.active_count,"clock_records":workload.clock_records,
				"active_with_clock_count":workload.active_with_clock_count,"active_missing_clock_count":workload.active_missing_clock_count,
				"untimed_complete_warm_calls_per_side":1,"warm_readonly":warm}
			if _errors.is_empty():
				for name: String in order:
					row[name]=_measure(lives[name],world,iterations)
					row[name].readonly=_readonly(world,snapshot,rng_sha,references,"timed "+name)
				row.complete_results_equal=row.before.readonly.complete_world_sha256==row.after.readonly.complete_world_sha256
				_check(row.complete_results_equal,"Timed A/B complete typed results differ")
			timings.append(row)
	var readonly: bool=world.freeze()==snapshot and _hash(world.freeze())==_input_world_sha and _hash(world.facts.rng)==rng_sha
	_check(readonly,"Complete input facts/RNG changed")
	var validation_after: String=world.validate(content)
	_check(validation_after.is_empty(),"Invalid World after local queries: "+validation_after)
	var result: Dictionary={"ok":_errors.is_empty(),"errors":_errors,"input":input,"input_sha256":INPUT_SHA256,
		"whole_world_readonly":readonly,"whole_world_sha256":_input_world_sha,"rng_sha256":rng_sha,
		"container_identity_preserved":_same_references(world,references) if input_ready else false,
		"world_validation_before":validation_before,"world_validation_after":validation_after,
		"actor_ids":world.ids("actors"),"actor_records":world.facts.actors.size(),"present":world.present_actor_count(),
		"moves":world.facts.moves.size(),"ward_stays":world.facts.ward_stays.size(),"tick":world.sim_tick,
		"workload":workload,"iterations_per_side":iterations,"pairs_per_operation":3,"untimed_counts":counted,
		"timings":timings,"baseline":proof,"policy":policy,"engine":OS.get_executable_path(),
		"engine_sha256":FileAccess.get_sha256(OS.get_executable_path()),"waiting_life_sha256":FileAccess.get_sha256(LIFE_SOURCE),
		"probe_sha256":FileAccess.get_sha256(PROBE_SOURCE),
		"scope":"Complete fixed 0daf mixed World and all Actor/Visit facts retained. Main-thread local ensure only, not a simulation window or 160-person acceptance. Separate counted runs and three plain AB/BA/AB pairs each make 1000 complete ensure calls per side. Before is the byte-exact pinned Git ensure; shared methods/content are unchanged. Input-derived expected counts include every active Visit and every missing clock; no active count or zero-query answer is preset. Validation, snapshots, hashes, container checks and one warm call per pair are outside timing. Timed calls have no admission counter and include loop/dispatch overhead."}
	var report: FileAccess=FileAccess.open(output,FileAccess.WRITE)
	if report==null: quit(2);return
	report.store_string(JSON.stringify(result,"\t"));report.close()
	print(JSON.stringify({"ok":result.ok,"actor_records":result.actor_records,"workload":workload,"timings":timings,"errors":_errors}))
	quit(0 if result.ok else 1)
