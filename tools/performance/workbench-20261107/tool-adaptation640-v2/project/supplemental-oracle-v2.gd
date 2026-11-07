extends SceneTree
const Query = preload("res://tools/performance/placement_query.gd")
var content: HospitalContent
func _initialize() -> void:
	call_deferred("_run")
func _lane(source: WorldState, id: String, cells: Array, candidate_mode: bool) -> Dictionary:
	var world: WorldState = WorldState.new(source.freeze().duplicate(true))
	var space: HospitalSpace = HospitalSpace.new(content)
	var actor: Dictionary = world.facts.actors[id] # Intentionally aliases the real actor, as original staff construction.
	var floor_id: int = int(actor.location.floor_id)
	var query: RefCounted = Query.new(space,world,actor,floor_id) if candidate_mode else null
	var rows: Array = []
	var cursor: int = 0
	var errors: Array = []
	var selected: Array = [48,91]
	var accepted: bool = false
	while cursor<cells.size():
		var cell: Array = cells[cursor]
		cursor += 1
		var reason: String
		if candidate_mode:
			reason = query.reason(cell)
		else:
			actor.location = {"kind":"floor","floor_id":floor_id,"cell":cell,"height_m":0.0}
			reason = space.static_reason(world,actor,floor_id,Vector2i(int(cell[0]),int(cell[1])))
		var dynamic: Variant = null
		if reason.is_empty():
			dynamic = query.dynamic_clear() if candidate_mode else space._dynamic_clear(world,id,floor_id,space.body_rectangle(actor))
		rows.append({"cursor":cursor,"cell":cell.duplicate(),"reason":reason,"dynamic":dynamic})
		if reason.is_empty() and dynamic==true:
			accepted = true
			selected = cell.duplicate()
			break
	if not accepted: errors.append("没有足够合法身体位置："+str(floor_id))
	# Drop the single-actor sealed query before original caller assignment/sync.
	query = null
	actor.location = {"kind":"floor","floor_id":floor_id,"cell":selected,"height_m":0.0}
	space.sync_actor(world,id)
	return {"rows":rows,"cursor":cursor,"errors":errors,"accepted":accepted,"returned":selected,"facts":world.freeze(),"scope_empty":space._route_queries.is_empty()}
func _compare(source: WorldState, id: String, cells: Array, label: String, expect_exhaustion: bool = false) -> Dictionary:
	var a: Dictionary = _lane(source,id,cells,false)
	var b: Dictionary = _lane(source,id,cells,true)
	var same: bool = a==b
	var exhaustion_ok: bool = not expect_exhaustion or not a.accepted and a.cursor==cells.size() and a.errors.size()==1 and a.returned==[48,91]
	var result: Dictionary = {"case":label,"actor":id,"ok":same and exhaustion_ok,"full_committed_facts_rng_equal":a.facts==b.facts,"cursor_errors_return_equal":a.cursor==b.cursor and a.errors==b.errors and a.returned==b.returned,"original":{"rows":a.rows,"cursor":a.cursor,"errors":a.errors,"accepted":a.accepted,"returned":a.returned},"candidate":{"rows":b.rows,"cursor":b.cursor,"errors":b.errors,"accepted":b.accepted,"returned":b.returned},"expected_exhaustion":expect_exhaustion,"scope_empty":a.scope_empty and b.scope_empty}
	print("SUPPLEMENTAL_ORACLE="+JSON.stringify(result))
	return result
func _run() -> void:
	var opts: Dictionary = {}
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg: opts[arg.trim_prefix("--").get_slice("=",0)] = arg.substr(arg.find("=")+1)
	if not opts.has("input") or not opts.has("output") or FileAccess.file_exists(opts.output):
		push_error("Require existing qualified --input and new --output")
		quit(2)
		return
	content = HospitalContent.new()
	var f: FileAccess = FileAccess.open(opts.input,FileAccess.READ)
	var payload: Dictionary = f.get_var(false)
	f.close()
	var world: WorldState = WorldState.new(payload.facts)
	var validation: String = world.validate(content)
	if not validation.is_empty() or payload.content_fingerprint!=content.content_fingerprint:
		push_error("Source invalid: "+validation)
		quit(2)
		return
	var original_facts: Dictionary = world.freeze()
	var rows: Array = []
	var staff: Array = []
	for id: String in world.ids("staff"):
		if world.facts.actors[id].location.kind=="floor" and staff.size()<3: staff.append(id)
	for id: String in staff:
		var cell: Array = world.facts.actors[id].location.cell.duplicate()
		# Predetermined finite positions, not a modified formal load. Last point is legal source position.
		rows.append(_compare(world,id,[[-1,-1],[6,6],[8,6],[10,6],cell],"staff_alias_commit"))
		rows.append(_compare(world,id,[[-1,-1],[-2,-2]],"staff_exhaustion_fallback",true))
	# Existing valid reservation only; no reservation or permission record invented.
	var reservation: Dictionary = {"status":"notcovered","reason":"No suitable existing validated facility adaptation with floor owner and nonowner"}
	for reservation_id: String in world.ids("adaptations"):
		var r: Dictionary = world.facts.adaptations[reservation_id]
		if r.get("kind","")!="facility" or r.get("regions",[]).is_empty(): continue
		var owner: String = str(r.get("actor_id",""))
		var floor_id: int = int(r.get("floor_id",0))
		if not world.facts.actors.has(owner): continue
		var actor: Dictionary = world.facts.actors[owner]
		if actor.location.kind!="floor" or int(actor.location.floor_id)!=floor_id: continue
		var other: String = ""
		for id: String in world.ids("actors"):
			var candidate: Dictionary = world.facts.actors[id]
			if candidate.location.kind=="floor" and int(candidate.location.floor_id)==floor_id and not RouteClearance.reservation_allows(r,id):
				other = id
				break
		if other.is_empty() or not RouteClearance.reservation_allows(r,owner): continue
		var area: Array = r.regions[0]
		var cells: Array = [[int(area[0]),int(area[1])],[-1,-1]]
		var owner_result: Dictionary = _compare(world,owner,cells,"existing_reservation_owner")
		var other_result: Dictionary = _compare(world,other,cells,"existing_reservation_nonowner")
		rows.append(owner_result);rows.append(other_result)
		var reason: String = other_result.original.rows[0].reason
		var denied_by_reservation: bool = reason.begins_with("真实展开与岗位预约阻挡：")
		reservation = {"status":"covered" if denied_by_reservation else "notcovered","reservation_id":reservation_id,"owner":owner,"nonowner":other,"owner_permission":true,"nonowner_permission":false,"nonowner_reason":reason,"reason":"Existing owner/nonowner compared; reservation-negative requires actual reservation rejection, other geometric rejection does not substitute"}
		break
	var ok: bool = staff.size()==3 and world.freeze()==original_facts
	for row: Dictionary in rows: ok = ok and row.ok
	var result: Dictionary = {"ok":ok,"source_sha256":FileAccess.get_sha256(opts.input),"source_validation":validation,"source_full_facts_rng_unchanged":world.freeze()==original_facts,"staff_selected":staff,"rows":rows,"reservation_coverage":reservation,"full640_qualified":false,"performance_pass":null,"scope":"Finite original staff alias/return/caller assignment/sync comparison on independent source clones. Hypothetical candidate and fallback commits are disposable oracle states, not legal saved gameplay input. No production step or formal load changed."}
	var output: FileAccess = FileAccess.open(opts.output,FileAccess.WRITE)
	output.store_string(JSON.stringify(result,"\t"));output.close()
	quit(0 if ok else 1)
