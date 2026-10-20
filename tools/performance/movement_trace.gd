extends RefCounted

# Diagnostic-only movement observer. Each override calls its original method
# exactly once. Counters and bounded samples never enter world facts.
class TraceMovement:
	extends HospitalMovement
	var trace: RefCounted

	func _init(geometry: HospitalSpace, observer: RefCounted) -> void:
		super(geometry)
		trace = observer

	func request_move(world: WorldState, actor_id: String, floor_id: int, target: Array) -> String:
		trace.enter("request_move",world,actor_id,world.facts.moves.get(actor_id,{}),{"requested_floor":floor_id,"requested_cell":target.duplicate()})
		var result: String = super.request_move(world,actor_id,floor_id,target)
		trace.leave(world,result)
		return result

	func request_group_move(world: WorldState, primary_id: String, members: Array, offsets: Dictionary, floor_id: int, target: Array) -> String:
		trace.enter("request_group_move",world,primary_id,world.facts.moves.get(primary_id,{}),{"requested_floor":floor_id,"requested_cell":target.duplicate()})
		var result: String = super.request_group_move(world,primary_id,members,offsets,floor_id,target)
		trace.leave(world,result)
		return result

	func _retarget(world: WorldState, previous: Dictionary, floor_id: int, target: Array) -> String:
		trace.enter("retarget",world,str(previous.actor_id),previous,{"requested_floor":floor_id,"requested_cell":target.duplicate()})
		var result: String = super._retarget(world,previous,floor_id,target)
		trace.leave(world,result)
		return result

	func advance(world: WorldState, present_at_start: int = -1) -> void:
		trace.enter("advance",world,"",{})
		super.advance(world,present_at_start)
		trace.leave(world)

	func _queue_route(world: WorldState, movement: Dictionary) -> void:
		trace.enter("queue_route",world,str(movement.actor_id),movement)
		super._queue_route(world,movement)
		trace.leave(world)

	func _replan_goal(world: WorldState, movement: Dictionary, preserve_order: bool = false) -> void:
		trace.enter("replan_goal",world,str(movement.actor_id),movement,{"preserve_order":preserve_order})
		super._replan_goal(world,movement,preserve_order)
		trace.leave(world)

	func _active_route_clear(world: WorldState, actor: Dictionary, movement: Dictionary, versions: Dictionary) -> bool:
		var result: bool = super._active_route_clear(world,actor,movement,versions)
		if not result: trace.route_invalid(str(actor.id))
		return result

	func _dispatch_routes(world: WorldState, present_at_start: int) -> void:
		trace.enter("dispatch_routes",world,"",{})
		var before: Dictionary = trace.pending(world)
		var count_before: int = int(space.query_counts.get("route_dispatches",0))
		super._dispatch_routes(world,present_at_start)
		var failures: Dictionary = get("_route_failures") if trace.has_failure_ledger else {}
		trace.dispatched(world,before,int(space.query_counts.get("route_dispatches",0))-count_before,failures)
		trace.leave(world)

	func queue_waypoint(world: WorldState, movement: Dictionary, floor_id: int, cell: Array) -> void:
		trace.enter("queue_waypoint",world,str(movement.actor_id),movement,{"requested_floor":floor_id,"requested_cell":cell.duplicate()})
		super.queue_waypoint(world,movement,floor_id,cell)
		trace.leave(world)

	func _queue_local_route(world: WorldState, actor: Dictionary, movement: Dictionary) -> void:
		trace.enter("queue_local_route",world,str(actor.id),movement)
		super._queue_local_route(world,actor,movement)
		trace.leave(world)

	func _yield(world: WorldState, actor: Dictionary, movement: Dictionary, result: MotionResult) -> void:
		trace.enter("yield",world,str(actor.id),movement,{"blockers":result.blocker_actor_ids.duplicate(),"reservations":result.reservation_ids.duplicate(),"door_id":result.door_id})
		super._yield(world,actor,movement,result)
		trace.leave(world)

	func _local_goal_occupied(world: WorldState, actor: Dictionary, movement: Dictionary, contact: MotionResult) -> bool:
		var result: bool = super._local_goal_occupied(world,actor,movement,contact)
		trace.goal_gate(world,self,actor,movement,contact.blocker_actor_ids,result)
		return result

	func _yield_idle_staff(world: WorldState, actor: Dictionary, movement: Dictionary, blocker_actor_ids: Array[String]) -> bool:
		trace.enter("yield_idle_staff",world,str(actor.id),movement)
		var result: bool = super._yield_idle_staff(world,actor,movement,blocker_actor_ids)
		trace.leave(world,result)
		return result

	func _movement_owners(world: WorldState, blocker_actor_ids: Array[String]) -> Array:
		var result: Array = super._movement_owners(world,blocker_actor_ids)
		trace.owners(world,result)
		return result

	func _has_priority(world: WorldState, first_id: String, second_id: String) -> bool:
		var result: bool = super._has_priority(world,first_id,second_id)
		trace.priority(world,first_id,second_id,result)
		return result

var errors: Array = []
var sources: Dictionary = {}
var max_samples: int = 96
var samples_per_kind: int = 4
var max_actor_rows: int = 256
var has_failure_ledger: bool = false
var _stack: Array = []
var _counts: Dictionary = {}
var _callers: Dictionary = {}
var _actors: Dictionary = {}
var _samples: Array = []
var _sample_counts: Dictionary = {}
var _goal_samples: Array = []
var _goal_sample_keys: Dictionary = {}
var _dispatch_signatures: Dictionary = {}
var _last_winners: Dictionary = {}
var _last_owners: Dictionary = {}
var _world: WeakRef
var _movement: WeakRef
var _first_tick: int = -1
var _last_tick: int = -1
var _dispatch_delta: int = 0
var _dispatch_observed: int = 0
var _query_start: Dictionary = {}
var _start_sequence: int = 0

func attach(simulation: HospitalSimulation) -> HospitalSimulation:
	if _movement!=null or simulation.step_in_progress():
		errors.append("attach requires an unused observer and a complete step boundary")
		return null
	var original: HospitalMovement = simulation.space.movement
	var base: Script = original.get_script()
	if base.resource_path!="res://game/building/hospital_movement.gd":
		errors.append("movement observer requires the unwrapped production service")
		return null
	var before: Dictionary = simulation.world.freeze()
	var replacement: TraceMovement = TraceMovement.new(simulation.space,self)
	var transferred: Array = []
	for property: Dictionary in original.get_property_list():
		if property.name=="space" or (int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE)==0: continue
		if property.name=="_route_failures": has_failure_ledger = true
		replacement.set(property.name,original.get(property.name))
		transferred.append(str(property.name))
	simulation.space.movement = replacement
	_world = weakref(simulation.world)
	_movement = weakref(replacement)
	_query_start = simulation.space.query_counts.duplicate(true)
	_start_sequence = int(simulation.world.facts.get("move_request_next",0))
	sources = {"production_path":base.resource_path,"production_sha256":base.source_code.sha256_text(),"transferred_properties":transferred,"attach_world_unchanged":simulation.world.freeze()==before,"mode":"movement_observer_only"}
	if not sources.attach_world_unchanged:
		errors.append("attach changed frozen world state")
		return null
	return simulation

func enter(operation: String, world: WorldState, actor_id: String, movement: Dictionary, extra: Dictionary = {}) -> void:
	if _first_tick<0: _first_tick = world.sim_tick
	_last_tick = world.sim_tick
	var parent: String = "external" if _stack.is_empty() else str(_stack.back().operation)
	var frame: Dictionary = {"operation":operation,"parent":parent,"actor_id":actor_id,"before":_state(world,actor_id,movement),"extra":extra,"queues":0,"local_routes":0,"idle_moved":false,"priority_checked":false,"owners":[]}
	if parent=="external":
		var callers: Array = []
		for site: Dictionary in get_stack():
			if str(site.source).ends_with("movement_trace.gd"): continue
			callers.append(str(site.source)+":"+str(site.function))
			if callers.size()==4: break
		extra.external_stack = callers
		if not callers.is_empty(): _increment(_callers,"external " + " <- ".join(callers)+" -> "+operation)
	if operation=="replan_goal":
		frame.reason = "retarget" if parent=="retarget" else "unknown"
		if parent=="advance":
			frame.reason = "active_route_invalid" if _stack.back().get("invalid_actor","")==actor_id else "advance_other"
	_stack.append(frame)
	_increment(_counts,"calls."+operation)
	_increment(_callers,parent+" -> "+operation)
	if operation=="queue_route":
		for outer: Dictionary in _stack:
			if outer.operation=="yield": outer.queues += 1
	if operation=="queue_local_route":
		for outer: Dictionary in _stack:
			if outer.operation=="yield": outer.local_routes += 1

func leave(world: WorldState, result: Variant = null) -> void:
	if _stack.is_empty():
		errors.append("movement observer stack underflow")
		return
	var frame: Dictionary = _stack.pop_back()
	var id: String = str(frame.actor_id)
	var after: Dictionary = _state(world,id,world.facts.moves.get(id,{}))
	var kind: String = ""
	match str(frame.operation):
		"request_move", "request_group_move":
			kind = "request."+("retarget" if not frame.before.is_empty() else "new")+(".accepted" if str(result).is_empty() else ".returned_reason")
		"retarget":
			if frame.before.get("goal",[])==[frame.extra.requested_floor,frame.extra.requested_cell]: kind = "retarget.same_goal"
			elif after.get("goal",[])!=frame.before.get("goal",[]): kind = "retarget.changed_goal"
			else: kind = "retarget.rejected"
		"queue_route": kind = "queue."+_queue_reason(frame)
		"replan_goal": kind = "replan."+str(frame.reason)+(".preserve_order" if frame.extra.preserve_order else ".new_sequence")
		"queue_local_route": kind = "local_route."+str(frame.parent)
		"queue_waypoint": kind = "waypoint."+str(frame.parent)
		"yield_idle_staff":
			kind = "idle_courtesy.moved" if result==true else "idle_courtesy.no_move"
			for outer: Dictionary in _stack:
				if outer.operation=="yield": outer.idle_moved = result==true
		"yield":
			if frame.before.get("yielding",false) or frame.before.get("travelled",0)==0: kind = "yield.skipped"
			elif frame.idle_moved: kind = "yield.idle_staff_moved"
			elif int(frame.local_routes)>0: kind = "yield.local_fallback"
			elif frame.priority_checked and frame.get("priority",false): kind = "yield.priority_wait"
			elif int(frame.queues)>0 and after.get("yielding",false): kind = "yield.retreat_queued"
			elif frame.priority_checked: kind = "yield.no_legal_retreat"
			elif _observed_yielded_owner(frame): kind = "yield.observed_yielded_owner_wait"
			else: kind = "yield.unknown_no_queue"
	if not kind.is_empty(): _record(kind,world,id,frame.before,after,frame.extra)

func _queue_reason(frame: Dictionary) -> String:
	match str(frame.parent):
		"request_move", "request_group_move": return "new_request"
		"dispatch_routes": return "dispatch_failure_retry"
		"queue_waypoint": return "explicit_waypoint"
		"queue_local_route": return "local_fallback"
		"yield": return "yield_retreat"
		"replan_goal": return "replan."+str(_stack.back().get("reason","unknown"))
		"advance":
			if int(frame.before.get("cursor",0))<0 and int(frame.before.get("path_size",0))==0: return "support_exit_completed"
			if int(frame.before.get("cursor",0))>=int(frame.before.get("path_size",0)): return "completed_retreat_resume"
	return "unknown."+str(frame.parent)

func route_invalid(actor_id: String) -> void:
	_increment(_counts,"active_route.invalid")
	if not _stack.is_empty() and _stack.back().operation=="advance": _stack.back().invalid_actor = actor_id

func owners(world: WorldState, ids: Array) -> void:
	if _stack.is_empty() or _stack.back().operation!="yield": return
	var rows: Array = []
	for id: String in ids:
		var state: Dictionary = _state(world,id,world.facts.moves.get(id,{}))
		state.actor_id = id
		rows.append(state)
		var key: String = str(_stack.back().actor_id)+"|"+id
		if _last_owners.has(key):
			var previous: Dictionary = _last_owners[key]
			if previous.goal!=state.get("goal",[]): _increment(_counts,"yield.observed_owner_goal_changed_since_previous_pair_check")
			if previous.sequence!=state.get("sequence",-1): _increment(_counts,"yield.observed_owner_sequence_changed_since_previous_pair_check")
		_last_owners[key] = {"goal":state.get("goal",[]),"sequence":state.get("sequence",-1)}
	_stack.back().owners = rows
	_stack.back().extra.moving_owners = rows

func priority(world: WorldState, first_id: String, second_id: String, result: bool) -> void:
	_increment(_counts,"priority.true" if result else "priority.false")
	if _stack.is_empty() or _stack.back().operation!="yield": return
	var frame: Dictionary = _stack.back()
	frame.priority_checked = true
	frame.priority = result
	var winner: Dictionary = _state(world,second_id,world.facts.moves.get(second_id,{}))
	frame.extra.priority = result
	frame.extra.priority_other_id = second_id
	frame.extra.priority_other = winner
	var key: String = first_id+"|"+second_id
	if _last_winners.has(key):
		var previous: Dictionary = _last_winners[key]
		if previous.goal!=winner.get("goal",[]): _increment(_counts,"priority.other_goal_changed_since_previous_pair_check")
		if previous.sequence!=winner.get("sequence",-1): _increment(_counts,"priority.other_sequence_changed_since_previous_pair_check")
	_last_winners[key] = {"goal":winner.get("goal",[]),"sequence":winner.get("sequence",-1)}

func _observed_yielded_owner(frame: Dictionary) -> bool:
	for owner: Dictionary in frame.owners:
		if owner.get("yielding",false): return true
	return false

# Observe the actual parent's one gate decision, including the older gate
# that only inspected contact IDs. These current-body probes are diagnostic;
# they never supply a decision to production or inspect accepted past sweeps.
func goal_gate(world: WorldState, service: HospitalMovement, actor: Dictionary, movement: Dictionary, actual_hits: Array[String], waited: bool) -> void:
	_increment(_counts,"calls.local_goal_occupied")
	var end: int = int(movement.cursor)
	var floor_id: int = int(actor.location.floor_id)
	if actual_hits.is_empty() or end<0 or end>=movement.path.size(): return
	while end+1<movement.path.size() and movement.path[end+1].kind=="floor" and int(movement.path[end+1].floor_id)==floor_id: end += 1
	var target: Dictionary = movement.path[end]
	if target.kind!="floor" or int(target.floor_id)!=floor_id: return
	var origin: Vector2 = Vector2(float(target.cell[0]),float(target.cell[1]))
	var members: Array = [actor.id]
	for id: String in movement.get("members",[]):
		if id!=actor.id: members.append(id)
	var cores: Array = []
	var occupied: Dictionary = {}
	var complete: bool = true
	for id: String in members:
		var member: Dictionary = world.facts.actors[id]
		if member.get("posture","standing")=="lying":
			complete = false
			continue
		var dimensions: Dictionary = service.space.body(member)
		var side: float = minf(float(dimensions.get("width_m",0.0)),float(dimensions.get("depth_m",0.0)))/HospitalSpace.CELL_METERS
		if not is_finite(side) or side<=0.0:
			complete = false
			continue
		var offset: Array = movement.get("offsets",{}).get(id,[0,0])
		var center: Vector2 = service.space._actor_rect(member,origin+Vector2(float(offset[0]),float(offset[1]))).get_center()
		var core: Rect2 = Rect2(center-Vector2.ONE*side*0.5,Vector2.ONE*side)
		var ids: Array[String] = service.space._actor_index.candidates(floor_id,core,members)
		for blocker_id: String in ids: occupied[blocker_id] = true
		cores.append({"member_id":id,"rect":[core.position.x,core.position.y,core.size.x,core.size.y],"current_body_ids":ids})
	var all_ids: Array = occupied.keys()
	all_ids.sort()
	var other_ids: Array = []
	for id: String in all_ids:
		if not id in actual_hits: other_ids.append(id)
	var kind: String = "other_body_at_destination" if not other_ids.is_empty() else "contact_body_at_destination" if not all_ids.is_empty() else "destination_core_clear" if complete else "not_proven"
	var state: Dictionary = _state(world,str(actor.id),movement)
	var extra: Dictionary = {"goal":[floor_id,target.cell.duplicate()],"actual_hit_ids":actual_hits.duplicate(),"current_destination_body_ids":all_ids,"other_destination_body_ids":other_ids,"member_cores":cores,"parent_waited":waited}
	_record("goal_gate."+kind,world,str(actor.id),state,state,extra)
	_record("goal_gate.waited" if waited else "goal_gate.allowed_local_route",world,str(actor.id),state,state)
	var sample_key: String = str(actor.id)+":"+kind
	if _goal_samples.size()<32 and not _goal_sample_keys.has(sample_key):
		_goal_sample_keys[sample_key] = true
		_goal_samples.append({"tick":world.sim_tick,"actor_id":actor.id,"kind":kind,"location":actor.location.duplicate(true),"observation":extra})

func pending(world: WorldState) -> Dictionary:
	var result: Dictionary = {}
	for id: String in world.facts.moves:
		var movement: Dictionary = world.facts.moves[id]
		if movement.get("route_pending",false): result[id] = _state(world,id,movement)
	return result

func dispatched(world: WorldState, before: Dictionary, count_delta: int, failures: Dictionary) -> void:
	_dispatch_delta += count_delta
	var observed: int = 0
	for id: String in before:
		var after: Dictionary = _state(world,id,world.facts.moves.get(id,{}))
		if after.is_empty(): continue
		var success: bool = not after.pending
		var failed: bool = int(after.sequence)!=int(before[id].sequence)
		if not success and not failed: continue
		observed += 1
		var kind: String = "dispatch.success" if success else "dispatch.failure."+("unreachable" if failures.has(id) else "other_unknown")
		var signature: String = JSON.stringify([id,before[id].goal,before[id].waypoint,before[id].get("body",[]),world.geometry_revision])
		if _dispatch_signatures.has(signature): _record("dispatch.repeated_same_actor_goal_waypoint_body_geometry",world,id,before[id],after)
		_dispatch_signatures[signature] = true
		_record(kind,world,id,before[id],after)
	_dispatch_observed += observed
	if observed!=count_delta: errors.append("dispatch count mismatch at tick "+str(world.sim_tick)+": "+str(observed)+" observed / "+str(count_delta)+" query counter")

func _state(world: WorldState, id: String, movement: Dictionary) -> Dictionary:
	if movement.is_empty(): return {}
	var actor: Dictionary = world.facts.actors.get(id,{})
	var waypoint: Dictionary = movement.get("route_waypoint",{})
	var bodies: Array = []
	for member_id: String in movement.get("members",[id]):
		var member: Dictionary = world.facts.actors.get(member_id,{})
		bodies.append([member_id,member.get("species_id",""),member.get("body_binding_id",""),member.get("posture","standing"),member.get("support_facility_id","")])
	return {"sequence":int(movement.get("request_sequence",-1)),"goal":[movement.get("target_floor",-1),movement.get("target_cell",[]).duplicate()],"waypoint":[] if waypoint.is_empty() else [waypoint.floor_id,waypoint.cell.duplicate(),waypoint.get("continuation",[]).size()],"pending":bool(movement.get("route_pending",false)),"retry_tick":int(movement.get("route_retry_tick",0)),"yielding":bool(movement.get("yielding",false)),"yield_partner":str(movement.get("yield_partner","")),"cursor":int(movement.get("cursor",0)),"path_size":movement.get("path",[]).size(),"travelled":movement.get("travelled",[]).size(),"blocked_since":int(movement.get("blocked_since",-1)),"reason":str(movement.get("waiting_reason","")),"location":actor.get("location",{}).duplicate(true),"body":[bodies,movement.get("offsets",{}).duplicate(true)]}

func _record(kind: String, world: WorldState, id: String, before: Dictionary, after: Dictionary, extra: Dictionary = {}) -> void:
	_increment(_counts,kind)
	if not id.is_empty():
		if not _actors.has(id) and _actors.size()<max_actor_rows: _actors[id] = {}
		if _actors.has(id): _increment(_actors[id],kind)
	if _samples.size()>=max_samples or int(_sample_counts.get(kind,0))>=samples_per_kind: return
	_increment(_sample_counts,kind)
	var staff: Dictionary = world.facts.staff.get(id,{})
	var public_intent: Dictionary = staff.get("life_task",{})
	if public_intent.is_empty():
		for collection: String in ["seats","needs"]:
			for intent: Dictionary in world.facts.get("waiting_life",{}).get(collection,{}).values():
				if intent.get("actor_id","")==id: public_intent = intent; break
	if public_intent.is_empty():
		for stay: Dictionary in world.facts.get("visitors",{}).get("stays",{}).values():
			if stay.get("actor_id","")==id: public_intent = stay.get("public_use",{}); break
	_samples.append({"tick":world.sim_tick,"kind":kind,"actor_id":id,"before":before.duplicate(true),"after":after.duplicate(true),"extra":extra.duplicate(true),"staff_task":staff.get("life_task",{}).duplicate(true),"base_task":staff.get("base_task",{}).duplicate(true),"public_intent":public_intent.duplicate(true)})

func _increment(target: Dictionary, key: String) -> void:
	target[key] = int(target.get(key,0))+1

func report() -> Dictionary:
	var actor_rows: Array = []
	var world: WorldState = _world.get_ref() if _world!=null else null
	var movement: HospitalMovement = _movement.get_ref() if _movement!=null else null
	var query_delta: Dictionary = {}
	if movement!=null:
		for name: String in ["route_dispatches","route_dispatch_scans","route_revalidations","yield_attempts","yield_candidates","local_goal_occupied_waits"]:
			query_delta[name] = int(movement.space.query_counts.get(name,0))-int(_query_start.get(name,0))
	for id: String in _actors:
		var total: int = 0
		for count: int in _actors[id].values(): total += count
		actor_rows.append({"actor_id":id,"events":total,"counts":_actors[id].duplicate(),"final_movement":_state(world,id,world.facts.moves.get(id,{})) if world!=null else {}})
	actor_rows.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(a.events)>int(b.events))
	return {"first_tick":_first_tick,"last_tick":_last_tick,"counts":_counts.duplicate(),"callers":_callers.duplicate(),"actors":actor_rows,"actor_rows_bounded":_actors.size()>=max_actor_rows,"samples":_samples.duplicate(true),"samples_limit":max_samples,"goal_gate_samples":_goal_samples.duplicate(true),"goal_gate_samples_limit":32,"query_count_delta":query_delta,"request_sequence_delta":int(world.facts.get("move_request_next",0))-_start_sequence if world!=null else 0,"dispatch_query_delta":_dispatch_delta,"dispatch_observed":_dispatch_observed,"dispatch_count_check":_dispatch_delta==_dispatch_observed,"stack_depth":_stack.size(),"sources":sources.duplicate(true),"errors":errors.duplicate(),"semantics":{"timings":"Observer mode counts only. Use paired plain elapsed times for performance.","caller":"Nearest wrapped movement method. Debug external_stack retains up to four real outside caller frames when available; release builds may not expose stacks.","advance_other_replan":"Production advance call not preceded by observed active-route invalidation; retain this label rather than claim an unobserved exact branch.","yielded_owner_wait":"A returned moving-owner row was already yielding; no queue and no priority call. This is observation, not a recomputed ownership decision.","goal_gate":"The production parent gate is called once; classify current destination cores against current bodies, including bodies absent from actual contact IDs. Per-actor/kind samples are separately bounded; no historical sweep or route query decides this observation.","dispatch_repeat":"Same actor, final goal, effective waypoint including continuation length, body/formation and geometry identity. It does not prove the earlier route is still reusable: live occupancy may differ.","business_validation":"Driver must compare final frozen facts, random streams and semantic events with the ordinary same-input run; compare dispatch/query counts too."}}
