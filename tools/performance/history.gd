extends SceneTree

# Bounded diagnostic: one active Visit, identical live hospital and commands,
# three legal archived-history sizes. This is not a Release acceptance run.
const F = preload("res://game/arrivals/exact_fraction.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var output: String = "res://history.json"
	var steps: int = 30
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		if argument.begins_with("--steps="): steps = argument.trim_prefix("--steps=").to_int()
	if steps<=0 or steps>=WorldState.TICKS_PER_DAY-1000:
		quit(2)
		return
	var content: HospitalContent = HospitalContent.new()
	var base: WorldState = HospitalFactory.create("00000000-0000-4000-8000-000000000001","历史量诊断",true,content)
	var setup: HospitalSimulation = HospitalSimulation.new(base,content)
	setup.services.arrivals.execute(base,"tutorial_set_enabled",{"enabled":false})
	setup.services.arrivals.execute(base,"arrivals_intake",{"open":false})
	# The input starts inside an already frozen zero-opportunity day. This
	# isolates ordinary complete steps; capacity/day-boundary cost is separate.
	base.facts.arrivals.plan = {"day_index":1,"preset":"normal","scale_numerator":3,"shift_capacities":[F.make(),F.make(),F.make()],"opportunity_count":0,"shift_opportunity_counts":[0,0,0],"schedule_seed":null,"schedule_algorithm":"arrival-load-slot-v1","next_slot_index":0,"held_capacity_fraction":F.make(),"held_scale_numerator":0}
	var admitted: CommandResult = setup.clinic.execute(base,"clinical_arrive",{"arrival_key":"history_active","binding_id":"B_S49_D37_M37","personality_id":"PP01"})
	if not admitted.accepted:
		push_error(admitted.reason)
		setup.dispose()
		quit(2)
		return
	base.facts.sim_tick = 1000
	var input: Dictionary = base.freeze()
	var visit: Dictionary = input.visits[admitted.changed_ids[0]]
	var actor: Dictionary = input.actors[visit.actor_id]
	setup.dispose()
	var observations: Array = []
	var valid: bool = true
	var live_result: Dictionary = {}
	for history: int in [16,64,256]:
		var facts: Dictionary = input.duplicate(true)
		for index: int in history:
			var id: String = "history_%04d"%index
			var actor_id: String = id+"_actor"
			var archived: Dictionary = visit.duplicate(true)
			archived.merge({"id":id,"actor_id":actor_id,"arrival_key":id,"phase":"departed","ticket_id":"","final_result":"referred","departed_tick":0,"departure_recorded":true,"companion_intent":false},true)
			var past_actor: Dictionary = actor.duplicate(true)
			past_actor.merge({"id":actor_id,"location":{"kind":"outside"}},true)
			facts.visits[id] = archived
			facts.actors[actor_id] = past_actor
			facts.arrival_receipts[id] = id
		var world: WorldState = WorldState.new(facts)
		var begin: int = Time.get_ticks_usec()
		var simulation: HospitalSimulation = HospitalSimulation.new(world,content)
		var load_us: int = Time.get_ticks_usec()-begin
		var initial_validation: String = world.validate(content)
		var samples: Array = []
		for index: int in steps:
			begin = Time.get_ticks_usec()
			var completed: TickResult = simulation.step_nonblocking()
			samples.append(Time.get_ticks_usec()-begin)
			valid = valid and completed!=null and simulation.preparing_error().is_empty()
			# Outside timing: compare the index with original facts each boundary.
			var expected: Array = []
			for id: String in world.facts.visits:
				var record: Dictionary = world.facts.visits[id]
				if record.phase!="departed" or not record.get("departure_recorded",false): expected.append(id)
			expected.sort()
			valid = valid and world.active_visit_ids()==expected
		var final_validation: String = world.validate(content)
		var live: Dictionary = world.freeze()
		for index: int in history:
			var id: String = "history_%04d"%index
			live.visits.erase(id)
			live.actors.erase(id+"_actor")
			live.arrival_receipts.erase(id)
		if live_result.is_empty(): live_result = live
		var same: bool = live==live_result
		valid = valid and initial_validation.is_empty() and final_validation.is_empty() and same
		observations.append({"history":history,"active":world.active_visit_ids().size(),"load_us":load_us,"complete_step_us":samples,"initial_validation":initial_validation,"final_validation":final_validation,"live_facts_and_rng_equal":same})
		simulation.dispose()
	# Separate fixed operation: settled ledger history grows, pending remains 0
	# for the warm samples and exactly one for the final settlement.
	var ledger_observations: Array = []
	for history: int in [16,1024,8192]:
		var facts: Dictionary = input.duplicate(true)
		for index: int in history:
			var component: String = "history_%08d"%index
			facts.ledger.entries[facts.hospital_id+":"+component] = {"owner_id":facts.hospital_id,"component":component,"amount":0,"tick":0,"settled":true}
		var world: WorldState = WorldState.new(facts)
		var before: Dictionary = world.freeze()
		var started: int = Time.get_ticks_usec()
		var first: Array[SimEvent] = HospitalLedger.settle(world)
		var rebuild_us: int = Time.get_ticks_usec()-started
		var samples: Array = []
		for index: int in steps:
			started = Time.get_ticks_usec()
			var events: Array[SimEvent] = HospitalLedger.settle(world)
			samples.append(Time.get_ticks_usec()-started)
			valid = valid and events.is_empty()
		var readonly: bool = world.freeze()==before and first.is_empty()
		var posted: CommandResult = HospitalLedger.post(world,LedgerEntry.new(world.hospital_id,"diagnostic_pending",1),false)
		started = Time.get_ticks_usec()
		var settled: Array[SimEvent] = HospitalLedger.settle(world)
		var one_pending_us: int = Time.get_ticks_usec()-started
		var validation: String = world.validate(content)
		valid = valid and readonly and posted.accepted and settled.size()==1 and validation.is_empty()
		ledger_observations.append({"settled_history":history,"pending_rebuild_us":rebuild_us,"zero_pending_settle_us":samples,"one_pending_settle_us":one_pending_us,"readonly":readonly,"validation":validation})
	var digest: HashingContext = HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(var_to_bytes(input))
	var report: Dictionary = {"diagnostic":true,"operation":"fixed_active_history","steps_per_scale":steps,"observations":observations,"valid":valid,"engine":Engine.get_version_info().string,"content_fingerprint":content.content_fingerprint,"input_sha256":digest.finish().hex_encode(),"native_sha256":FileAccess.get_sha256("res://game/platform/windows/bin/oddly_good_platform.windows.x86_64.dll")}
	report.ledger_observations = ledger_observations
	var file: FileAccess = FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("PERFORMANCE_HISTORY="+JSON.stringify({"valid":valid,"scales":observations.size(),"steps":steps,"output":output}))
	quit(0 if valid else 1)
