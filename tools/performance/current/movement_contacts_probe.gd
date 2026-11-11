extends SceneTree

const Oracle=preload("res://tests/acceptance/movement_contacts_oracle.gd")
const KINDS: Array[String]=["goal","local","current_body"]
var world: WorldState
var space: HospitalSpace

func _initialize() -> void: call_deferred("run")

func _hash(value: Variant) -> String:
	var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(value));return context.finish().hex_encode()

func _row(actor: Dictionary, movement: Dictionary, floor_id: int, from: Rect2, to: Rect2, ordinal: int) -> Dictionary:
	var sweep:=BodyIndex.Record.new()
	sweep.id=actor.id;sweep.sweep_from=from;sweep.sweep_to=to
	var probes: Array[BodyIndex.Record]=[sweep]
	return {"actor_id":actor.id,"floor_id":floor_id,"broad":from.merge(to),"probes":probes,"members":movement.get("members",[actor.id]).duplicate(),"ordinal":ordinal}

func _queries() -> Dictionary:
	var result: Dictionary={"goal":[],"local":[],"current_body":[],"source_queries":{"goal":0,"local":0,"current_body":0},"source_ids":{"goal":[],"local":[],"current_body":[]},"not_ground":[],"route_pending":[],"invalid":[],"non_cardinal_original_legs":[]}
	for id: String in world.ids("moves"):
		var movement: Dictionary=world.facts.moves[id]
		var actor: Dictionary=world.facts.actors[id]
		if actor.location.kind!="floor": result.not_ground.append(id);continue
		if movement.get("route_pending",false): result.route_pending.append(id);continue
		result.source_queries.goal+=1;result.source_queries.current_body+=1
		result.source_ids.goal.append(id);result.source_ids.current_body.append(id)
		var regions: Array[Rect2]=space.movement._bed_goal_regions(world,actor,movement)
		if regions.is_empty(): result.invalid.append({"id":id,"reason":"Ready original Move has no goal body regions"})
		for ordinal: int in regions.size(): result.goal.append(_row(actor,movement,int(movement.target_floor),regions[ordinal],regions[ordinal],ordinal))
		var current: Rect2=space.body_rectangle(actor)
		result.current_body.append(_row(actor,movement,int(actor.location.floor_id),current,current,0))
		if not movement.has("local_move"): continue
		result.source_queries.local+=1
		result.source_ids.local.append(id)
		var path: Array=[movement.local_move.target]
		path.append_array(movement.local_move.get("corners",[]))
		var origin: Vector2=ConvoyTrail.point(actor.location.cell)
		var sample: Dictionary=actor.duplicate()
		var previous: Rect2=current
		var ordinal: int=0
		for point: Dictionary in path:
			if point.get("kind","")!="floor" or int(point.get("floor_id",0))!=int(actor.location.floor_id):
				result.invalid.append({"id":id,"reason":"Original local path leaves its actual floor"});continue
			var target: Vector2=ConvoyTrail.point(point.cell)
			if origin.x!=target.x and origin.y!=target.y: result.non_cardinal_original_legs.append({"id":id,"from":[origin.x,origin.y],"to":[target.x,target.y]})
			if target==origin:
				# Retain this original endpoint input as a stationary contact
				# calculation. It does not claim another real walking step.
				result.local.append(_row(actor,movement,int(actor.location.floor_id),previous,previous,ordinal));ordinal+=1;continue
			sample.facing=atan2(target.x-origin.x,target.y-origin.y)
			var first: Vector2=space.movement._step_toward(origin,target,space.walking_speed(actor)*WorldState.TICK_SECONDS)
			for next: Vector2 in [first,target]:
				if next==origin: continue
				var next_rect: Rect2=space._actor_rect(sample,next)
				result.local.append(_row(actor,movement,int(actor.location.floor_id),previous,next_rect,ordinal));ordinal+=1
				origin=next;previous=next_rect
	return result

func _actual(row: Dictionary, first: bool) -> HospitalMovement.MotionResult:
	var result:=HospitalMovement.MotionResult.new();result.first_contact_only=first
	space.movement._movement_contacts(world,row.actor_id,int(row.floor_id),row.broad,row.probes,row.members,result)
	return result

func _pass(groups: Dictionary, snapshot: Dictionary, expected: bool) -> Array:
	var outputs: Array=[]
	for first: bool in [false,true]:
		for kind: String in KINDS:
			for row: Dictionary in groups[kind]:
				var typed: Dictionary
				if expected:
					var oracle: Dictionary=Oracle.query(snapshot,row.actor_id,int(row.floor_id),row.broad,row.probes,row.members,first)
					typed=Oracle.expected_typed(oracle,first)
				else: typed=Oracle.typed(_actual(row,first))
				outputs.append({"kind":kind,"actor_id":row.actor_id,"ordinal":row.ordinal,"output":typed})
	return outputs

func _measure(rows: Array, iterations: int, first: bool, timed: bool) -> Dictionary:
	var last: HospitalMovement.MotionResult
	var started: int=Time.get_ticks_usec() if timed else 0
	for repeat: int in iterations:
		for row: Dictionary in rows: last=_actual(row,first)
	var elapsed: int=Time.get_ticks_usec()-started if timed else 0
	return {"queries":rows.size(),"iterations":iterations,"calls":rows.size()*iterations,"elapsed_us":elapsed if timed else null,"last":Oracle.typed(last) if last!=null else {}}

func _delta(after: Dictionary, before: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for key: String in after:
		var value: int=int(after[key])-int(before.get(key,0))
		if value!=0: result[key]=value
	return result

func run() -> void:
	var input: String="";var output: String="";var mode: String="plain";var iterations: int=1000
	var expected_actors: int=179;var expected_source_queries: int=0
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--input="): input=arg.trim_prefix("--input=")
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
		if arg.begins_with("--mode="): mode=arg.trim_prefix("--mode=")
		if arg.begins_with("--iterations="): iterations=arg.trim_prefix("--iterations=").to_int()
		if arg.begins_with("--expected-actors="): expected_actors=arg.trim_prefix("--expected-actors=").to_int()
		if arg.begins_with("--expected-source-queries="): expected_source_queries=arg.trim_prefix("--expected-source-queries=").to_int()
	if input.is_empty() or output.is_empty() or FileAccess.file_exists(output) or not mode in ["plain","counted"] or iterations<=0: quit(2);return
	var policy: Dictionary=ClassDB.class_call_static("PlatformThreadPolicy","apply_main_thread") if ClassDB.class_exists("PlatformThreadPolicy") else {"applied":false}
	var database:=HospitalContent.new()
	var file: FileAccess=FileAccess.open(input,FileAccess.READ)
	if file==null: quit(2);return
	var envelope: Dictionary=file.get_var(false);file.close()
	if envelope.get("content_fingerprint","")!=database.content_fingerprint: quit(2);return
	world=WorldState.new(envelope.facts);space=HospitalSpace.new(database)
	var before: Dictionary=world.freeze();var validation: String=world.validate(database)
	space._ensure_actor_index(world)
	var groups: Dictionary=_queries()
	var snapshot: Dictionary=Oracle.capture(world,space,space.movement._accepted_sweeps)
	var errors: Array=[]
	if not validation.is_empty(): errors.append(validation)
	if not groups.invalid.is_empty(): errors.append("Original Move query geometry is invalid")
	if world.facts.actors.size()!=expected_actors: errors.append("Complete actor population differs from the protocol")
	var source_total: int=int(groups.source_queries.goal)+int(groups.source_queries.local)+int(groups.source_queries.current_body)
	if expected_source_queries>0 and source_total!=expected_source_queries: errors.append("Complete source Move corpus differs from the protocol; no filtering is allowed")
	var original_ids: Dictionary={"goal":[],"local":[],"current_body":[]}
	for id: String in world.facts.moves:
		var actor: Dictionary=world.facts.actors[id]
		var move: Dictionary=world.facts.moves[id]
		if actor.location.kind!="floor" or move.get("route_pending",false): continue
		original_ids.goal.append(id);original_ids.current_body.append(id)
		if move.has("local_move"): original_ids.local.append(id)
	for kind: String in KINDS:
		original_ids[kind].sort()
		if original_ids[kind]!=groups.source_ids[kind]: errors.append("Ready original Move identities were omitted or duplicated: "+kind)
	if not policy.get("applied",false): errors.append("Application main-thread policy failed")
	var expected: Array=_pass(groups,snapshot,true)
	var counts: Dictionary=space.query_counts.duplicate()
	var actual: Array=_pass(groups,snapshot,false)
	if var_to_bytes(actual)!=var_to_bytes(expected): errors.append("Typed contact results differ from the independent complete oracle")
	var correctness_counts: Dictionary=_delta(space.query_counts,counts)
	var measured: Dictionary={};var before_measure: Dictionary=space.query_counts.duplicate()
	if errors.is_empty():
		for kind: String in KINDS:
			measured[kind]={"full":_measure(groups[kind],iterations,false,mode=="plain"),"first":_measure(groups[kind],iterations,true,mode=="plain")}
	var measured_counts: Dictionary=_delta(space.query_counts,before_measure)
	var repeated: Array=_pass(groups,snapshot,false)
	if var_to_bytes(repeated)!=var_to_bytes(expected): errors.append("Typed results changed after repeated readonly contact queries")
	if before!=world.freeze(): errors.append("Contact queries changed complete world facts")
	if not world.validate(database).is_empty(): errors.append("World validation failed after contact queries")
	if (mode=="counted")!=space.query_counts.has("contacts_probe_calls"): errors.append("Plain/counted source mismatch")
	var population: Dictionary={"actor_records":world.facts.actors.size(),"present":world.present_actor_count(),"moves":world.facts.moves.size(),"facilities":world.facts.facilities.size(),"reservations":world.facts.adaptations.size()}
	var result: Dictionary={"ok":errors.is_empty(),"mode":mode,"timings_are_plain":mode=="plain","input_sha256":FileAccess.get_sha256(input),"source_sha256":{"movement":FileAccess.get_sha256("res://game/building/hospital_movement.gd"),"space":FileAccess.get_sha256("res://game/building/hospital_space.gd"),"probe":FileAccess.get_sha256("res://tools/performance/current/movement_contacts_probe.gd"),"oracle":FileAccess.get_sha256("res://tests/acceptance/movement_contacts_oracle.gd")},"tick":world.sim_tick,"population":population,"policy":policy,"OMP_NUM_THREADS":OS.get_environment("OMP_NUM_THREADS"),"world_validation":validation,"whole_world_readonly":before==world.freeze(),"whole_world_sha256":_hash(before),"oracle_typed_sha256":_hash(expected),"actual_typed_sha256":_hash(actual),"results":actual,"source_queries":groups.source_queries,"contact_queries":{"goal":groups.goal.size(),"local":groups.local.size(),"current_body":groups.current_body.size()},"excluded_not_ground_move_ids":groups.not_ground,"pending_unissued_move_ids":groups.route_pending,"invalid_geometry":groups.invalid,"correctness_counter_delta":correctness_counts,"measured_counter_delta":measured_counts,"measurements":measured,"errors":errors,"scope":"Complete real 7000-step terminal facts and all ready ground Moves retained. Original goal/local/current owner corpus is checked without truncation; local target/corners retain every first-turn and subsequent straight contact probe, including stationary endpoint calculations. No step, movement, RNG, quote or reservation is executed. The full-facts oracle runs outside timing. Plain timings include complete query dispatch and MotionResult creation; counted processes report no elapsed measurements. Fresh complete-boundary runtimes have no prior accepted sweeps; dedicated selectors cover accepted-only and mixed sets. This readonly contact microbenchmark is not a 160-person full-step or gameplay performance result."}
	result.source_move_ids=groups.source_ids
	result.non_cardinal_original_local_legs=groups.non_cardinal_original_legs
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify({"ok":result.ok,"mode":mode,"source_queries":result.source_queries,"contact_queries":result.contact_queries,"population":population,"errors":errors}))
	quit(0 if result.ok else 1)
