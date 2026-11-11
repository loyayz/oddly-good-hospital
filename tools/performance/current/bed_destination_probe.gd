extends SceneTree

const Oracle = preload("res://tests/acceptance/bed_destination_oracle.gd")
var database: HospitalContent
var space: HospitalSpace
var world: WorldState

func _initialize() -> void: call_deferred("run")

func _hash(value: Variant) -> String:
	var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(value));return context.finish().hex_encode()

func _actual(kind: String, row: Dictionary) -> String:
	if kind=="goal": return space.movement._bed_goal_blocker(world,row.actor,row.movement)
	if kind=="local": return space.movement._bed_local_path_blocker(world,row.actor,row.movement,row.path)
	return space.bed_destination_blocker(world,row.actor.id,int(row.actor.location.floor_id),row.rect,row.movement.get("members",[row.actor.id]))

func _expected(kind: String, row: Dictionary) -> String:
	var actor: Dictionary=row.actor;var movement: Dictionary=row.movement
	var members: Array=movement.get("members",[actor.id])
	if kind=="current_body": return Oracle.blocker(world,actor.id,int(actor.location.floor_id),row.rect,members)
	if kind=="goal":
		# The unchanged body/final-facing interface supplies geometry; expected
		# permission and first blocker come from all reservation facts.
		for region: Rect2 in space.movement._bed_goal_regions(world,actor,movement):
			var held: String=Oracle.blocker(world,actor.id,int(movement.target_floor),region,members)
			if not held.is_empty(): return held
		return ""
	var origin: Vector2=ConvoyTrail.point(actor.location.cell)
	var sample: Dictionary=actor.duplicate()
	for index: int in row.path.size():
		var segment: Dictionary=row.path[index];var target: Vector2=ConvoyTrail.point(segment.cell)
		if target==origin and index<row.path.size()-1: continue
		if target!=origin: sample.facing=atan2(target.x-origin.x,target.y-origin.y)
		var held: String=Oracle.blocker(world,actor.id,int(segment.floor_id),space._actor_rect(sample,target),members)
		if not held.is_empty(): return held
		origin=target
	return ""

func _queries() -> Dictionary:
	var result: Dictionary={"goal":[],"local":[],"current_body":[],"not_ground":[],"route_pending":[],"invalid_local":[]}
	for id: String in world.ids("moves"):
		var movement: Dictionary=world.facts.moves[id];var actor: Dictionary=world.facts.actors[id]
		if actor.location.kind!="floor": result.not_ground.append(id);continue
		if movement.get("route_pending",false): result.route_pending.append(id);continue
		var row: Dictionary={"actor":actor,"movement":movement}
		result.goal.append(row)
		result.current_body.append({"actor":actor,"movement":movement,"rect":space.body_rectangle(actor)})
		if not movement.has("local_move"): continue
		var local: Dictionary=movement.local_move
		var path: Array=[local.target]
		path.append_array(local.get("corners",[]))
		var valid: bool=true
		for segment: Dictionary in path:
			valid=valid and segment.kind=="floor" and int(segment.floor_id)==int(actor.location.floor_id)
		if not valid: result.invalid_local.append(id);continue
		result.local.append({"actor":actor,"movement":movement,"path":path})
	return result

func _run_pass(groups: Dictionary, expected: bool) -> Dictionary:
	var result: Dictionary={}
	for kind: String in ["goal","local","current_body"]:
		var rows: Array=[]
		for row: Dictionary in groups[kind]: rows.append({"actor_id":row.actor.id,"blocker":_expected(kind,row) if expected else _actual(kind,row)})
		result[kind]=rows
	return result

func _measure(kind: String, rows: Array, iterations: int, timed: bool) -> Dictionary:
	var last: String=""
	var started: int=Time.get_ticks_usec() if timed else 0
	for repeat: int in iterations:
		for row: Dictionary in rows: last=_actual(kind,row)
	var elapsed: int=Time.get_ticks_usec()-started if timed else 0
	return {"query_count":rows.size(),"iterations":iterations,"calls":rows.size()*iterations,"elapsed_us":elapsed if timed else null,"last_blocker":last}

func _delta(after: Dictionary, before: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for key: String in after:
		var difference: int=int(after[key])-int(before.get(key,0))
		if difference!=0: result[key]=difference
	return result

func run() -> void:
	var input: String="";var output: String="";var mode: String="plain";var iterations: int=1000
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--input="): input=arg.trim_prefix("--input=")
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
		if arg.begins_with("--mode="): mode=arg.trim_prefix("--mode=")
		if arg.begins_with("--iterations="): iterations=arg.trim_prefix("--iterations=").to_int()
	if input.is_empty() or output.is_empty() or FileAccess.file_exists(output) or not mode in ["plain","counted"] or iterations<=0: quit(2);return
	var policy: Dictionary=ClassDB.class_call_static("PlatformThreadPolicy","apply_main_thread") if ClassDB.class_exists("PlatformThreadPolicy") else {"applied":false}
	database=HospitalContent.new()
	var file: FileAccess=FileAccess.open(input,FileAccess.READ);var envelope: Dictionary=file.get_var(false);file.close()
	if envelope.content_fingerprint!=database.content_fingerprint: quit(2);return
	world=WorldState.new(envelope.facts);space=HospitalSpace.new(database)
	var before: Dictionary=world.freeze();var validation: String=world.validate(database)
	var groups: Dictionary=_queries()
	var errors: Array=[]
	if not validation.is_empty(): errors.append(validation)
	if not groups.invalid_local.is_empty(): errors.append("Original local path is not a legal same-floor path")
	if groups.goal.is_empty() or groups.local.is_empty(): errors.append("Frozen boundary has no required actual ground Move/local queries")
	if not policy.get("applied",false): errors.append("Application main-thread policy failed")
	var expected: Dictionary=_run_pass(groups,true)
	var before_counts: Dictionary=space.query_counts.duplicate()
	var actual: Dictionary=_run_pass(groups,false)
	if actual!=expected: errors.append("Query result differs from the independent full-facts oracle")
	var correctness_counts: Dictionary=_delta(space.query_counts,before_counts)
	var warmed: Dictionary=space.query_counts.duplicate();var measurements: Dictionary={}
	for kind: String in ["goal","local","current_body"]: measurements[kind]=_measure(kind,groups[kind],iterations,mode=="plain")
	var measured_counts: Dictionary=_delta(space.query_counts,warmed)
	var repeated: Dictionary=_run_pass(groups,false)
	if repeated!=expected: errors.append("Result changed after repeated readonly queries")
	if before!=world.freeze(): errors.append("Query changed complete world facts")
	if not world.validate(database).is_empty(): errors.append("World validation failed after queries")
	var counted: bool=space.query_counts.has("bed_probe_reservation_view_calls")
	if (mode=="counted")!=counted: errors.append("Plain/counted source mode mismatch")
	var population: Dictionary={"actor_records":world.facts.actors.size(),"present":world.present_actor_count(),"facilities":world.facts.facilities.size(),"rooms":world.facts.rooms.size(),"moves":world.facts.moves.size(),"reservation_records":world.facts.adaptations.size()}
	var result: Dictionary={"ok":errors.is_empty(),"mode":mode,"timings_are_plain":mode=="plain","input_sha256":FileAccess.get_sha256(input),"source_sha256":{"space":FileAccess.get_sha256("res://game/building/hospital_space.gd"),"movement":FileAccess.get_sha256("res://game/building/hospital_movement.gd"),"probe":FileAccess.get_sha256("res://tools/performance/current/bed_destination_probe.gd"),"oracle":FileAccess.get_sha256("res://tests/acceptance/bed_destination_oracle.gd")},"tick":world.sim_tick,"population":population,"main_thread_policy":policy,"OMP_NUM_THREADS":OS.get_environment("OMP_NUM_THREADS"),"world_validation":validation,"all_world_facts_unchanged":before==world.freeze(),"world_facts_sha256":_hash(before),"oracle_results_sha256":_hash(expected),"actual_results_sha256":_hash(actual),"business_results":actual,"queries":{"goal":groups.goal.size(),"local":groups.local.size(),"current_body":groups.current_body.size(),"excluded_non_ground_move_ids":groups.not_ground,"pending_unissued_move_ids":groups.route_pending,"invalid_local_move_ids":groups.invalid_local},"measurements":measurements,"correctness_pass_private_counter_delta":correctness_counts,"measured_private_counter_delta":measured_counts,"errors":errors,"scope":"Complete frozen facts retained. Only actual ground actors and their ready original Moves are queried; no steps, moves, RNG, candidate truncation or business changes. The unchanged body/facing interface supplies geometry to an independent full-facts reservation oracle before measurement. Timed loops include query dispatch and return assignment but no oracle, hashing, file writes or counting hooks. Counted runs do not report timings. This is a readonly microbenchmark, not a 160-person full-step performance result."}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify({"ok":result.ok,"mode":mode,"queries":result.queries,"population":population,"errors":errors}))
	quit(0 if result.ok else 1)
