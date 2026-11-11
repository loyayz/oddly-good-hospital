extends SceneTree

# Read-only diagnosis of a saved clinical boundary. No step, command, reservation,
# actor relocation or random draw is performed. These timings are not benchmarks.
func _initialize() -> void:
	call_deferred("_run")

func _write(path: String, value: Dictionary) -> void:
	var file: FileAccess=FileAccess.open(path,FileAccess.WRITE)
	if file!=null:
		file.store_string(JSON.stringify(value,"\t"))
		file.close()

func _changed(before: Dictionary, after: Dictionary) -> Array:
	var keys: Array=before.keys()
	for key: String in after:
		if not key in keys: keys.append(key)
	var changes: Array=[]
	for key: String in keys:
		if before.get(key)!=after.get(key): changes.append(key)
	return changes

func _run() -> void:
	var input: String=""
	var output: String=""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--input="): input=argument.trim_prefix("--input=")
		if argument.begins_with("--output="): output=argument.trim_prefix("--output=")
	if input.is_empty() or output.is_empty() or FileAccess.file_exists(output): quit(2);return
	var content: HospitalContent=HospitalContent.new()
	var file: FileAccess=FileAccess.open(input,FileAccess.READ)
	if file==null: _write(output,{"complete":false,"reason":"Input is unreadable"});quit(2);return
	var envelope: Dictionary=file.get_var(false)
	file.close()
	if envelope.get("content_fingerprint","")!=content.content_fingerprint: _write(output,{"complete":false,"reason":"Content mismatch"});quit(2);return
	var world: WorldState=WorldState.new(envelope.facts)
	var before: Dictionary=world.freeze()
	var validation: String=world.validate(content)
	if not validation.is_empty(): _write(output,{"complete":false,"reason":validation});quit(2);return
	var sim: HospitalSimulation=HospitalSimulation.new(world,content)
	var after_ensure: Dictionary=world.freeze()
	var started: int=Time.get_ticks_usec()
	var nurses: Array=[]
	for nurse_id: String in world.ids("staff"):
		var nurse: Dictionary=world.facts.staff[nurse_id]
		if nurse.role!="nurse" or not "q_ward" in nurse.certificates: continue
		var assignment: Dictionary=sim.services.scheduler.assignment(world,nurse_id,sim.services.scheduler.shift_index(world))
		nurses.append({"id":nurse_id,"assignment":assignment.duplicate(true),"location":world.facts.actors[nurse_id].location.duplicate(true),"on_shift":nurse.on_shift,"base_prepared":nurse.get("base_prepared",true),"base_task":nurse.get("base_task",{}).duplicate(true),"life_task":nurse.get("life_task",{}).duplicate(true),"energy":nurse.energy,"block_new_work":nurse.get("block_new_work",false),"can_start":sim.clinic._can_start(world,nurse),"staff_busy":sim.clinic._staff_busy(world,nurse_id),"workbenches":[]})
		for bench_id: String in world.facility_ids("SE06"):
			var bench: Dictionary=world.facts.facilities[bench_id]
			if not bench.failed:
				nurses.back().workbenches.append({"id":bench_id,"floor_id":bench.floor_id,"quote":sim.space.travel_quote(world,nurse_id,int(bench.floor_id),bench.operator_cells[0])})
	var visits: Array=[]
	for visit_id: String in world.ids("visits"):
		var visit: Dictionary=world.facts.visits[visit_id]
		var row: Dictionary={"id":visit_id,"phase":visit.phase,"location":world.facts.actors[visit.actor_id].location.duplicate(true),"guidance":sim.services.floor_guidance.state(world,visit_id).duplicate(true),"local_targets":sim.services.floor_guidance._target_ids(world,visit,"surgery"),"floor_quotes":[],"bed_checks":[]}
		for floor_id: int in [1,2,3,4]:
			row.floor_quotes.append({"floor_id":floor_id,"quote":sim.clinic._compatible_bed(world,visit,floor_id,[])})
		for bed_id: String in world.facility_ids("EQ05"):
			var bed: Dictionary=world.facts.facilities[bed_id]
			for nurse: Dictionary in nurses:
				if not bed.get("room_id","") in nurse.assignment.get("pools",[]): continue
				var geometry: Dictionary=sim.space.facility_geometry_quote(world,bed_id,visit.actor_id,[nurse.id])
				var preflight: Dictionary=sim.space.facility_preflight_quote(world,bed_id,visit.actor_id,[nurse.id])
				var fit: Dictionary=sim.space.facility_quote(world,bed_id,visit.actor_id,[nurse.id])
				var layout: Dictionary=geometry if geometry.get("ok",false) and not geometry.get("unchanged",false) else sim.space.facility_layout(world,bed_id)
				row.bed_checks.append({"bed_id":bed_id,"room_id":bed.room_id,"floor_id":bed.floor_id,"nurse_id":nurse.id,"room_reason":sim.clinic.service_room_reason(world,bed),"bed_unavailable":sim.clinic._facility_unavailable(bed),"bed_busy":sim.clinic._bed_busy(world,bed_id,visit_id),"schedule_allows":sim.clinic._schedule_allows(world,nurse.id,"care",visit,bed_id),"geometry":geometry,"preflight":preflight,"fit":fit,"patient_route":sim.space.travel_quote(world,visit.actor_id,int(bed.floor_id),layout.patient_cell),"nurse_route":sim.space.travel_quote(world,nurse.id,int(bed.floor_id),layout.operator_cells[0])})
		visits.append(row)
	var after_queries: Dictionary=world.freeze()
	var ensure_changes: Array=_changed(before,after_ensure)
	var query_changes: Array=_changed(after_ensure,after_queries)
	var ok: bool=ensure_changes.is_empty() and query_changes.is_empty()
	_write(output,{"complete":ok,"input":input,"input_sha256":FileAccess.get_sha256(input),"tick":world.sim_tick,"scope":"Read-only clinical eligibility diagnosis; no simulation step and no performance qualification","ensure_changed_collections":ensure_changes,"query_changed_collections":query_changes,"elapsed_us":Time.get_ticks_usec()-started,"nurses":nurses,"visits":visits})
	print("CLINICAL_BOUNDARY_PROBE="+JSON.stringify({"complete":ok,"tick":world.sim_tick,"output":output,"ensure_changed_collections":ensure_changes,"query_changed_collections":query_changes}))
	sim.dispose()
	quit(0 if ok else 1)
