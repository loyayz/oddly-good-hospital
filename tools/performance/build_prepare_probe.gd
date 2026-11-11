extends SceneTree

const Timing = preload("res://tools/performance/build_prepare_timer.gd")

func _hash(value: Variant) -> String:
	var digest: HashingContext=HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(var_to_bytes(value))
	return digest.finish().hex_encode()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var output: String=""
	var repeats: int=3
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output=argument.trim_prefix("--output=")
		if argument.begins_with("--repeats="): repeats=argument.trim_prefix("--repeats=").to_int()
	if output.is_empty() or repeats<=0 or FileAccess.file_exists(output) or not FileAccess.file_exists("res://build-prepare-identity.json"):
		push_error("Use a frozen build_prepare_probe.py project and a new output path.")
		quit(2)
		return
	var identity: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://build-prepare-identity.json"))
	var instrumented: bool=bool(identity.instrumented)
	var policy: Dictionary={"applied":false,"reason":"platform_default"}
	if OS.get_name()=="Windows" and ClassDB.class_exists("PlatformThreadPolicy"): policy=ClassDB.class_call_static("PlatformThreadPolicy","apply_main_thread")
	var content: HospitalContent=HospitalContent.new()
	var fixture: RefCounted=load("res://tools/performance/fixture.gd").new(content,640,"tall")
	var world: WorldState=fixture.world
	var raw: Dictionary={"tick":world.sim_tick,"rng":world.facts.rng.duplicate(true),"ledger":world.facts.ledger.duplicate(true),"actors":world.facts.actors.size(),"facilities":world.facts.facilities.size()}
	var initializer: HospitalSimulation=HospitalSimulation.new(world,content)
	initializer.dispose()
	var validation: String=world.validate(content)
	if not content.error.is_empty() or not fixture.errors.is_empty() or not validation.is_empty() or world.sim_tick!=raw.tick or world.facts.rng!=raw.rng or world.facts.ledger!=raw.ledger or world.facts.actors.size()!=raw.actors or world.facts.facilities.size()!=raw.facilities:
		push_error("Invalid complete geometry input: "+validation)
		quit(2)
		return
	var facts: Dictionary=world.freeze()
	var rows: Array=[]
	var ok: bool=true
	for repeat: int in repeats:
		for kind: String in ["85x95","96x95","auxiliary8x8"]:
			var current: WorldState=WorldState.new(facts.duplicate(true))
			var auxiliary: bool=kind=="auxiliary8x8"
			var draft: Dictionary={"kind":"build_room","room_type_id":"gp","floor_id":1 if auxiliary else 2,"origin":[16,82] if auxiliary else [0,0],"size":[8,8] if auxiliary else [85 if kind=="85x95" else 96,95],"door":{"definition_id":"DR01","edge":"south","offset":1}}
			if auxiliary:
				# Same irrelevant-revision/2F obstacle boundary as SPACE-52's
				# auxiliary occupancy case; all original bodies and objects stay.
				current.touch()
				HospitalSpace.materialize_layout(current,2)
				current.facts.floors.overrides["2"].blocked.append([0,0])
			var before: Dictionary=current.freeze()
			var job: BuildPreviewJob=BuildPreviewJob.new(BuildService.new(content),current,draft)
			for unit: int in 20000:
				if job.complete or job._phase=="prepare": break
				job.advance(current,2000,1)
			if job.complete or job._phase!="prepare":
				push_error("Shape prerequisite failed: "+str(job.result))
				quit(2)
				return
			Timing.begin()
			var started: int=Time.get_ticks_usec()
			job.advance(current,2000,1)
			var elapsed: int=Time.get_ticks_usec()-started
			var timing: Dictionary=Timing.finish()
			var phase_after: String=job._phase
			for unit: int in 20000:
				if job.complete or auxiliary and not job._occupancy_views.is_empty(): break
				job.advance(current,2000,1 if auxiliary else 0)
			var business: bool=not job._occupancy_views.is_empty() if auxiliary else job.complete and (job.result.get("ok",false) and int(job.result.get("price",-1))==7250 if kind=="85x95" else not job.result.get("ok",true) and str(job.result.get("reason","")).contains("竖向结构"))
			var unchanged: bool=current.freeze()==before
			var plan_facts: Dictionary=job._plan.duplicate()
			plan_facts.erase("candidate")
			var row: Dictionary={"case":kind,"repeat":repeat+1,"draft":draft,"prepare_advance_usec":elapsed,"phase_after_prepare":phase_after,"phase_at_business_boundary":job._phase,"plan_ok":job._plan.get("ok",false),"complete":job.complete,"business_ok":business,"reason":job.result.get("reason",""),"price":job.result.get("price",job._plan.get("price",-1)),"actors":current.present_actor_count(),"facilities":current.facts.facilities.size(),"candidate_rooms":job._candidate.facts.rooms.size() if job._candidate!=null else 0,"complete_business_hash":_hash([plan_facts,job.result,job._candidate.freeze() if job._candidate!=null else {}]),"world_facts_unchanged":unchanged,"timing":timing}
			rows.append(row)
			ok=ok and business and unchanged and job._plan.get("ok",false) and timing.errors.is_empty() and (not instrumented or not timing.rows.is_empty())
			print("BUILD_PREPARE_STAGE="+JSON.stringify({"case":kind,"repeat":repeat+1,"elapsed_usec":elapsed,"business_ok":business,"facts_unchanged":unchanged}))
	var result: Dictionary={"complete":true,"ok":ok,"diagnostic_only":instrumented,"geometry_reference":identity.get("geometry_reference"),"scope":"Inclusive/exclusive synchronous prepare spans on complete unchanged SPACE-52 640-person inputs; wrapper times include instrumentation overhead and cannot prove acceleration. Auxiliary input stops after a real occupancy view." if instrumented else "Plain complete unchanged SPACE-52 640-person prepare measurements. Auxiliary input stops after a real occupancy view; all business facts are hashed outside timing.","actors":world.present_actor_count(),"facilities":world.facts.facilities.size(),"content_fingerprint":content.content_fingerprint,"main_thread_policy":policy,"repeats_per_case":repeats,"cases":rows}
	var output_file: FileAccess=FileAccess.open(output,FileAccess.WRITE)
	if output_file==null:
		push_error("Cannot write stage probe result.")
		quit(2)
		return
	output_file.store_string(JSON.stringify(result,"\t"))
	output_file.close()
	print("BUILD_PREPARE_COMPLETE="+JSON.stringify({"ok":ok,"cases":rows.size(),"output":output}))
	quit(0 if ok else 1)
