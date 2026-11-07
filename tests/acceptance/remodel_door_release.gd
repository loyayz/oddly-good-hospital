extends SceneTree

# Focused semantic-boundary regression. Arguments: immutable full-world .bin,
# unused evidence prefix. Input must be a completed-renovation exit with live
# source-door ownership and two independently prepared room moves.
var content: HospitalContent
var suite
var f: Dictionary
var prefix: String
var checks: Array = []
var trace: Array = []
var aid: String
var bid: String
var door_id: String

func _initialize(): call_deferred("run")
func save(label: String, value: Variant):
	var path: String = prefix+"-"+label
	assert(not FileAccess.file_exists(path+".bin"))
	FileAccess.open(path+".bin",FileAccess.WRITE).store_var(value,true)
	FileAccess.open(path+".json",FileAccess.WRITE).store_string(JSON.stringify(value,"\t"))
func ck(label: String, ok: bool, detail: Variant = null) -> bool:
	checks.append({"label":label,"ok":ok,"detail":detail})
	print(JSON.stringify(checks.back()))
	return ok
func bind(raw: Dictionary):
	if not f.is_empty(): f.s.dispose()
	var world: WorldState = WorldState.new(raw.duplicate(true))
	f = {"w":world,"s":HospitalSimulation.new(world,content),"errors":[]}
func command(kind: String, payload: Dictionary) -> CommandResult:
	var result: CommandResult = suite._command(f,kind,payload,"door_release_"+str(trace.size()))
	trace.append({"command":kind,"payload":payload,"result":result.to_record(),"tick":f.w.sim_tick})
	return result
func safety(label: String) -> bool:
	var errors: String = f.w.validate(content)
	var body_errors: Array = []
	for actor: Dictionary in f.w.facts.actors.values():
		if actor.location.kind!="floor": continue
		var rect: Rect2 = f.s.space.body_rectangle(actor)
		var query: RouteClearance = RouteClearance.new(f.s.space,f.w,actor,int(actor.location.floor_id))
		var wall_reason: String = query._wall_reason(rect)
		var facility: String = f.s.space._blocking_facility(f.w,int(actor.location.floor_id),rect)
		if not facility.is_empty(): body_errors.append({"actor":actor.id,"facility":facility})
		for y: int in range(floori(rect.position.y),ceili(rect.end.y)):
			for x: int in range(floori(rect.position.x),ceili(rect.end.x)):
				if not f.s.space.owned(f.w,int(actor.location.floor_id),Vector2i(x,y)): body_errors.append({"actor":actor.id,"unowned_cell":[x,y]})
		if not wall_reason.is_empty() or not f.s.space._dynamic_clear(f.w,actor.id,int(actor.location.floor_id),rect):
			body_errors.append({"actor":actor.id,"body":str(rect),"wall_reason":wall_reason})
	return ck(label,errors.is_empty() and body_errors.is_empty(),{"validation":errors,"body_errors":body_errors})
func waiting_queries(label: String, expected_blocked: bool) -> bool:
	var raw: Dictionary = f.w.freeze().duplicate(true)
	var remodel = f.s.services.remodel
	var view: Dictionary = remodel._waiting_view(f.w)
	var all: Dictionary = remodel.waiting_all(f.w)
	var a: Dictionary = remodel.preview(f.w,aid)
	var b: Dictionary = remodel.preview(f.w,bid)
	return ck(label,raw==f.w.freeze() and a.ok and b.ok!=expected_blocked and all[aid].is_empty() and all[bid].is_empty()!=expected_blocked and remodel._waiting(f.w,f.w.facts.remodels[bid],view)==all[bid],{"a_ok":a.ok,"b_ok":b.ok,"all":all,"view_rooms":view.occupied_door_rooms})
func apply_one(rid: String) -> bool:
	var before: Dictionary = f.w.freeze().duplicate(true)
	var plan: Dictionary = f.s.services.remodel.preview(f.w,rid)
	if not ck("ready-"+rid,plan.ok and before==f.w.freeze(),plan.reason): return false
	var result: CommandResult = command("remodel_apply",{"order_id":rid,"quote":{"price":plan.price,"refund":plan.refund,"layout":plan.layout}})
	var ledger_ok: bool = true
	for key: String in before.ledger.entries:
		ledger_ok = ledger_ok and f.w.facts.ledger.entries[key]==before.ledger.entries[key]
	var preserved: bool = before.actors==f.w.facts.actors and before.moves==f.w.facts.moves and before.environment.receipts==f.w.facts.environment.receipts and before.environment.orders==f.w.facts.environment.orders and ledger_ok
	save("after-"+rid,f.w.freeze())
	return ck("apply-"+rid,result.accepted and preserved and HospitalLedger.balance(f.w)==int(before.ledger.opening_balance)+_entries_total(before.ledger.entries)+int(plan.refund)-int(plan.price),result.to_record()) and safety("validate-immediately-"+rid)
func _entries_total(entries: Dictionary) -> int:
	var total: int = 0
	for entry: Dictionary in entries.values(): total += int(entry.amount)
	return total
func finish():
	save("final",f.w.freeze()); save("checks",checks); save("trace",trace)
	f.s.dispose()
	quit(0 if checks.all(func(x): return x.ok) else 1)
func run():
	var args: PackedStringArray = OS.get_cmdline_user_args()
	prefix = args[1]
	content = HospitalContent.new()
	suite = load("res://tests/acceptance/operations.gd").new(); suite._content = content
	var raw: Dictionary = FileAccess.open(args[0],FileAccess.READ).get_var(true)
	bind(raw)
	for id: String in f.w.facts.remodels:
		if f.w.facts.remodels[id].room_ids==["room_a"]: aid = id
		if f.w.facts.remodels[id].room_ids==["room_b"]: bid = id
	for layout: Dictionary in f.w.facts.floors.overrides.values():
		for door: Dictionary in layout.get("doors",[]):
			if door.room_id=="room_b": door_id = door.id
	if not ck("exact-full-world-bind",raw==f.w.freeze() and not aid.is_empty() and not bid.is_empty() and f.w.facts.adaptations.has(door_id) and not door_id in f.w.facts.remodels[bid].member_ids) or not safety("initial-valid-body"): finish(); return
	if not waiting_queries("saved-orders-affected-door-blocks-only-room-b",true): finish(); return
	var before: Dictionary = f.w.freeze().duplicate(true)
	var result: CommandResult = command("remodel_apply",{"order_id":bid,"quote":{}})
	if not ck("unsafe-apply-rejected-atomic-full-freeze-rng",not result.accepted and before==f.w.freeze(),result.to_record()): finish(); return
	# Cancel only the remodel and reprepare via production commands. The live
	# source reservation and renovation cancellation remain untouched.
	if not ck("cancel-remodel",command("remodel_cancel",{"order_id":bid}).accepted): finish(); return
	var prepared: CommandResult = command("remodel_prepare",{"commands":raw.remodels[bid].commands})
	if not ck("live-reprepare",prepared.accepted): finish(); return
	bid = prepared.changed_ids[0]
	if not waiting_queries("live-order-still-blocked",true): finish(); return
	if not ck("cancel-did-not-release-door-or-alter-renovation",f.w.facts.adaptations==raw.adaptations and f.w.facts.environment==raw.environment and f.w.facts.actors==raw.actors): finish(); return
	# A group owns both rooms' doors even when member_ids only names rooms.
	if not ck("cancel-both-for-group",command("remodel_cancel",{"order_id":aid}).accepted and command("remodel_cancel",{"order_id":bid}).accepted): finish(); return
	var grouped: CommandResult = command("remodel_prepare",{"commands":raw.remodels[aid].commands+raw.remodels["remodel_00000008"].commands})
	if not ck("prepare-live-group",grouped.accepted): finish(); return
	var gid: String = grouped.changed_ids[0]
	var group_raw: Dictionary = f.w.freeze().duplicate(true)
	var group_preview: Dictionary = f.s.services.remodel.preview(f.w,gid)
	if not ck("live-group-blocked-by-second-room-door",not group_preview.ok and group_raw==f.w.freeze() and not door_id in f.w.facts.remodels[gid].member_ids,group_preview.reason): finish(); return
	bind(group_raw)
	var group_apply: CommandResult = command("remodel_apply",{"order_id":gid,"quote":{}})
	if not ck("saved-group-rejects-atomically",not group_apply.accepted and group_raw==f.w.freeze() and f.w.validate(content).is_empty(),group_apply.to_record()): finish(); return
	# Independent branch ends here; restore every original fact for actual release.
	bind(raw); bid = ""
	for id: String in raw.remodels:
		if raw.remodels[id].room_ids==["room_b"]: bid = id
	if not ck("rebound-original-exact",raw==f.w.freeze()): finish(); return
	var released: bool = false
	for step: int in 30:
		f.s.services.remodel.dispatch(f.w)
		suite._work_tick(f,"environment")
		trace.append({"step":step,"tick":f.w.sim_tick,"actors":f.w.facts.actors.duplicate(true),"moves":f.w.facts.moves.duplicate(true),"adaptations":f.w.facts.adaptations.duplicate(true)})
		if not safety("real-step-"+str(step)): finish(); return
		if not f.w.facts.adaptations.has(door_id): released = true; break
		if not waiting_queries("held-step-"+str(step),true): finish(); return
	if not ck("terminal-natural-door-release-before-long-route-end",released and f.w.facts.moves.has("ops_decorator") and f.w.facts.moves.ops_decorator.request_sequence==raw.moves.ops_decorator.request_sequence): finish(); return
	save("naturally-released",f.w.freeze())
	if not waiting_queries("released-orders-independently-ready",false): finish(); return
	if not apply_one(aid) or not apply_one(bid): finish(); return
	var surfaces: Dictionary = f.w.facts.environment.surfaces
	var originals: Dictionary = raw.environment.surfaces
	var moved_ok: bool = surfaces.size()==originals.size()
	for surface: Dictionary in originals.values():
		var moved: Dictionary = surface.duplicate(true)
		moved.cell = [int(surface.cell[0]),int(surface.cell[1])-6]
		moved_ok = moved_ok and moved in surfaces.values()
	ck("terminal-surfaces-original-paid-cost-completed-tick",moved_ok,{"before":originals,"after":surfaces})
	finish()
