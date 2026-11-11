extends SceneTree

class BudgetGuard extends RefCounted:
	var status: Dictionary={}
	func get_resource_status() -> Dictionary: return status

# Independent original formula. This retains every value conversion, key
# charge, recursive visit and integer operation before key-name reuse.
static func reference_estimate(value: Variant) -> int:
	if value is Dictionary:
		var size: int=2
		for key: String in value:
			size+=key.to_utf8_buffer().size()*6+4+reference_estimate(value[key])
		return size
	if value is Array:
		var size: int=2
		for element: Variant in value:
			size+=reference_estimate(element)+1
		return size
	return str(value).to_utf8_buffer().size()*6+32

func _initialize() -> void:
	call_deferred("_run")

func _key_work(value: Variant, names: Dictionary) -> int:
	var count: int=0
	if value is Dictionary:
		for key: String in value:
			names[key]=true
			count+=1+_key_work(value[key],names)
	elif value is Array:
		for element: Variant in value: count+=_key_work(element,names)
	return count

func _run() -> void:
	var input: String=""
	var output: String=""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--input="): input=argument.trim_prefix("--input=")
		if argument.begins_with("--output="): output=argument.trim_prefix("--output=")
	if input.is_empty() or output.is_empty() or FileAccess.file_exists(output) or FileAccess.get_sha256(input)!="752924c562f275804cee40cbd2a8760f8f0780cab3276a04330db63a2866e780": push_error("Use the original complete160 input and a new result path");quit(2);return
	var policy: Dictionary={"applied":false,"reason":"platform_default"}
	if OS.get_name()=="Windows" and ClassDB.class_exists("PlatformThreadPolicy"): policy=ClassDB.class_call_static("PlatformThreadPolicy","apply_main_thread")
	var file: FileAccess=FileAccess.open(input,FileAccess.READ)
	if file==null: push_error("Cannot open the original complete160 input");quit(2);return
	var envelope: Dictionary=file.get_var(false)
	file.close()
	var world: WorldState=WorldState.new(envelope.facts)
	var before: PackedByteArray=var_to_bytes(world.facts)
	var nested: Variant={"字段":"末端"}
	for depth: int in 24: nested={"字段":[nested,{"字段":depth,"":""}]}
	var escaped: String="\n\t\"\\"+String.chr(0)
	var combining: String="e"+String.chr(0x0301)
	var samples: Dictionary={
		"empty_dictionary":{},"empty_array":[],"empty_key":{"":{}},
		"leaf_variants":[null,true,false,0,-1,9223372036854775807,-9223372036854775807,0.0,-0.0,1.25,NAN,INF,-INF,&"标签",Vector2i(1,-2),Color(0.1,0.2,0.3,0.4),PackedByteArray([0,1,255])],
		"unicode":{"中文":1,"😀":2,"é":3,combining:4,"𐐀":"终点"},
		"stringname_keys":{&"名称":{&"😀":1,&"":""},&"same":[{"same":false},{&"same":null}]},
		"escaped_keys":{escaped:escaped,String.chr(0):["\"","\\"]},
		"repeated_names":[{"同名":{"同名":1,"":[]}}, {"同名":[{"同名":false},{"":null}]}],
		"nested":nested,"complete160":world.facts
	}
	var checks: Dictionary={}
	for name: String in samples:
		var original: PackedByteArray=var_to_bytes(samples[name])
		checks[name]=HospitalSnapshots.estimate(samples[name])==reference_estimate(samples[name]) and var_to_bytes(samples[name])==original
	var changed: Dictionary={"重复":"短"}
	var first: int=HospitalSnapshots.estimate(changed)
	changed["重复"]=escaped.repeat(40)
	checks.values_recomputed=HospitalSnapshots.estimate(changed)==reference_estimate(changed) and HospitalSnapshots.estimate(changed)!=first
	changed["新字段"]={"重复":null}
	checks.next_call_new_keys=HospitalSnapshots.estimate(changed)==reference_estimate(changed)
	var key_costs: Dictionary={}
	var amount: int=HospitalSnapshots._estimate(world.facts,key_costs)
	var names: Dictionary={}
	var key_occurrences: int=_key_work(world.facts,names)
	checks.all_complete_input_keys_cached=key_costs.size()==names.size() and key_costs.size()==2430 and key_occurrences==44642
	checks.every_cached_key_charge_exact=true
	for key: String in names:
		if not key_costs.has(key) or key_costs[key]!=key.to_utf8_buffer().size()*6+4: checks.every_cached_key_charge_exact=false
	checks.complete_input_original_amount=amount==5723348 and amount==reference_estimate(world.facts)
	var other_world: WorldState=WorldState.new(world.freeze())
	other_world.facts.display_name="另一个完整资料库😀".repeat(17)
	var other_amount: int=reference_estimate(other_world.facts)
	checks.two_world_calls_isolated=not is_same(world.facts,other_world.facts) and other_amount!=amount and HospitalSnapshots.estimate(other_world.facts)==other_amount and HospitalSnapshots.estimate(world.facts)==amount
	var guard: BudgetGuard=BudgetGuard.new()
	var store: HospitalSnapshots=HospitalSnapshots.new(null,guard)
	var memory_threshold: int=(amount*4+HospitalSnapshots.HEADROOM)*2
	var disk_threshold: int=amount*3+HospitalSnapshots.HEADROOM
	var budget_samples: Array=[
		{"id":"exact","memory":memory_threshold,"disk":disk_threshold,"expected":true},
		{"id":"memory_minus_one","memory":memory_threshold-1,"disk":disk_threshold,"expected":false},
		{"id":"disk_minus_one","memory":memory_threshold,"disk":disk_threshold-1,"expected":false},
		{"id":"plus_one","memory":memory_threshold+1,"disk":disk_threshold+1,"expected":true}
	]
	for sample: Dictionary in budget_samples:
		guard.status={"ok":true,"available_physical_bytes":sample.memory,"available_disk_bytes":sample.disk}
		checks["budget_"+sample.id]=store._budget(HospitalSnapshots.estimate(world.facts))==sample.expected and store._budget(reference_estimate(world.facts))==sample.expected
	guard.status={"ok":false}
	checks.budget_resource_failure=not store._budget(amount)
	checks.budget_numeric_guards=not store._budget(-1) and not store._budget(2305843009196916736)
	var rows: Array=[]
	for repeat: int in 3:
		for variant: String in (["reference","candidate"] if repeat%2==0 else ["candidate","reference"]):
			var operation: Callable=reference_estimate if variant=="reference" else HospitalSnapshots.estimate
			var started_at: int=Time.get_ticks_usec()
			var actual: int=operation.call(world.facts)
			var elapsed: int=Time.get_ticks_usec()-started_at
			checks[variant+"_round_"+str(repeat+1)]=actual==amount
			rows.append({"variant":variant,"repeat":repeat+1,"elapsed_usec":elapsed,"estimated_bytes":actual})
	checks.source_facts_exact=var_to_bytes(world.facts)==before
	var ok: bool=checks.values().all(func(value: Variant)->bool:return value==true)
	var result: Dictionary={"complete":true,"ok":ok,"scope":"Independent original estimate formula and actual candidate on all complete160 facts. Local function timing only; deterministic resource-state doubles call the unchanged real _budget method at exact boundaries, not real machine RAM pressure.","input_sha256":FileAccess.get_sha256(input),"snapshot_source_sha256":FileAccess.get_sha256("res://game/persistence/snapshot_store.gd"),"test_source_sha256":FileAccess.get_sha256("res://tests/acceptance/snapshot_estimate_contract.gd"),"checks":checks,"main_thread_policy":policy,"work":{"dictionary_key_occurrences":key_occurrences,"actual_cached_key_names":key_costs.size(),"estimated_bytes":amount,"memory_threshold":memory_threshold,"disk_threshold":disk_threshold},"timing":rows}
	file=FileAccess.open(output,FileAccess.WRITE)
	if file==null: push_error("Cannot write the estimate contract result");quit(2);return
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	print("SNAPSHOT_ESTIMATE="+JSON.stringify({"ok":ok,"checks":checks.size(),"output":output}))
	quit(0 if ok else 1)
