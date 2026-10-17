extends SceneTree

const Fixture = preload("res://tools/performance/fixture.gd")
const Timing = preload("res://tools/performance/profile.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var count: int = 160
	var steps: int = 3
	var output: String = "res://diagnostic.json"
	var layout: String = "four_floors"
	var profile: bool = false
	var input: String = ""
	var operation: String = "step"
	var binding: String = "B_S13_D09_M09"
	var shift: int = 0
	var constraints: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--actors="): count = argument.get_slice("=",1).to_int()
		if argument.begins_with("--steps="): steps = argument.get_slice("=",1).to_int()
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		if argument.begins_with("--layout="): layout = argument.get_slice("=",1)
		if argument=="--profile": profile = true
		if argument.begins_with("--input="): input = argument.trim_prefix("--input=")
		if argument.begins_with("--operation="): operation = argument.get_slice("=",1)
		if argument.begins_with("--binding="): binding = argument.get_slice("=",1)
		if argument.begins_with("--shift="): shift = argument.get_slice("=",1).to_int()
		if argument.begins_with("--constraints="): constraints = argument.trim_prefix("--constraints=")
	var started: int = Time.get_ticks_usec()
	var content: HospitalContent = HospitalContent.new()
	var fixture: RefCounted = Fixture.new(content,count,layout,input)
	var simulation: HospitalSimulation = HospitalSimulation.new(fixture.world,content)
	var validation: String = fixture.world.validate(content)
	print("PERFORMANCE_FIXTURE="+JSON.stringify({"elapsed_ms":(Time.get_ticks_usec()-started)/1000.0,"description":fixture.describe(),"validation":validation}))
	if not validation.is_empty() or not fixture.errors.is_empty():
		quit(2)
		return
	fixture.store_input(output+".input.bin")
	var timing: RefCounted = Timing.new()
	if profile:
		timing.snapshot_path = output+".profile.json"
		if not timing.attach(simulation):
			quit(2)
			return
	var samples: Array = []
	if operation=="capture":
		var preparation: CaptureTiming = CaptureTiming.new(content)
		var previous: Dictionary = {}
		var before: Dictionary = fixture.world.freeze()
		for repeat: int in steps:
			var begin: int = Time.get_ticks_usec()
			var captured: Dictionary = preparation._capture(fixture.world,true,-1)
			var elapsed: int = Time.get_ticks_usec()-begin
			var collections: Dictionary = {}
			# Scan/count/serialization observations are outside capture timing.
			# Serialized bytes estimate payload, never allocation or residency.
			for field: String in captured.facts:
				if not captured.facts[field] is Dictionary: continue
				var values: Dictionary = captured.facts[field]
				var prior: Dictionary = previous.get(field,{})
				var counters: Dictionary = {"records_scanned":values.size(),"records_compared":0,"deep_compare_count":0,"records_changed":0,"records_reused":0,"copied_payload_bytes_estimate":0}
				for id: Variant in values:
					var nested: bool = values[id] is Dictionary or values[id] is Array
					if prior.has(id):
						counters.records_compared += 1
						if nested: counters.deep_compare_count += 1
					if prior.has(id) and (is_same(values[id],prior[id]) if nested else values[id]==prior[id]): counters.records_reused += 1
					else:
						counters.records_changed += 1
						counters.copied_payload_bytes_estimate += var_to_bytes(values[id]).size()
				collections[field] = counters
			samples.append({"capture_us":elapsed,"ownership_us":preparation.ownership_us,"extraction_us":elapsed-preparation.ownership_us,"collections":collections})
			previous = captured.facts
		var evidence: Dictionary = {"diagnostic":true,"operation":operation,"fixture":fixture.describe(),"samples":samples,"metrics":preparation.metrics(),"readonly":fixture.world.freeze()==before,"bytes_kind":"serialized_payload_estimate"}
		var report: FileAccess = FileAccess.open(output,FileAccess.WRITE)
		report.store_string(JSON.stringify(evidence,"\t"))
		preparation.dispose()
		simulation.dispose()
		print("PERFORMANCE_CAPTURE="+JSON.stringify({"samples":samples.size(),"readonly":evidence.readonly,"output":output}))
		quit(0 if evidence.readonly else 1)
		return
	if operation in ["preparation","session"]:
		var begin: int = Time.get_ticks_usec()
		var session: GameSession = GameSession.new(simulation,"preparation-diagnostic")
		var main_us: int = Time.get_ticks_usec()-begin
		var max_main_us: int = main_us
		session.set_speed(1)
		var completed: Array[TickResult] = []
		var polls: int = 0
		var requested_steps: int = steps if operation=="session" else 1
		while completed.size()<requested_steps and simulation.preparing_error().is_empty():
			var poll_started: int = Time.get_ticks_usec()
			var batch: Array[TickResult] = session.advance(0.1 if not simulation.pending() else 0.0)
			completed.append_array(batch)
			var elapsed: int = Time.get_ticks_usec()-poll_started
			main_us += elapsed
			max_main_us = maxi(max_main_us,elapsed)
			polls += 1
			if batch.is_empty(): await create_timer(0.005).timeout
		var evidence: Dictionary = {"diagnostic":true,"operation":operation,"wall_ms":(Time.get_ticks_usec()-begin)/1000.0,
			"main_ms":main_us/1000.0,"max_main_slice_ms":max_main_us/1000.0,"polls":polls,
			"step_ms":completed[0].elapsed_us/1000.0 if not completed.is_empty() else null,
			"completed_steps":completed.size(),"requested_steps":requested_steps,
			"kernel_steps_ms":completed.map(func(step: TickResult)->float: return step.elapsed_us/1000.0),
			"metrics":simulation.services.arrivals.preparation_metrics(),"plan":fixture.world.facts.arrivals.plan,
			"error":simulation.preparing_error(),"tracked_bytes":OS.get_static_memory_usage(),"profile":timing.report()}
		fixture.store_input(output+".after.bin")
		var report: FileAccess = FileAccess.open(output,FileAccess.WRITE)
		report.store_string(JSON.stringify(evidence,"\t"))
		print("PERFORMANCE_PREPARATION="+JSON.stringify(evidence.merged({"profile":{}})))
		simulation.dispose()
		quit(0 if completed.size()==requested_steps else 1)
		return
	if operation in ["solve","solver","pairs"]:
		var file: FileAccess = FileAccess.open(constraints,FileAccess.READ)
		var saved: Dictionary = file.get_var()
		var parts: int = 0
		var groups: int = 0
		for case: Dictionary in saved.classes:
			parts += case.bundles.size()
			groups += case.get("choice_groups",{}).size()
			for options: Array in case.get("choice_groups",{}).values(): parts += options.size()
		print("PERFORMANCE_CONSTRAINTS="+JSON.stringify({"classes":saved.classes.size(),"groups":groups,"parts":parts,"tracked_bytes":OS.get_static_memory_usage()}))
		var begin: int = Time.get_ticks_usec()
		var result: Dictionary
		if operation=="solver":
			var solver: RefCounted = timing.solver()
			result = solver.solve(saved.classes,saved.budgets)
		elif operation=="pairs":
			for case: Dictionary in saved.classes:
				if case.get("choice_groups",{}).has("reception"): case.reception_bundles = case.choice_groups.reception
			result = simulation.services.arrivals._structural_pairs(fixture.world,saved.classes,int(saved.shift))
			result.structural_pairs = result.get("pairs",-1)
		else: result = simulation.services.arrivals._solve_roles(fixture.world,saved.classes,saved.budgets,int(saved.shift))
		print("PERFORMANCE_SOLVE="+JSON.stringify({"operation":operation,"elapsed_ms":(Time.get_ticks_usec()-begin)/1000.0,"capacity":result.get("capacity",{}),"structural_pairs":result.get("structural_pairs",-1),"error":result.get("error",""),"bundles":result.get("bundle_count",0)}))
		var report: FileAccess = FileAccess.open(output,FileAccess.WRITE)
		report.store_string(JSON.stringify({"diagnostic":true,"result":result,"profile":timing.report()},"\t"))
		simulation.dispose()
		quit(0)
		return
	if operation in ["classes","prepared"]:
		var begin: int = Time.get_ticks_usec()
		var service: RefCounted = simulation.services.arrivals
		var query: Dictionary = {}
		var classes: Array = service._reference_classes(fixture.world,shift,query)
		var reference_ms: float = (Time.get_ticks_usec()-begin)/1000.0
		var budgets: Dictionary = service._resource_budgets(fixture.world,classes,shift,query.resource_ids)
		if operation=="prepared":
			begin = Time.get_ticks_usec()
			var initial: Dictionary = service._solve_roles(fixture.world,classes,budgets,shift,query.model_key)
			var solve_ms: float = (Time.get_ticks_usec()-begin)/1000.0
			var warm: Array = []
			var valid: bool = not initial.has("error")
			for repeat: int in 2:
				begin = Time.get_ticks_usec()
				var repeated_query: Dictionary = {}
				var repeated: Array = service._reference_classes(fixture.world,shift,repeated_query)
				var repeated_budgets: Dictionary = service._resource_budgets(fixture.world,repeated,shift,repeated_query.resource_ids)
				var updated: Dictionary = service._solve_roles(fixture.world,repeated,repeated_budgets,shift,repeated_query.model_key)
				warm.append({"elapsed_ms":(Time.get_ticks_usec()-begin)/1000.0,"result":updated})
				# Cumulative timing and proof counters may change on a warm call.
				# Compare the complete numerical/model summary separately.
				var stable: Dictionary = initial.duplicate()
				var current: Dictionary = updated.duplicate()
				for field: String in ["timing_us","nursing_timing_us","proof_reuses"]:
					stable.erase(field)
					current.erase(field)
				valid = valid and repeated==classes and current==stable
			var evidence: Dictionary = {"diagnostic":true,"reference_ms":reference_ms,"solve_ms":solve_ms,"initial":initial,"warm":warm,"valid":valid,"classes":classes.size(),"resources":budgets.size(),"tracked_bytes":OS.get_static_memory_usage(),"profile":timing.report()}
			var report: FileAccess = FileAccess.open(output,FileAccess.WRITE)
			report.store_string(JSON.stringify(evidence,"\t"))
			print("PERFORMANCE_PREPARED="+JSON.stringify(evidence.merged({"profile":{}})))
			simulation.dispose()
			quit(0 if valid else 1)
			return
		var file: FileAccess = FileAccess.open(output,FileAccess.WRITE)
		file.store_var({"classes":classes,"budgets":budgets,"shift":shift})
		print("PERFORMANCE_CLASSES="+JSON.stringify({"elapsed_ms":(Time.get_ticks_usec()-begin)/1000.0,"classes":classes.size(),"budgets":budgets.size(),"tracked_bytes":OS.get_static_memory_usage()}))
		simulation.dispose()
		quit(0)
		return
	if operation=="graphs":
		for actor_id: String in ["bench_staff_0000","bench_patient_0000"]:
			for floor_id: int in fixture.floors:
				var before: int = OS.get_static_memory_usage()
				var begin: int = Time.get_ticks_usec()
				var graph: FloorNavigation = simulation.space._navigation.graph(simulation.space,fixture.world,floor_id,fixture.world.facts.actors[actor_id],[],{})
				print("PERFORMANCE_GRAPH="+JSON.stringify({"actor":actor_id,"body":simulation.space.body(fixture.world.facts.actors[actor_id]),"floor":floor_id,"elapsed_ms":(Time.get_ticks_usec()-begin)/1000.0,"tracked_bytes_delta":OS.get_static_memory_usage()-before,"tracked_bytes":OS.get_static_memory_usage(),"charged":simulation.space._navigation._charged,"retained":simulation.space._navigation._entries.size(),"points":graph.get_point_count()}))
		simulation.dispose()
		quit(0)
		return
	if operation=="route":
		for index: int in 3:
			var begin: int = Time.get_ticks_usec()
			var route: Dictionary = simulation.space.route(fixture.world,"bench_staff_0000",1,[48,91],[],{},true)
			print("PERFORMANCE_ROUTE="+JSON.stringify({"elapsed_ms":(Time.get_ticks_usec()-begin)/1000.0,"ok":route.ok,"reason":route.get("reason",""),"cells":route.get("path",[]).size()}))
		simulation.dispose()
		quit(0)
		return
	if operation=="reference":
		var begin: int = Time.get_ticks_usec()
		var reference: Dictionary = simulation.clinic.reference_demand(fixture.world,binding,false,0)
		print("PERFORMANCE_REFERENCE="+JSON.stringify({"binding":binding,"elapsed_ms":(Time.get_ticks_usec()-begin)/1000.0,"ok":reference.ok,"bundles":reference.bundles.size()}))
		var file: FileAccess = FileAccess.open(output,FileAccess.WRITE)
		file.store_string(JSON.stringify({"diagnostic":true,"reference":reference,"profile":timing.report()},"\t"))
		simulation.dispose()
		quit(0)
		return
	for index: int in steps:
		var begin: int = Time.get_ticks_usec()
		var result: TickResult = simulation.step()
		var sample: Dictionary = {"tick":fixture.world.sim_tick,"elapsed_ms":(Time.get_ticks_usec()-begin)/1000.0,"present":fixture.world.present_actor_count(),"moves":fixture.world.facts.moves.size(),"preparations":fixture.world.facts.preparations.size(),"sessions":fixture.world.facts.sessions.size(),"events":result.facts.size()}
		if profile: sample.profile = timing.report()
		samples.append(sample)
		print("PERFORMANCE_STEP="+JSON.stringify(sample.merged({"profile":{}}) if profile else sample))
		fixture.store_input(output+".after.bin")
		var file: FileAccess = FileAccess.open(output,FileAccess.WRITE)
		file.store_string(JSON.stringify({"diagnostic":true,"fixture":fixture.describe(),"steps":samples,"profile":timing.report()},"\t"))
		file.close()
	simulation.dispose()
	quit(0)

class CaptureTiming extends ArrivalPreparation:
	var ownership_us: int = 0
	func _own_capture(facts: Dictionary) -> Dictionary:
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = super._own_capture(facts)
		ownership_us = Time.get_ticks_usec()-started
		return result
