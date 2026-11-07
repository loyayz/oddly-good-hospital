extends SceneTree
const Population = preload("res://tools/performance/acceptance/fixtures/prepare_inputs.gd")
const Profile = preload("res://tools/performance/step_profile.gd")
var output: String
func _initialize() -> void: call_deferred("_run")
func write_json(path: String, data: Dictionary) -> void:
	var f: FileAccess = FileAccess.open(path,FileAccess.WRITE);f.store_string(JSON.stringify(data,"\t"));f.close()
func population_current(world: WorldState) -> Dictionary:
	var result: Dictionary = Population.population_of(world)
	var unclassified: Array = result.unowned.duplicate()
	result.erase("unowned")
	var others: Array = []
	for id: String in unclassified.duplicate():
		var contractor: Dictionary = world.facts.get("maintenance",{}).get("contractors",{}).get(id,{})
		var orders: Dictionary = world.facts.get("maintenance",{}).get("jobs",{}).duplicate()
		orders.merge(world.facts.get("maintenance",{}).get("upgrades",{}))
		var actor: Dictionary = world.facts.actors[id]
		var order: Dictionary = orders.get(contractor.get("job_id",""),{})
		var valid: bool = contractor.get("id","")==id and not order.is_empty() and actor.get("service_role","")=="mechanic" and not world.facts.staff.has(id)
		valid = valid and contractor.get("phase","") in ["assigned","leaving"] and actor.location.kind!="outside"
		if contractor.get("phase","")=="assigned": valid = valid and order.get("worker_id","")==id
		if valid:
			others.append({"actor_id":id,"owner":"maintenance.contractors","job_id":contractor.job_id,"phase":contractor.phase,"service_role":actor.service_role,"location_kind":actor.location.kind,"job_phase":order.get("phase","")})
			unclassified.erase(id)
	result.other_owned_present = others
	result.unclassified_actor_ids = unclassified
	return result

func snapshot(world: WorldState) -> Dictionary:
	var beds: int = 0
	var props: int = 0
	var desks: Array = []
	var nurses: Array = []
	for f: Dictionary in world.facts.facilities.values():
		if f.definition_id=="EQ05": beds += 1
		if f.definition_id=="FUR18": props += 1
		if f.definition_id=="SE01": desks.append({"id":f.id,"floor":f.floor_id})
	for id: String in world.facts.staff:
		var s: Dictionary = world.facts.staff[id]
		if s.role=="nurse": nurses.append({"id":id,"location":world.facts.actors[id].location.duplicate(true),"on_shift":s.get("on_shift",false),"job":s.get("active_job_id",""),"schedule":s.schedule,"abilities":s.abilities,"certificates":s.certificates})
	return {"tick":world.sim_tick,"population":population_current(world),"beds":beds,"props":props,"rooms":world.facts.rooms.size(),"facilities":world.facts.facilities.size(),"desks":desks,"nurses":nurses,"guidance":world.facts.get("floor_guidance",{}).duplicate(true),"sessions":world.facts.sessions.duplicate(true),"intake":world.facts.arrivals.duplicate(true)}
func _run() -> void:
	var input: String = ""
	var steps: int = 1000
	var prefix_steps: int = 0
	var profile_enabled: bool = false
	var soft_seconds: float = 360.0
	for arg: String in OS.get_cmdline_user_args():
		if arg=="--profile": profile_enabled=true
		if arg.begins_with("--soft-seconds="): soft_seconds=arg.trim_prefix("--soft-seconds=").to_float()
		if arg.begins_with("--input="): input=arg.trim_prefix("--input=")
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
		if arg.begins_with("--steps="): steps=arg.trim_prefix("--steps=").to_int()
		if arg.begins_with("--prefix-steps="): prefix_steps=arg.trim_prefix("--prefix-steps=").to_int()
	if input.is_empty() or output.is_empty() or steps<=0 or prefix_steps<0 or FileAccess.file_exists(output): quit(2);return
	var init_start: int = Time.get_ticks_usec()
	var content: HospitalContent = HospitalContent.new()
	var file: FileAccess = FileAccess.open(input,FileAccess.READ)
	var envelope: Dictionary = file.get_var(false);file.close()
	if envelope.content_fingerprint!=content.content_fingerprint: write_json(output,{"complete":false,"reason":"content mismatch"});quit(2);return
	var world: WorldState = WorldState.new(envelope.facts)
	var validation: String = world.validate(content)
	if not validation.is_empty(): write_json(output,{"complete":false,"reason":validation});quit(2);return
	var sim: HospitalSimulation = HospitalSimulation.new(world,content)

	var observer: RefCounted = null
	var attach_report: Dictionary = {"enabled":profile_enabled}
	if profile_enabled:
		observer=Profile.new();observer.source_directory=output+".generated"
		var before_bytes: PackedByteArray = var_to_bytes(world.freeze())
		var old: HospitalSimulation = sim
		var attach_start: int = Time.get_ticks_usec()
		var attached: HospitalSimulation = observer.attach(old,false)
		attach_report.elapsed_us=Time.get_ticks_usec()-attach_start
		attach_report.facts_rng_bytes_unchanged=before_bytes==var_to_bytes(world.freeze())
		attach_report.errors=observer.errors.duplicate()
		attach_report.returned_instance=attached!=null
		var references_ok: bool = attached!=null
		if attached!=null:
			for key: String in ["world","content","space","clinic","services","_commands","_command_boundary","_save_commands","_command_events","_business_handlers"]:
				var same: bool = is_same(old.get(key),attached.get(key))
				attach_report[key+"_same_reference"]=same;references_ok=references_ok and same
		attach_report.references_ok=references_ok
		write_json(output+".attach.json",attach_report)
		if attached==null or not references_ok or not attach_report.facts_rng_bytes_unchanged or not observer.errors.is_empty():
			write_json(output,{"complete":false,"reason":"attach gate failed; no continuation","attach":attach_report});quit(2);return
		sim=attached;old=null
	var init_us: int = Time.get_ticks_usec()-init_start
	var initial: Dictionary = snapshot(world)
	write_json(output+".initial.json",initial)
	var stream: FileAccess = FileAccess.open(output+".steps.ndjson",FileAccess.WRITE)
	var samples: Array = []
	var events: Array = []
	var event_counts: Dictionary = {}
	var work: Dictionary = {}
	var guidance_work: int = 0
	var actual_moving_steps: int = 0
	var errors: Array = []
	var prefix_work: Dictionary = {}
	var prefix_guidance: int = 0
	var prefix_events: Dictionary = {}
	var sample_start_population: Dictionary = {}
	var sample_wall_start: int = 0
	var prefix_wall_us: int = 0
	var wall_start: int = Time.get_ticks_usec()
	for index: int in prefix_steps+steps:
		if Time.get_ticks_usec()-wall_start>=soft_seconds*1000000.0: errors.append("soft deadline at complete boundary");break
		if index==prefix_steps:
			prefix_work=work.duplicate();prefix_guidance=guidance_work;prefix_events=event_counts.duplicate()
			sample_start_population=population_current(world)
			sample_wall_start=Time.get_ticks_usec();prefix_wall_us=sample_wall_start-wall_start
		var before_sessions: Dictionary = world.facts.sessions.duplicate(true)
		var before_guidance: Dictionary = world.facts.floor_guidance.visits.duplicate(true)
		stream.store_line(JSON.stringify({"kind":"enter","index":index,"tick":world.sim_tick}));stream.flush()
		if observer!=null: observer.begin_step()
		var started: int = Time.get_ticks_usec()
		var result: TickResult = sim.step()
		var elapsed: int = Time.get_ticks_usec()-started
		if observer!=null:
			observer.end_step(result,elapsed)
			if not observer.errors.is_empty(): errors.append("observer error");break
		if result==null: errors.append("Incomplete production step");break
		if world.sim_tick!=int(initial.tick)+index+1: errors.append("Unexpected tick increment");break
		for id: String in before_sessions:
			var old: Dictionary = before_sessions[id]
			var now: Dictionary = world.facts.sessions.get(id,{})
			if not now.is_empty() and int(now.remaining_ticks)<int(old.remaining_ticks):
				work[old.kind]=int(work.get(old.kind,0))+int(old.remaining_ticks)-int(now.remaining_ticks)
		for id: String in before_guidance:
			var old: Dictionary = before_guidance[id]
			var now: Dictionary = world.facts.floor_guidance.visits.get(id,{})
			if old.get("phase","")=="working" and not now.is_empty() and int(now.get("remaining_ticks",0))<int(old.get("remaining_ticks",0)): guidance_work += 1
		if not world.facts.moves.is_empty(): actual_moving_steps += 1
		for event: SimEvent in result.facts:
			events.append(event.to_record());event_counts[event.kind]=int(event_counts.get(event.kind,0))+1
		var row: Dictionary = {"index":index,"tick":world.sim_tick,"elapsed_us":elapsed,"present":world.present_actor_count(),"sessions":world.facts.sessions.size(),"moves":world.facts.moves.size()}
		samples.append(row)
		stream.store_line(JSON.stringify({"kind":"complete","sample":row}));stream.flush()
		if index%100==0: print("PLAIN_PROGRESS="+JSON.stringify(row))
	var window_end: int = Time.get_ticks_usec()
	var all_wall_us: int = window_end-wall_start
	var wall_us: int = window_end-sample_wall_start if sample_wall_start>0 else 0
	stream.close()
	validation=world.validate(content)
	if not validation.is_empty(): errors.append(validation)
	if observer!=null: write_json(output+".profile.json",observer.report())
	var final: Dictionary = snapshot(world)
	var ending: FileAccess = FileAccess.open(output+".final.bin",FileAccess.WRITE)
	ending.store_var({"content_fingerprint":content.content_fingerprint,"facts":world.freeze(),"floors":envelope.floors,"visitor_ids":envelope.visitor_ids,"events":events});ending.close()
	var values: Array = []
	var sum_us: int = 0
	for row: Dictionary in samples:
		if int(row.index)>=prefix_steps: values.append(int(row.elapsed_us));sum_us+=int(row.elapsed_us)
	values.sort()
	var metrics: Dictionary = {"count":values.size(),"sum_step_us":sum_us,"real_window_us_including_observation":wall_us,"simulated_seconds":values.size()*0.1,"simulation_seconds_per_wall_second":values.size()*100000.0/maxi(1,wall_us),"observation_logging_and_loop_wall_us":wall_us-sum_us}
	if not values.is_empty():
		metrics.mean_step_us=float(sum_us)/values.size();metrics.fresh_runtime_first_prefix_or_sample_step_us=samples[0].elapsed_us;metrics.first_sample_step_us=samples[prefix_steps].elapsed_us;metrics.max_us=values.back()
		for pct: int in [50,95,99]: metrics["p%d_us"%pct]=values[ceili(values.size()*pct/100.0)-1]
	var sample_work: Dictionary = {}
	for kind: String in work: sample_work[kind]=int(work[kind])-int(prefix_work.get(kind,0))
	var sample_events: Dictionary = {}
	for kind: String in event_counts: sample_events[kind]=int(event_counts[kind])-int(prefix_events.get(kind,0))
	var complete: bool = samples.size()==steps+prefix_steps and errors.is_empty()
	write_json(output,{"complete":complete,"performance_pass":null,"source_input_sha256":FileAccess.get_sha256(input),"mode":"root_diagnostic" if profile_enabled else "paired_plain_diagnostic","attach":attach_report,"soft_seconds":soft_seconds,"requested_sample_steps":steps,"requested_prefix_steps":prefix_steps,"all_completed_steps":samples.size(),"prefix_wall_us":prefix_wall_us,"all_wall_us":all_wall_us,"sample_start_population":sample_start_population,"prefix_business":{"work":prefix_work,"guidance":prefix_guidance,"events":prefix_events},"sample_business":{"clinical_work_ticks_observed_lower_bound":sample_work,"guidance_work_ticks":guidance_work-prefix_guidance,"events":sample_events},"initialization_us":init_us,"initial":initial,"final":final,"metrics":metrics,"business":{"clinical_work_ticks_observed_lower_bound":work,"guidance_work_ticks":guidance_work,"steps_with_active_moves_not_arrival_proof":actual_moving_steps,"events":event_counts},"errors":errors,"gpu_fps":null,"scope":"HospitalSimulation CPU full steps only; no GameSession/renderer/persistence lifecycle. Ordinary business rules retained; no fixed-population hold. Work counter excludes transition ticks and is a lower bound, not total completed work.","final_sha256":FileAccess.get_sha256(output+".final.bin")})
	sim.dispose();quit(0 if complete else 1)
