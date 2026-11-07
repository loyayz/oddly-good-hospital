extends SceneTree
const Query = preload("res://tools/performance/placement_query.gd")
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var opts: Dictionary = {}
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg: opts[arg.trim_prefix("--").get_slice("=",0)] = arg.substr(arg.find("=")+1)
	if not opts.has("input") or not opts.has("output") or FileAccess.file_exists(opts.output):
		push_error("Require existing qualified --input and new --output")
		quit(2)
		return
	var content: HospitalContent = HospitalContent.new()
	var input: FileAccess = FileAccess.open(opts.input,FileAccess.READ)
	var payload: Dictionary = input.get_var(false)
	input.close()
	var source: WorldState = WorldState.new(payload.facts)
	var validation: String = source.validate(content)
	if not validation.is_empty() or payload.content_fingerprint!=content.content_fingerprint:
		push_error("Unqualified source: "+validation)
		quit(2)
		return
	var selected: Dictionary = {"staff":[],"patients":[],"visitors":[]}
	for id: String in source.ids("staff"):
		if source.facts.actors[id].location.kind=="floor" and selected.staff.size()<3: selected.staff.append(id)
	for id: String in source.active_visit_ids():
		var actor_id: String = source.facts.visits[id].actor_id
		if source.facts.actors[actor_id].location.kind=="floor" and selected.patients.size()<3: selected.patients.append(actor_id)
	var visitor_ids: Array = source.facts.visitors.stays.keys()
	visitor_ids.sort()
	for id: String in visitor_ids:
		var actor_id: String = source.facts.visitors.stays[id].actor_id
		if source.facts.actors[actor_id].location.kind=="floor" and selected.visitors.size()<3: selected.visitors.append(actor_id)
	for role: String in selected:
		if selected[role].size()!=3:
			push_error("Need three actual owned floor actors per role; missing "+role)
			quit(2)
			return
	var rows: Array = []
	var all_ok: bool = true
	var static_negative: bool = false
	var dynamic_negative: bool = false
	for role: String in selected:
		for id: String in selected[role]:
			var world_a: WorldState = WorldState.new(source.freeze().duplicate(true))
			var world_b: WorldState = WorldState.new(source.freeze().duplicate(true))
			var before_a: Dictionary = world_a.freeze()
			var before_b: Dictionary = world_b.freeze()
			var space_a: HospitalSpace = HospitalSpace.new(content)
			var space_b: HospitalSpace = HospitalSpace.new(content)
			var original_actor: Dictionary = world_a.facts.actors[id]
			var floor_id: int = int(original_actor.location.floor_id)
			var actor_a: Dictionary = original_actor.duplicate(true)
			var candidate: RefCounted = Query.new(space_b,world_b,world_b.facts.actors[id],floor_id)
			# Fixed four prefix-grid questions plus original position and first other body.
			var cells: Array = [[6,6],[8,6],[10,6],[12,6],original_actor.location.cell.duplicate()]
			for other_id: String in world_a.ids("actors"):
				var other: Dictionary = world_a.facts.actors[other_id]
				if other_id!=id and other.location.kind=="floor" and int(other.location.floor_id)==floor_id:
					cells.append(other.location.cell.duplicate())
					break
			for index: int in cells.size():
				var cell: Array = cells[index]
				actor_a.location = {"kind":"floor","floor_id":floor_id,"cell":cell,"height_m":0.0}
				var reason_a: String = space_a.static_reason(world_a,actor_a,floor_id,Vector2i(int(cell[0]),int(cell[1])))
				var dynamic_a: Variant = null
				if reason_a.is_empty(): dynamic_a = space_a._dynamic_clear(world_a,id,floor_id,space_a.body_rectangle(actor_a))
				var reason_b: String = candidate.reason(cell)
				var dynamic_b: Variant = null
				if reason_b.is_empty(): dynamic_b = candidate.dynamic_clear()
				var same: bool = reason_a==reason_b and dynamic_a==dynamic_b
				all_ok = all_ok and same
				static_negative = static_negative or not reason_a.is_empty()
				dynamic_negative = dynamic_negative or dynamic_a==false
				var row: Dictionary = {"role":role,"actor":id,"index":index,"cell":cell,"original_reason":reason_a,"candidate_reason":reason_b,"original_dynamic":dynamic_a,"candidate_dynamic":dynamic_b,"same":same}
				rows.append(row)
				print("PLACEMENT_ORACLE="+JSON.stringify(row))
			var unchanged: bool = world_a.freeze()==before_a and world_b.freeze()==before_b
			all_ok = all_ok and unchanged
			rows.append({"actor":id,"full_facts_rng_unchanged":unchanged,"scope_stack_empty":space_a._route_queries.is_empty() and space_b._route_queries.is_empty()})
	var result: Dictionary = {"ok":all_ok,"input_sha256":FileAccess.get_sha256(opts.input),"selected":selected,"rows":rows,"scope":"9 actual owned actors; fixed read-only questions on independent complete clones, not constructor commits or 640 qualification","static_negative_observed":static_negative,"dynamic_negative_observed":dynamic_negative,"reservation_identity_negative":"not separately established by this finite oracle","exhaustion_negative":"not exercised","full_fixture_equivalence":false,"legal640_input_qualified":false,"performance_pass":null}
	var output: FileAccess = FileAccess.open(opts.output,FileAccess.WRITE)
	output.store_string(JSON.stringify(result,"\t"))
	output.close()
	quit(0 if all_ok else 1)
