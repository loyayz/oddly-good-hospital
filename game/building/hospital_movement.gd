class_name HospitalMovement
extends RefCounted

# Conservative binary32 position allowance on the bounded floor, including
# accumulated rounding along an ordinary leg. This is only an endpoint budget
# correction; body and sweep collision predicates retain their strict edges.
const POSITION_ROUNDING: float = 2.0*FloorNavigation.SIDE/8388608.0
const RETURN_CONTACT_REGION_CELLS: float = 2.0
const MAX_RETURN_CONTACT_REGIONS: int = 4096

class MotionResult:
	extends RefCounted
	# One synchronous attempt, never a second copy of a journey or world fact.
	var requested_motion: Vector2 = Vector2.ZERO
	var actual_motion: Vector2 = Vector2.ZERO
	var blocker_actor_ids: Array[String] = []
	var reservation_ids: Array[String] = []
	var static_reason: String = ""
	var door_id: String = ""
	# Only private return-proof consumers request an existence witness.
	var first_contact_only: bool = false
	var blocked: bool:
		get: return not static_reason.is_empty() or not door_id.is_empty() or not blocker_actor_ids.is_empty() or not reservation_ids.is_empty()

# Private to one synchronous nonconvoy return search. Contacts only borrow
# these objects; they never retain or mutate the sweep, or change motion fields.
class ReturnContactScratch:
	extends RefCounted
	var sweep: BodyIndex.Record = BodyIndex.Record.new()
	var result: MotionResult = MotionResult.new()
	var sweeps: Array[BodyIndex.Record] = [sweep]
	var queries: Dictionary = {}
	func _init() -> void:
		result.first_contact_only = true

var _space: WeakRef
var space: HospitalSpace:
	get: return _space.get_ref()

var _sweep_index: BodyIndex
var _accepted_sweeps: Dictionary = {}
var _route_checks: Dictionary = {}
var _movement_reservations: Dictionary = {}
var _world: WeakRef
var _pending_world: WeakRef
var _pending_routes: Dictionary = {}
var _ready_routes: PlatformRouteQueue
var _delayed_routes: PlatformRouteQueue
var _phase_owners: Dictionary = {}
var _route_failures: Dictionary = {}
# Journey ownership is independent of the disposable spatial projection.
# Rebuild once on world/moves replacement, then maintain official group writes.
var _membership_world: WeakRef
var _membership_moves: Dictionary = {}
var _member_owners: Dictionary = {}

func _ensure_membership(world: WorldState) -> void:
	if _membership_world!=null and _membership_world.get_ref()==world and is_same(_membership_moves,world.facts.moves): return
	_membership_world = weakref(world)
	_membership_moves = world.facts.moves
	_member_owners.clear()
	for movement: Dictionary in world.facts.moves.values():
		if movement.has("convoy"): _register_members(movement)

func _register_members(movement: Dictionary) -> void:
	for index: int in movement.members.size():
		_member_owners[movement.members[index]] = {"owner":movement.actor_id,"index":index}

func _unregister_members(movement: Dictionary) -> void:
	for id: String in movement.get("members",[]):
		if _member_owners.get(id,{}).get("owner","")==movement.actor_id: _member_owners.erase(id)

func _member_owner(world: WorldState, actor_id: String) -> String:
	_ensure_membership(world)
	var entry: Dictionary = _member_owners.get(actor_id,{})
	if entry.is_empty(): return ""
	var movement: Dictionary = world.facts.moves.get(entry.owner,{})
	var members: Array = movement.get("members",[])
	# Direct external erasure of a journey must not leave stale ownership.
	if not movement.has("convoy") or int(entry.index)>=members.size() or members[int(entry.index)]!=actor_id:
		_member_owners.erase(actor_id)
		return ""
	return str(entry.owner)


func _init(geometry: HospitalSpace) -> void:
	_space = weakref(geometry)
	var cells: Array = geometry.content.balance.pathfinding.local_updates.chunk_cells
	_sweep_index = BodyIndex.new(Vector2(float(cells[0]),float(cells[1])))

func request_move(world: WorldState, actor_id: String, floor_id: int, target: Array) -> String:
	var owner: String = _member_owner(world,actor_id)
	if not owner.is_empty() and owner!=actor_id: return "等待当前队列完成后独立移动"
	if world.facts.moves.has(actor_id):
		return _retarget(world,world.facts.moves[actor_id],floor_id,target)
	var actor: Dictionary = world.facts.actors[actor_id]
	if actor.location.kind!="floor":
		return "角色正在竖向通行或院外"
	if actor.get("posture","standing") == "lying":
		var facility: Dictionary = space.facility_layout(world,actor.support_facility_id)
		world.facts.moves[actor_id] = {"actor_id":actor_id,"path":[{"kind":"support_exit","floor_id":int(facility.floor_id),"cell":facility.patient_cell.duplicate()}],
			"cursor":0,"travelled":[_checkpoint(actor)],"blocked_since":-1,"target_floor":floor_id,"target_cell":target.duplicate()}
		if space.public_areas!=null: space.public_areas.changed(world)
		return ""
	var reason: String = space.navigation.destination_reason(world,actor,floor_id,Vector2(float(target[0]),float(target[1])))
	if not reason.is_empty():
		return reason
	world.facts.moves[actor_id] = {"actor_id":actor_id,"path":[],"cursor":0,
		"travelled":[_checkpoint(actor)],"blocked_since":-1,"target_floor":floor_id,"target_cell":target.duplicate()}
	_queue_route(world,world.facts.moves[actor_id])
	if space.public_areas!=null: space.public_areas.changed(world)
	return ""

func _retarget(world: WorldState, previous: Dictionary, floor_id: int, target: Array) -> String:
	# Scalar equality accepts int/float forms without rounding distinct targets.
	# Malformed group goals must still reach the existing destination validator.
	if previous.target_floor==floor_id and ConvoyTrail._finite_point(target) and previous.target_cell[0]==target[0] and previous.target_cell[1]==target[1]:
		# Accepting an identical destination may still transfer task ownership.
		previous.erase("waiting_seat_id")
		previous.erase("waiting_need_id")
		previous.erase("waiting_safety_visit")
		previous.erase("floor_guidance_key")
		previous.erase("guidance_nurse_desk")
		previous.erase("floor_only")
		return previous.get("waiting_reason","")
	var actor: Dictionary = world.facts.actors[previous.actor_id]
	var reason: String = _convoy_goal_reason(world,previous,floor_id,target) if previous.has("convoy") else space.navigation.destination_reason(world,actor,floor_id,Vector2(float(target[0]),float(target[1])),previous.get("members",[]),previous.get("offsets",{}))
	if not reason.is_empty(): return reason
	# A new destination belongs to its requesting task, not the old optional trip.
	previous.erase("waiting_seat_id")
	previous.erase("waiting_need_id")
	previous.erase("waiting_safety_visit")
	previous.erase("floor_guidance_key")
	previous.erase("guidance_nurse_desk")
	previous.erase("floor_only")
	HospitalTransit.cancel_waiting(world,previous)
	previous.erase("route_waypoint")
	previous.erase("detour")
	previous.erase("live_floor_route")
	previous.erase("rejoin_origin")
	previous.erase("route_capability_error")
	previous.target_floor = floor_id
	previous.target_cell = target.duplicate()
	previous.erase("route_retry_tick")
	previous.erase("waiting_reason")
	if actor.location.kind=="transit": previous.replan_after_transit = true
	elif previous.path.is_empty() or int(previous.cursor)>=previous.path.size() or previous.path[int(previous.cursor)].kind!="support_exit":
		_replan_goal(world,previous,bool(previous.get("route_pending",false)))
	if space.public_areas!=null: space.public_areas.changed(world)
	return previous.get("waiting_reason","")

func request_group_move(world: WorldState, primary_id: String, members: Array, offsets: Dictionary, floor_id: int, target: Array) -> String:
	if not offsets.is_empty(): return "同行组只支持前后队列，不再使用横向配位"
	if members.is_empty() or members[0]!=primary_id: return "队列首位必须为队长"
	if world.facts.moves.has(primary_id):
		var previous: Dictionary = world.facts.moves[primary_id]
		if not previous.has("convoy") or previous.members!=members: return "等待原队列结束后再变更成员"
		return _retarget(world,previous,floor_id,target)
	var seen: Dictionary = {}
	for id: String in members:
		if not world.facts.actors.has(id) or seen.has(id): return "队列成员不存在或重复"
		seen[id] = true
		if world.facts.actors[id].location.kind!="floor" or world.facts.moves.has(id): return "等待完整队列真实到场"
		if not _member_owner(world,id).is_empty(): return "成员已有队列归属"
	var created: Dictionary = ConvoyTrail.create(space,world,primary_id,members)
	if not created.ok: return created.reason
	var actor: Dictionary = world.facts.actors[primary_id]
	var m: Dictionary = {"actor_id":primary_id,"members":members.duplicate(),"convoy":created.convoy,"path":[],"cursor":0,"travelled":[_checkpoint(actor)],"blocked_since":-1,"target_floor":floor_id,"target_cell":target.duplicate()}
	var proxy: Dictionary = ConvoyTrail.proxy(world,m)
	var query: RouteClearance = space.navigation.structural_clearance(world,proxy,int(actor.location.floor_id))
	var shift: Vector2 = Vector2.ONE*float(m.convoy.shift)
	for region: Rect2 in ConvoyTrail.regions(m.convoy):
		if not space._dynamic_clear(world,primary_id,int(actor.location.floor_id),region,members,false,true): return "队列集合尾迹已有占用"
		for door: Dictionary in space.movement_doors(world,proxy,region):
			if region.intersects(space._door_rect(door,space._door_span(proxy,door)),false): return "必须离开门口后完整成队"
	for i: int in range(1,m.convoy.points.size()):
		var reason: String = query.sweep_reason(ConvoyTrail.point(m.convoy.points[i-1])+shift,ConvoyTrail.point(m.convoy.points[i])+shift)
		if not reason.is_empty(): return reason
	var reason: String = _convoy_goal_reason(world,m,floor_id,target)
	if not reason.is_empty(): return reason
	world.facts.moves[primary_id] = m
	_register_members(m)
	space._sync_convoy(world,m)
	_queue_route(world,m)
	if space.public_areas!=null: space.public_areas.changed(world)
	return ""

# An unreachable search is different from traffic contention. Its proof is
# query-local runtime data, rechecked against current static geometry and body
# conditions before the owning task may act on it.
func failure(world: WorldState, actor_id: String) -> Dictionary:
	var saved: Dictionary = _route_failures.get(actor_id,{})
	var movement: Dictionary = world.facts.moves.get(actor_id,{})
	if saved.is_empty() or movement.is_empty() or saved.world.get_ref()!=world or int(saved.sequence)!=int(movement.get("request_sequence",-1)) or int(saved.geometry)!=world.geometry_revision: return {}
	if saved.basis!=_failure_body_basis(world,movement) or saved.connectors!=space.navigation.connection_basis(world): return {}
	for floor_id: int in saved.floors:
		if saved.floors[floor_id]!=space._navigation.floor_static_version(space,world,floor_id): return {}
	return {"status":"unreachable","reason":saved.reason,"floor_id":movement.target_floor,"cell":movement.target_cell.duplicate()}

# A task can stop a ground walk or landing queue. It cannot interrupt a real
# ride, a support-exit segment or a group whose full body is not on the floor.
func cancel_ground(world: WorldState, actor_id: String) -> bool:
	var owner: String = _member_owner(world,actor_id)
	if not owner.is_empty() and owner!=actor_id: return false
	var movement: Dictionary = world.facts.moves.get(actor_id,{})
	if movement.is_empty():
		var actor: Dictionary = world.facts.actors[actor_id]
		return actor.location.kind=="floor" and actor.get("posture","standing")!="lying"
	for id: String in movement.get("members",[actor_id]):
		var actor: Dictionary = world.facts.actors[id]
		if actor.location.kind!="floor" or actor.get("posture","standing")=="lying": return false
	if int(movement.cursor)<movement.path.size() and int(movement.cursor)>=0 and movement.path[int(movement.cursor)].kind=="support_exit": return false
	HospitalTransit.cancel_waiting(world,movement)
	world.facts.moves.erase(actor_id)
	if movement.has("convoy"):
		_unregister_members(movement)
		space._end_convoy(world,movement)
	_pending_routes.erase(actor_id)
	_route_checks.erase(actor_id)
	_route_failures.erase(actor_id)
	if space.public_areas!=null: space.public_areas.changed(world)
	return true

func _failure_body_basis(world: WorldState, movement: Dictionary) -> Array:
	var result: Array = [movement.target_floor,movement.target_cell,movement.get("members",[]),movement.get("offsets",{})]
	for id: String in movement.get("members",[str(movement.actor_id)]):
		var actor: Dictionary = world.facts.actors[id]
		result.append([id,actor.location,_route_body_basis(actor)])
	return result

func _remember_failure(world: WorldState, movement: Dictionary, reason: String) -> void:
	var floors: Dictionary = {}
	var actor: Dictionary = world.facts.actors[movement.actor_id]
	var candidates: Dictionary = HospitalTransit._routing_candidates(world,int(actor.location.floor_id),int(movement.target_floor))
	for floor_id: int in candidates:
		floors[floor_id] = space._navigation.floor_static_version(space,world,floor_id)
	_route_failures[movement.actor_id] = {"world":weakref(world),"sequence":int(movement.request_sequence),"geometry":world.geometry_revision,"basis":_failure_body_basis(world,movement).duplicate(true),"connectors":space.navigation.connection_basis(world).duplicate(true),"floors":floors,"reason":reason}
	if space.public_areas!=null: space.public_areas.changed(world)

func advance(world: WorldState, present_at_start: int = -1) -> void:
	# Read-only facility projections can temporarily replace the geometry
	# index's world. They never replace this world's actual journeys.
	if _world==null or _world.get_ref()!=world:
		_route_checks.clear()
		_route_failures.clear()
		_world = weakref(world)
	_sweep_index.begin_boundary(world.facts.actors)
	_accepted_sweeps.clear()
	_phase_owners.clear()
	space._ensure_actor_index(world)
	space._sync_convoys(world)
	space.release_adaptations(world)
	_movement_reservations = space.reservation_view(world)
	HospitalTransit.advance(space,world)
	_dispatch_routes(world,world.present_actor_count() if present_at_start<0 else present_at_start)
	for id: String in _route_checks.keys():
		if not world.facts.moves.has(id):
			_route_checks.erase(id)
	for id: String in _route_failures.keys():
		if not world.facts.moves.has(id): _route_failures.erase(id)
	var floor_versions: Dictionary = {}
	for actor_id: String in world.ids("moves"):
		if not world.facts.moves.has(actor_id):
			continue
		var movement: Dictionary = world.facts.moves[actor_id]
		var actor: Dictionary = world.facts.actors[actor_id]
		if movement.get("replan_after_transit",false) and actor.location.kind=="floor":
			movement.erase("replan_after_transit")
			_replan_goal(world,movement)
		if actor.location.kind == "transit" or movement.get("route_pending",false):
			continue
		# Final portal egress already spent this frame's leader walking budget.
		# Publishing a floor location does not grant a second movement attempt.
		if _accepted_sweeps.has(actor_id): continue
		# A new bed claim can supersede an old destination without becoming a
		# passage wall. Wait before entering its post, keeping this journey and
		# request order. An already requested local yield may still clear traffic.
		var held_goal: String=_bed_goal_blocker(world,actor,movement)
		if not held_goal.is_empty():
			movement.waiting_reason="护理床岗位已有使用预约："+held_goal
			if not movement.has("local_move"): continue
			var local: Dictionary=movement.local_move
			if actor.location.kind=="floor" and not local.get("retreat",false) and ConvoyTrail.point(actor.location.cell)==ConvoyTrail.point(local.target.cell) and _bed_local_path_blocker(world,actor,movement,[local.target]).is_empty(): continue

		# Dispatch can legally publish outside or a supported body position
		# after real arrival but before this phase cleans the exhausted route.
		# Its last real checkpoint survives that handoff, including cold restore.
		var reached_target: bool = not movement.has("convoy") and int(movement.cursor)>=movement.path.size() and _target_checkpoint_reached(movement)
		if not reached_target and not _active_route_clear(world,actor,movement,floor_versions):
			if int(movement.cursor)<movement.path.size() and movement.path[int(movement.cursor)].kind=="support_exit":
				movement.waiting_reason = "等待支撑设施离位通路恢复"
			else:
				_replan_goal(world,movement)
			continue
		if int(movement.cursor)==0 and not movement.has("local_move"):
			movement.cursor = _initial_route_cursor(actor,movement.path,world)
		if movement.has("local_move"):
			if not _local_resume(world,actor,movement): continue
			if not held_goal.is_empty() and not movement.has("local_move"): continue
			# Rejoining transfers movement back to the original route. Its
			# earlier proof may have expired while the local action was active.
			if not movement.has("local_move") and int(movement.cursor)<movement.path.size() and not _active_route_clear(world,actor,movement,floor_versions):
				movement.route_pending=true
				_replan_goal(world,movement,true)
				continue
		if movement.has("detour"):
			var temporary_route: bool=movement.detour.phase!="rejoin"
			_continue_detour(world,actor,movement)
			# Publishing the rejoin suffix can reveal the final approach in this
			# same frame; do not enter a claimed post before next frame's gate.
			if temporary_route and movement.has("detour") and movement.detour.phase=="rejoin":
				var rejoin_held: String=_bed_goal_blocker(world,actor,movement)
				if not rejoin_held.is_empty():
					movement.waiting_reason="护理床岗位已有使用预约："+rejoin_held
					continue
			if movement.has("detour") and int(movement.cursor)>=movement.path.size(): continue
		if int(movement.cursor) >= movement.path.size():
			if not movement.has("convoy") and not reached_target and not space.at(world,actor_id,int(movement.target_floor),movement.target_cell):
				# A restored or shortened path is not proof of arrival. Retain
				# the task and its order, and walk a newly proved remaining route.
				movement.route_pending = true
				_replan_goal(world,movement,true)
				continue
			world.facts.moves.erase(actor_id)
			if movement.has("convoy"):
				_unregister_members(movement)
				space._end_convoy(world,movement)
			_route_failures.erase(actor_id)
			if space.public_areas!=null: space.public_areas.changed(world)
			continue
		var segment: Dictionary = movement.local_move.target if movement.has("local_move") else movement.path[int(movement.cursor)]
		# Resume may replace a reached local corner with the rejoin target in
		# this same frame. Check the segment we will actually execute, not the
		# stale local target from before that ownership transition.
		if movement.has("local_move"):
			var local_held: String=_bed_local_path_blocker(world,actor,movement,[segment])
			if not local_held.is_empty():
				movement.waiting_reason="护理床岗位已有使用预约："+local_held
				continue
		if movement.has("convoy") and movement.has("detour") and movement.detour.phase in ["back","aside"] and not movement.path.is_empty():
			var stop: Dictionary=movement.path[-1]
			if stop.kind=="floor":
				var local_stop: Dictionary=movement.duplicate()
				local_stop.target_floor=stop.floor_id
				local_stop.target_cell=stop.cell
				var temporary_held: String=_bed_goal_blocker(world,actor,local_stop)
				if not temporary_held.is_empty():
					movement.waiting_reason="护理床岗位已有使用预约："+temporary_held
					continue
		if segment.kind == "connector":
			HospitalTransit.begin(space,world,actor,movement,segment)
			continue
		# A queue cannot undo a partly entered corner by folding its leader
		# into its own trail. Read only the immediately adjoining turn first,
		# so an already occupied local leg is handled at the real corner.
		var result: MotionResult = _convoy_turn_contact(world,actor,movement,segment)
		if result==null or not result.blocked:
			result = _move_step(world,actor,movement,segment)
		# Door ownership retains its own wait; it never pushes the owner aside.
		if not result.door_id.is_empty(): continue
		if result.blocked:
			if not movement.has("convoy") and movement.get("members",[actor.id]).size()==1:
				_local_collision(world,actor,movement,result)
				continue
			# Local return intentions are not full-route proofs. If the actual
			# next step hits fixed geometry, rebuild from here instead of
			# repeatedly sidestepping around the same impossible return leg.
			if not result.static_reason.is_empty() and movement.has("detour") and not movement.has("convoy") and movement.get("members",[actor.id]).size()==1:
				_replan_goal(world,movement)
				continue
			if movement.has("detour") and _detour_obstruction(world,actor,movement,result): continue
			if int(movement.blocked_since) < 0:
				movement.blocked_since = world.facts.sim_tick
			_yield(world,actor,movement,result)
	# Publish departure from a landing in this same movement boundary, before
	# other services quote transport or save the world. Active rides are untouched.
	HospitalTransit.cancel_absent_waiters(space,world)
	# Historic sweeps exist only during movement phase, never in later queries.
	_accepted_sweeps.clear()
	_sweep_index.expire_boundary()
	_movement_reservations = {}

# Only the last checkpoint counts: every accepted floor segment and completed
# transit appends its actually reached position. A truncated path therefore
# retains its integer neighbor, never the unvisited requested fraction.
func _target_checkpoint_reached(movement: Dictionary) -> bool:
	# A rejoin can itself be the final target, with no original suffix. Its
	# pending bookkeeping is complete; aside/back waiting prefixes are not.
	if movement.has("detour") and (movement.detour.phase!="rejoin" or int(movement.cursor)<int(movement.detour.prefix_size)): return false
	var travelled: Array = movement.get("travelled",[])
	if travelled.is_empty(): return false
	var last: Dictionary = travelled.back()
	return last.get("kind","")=="floor" and int(last.floor_id)==int(movement.target_floor) and ConvoyTrail.point(last.cell)==ConvoyTrail.point(movement.target_cell)

func _step_toward(start: Vector2, target: Vector2, budget: float) -> Vector2:
	# Measure the actual published endpoints with scalar arithmetic. The old
	# remaining-distance snap could spend up to another .001 cells per tick.
	var dx: float = float(target.x)-float(start.x)
	var dy: float = float(target.y)-float(start.y)
	if sqrt(dx*dx+dy*dy)<=budget+POSITION_ROUNDING: return target
	return start.move_toward(target,budget)

# Read only the issued route's final arrival direction/tail. The convoy
# suffix is bounded by its own physical tail length, never by floor size.
func _bed_goal_regions(world: WorldState, actor: Dictionary, movement: Dictionary) -> Array[Rect2]:
	var goal: Vector2=ConvoyTrail.point(movement.target_cell)
	var floor_id: int=int(movement.target_floor)
	var path: Array=movement.path
	var final_leg: bool=not path.is_empty() and path[-1].kind=="floor" and int(path[-1].floor_id)==floor_id and ConvoyTrail.point(path[-1].cell)==goal
	var direct_local: bool=movement.has("local_move") and int(movement.local_move.target.floor_id)==floor_id and ConvoyTrail.point(movement.local_move.target.cell)==goal
	var landing: Dictionary={}
	if not path.is_empty() and path[-1].kind=="connector" and int(path[-1].to)==floor_id:
		landing=world.facts.connectors[path[-1].connector_id]
		if movement.has("convoy"):
			var plan: Dictionary=ConvoyPortal.plan(space,world,landing,actor.id,movement.members,movement.convoy)
			if plan.get("ok",false) and ConvoyTrail.point(plan.egress)==goal: return ConvoyTrail.regions(ConvoyPortal.predict(movement.convoy,plan,floor_id))
		elif ConvoyTrail.point(landing.anchor)==goal: return [space._actor_rect(actor,goal)]
	# A temporary waypoint/support exit has not issued its final approach yet.
	# Never invent a straight line from another floor or around an unseen turn.
	if not final_leg and not direct_local: return []
	if not movement.has("convoy"):
		var sample: Dictionary=actor.duplicate()
		var previous: Vector2=goal
		if direct_local: previous=ConvoyTrail.point(actor.location.cell)
		elif path.size()>1:
			var prior: Dictionary=path[-2]
			if prior.kind=="floor" and int(prior.floor_id)==floor_id: previous=ConvoyTrail.point(prior.cell)
			elif prior.kind=="connector" and int(prior.to)==floor_id: previous=ConvoyTrail.point(world.facts.connectors[prior.connector_id].anchor)
		elif actor.location.kind=="floor" and int(actor.location.floor_id)==floor_id: previous=ConvoyTrail.point(actor.location.cell)
		var direction: Vector2=goal-previous
		if direction!=Vector2.ZERO: sample.facing=atan2(direction.x,direction.y)
		return [space._actor_rect(sample,goal)]
	var convoy: Dictionary=movement.convoy
	var tail: Dictionary={"left":float(convoy.spacing)*(movement.members.size()-1),"points":[[goal.x,goal.y]]}
	var cursor: int=maxi(0,int(movement.cursor))
	var reached_connector: bool=false
	for index: int in range(path.size()-2,cursor-1,-1):
		if float(tail.left)<=0.000001: break
		var segment: Dictionary=path[index]
		if segment.kind=="connector":
			reached_connector=true
			if int(segment.to)!=floor_id: break
			var connection: Dictionary=world.facts.connectors[segment.connector_id]
			var plan: Dictionary=ConvoyPortal.plan(space,world,connection,actor.id,movement.members,convoy)
			if not plan.get("ok",false): break
			var predicted: Dictionary=ConvoyPortal.predict(convoy,plan,floor_id)
			for i: int in range(predicted.points.size()-1,-1,-1): _bed_tail_append(tail,ConvoyTrail.point(predicted.points[i]))
			break
		if segment.kind!="floor" or int(segment.floor_id)!=floor_id: break
		_bed_tail_append(tail,ConvoyTrail.point(segment.cell))
	# begin() advances the issued route cursor before the actual ride. Its
	# in-flight canonical egress supplies the missing short terminal tail.
	if not reached_connector and float(tail.left)>0.000001 and convoy.has("portal"):
		var connection: Dictionary=world.facts.connectors.get(actor.location.get("connector_id",""),{})
		if not connection.is_empty() and int(connection.to)==floor_id:
			var predicted: Dictionary=ConvoyPortal.predict(convoy,convoy.portal.plan,floor_id)
			for i: int in range(predicted.points.size()-1,-1,-1): _bed_tail_append(tail,ConvoyTrail.point(predicted.points[i]))
	if not reached_connector and float(tail.left)>0.000001 and not convoy.has("portal") and actor.location.kind=="floor" and int(actor.location.floor_id)==floor_id:
		for index: int in range(convoy.points.size()-1,-1,-1):
			if float(tail.left)<=0.000001: break
			_bed_tail_append(tail,ConvoyTrail.point(convoy.points[index]))
	return ConvoyTrail.regions(convoy,tail.points)

func _bed_tail_append(tail: Dictionary, point: Vector2) -> void:
	if float(tail.left)<=0.000001: return
	var current: Vector2=ConvoyTrail.point(tail.points[-1])
	var distance: float=current.distance_to(point)
	if distance<=0.000001: return
	var used: float=minf(float(tail.left),distance)
	current=current.move_toward(point,used)
	tail.points.append([current.x,current.y])
	tail.left=float(tail.left)-used

func _bed_goal_blocker(world: WorldState, actor: Dictionary, movement: Dictionary) -> String:
	for region: Rect2 in _bed_goal_regions(world,actor,movement):
		var blocker: String=space.bed_destination_blocker(world,actor.id,int(movement.target_floor),region,movement.get("members",[actor.id]))
		if not blocker.is_empty(): return blocker
	return ""

# Local single-person targets are real temporary stops, including each
# corner installed before a rejoin. Test the actual approach facing while
# choosing them, so an unavailable post cannot hide the other legal side.
# Passage along the segments remains soft; only their stops hold use rights.
func _bed_local_path_blocker(world: WorldState, actor: Dictionary, movement: Dictionary, path: Array) -> String:
	var origin: Vector2=ConvoyTrail.point(actor.location.cell)
	var sample: Dictionary=actor.duplicate()
	for index: int in path.size():
		var segment: Dictionary=path[index]
		var target: Vector2=ConvoyTrail.point(segment.cell)
		if target==origin and index<path.size()-1: continue
		if target!=origin: sample.facing=atan2(target.x-origin.x,target.y-origin.y)
		var held: String=space.bed_destination_blocker(world,actor.id,int(segment.floor_id),space._actor_rect(sample,target),movement.get("members",[actor.id]))
		if not held.is_empty(): return held
		origin=target
	return ""

# A convoy's side/retreat stop owns its whole predicted tail, not just the
# leader. Reuse final-arrival geometry without replacing the real journey.
func _bed_path_stop_blocker(world: WorldState, actor: Dictionary, movement: Dictionary, path: Array) -> String:
	if path.is_empty(): return ""
	var stop: Dictionary=movement.duplicate()
	stop.path=path
	stop.cursor=0
	stop.target_floor=path[-1].floor_id
	stop.target_cell=path[-1].cell
	stop.erase("local_move")
	return _bed_goal_blocker(world,actor,stop)

func _move_step(world: WorldState, actor: Dictionary, movement: Dictionary, segment: Dictionary) -> MotionResult:
	if movement.has("convoy"): return _move_convoy(world,actor,movement,segment)
	var result: MotionResult = MotionResult.new()
	var target: Vector2 = Vector2(float(segment.cell[0]),float(segment.cell[1]))
	var start: Vector2 = Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))
	var speed: float = float(space.content.balance.movement_speeds[str(space.clearance(actor))])
	var members: Array = movement.get("members",[actor.id])
	var offsets: Dictionary = movement.get("offsets",{})
	if members.size()>1: speed = float(space.content.balance.movement_speeds["2"])
	var next: Vector2 = _step_toward(start,target,speed*WorldState.TICK_SECONDS)
	result.requested_motion = next-start
	if (movement.has("detour") or movement.has("local_move")) and members.size()==1 and segment.kind=="floor":
		var actual_clearance: RouteClearance=space.navigation.structural_clearance(world,actor,int(actor.location.floor_id))
		result.static_reason=actual_clearance.sweep_reason(start,next)
		if not result.static_reason.is_empty(): return result
	var initial_rect: Rect2 = space._actor_index.rectangle(actor.id) if members.size()==1 else space._unit_rect(world,actor,start,members,offsets)
	var sweeps: Array[BodyIndex.Record] = _unit_sweeps(world,actor,next,members,offsets,target-start)
	var swept: Rect2 = initial_rect
	for sweep: BodyIndex.Record in sweeps: swept = swept.merge(sweep.sweep_from).merge(sweep.sweep_to)
	var doors: Array[Dictionary] = space.movement_doors(world,actor,swept,members)
	if not _reserve_doors(world,actor,movement,swept,doors,result): return result
	_movement_contacts(world,actor.id,int(actor.location.floor_id),swept,sweeps,members,result)
	if result.blocked: return result
	# Commit the complete fixed step only after the one collision attempt.
	# A rejected step keeps every member, facing and support height unchanged.
	movement.blocked_since = -1
	movement.erase("waiting_reason")
	actor.location.cell = [next.x,next.y]
	result.actual_motion = next-start
	_mark_door_use(world,int(actor.location.floor_id),swept,doors)
	if segment.kind=="support_exit":
		actor.location.height_m = move_toward(float(actor.location.get("height_m",0)),0.0,speed*HospitalSpace.CELL_METERS*WorldState.TICK_SECONDS)
	actor.facing = atan2(target.x-start.x,target.y-start.y)
	for member_id: String in members:
		if member_id==actor.id: continue
		var offset: Array = offsets[member_id]
		world.facts.actors[member_id].location.cell = [next.x+float(offset[0]),next.y+float(offset[1])]
		world.facts.actors[member_id].facing = actor.facing
	for sweep: BodyIndex.Record in sweeps:
		_accepted_sweeps[sweep.id] = sweep
		_sweep_index.update(sweep.id,int(actor.location.floor_id),sweep.sweep_from.merge(sweep.sweep_to))
		space._actor_index.update(sweep.id,int(actor.location.floor_id),sweep.sweep_to)
		if space.public_areas!=null: space.public_areas.actor_changed(world,sweep.id,int(actor.location.floor_id),sweep.sweep_from,int(actor.location.floor_id),sweep.sweep_to)
	# Only the actual target earns a
	# reached checkpoint. Relative vector tolerance can advance a diagonal
	# stub while it is still farther away than the arrival tolerance.
	if next==target:
		if segment.kind=="support_exit":
			actor.posture = "standing"
			actor.location.height_m = 0.0
			actor.erase("support_facility_id")
			space._sync_actor(world,actor.id)
			movement.path = []
			movement.cursor = -1
			_queue_route(world,movement)
		movement.travelled.append({"kind":"floor","floor_id":actor.location.floor_id,"cell":segment.cell.duplicate()})
		if not movement.has("local_move"): movement.cursor += 1
	return result

func _ensure_route_queue(world: WorldState) -> void:
	if _pending_world!=null and _pending_world.get_ref()==world: return
	_pending_world = weakref(world)
	_pending_routes.clear()
	_ready_routes = PlatformRouteQueue.new()
	_delayed_routes = PlatformRouteQueue.new()
	for id: String in world.facts.moves:
		if world.facts.moves[id].get("route_pending",false): _schedule_route(world,world.facts.moves[id])
	space.query_counts.route_dispatch_restores += 1

func _schedule_route(world: WorldState, movement: Dictionary) -> void:
	_pending_routes[movement.actor_id] = int(movement.request_sequence)
	if int(movement.get("route_retry_tick",0))>world.sim_tick:
		_delayed_routes.push({"id":movement.actor_id,"tick":int(movement.route_retry_tick),"sequence":int(movement.request_sequence)})
	else:
		_ready_routes.push({"id":movement.actor_id,"tick":int(movement.request_sequence)})

func _queue_route(world: WorldState, movement: Dictionary) -> void:
	_ensure_route_queue(world)
	world.facts.move_request_next = int(world.facts.get("move_request_next",0))+1
	movement.request_sequence = world.facts.move_request_next
	movement.route_pending = true
	_schedule_route(world,movement)

func _checkpoint(actor: Dictionary) -> Dictionary:
	return {"kind":"floor","floor_id":int(actor.location.floor_id),"cell":actor.location.cell.duplicate()}

func _replan_goal(world: WorldState, movement: Dictionary, preserve_order: bool = false) -> void:
	HospitalTransit.cancel_waiting(world,movement)
	movement.erase("route_waypoint")
	movement.erase("detour")
	movement.erase("local_move")
	movement.erase("yielding")
	movement.erase("yield_partner")
	_route_checks.erase(movement.actor_id)
	if not preserve_order:
		_queue_route(world,movement)
	else:
		movement.route_pending=true
		_ensure_route_queue(world)
		_schedule_route(world,movement)

func _active_route_clear(world: WorldState, actor: Dictionary, movement: Dictionary, versions: Dictionary) -> bool:
	if movement.has("local_move"): return true
	if movement.has("detour") and not movement.has("convoy") and movement.get("members",[actor.id]).size()==1 and (movement.detour.phase!="rejoin" or int(movement.cursor)<int(movement.detour.prefix_size)): return true
	if movement.has("convoy"): return _active_convoy_route_clear(world,actor,movement)
	space.query_counts.route_checks += 1
	var sequence: int = int(movement.get("request_sequence",0))
	var record: Dictionary = _route_checks.get(actor.id,{})
	if record.is_empty() or int(record.sequence)!=sequence:
		var floors: Dictionary = {}
		var connections: Dictionary = {}
		for segment: Dictionary in movement.path.slice(int(movement.cursor)):
			if segment.kind=="connector": connections[segment.connector_id] = []
			else: floors[int(segment.floor_id)] = ""
		record = {"sequence":sequence,"floors":floors,"connections":connections,"bodies":{},"members":[],"offsets":{},"validated":false}
	var members: Array = movement.get("members",[actor.id])
	var offsets: Dictionary = movement.get("offsets",{})
	# Collision-index shapes are disposable when a read-only projection changes
	# its indexed world. A route instead owns the actual body facts it proved.
	var bodies: Dictionary = {actor.id:_route_body_basis(actor)}
	for id: String in members:
		if id!=actor.id: bodies[id] = _route_body_basis(world.facts.actors[id])
	var body_changed: bool = record.bodies!=bodies
	var formation_changed: bool = record.members!=members or record.offsets!=offsets
	var floor_changed: bool = false
	var connection_changed: bool = false
	for floor_id: int in record.floors:
		if not versions.has(floor_id): versions[floor_id] = space._navigation.floor_static_version(space,world,floor_id)
		if record.floors[floor_id]!=versions[floor_id]: floor_changed = true
	if not versions.has("connections"): versions.connections = {}
	for id: String in record.connections:
		if not versions.connections.has(id):
			var connection: Dictionary = world.facts.connectors.get(id,{})
			if connection.is_empty(): return false
			versions.connections[id] = [connection.definition_id,HospitalTransit.endpoints(connection).duplicate(),connection.anchor.duplicate(),connection.get("failed",false),connection.get("pending_failure",false)]
		if record.connections[id]!=versions.connections[id]: connection_changed = true
	if record.validated and not body_changed and not formation_changed and not floor_changed and not connection_changed: return true
	space.query_counts.route_revalidations += 1
	# Reasons count checks which actually revalidate. An unproved route counts
	# only as unvalidated; an existing proof can have several changed reasons.
	var reasons: Array[String] = []
	if not record.validated: reasons.append("unvalidated")
	else:
		if body_changed: reasons.append("body")
		if formation_changed: reasons.append("formation")
		if floor_changed: reasons.append("floor")
		if connection_changed: reasons.append("connection")
	for reason: String in reasons:
		var key: String = "route_revalidation_"+reason
		space.query_counts[key] = int(space.query_counts.get(key,0))+1
	var floor_id: int = int(actor.location.floor_id)
	var current: Vector2 = Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))
	var queries: Dictionary = {}
	for segment: Dictionary in movement.path.slice(int(movement.cursor)):
		if segment.kind=="support_exit":
			# Leaving a support begins inside that owned support. Exclude only
			# its solid footprint; walls, edits and every other obstacle remain.
			var source: Dictionary = space._navigation.floor_source(space,world,floor_id).duplicate()
			source.facilities = source.facilities.duplicate()
			source.facilities.erase(actor.get("support_facility_id",""))
			var departure: RouteClearance = RouteClearance.new(space,world,actor,floor_id,members,offsets,false,source)
			var exit: Vector2 = Vector2(float(segment.cell[0]),float(segment.cell[1]))
			if not departure.sweep_reason(current,exit).is_empty(): return false
			current = exit
			continue
		if segment.kind=="connector":
			var connection: Dictionary = world.facts.connectors.get(segment.connector_id,{})
			if connection.is_empty() or int(segment.from)!=floor_id or not HospitalTransit.has_stop(connection,int(segment.from)) or not HospitalTransit.has_stop(connection,int(segment.to)) or not HospitalTransit.fits(space,world,connection,actor.id,members).ok or (HospitalTransit._lowering(connection) and int(segment.to)>=int(segment.from)):
				return false
			floor_id = int(segment.to)
			current = Vector2(float(connection.anchor[0]),float(connection.anchor[1]))
			continue
		if int(segment.floor_id)!=floor_id:
			return false
		var target: Vector2 = Vector2(float(segment.cell[0]),float(segment.cell[1]))
		if not queries.has(floor_id):
			queries[floor_id] = space.navigation.structural_clearance(world,actor,floor_id,members,offsets)
		if not (queries[floor_id] as RouteClearance).sweep_reason(current,target).is_empty():
			return false
		current = target
	record.validated = true
	record.members = members.duplicate()
	record.offsets = offsets.duplicate(true)
	record.bodies = bodies
	for id: int in record.floors: record.floors[id] = versions[id]
	for id: String in record.connections: record.connections[id] = versions.connections[id]
	_route_checks[actor.id] = record
	return true

func _route_body_basis(actor: Dictionary) -> Array:
	# RouteClearance uses integer width/depth clearance and posture-dependent
	# height; doors and connector fits also use the full standing dimensions.
	# Facing belongs to the exact collision sweep performed during movement.
	return space.navigation.route_body_basis(actor)

# Invocation-local original-route iterator. No dynamic failure survives a tick.
func _next_rejoin_candidate(actor: Dictionary, movement: Dictionary) -> Dictionary:
	var search: Dictionary=movement.search
	var index: int=int(search.index)
	if index>=movement.path.size():return {}
	var segment: Dictionary=movement.path[index]
	if segment.kind!="floor" or int(segment.floor_id)!=int(actor.location.floor_id):return {}
	var previous: Vector2=ConvoyTrail.point(search.previous)
	var end: Vector2=ConvoyTrail.point(segment.cell)
	var delta: Vector2=end-previous
	if delta.x!=0.0 and delta.y!=0.0:
		# Exact fractional start/end stubs are original route endpoints, not
		# cardinal compressed segments. Do not invent intermediate cells.
		search.previous=segment.cell.duplicate();search.index=index+1
		return {"cell":segment.cell.duplicate(),"resume":index+1}
	var direction: Vector2=delta.sign()
	var coordinate: float=previous.x if direction.x!=0.0 else previous.y
	var limit: float=end.x if direction.x!=0.0 else end.y
	var sign_step: float=direction.x if direction.x!=0.0 else direction.y
	var next_coordinate: float=floorf(coordinate)+1.0 if sign_step>0.0 else ceilf(coordinate)-1.0
	var point: Vector2=end
	if sign_step!=0.0 and (limit-next_coordinate)*sign_step>0.0:
		point=Vector2(next_coordinate,previous.y) if direction.x!=0.0 else Vector2(previous.x,next_coordinate)
	search.previous=[point.x,point.y]
	if point==end:search.index=index+1
	return {"cell":[point.x,point.y],"resume":index+1 if point==end else index}

func _dispatch_routes(world: WorldState, present_at_start: int) -> void:
	_ensure_route_queue(world)
	while _delayed_routes.size()>0:
		var due: Dictionary = _delayed_routes.pop()
		if int(due.tick)>world.sim_tick:
			_delayed_routes.push(due)
			break
		if not _pending_routes.has(due.id) or int(_pending_routes[due.id])!=int(due.sequence): continue
		if not world.facts.moves.has(due.id):
			_pending_routes.erase(due.id)
			continue
		var movement: Dictionary = world.facts.moves[due.id]
		if not movement.get("route_pending",false):
			_pending_routes.erase(due.id)
			continue
		if int(movement.get("route_retry_tick",0))<=world.sim_tick:
			_ready_routes.push({"id":due.id,"tick":int(movement.request_sequence)})
	var budget: int = maxi(int(space.content.balance.pathfinding.minimum_actor_requests_per_tick),ceili(float(present_at_start)/float(space.content.balance.pathfinding.actors_per_request)))
	var dispatched: int = 0
	while dispatched<budget and _ready_routes.size()>0:
		space.query_counts.route_dispatch_scans += 1
		var item: Dictionary = _ready_routes.pop()
		var id: String = str(item.id)
		if not _pending_routes.has(id): continue
		if not world.facts.moves.has(id):
			_pending_routes.erase(id)
			continue
		var movement: Dictionary = world.facts.moves[id]
		if not movement.get("route_pending",false):
			_pending_routes.erase(id)
			continue
		if int(item.tick)!=int(movement.get("request_sequence",-1)): continue
		if int(movement.get("route_retry_tick",0))>world.sim_tick: continue
		dispatched += 1
		space.query_counts["route_dispatches"] = int(space.query_counts.get("route_dispatches",0))+1
		_pending_routes.erase(id)
		var waypoint: Dictionary = movement.get("route_waypoint",{})
		var floor_id: int = int(movement.target_floor) if waypoint.is_empty() else int(waypoint.floor_id)
		var cell: Array = movement.target_cell if waypoint.is_empty() else waypoint.cell
		var quote: Dictionary={}
		if waypoint.is_empty():quote=preload("res://game/operations/guidance_queue_routes.gd").quote(space,world,movement,floor_id,cell)
		if not quote.is_empty():pass
		elif not waypoint.is_empty() and movement.has("convoy"):
			quote = space.navigation.convoy_local_route(world,movement,floor_id,cell)
		elif waypoint.is_empty() and not movement.get("floor_only",false):
			quote = space.route(world,id,floor_id,cell,movement.get("members",[]),movement.get("offsets",{}))
		else:
			var actor: Dictionary = world.facts.actors[id]
			quote = space.navigation.exact_floor_route(world,actor,floor_id,cell,movement.get("members",[]),movement.get("offsets",{}))
		if not quote.ok:
			if quote.get("status","")=="unsupported":
				movement.route_capability_error=quote.reason
				push_error(quote.reason)
				continue
			movement.waiting_reason = quote.reason
			movement.route_retry_tick = world.sim_tick+int(space.content.balance.movement_courtesy.retry_hard_block_seconds)*10
			_schedule_route(world,movement)
			if quote.get("status","")=="unreachable": _remember_failure(world,movement,str(quote.reason))
			else: _route_failures.erase(id)
			continue
		movement.path = quote.path
		if not waypoint.is_empty():
			movement.path.append_array(waypoint.continuation)
			movement.erase("route_waypoint")
		movement.cursor = 0
		if waypoint.is_empty(): _accept_static_proof(world,world.facts.actors[id],movement,quote.get("static_proof",{}))
		movement.route_pending = false
		movement.erase("live_floor_route")
		movement.erase("rejoin_origin")
		movement.erase("route_capability_error")
		movement.erase("route_retry_tick")
		movement.erase("waiting_reason")
		_route_failures.erase(id)

# Consume only a planner-owned exact single-floor proof. No proof is serialized
# with movement facts; cold restore and every other route keep full validation.
func _accept_static_proof(world: WorldState, actor: Dictionary, movement: Dictionary, proof: Dictionary) -> bool:
	if proof.is_empty() or proof.world.get_ref()!=world or movement.has("convoy") or movement.has("detour"): return false
	var members: Array = movement.get("members",[actor.id])
	var offsets: Dictionary = movement.get("offsets",{})
	if members!=[actor.id] or not offsets.is_empty() or actor.location.kind!="floor" or int(actor.location.floor_id)!=int(proof.floor): return false
	if int(movement.target_floor)!=int(proof.floor) or movement.target_cell!=proof.target: return false
	if proof.origin!=Vector2(float(actor.location.cell[0]),float(actor.location.cell[1])) or proof.path!=movement.path or proof.body!=_route_body_basis(actor): return false
	if proof.version!=space._navigation.floor_static_version(space,world,int(proof.floor)): return false
	_route_checks[actor.id] = {"sequence":int(movement.get("request_sequence",0)),"floors":{int(proof.floor):proof.version},"connections":{},"bodies":{actor.id:proof.body.duplicate()},"members":members.duplicate(),"offsets":{},"validated":true}
	space.query_counts["route_proof_handoffs"] = int(space.query_counts.get("route_proof_handoffs",0))+1
	return true

func _initial_route_cursor(actor: Dictionary, path: Array, world: WorldState = null) -> int:
	if path.size()<2 or path[0].kind!="floor" or path[1].kind!="floor" or int(path[0].floor_id)!=int(actor.location.floor_id) or int(path[1].floor_id)!=int(actor.location.floor_id):
		return 0
	var actual: Vector2 = Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))
	var first: Vector2 = Vector2(float(path[0].cell[0]),float(path[0].cell[1]))
	var next: Vector2 = Vector2(float(path[1].cell[0]),float(path[1].cell[1]))
	# A retreat can begin between these cells. Returning to the rounded start
	# would move toward the body being yielded to before moving away from it.
	# Near-collinear starts retain forward travel, but a point still on the
	# perpendicular incoming leg has zero forward projection. A triangle
	# tolerance alone must not skip that unfinished corner or either endpoint.
	var dx: float = float(next.x)-float(first.x)
	var dy: float = float(next.y)-float(first.y)
	var projection: float = (float(actual.x)-float(first.x))*dx+(float(actual.y)-float(first.y))*dy
	if actual!=first and projection>0.0 and projection<=dx*dx+dy*dy and absf(actual.distance_to(first)+actual.distance_to(next)-first.distance_to(next))<0.001:
		# An off-line shortcut is not the proved route segment. Preserve the
		# established near-collinear start only when its entire remaining segment is
		# structurally clear. Exact collinear starts need no additional query.
		var cross: float = (float(actual.x)-float(first.x))*dy-(float(actual.y)-float(first.y))*dx
		if cross!=0.0:
			if world==null: return 0
			var movement: Dictionary = world.facts.moves.get(actor.id,{})
			var proxy: Dictionary = ConvoyTrail.proxy(world,movement) if movement.has("convoy") else actor
			var shift: Vector2 = Vector2.ONE*float(movement.convoy.shift) if movement.has("convoy") else Vector2.ZERO
			var query: RouteClearance = space.navigation.structural_clearance(world,proxy,int(actor.location.floor_id))
			if not query.sweep_reason(actual+shift,next+shift).is_empty(): return 0
		return 1
	return 0

func queue_waypoint(world: WorldState, movement: Dictionary, floor_id: int, cell: Array) -> void:
	var remaining: Array = movement.path.slice(int(movement.cursor))
	movement.route_waypoint = {"floor_id":floor_id,"cell":cell.duplicate(),"continuation":remaining}
	_queue_route(world,movement)

# Only an obstacle actually encountered by this movement triggers a local
# detour. Future landings and queues do not enter this floor query.
func _queue_local_route(world: WorldState, actor: Dictionary, movement: Dictionary) -> void:
	_start_detour(world,actor,movement)

func _local_goal_occupied(world: WorldState, actor: Dictionary, movement: Dictionary, contact: MotionResult) -> bool:
	if contact.blocker_actor_ids.is_empty(): return false
	var end: int = int(movement.cursor)
	if end<0 or end>=movement.path.size(): return false
	var floor_id: int = int(actor.location.floor_id)
	while end+1<movement.path.size() and movement.path[end+1].kind=="floor" and int(movement.path[end+1].floor_id)==floor_id:
		end += 1
	var target: Dictionary = movement.path[end]
	if target.kind!="floor" or int(target.floor_id)!=floor_id: return false
	var origin: Vector2 = Vector2(float(target.cell[0]),float(target.cell[1]))
	if movement.has("convoy"):
		# The leader's fixed proxy is required at the destination on every
		# approach. Followers have path-derived positions, not fixed offsets.
		var rectangle: Rect2 = Rect2(origin+Vector2.ONE*float(movement.convoy.shift),Vector2.ONE*int(movement.convoy.size))
		if space._actor_index.intersects(floor_id,rectangle,actor.id,movement.members):
			space.query_counts["local_goal_occupied_waits"] = int(space.query_counts.get("local_goal_occupied_waits",0))+1
			return true
		return false
	var members: Array = [actor.id]
	for id: String in movement.get("members",[]):
		if id!=actor.id: members.append(id)
	var unavoidable: Array[Rect2] = []
	for id: String in members:
		var member: Dictionary = world.facts.actors[id]
		if member.get("posture","standing")=="lying": continue
		var dimensions: Dictionary = space.body(member)
		var width: Variant = dimensions.get("width_m")
		var depth: Variant = dimensions.get("depth_m")
		if not (width is float or width is int) or not (depth is float or depth is int): continue
		if not is_finite(float(width)) or not is_finite(float(depth)) or float(width)<=0.0 or float(depth)<=0.0: continue
		var side: float = minf(float(width),float(depth))/HospitalSpace.CELL_METERS
		var offset: Array = movement.get("offsets",{}).get(id,[0,0])
		var center: Vector2 = space._actor_rect(member,origin+Vector2(float(offset[0]),float(offset[1]))).get_center()
		unavoidable.append(Rect2(center-Vector2.ONE*side*0.5,Vector2.ONE*side))
	# Every upright facing's collision AABB contains this centered square.
	# Current-facing corners alone do not prove an alternative approach blocked.
	# An actual collision triggered this decision. A different current body
	# may occupy the destination; every detour would still meet it there.
	# The current body index excludes past sweeps and member-to-member gaps.
	for rectangle: Rect2 in unavoidable:
		if not space._actor_index.intersects(floor_id,rectangle,actor.id,members): continue
		space.query_counts["local_goal_occupied_waits"] = int(space.query_counts.get("local_goal_occupied_waits",0))+1
		return true
	return false

func _unit_sweeps(world: WorldState, actor: Dictionary, next: Vector2, members: Array, offsets: Dictionary, direction: Vector2) -> Array[BodyIndex.Record]:
	var result: Array[BodyIndex.Record] = []
	for id: String in members:
		var member: Dictionary = world.facts.actors[id]
		var offset: Array = offsets.get(id,[0,0])
		var sweep: BodyIndex.Record = space._actor_index.record(id)
		var from: Rect2 = sweep.rect
		var position: Vector2 = next+Vector2(float(offset[0]),float(offset[1]))
		var facing: float = atan2(direction.x,direction.y)
		var to: Rect2
		if facing==float(member.facing):
			# Derive the destination from the actual position and cached shape.
			# Repeatedly translating the old float32 rectangle drifts away from
			# the actor's body and can miss an exact edge-crossing collision.
			to = space._actor_rect(member,position)
		else:
			var sample: Dictionary = member.duplicate()
			sample.facing = facing
			to = space._actor_rect(sample,position)
		sweep.sweep_from = from
		sweep.sweep_to = to
		result.append(sweep)
	return result

func _movement_contacts(world: WorldState, actor_id: String, floor_id: int, broad: Rect2, sweeps: Array[BodyIndex.Record], members: Array, result: MotionResult, queries: Dictionary = {}) -> void:
	# Installing the first region prepares the index for this frozen search.
	if not queries.has("last"): space._ensure_actor_index(world)
	var cached: Dictionary = _return_contact_region(world,actor_id,floor_id,broad,members,queries) if queries.has("regions") else {}
	if not cached.is_empty() and cached.actors.is_empty() and cached.accepted.is_empty() and cached.reservations.is_empty():
		result.reservation_ids.sort()
		return
	var candidates: Dictionary = {}
	var reservations: Array = []
	if cached.is_empty():
		for id: String in space._actor_index.candidates(floor_id,broad,members): candidates[id] = true
		for id: String in _sweep_index.candidates(floor_id,broad,members): candidates[id] = true
		reservations = space._reservation_regions(world,floor_id,broad)
	else:
		# The enclosing box only supplies complete candidates. Reapply the
		# original strict overlap before the original exact sweep predicates.
		for id: String in cached.actors:
			if space._actor_index._overlap(space._actor_index._records[id],broad): candidates[id] = true
		for id: String in cached.accepted:
			if _sweep_index._overlap(_sweep_index._records[id],broad): candidates[id] = true
		for region: Dictionary in cached.reservations:
			if broad.intersects(region.rect,false): reservations.append(region)
	var ids: Array = candidates.keys()
	ids.sort()
	space.query_counts.movement_candidates += ids.size()
	# The cached region is complete before narrow-phase first-hit exits.
	# Ordinary movement still retains all contacts; actor IDs confer no priority.
	for id: String in ids:
		var other: BodyIndex.Record = _accepted_sweeps.get(id)
		var current: BodyIndex.Record = space._actor_index._records.get(id)
		var other_from: Rect2 = current.rect if other==null else other.sweep_from
		var other_to: Rect2 = other_from if other==null else other.sweep_to
		var compound: Array[Rect2] = []
		if other!=null and not other.regions.is_empty():
			compound = other.regions
		elif current!=null:
			compound = current.regions
		for sweep: BodyIndex.Record in sweeps:
			var hit: bool = false
			if compound.is_empty(): hit = BodySweep.intersects(sweep.sweep_from,sweep.sweep_to,other_from,other_to)
			else:
				for region: Rect2 in compound:
					if BodySweep.intersects(sweep.sweep_from,sweep.sweep_to,region,region): hit = true;break
			if hit:
				result.blocker_actor_ids.append(id)
				if result.first_contact_only: return
				break
	for region: Dictionary in reservations:
		if not bool(region.blocks_passage): continue
		var reservation: Dictionary = region.reservation
		if int(reservation.floor_id)!=floor_id or RouteClearance.reservation_allows(reservation,actor_id,members) or str(region.reservation_id) in result.reservation_ids:
			continue
		for sweep: BodyIndex.Record in sweeps:
			if BodySweep.intersects(sweep.sweep_from,sweep.sweep_to,region.rect,region.rect):
				result.reservation_ids.append(str(region.reservation_id))
				if result.first_contact_only: return
				break
	result.reservation_ids.sort()

# The return-search owner creates this memo before any trial and discards it
# before a real move or reservation change. Floor, members, bodies and accepted
# sweeps stay fixed in that synchronous search. Region size affects reuse only.
func _return_contact_region(world: WorldState, actor_id: String, floor_id: int, broad: Rect2, members: Array, queries: Dictionary) -> Dictionary:
	if queries.has("last") and (queries.last.bounds as Rect2).encloses(broad): return queries.last
	var low: Vector2 = (broad.position/RETURN_CONTACT_REGION_CELLS).floor()*RETURN_CONTACT_REGION_CELLS
	var high: Vector2 = (broad.end/RETURN_CONTACT_REGION_CELLS).ceil()*RETURN_CONTACT_REGION_CELLS
	var region: Rect2 = Rect2(low,high-low)
	if not region.encloses(broad): return {}
	if not queries.regions.has(region):
		# Bound memo entries only; never truncate candidates or the legal search.
		if queries.regions.size() >= MAX_RETURN_CONTACT_REGIONS: return {}
		var reservations: Array = []
		for entry: Dictionary in space._reservation_regions(world,floor_id,region):
			if bool(entry.blocks_passage) and int(entry.reservation.floor_id)==floor_id and not RouteClearance.reservation_allows(entry.reservation,actor_id,members): reservations.append(entry)
		queries.regions[region] = {"bounds":region,"actors":space._actor_index.candidates(floor_id,region,members),"accepted":_sweep_index.candidates(floor_id,region,members),"reservations":reservations}
		space.query_counts["return_contact_regions_built"] = int(space.query_counts.get("return_contact_regions_built",0))+1
	queries.last = queries.regions[region]
	return queries.last

func _reserve_doors(world: WorldState, actor: Dictionary, movement: Dictionary, swept: Rect2, doors: Array[Dictionary], result: MotionResult) -> bool:
	var floor_id: int = int(actor.location.floor_id)
	var staged: Dictionary = {}
	var members: Array = movement.get("members",[actor.id])
	for door: Dictionary in doors:
		var span: int = space._door_span(actor,door)
		if not swept.intersects(space._door_rect(door,span),false): continue
		var quote: Dictionary = space.door_passage_quote(world,actor,floor_id,door)
		if not quote.ok:
			result.door_id = str(door.id)
			return false
		var current: Dictionary = world.facts.adaptations.get(door.id,{})
		if not current.is_empty():
			if not RouteClearance.reservation_allows(current,actor.id,members) or int(quote.span)>int(current.span) or float(quote.clear_height_m)>float(current.clear_height_m) or float(quote.clear_width_m)>float(current.clear_width_m):
				result.door_id = str(door.id)
				result.reservation_ids.append(str(door.id))
				return false
			# The held opening already belongs to these participants. Actual
			# sweep contacts prove this step; do not reacquire the whole doorway
			# against another retained participant or replace the old obligation.
			continue
		# An unchanged opening is ordinary walkable geometry, not a single-person
		# ticket. Actual swept-body contacts still decide this step. Existing
		# obligations above and genuine enlarged/group openings remain exclusive.
		var definition: Dictionary = space.content.definition("doors",door.definition_id)
		if members.size()==1 and not movement.has("convoy") and int(quote.span)==int(door.span) and float(quote.clear_height_m)<=float(definition.clear_height_m) and float(quote.clear_width_m)<=float(definition.clear_width_m):
			continue
		var rect: Rect2 = space._door_rect(door,int(quote.span))
		if not space._dynamic_clear(world,actor.id,floor_id,rect,members,false,true):
			result.door_id = str(door.id)
			return false
		var reservation: Dictionary = {"kind":"door","owner_id":actor.id,"actor_id":actor.id,"staff_ids":members,"floor_id":floor_id,"span":quote.span,"clear_height_m":quote.clear_height_m,"clear_width_m":quote.clear_width_m,"regions":[[rect.position.x,rect.position.y,rect.size.x,rect.size.y]]}
		if movement.has("convoy"): reservation.convoy_envelope = {"size":movement.convoy.size,"height":movement.convoy.height}
		staged[door.id] = reservation
	for id: String in staged:
		if world.facts.adaptations.get(id,{})!=staged[id]:
			world.facts.adaptations[id] = staged[id]
			space.reservation_changed(world,id)
	return true

func _mark_door_use(world: WorldState, floor_id: int, swept: Rect2, doors: Array[Dictionary]) -> void:
	for door: Dictionary in doors:
		var current: Dictionary = world.facts.adaptations.get(door.id,{})
		if swept.intersects(space._door_rect(door,int(current.get("span",door.span))),false):
			door.used = true

func _movement_owners(world: WorldState, blocker_actor_ids: Array[String]) -> Array:
	if blocker_actor_ids.is_empty(): return []
	if _phase_owners.is_empty():
		for primary: String in world.facts.moves:
			for id: String in world.facts.moves[primary].get("members",[primary]): _phase_owners[id] = primary
	var found: Dictionary = {}
	for id: String in blocker_actor_ids:
		# A group can finish and its former member start an individual journey
		# later in this same phase. Prefer that current owner over the old map.
		var owner: String = id if world.facts.moves.has(id) else str(_phase_owners.get(id,id))
		if world.facts.moves.has(owner) and id in world.facts.moves[owner].get("members",[owner]): found[owner] = true
	var result: Array = found.keys()
	result.sort()
	return result

# Traffic changes only the short local prefix. The approved route and its
# request order remain intact, and no actor gains a right of way.
func _yield(world: WorldState, actor: Dictionary, movement: Dictionary, result: MotionResult) -> void:
	if movement.has("detour"): return
	var owners: Array = _movement_owners(world,result.blocker_actor_ids)
	# A stationary occupied destination waits. Two active journeys may need
	# to pass even when each destination is the other's present position.
	if _local_goal_occupied(world,actor,movement,result) and owners.is_empty(): return
	for owner: String in owners:
		# One actually obstructed actor is already making room. The other
		# still attempts its own real step every tick, without an endpoint lock.
		if owner!=actor.id and world.facts.moves[owner].has("detour"):
			var other: Dictionary = world.facts.moves[owner]
			# Do not start a second passing manoeuvre while the first is
			# actually under way. A finished local prefix which cannot return
			# is a new obstruction, not a permanent right to block everyone.
			if int(other.cursor)<int(other.detour.prefix_size):
				var other_actor: Dictionary = world.facts.actors[owner]
				var point: Dictionary = other.path[int(other.cursor)]
				if point.kind=="floor" and other_actor.location.kind=="floor" and int(point.floor_id)==int(other_actor.location.floor_id):
					var origin: Vector2 = ConvoyTrail.point(other_actor.location.cell)
					var next: Vector2 = _step_toward(origin,ConvoyTrail.point(point.cell),space.walking_speed(other_actor)*WorldState.TICK_SECONDS)
					# An intention blocked by a third body is not a passage right.
					# Keep one-sided avoidance while its actual next step is clear.
					if _detour_path_clear(world,other_actor,other,[_floor_point(other_actor,next)]): return
	_start_detour(world,actor,movement)

# This is a current local occupancy probe, not a future journey permission.
# One fixed leader envelope covers at most one body width of the new leg.
# Every actual 0.1-second step still performs the normal exact front sweep.
func _convoy_turn_contact(world: WorldState, actor: Dictionary, movement: Dictionary, segment: Dictionary) -> MotionResult:
	if not movement.has("convoy") or movement.members.size()<2 or movement.convoy.points.size()<2: return null
	var points: Array = movement.convoy.points
	var start: Vector2 = ConvoyTrail.point(actor.location.cell)
	var delta: Vector2 = ConvoyTrail.point(segment.cell)-start
	var incoming: Vector2 = start-ConvoyTrail.point(points[-2])
	if delta.length()<0.001 or absf(incoming.normalized().dot(delta.normalized()))>0.001: return null
	var end: Vector2 = start.move_toward(ConvoyTrail.point(segment.cell),float(movement.convoy.size))
	var shift: Vector2 = Vector2.ONE*float(movement.convoy.shift)
	var sweep: BodyIndex.Record = BodyIndex.Record.new()
	sweep.id = actor.id
	sweep.sweep_from = Rect2(start+shift,Vector2.ONE*int(movement.convoy.size))
	sweep.sweep_to = Rect2(end+shift,Vector2.ONE*int(movement.convoy.size))
	var sweeps: Array[BodyIndex.Record] = [sweep]
	var result: MotionResult = MotionResult.new()
	_movement_contacts(world,actor.id,int(actor.location.floor_id),sweep.sweep_from.merge(sweep.sweep_to),sweeps,movement.members,result)
	# Operation/door reservations keep their ordinary exact-step handling;
	# this corner probe only avoids entering a currently occupied body turn.
	result.reservation_ids.clear()
	space.query_counts["convoy_turn_probes"] = int(space.query_counts.get("convoy_turn_probes",0))+1
	return result

# Only the continuous trail since the last actual floor arrival is a local
# retreat. An earlier visit to the same floor across transit is not adjacent.
func _local_travelled(movement: Dictionary, floor_id: int) -> Array:
	var result: Array=[]
	for index: int in range(movement.travelled.size()-1,-1,-1):
		var past: Dictionary=movement.travelled[index]
		if int(past.floor_id)!=floor_id: break
		result.append(past.duplicate(true))
	result.reverse()
	return result

# Single-person movement owns one original route and one local target.
# Temporary moves never replace its route or advance its route cursor.
# Current geometry/occupancy of a proposed single-person local path, not a
# reservation or a prediction of future actors. Actual movement rechecks it.
# Each straight leg has one real first-step facing change, then one constant
# facing sweep for the rest; no quarter-cell simulation or copied history.
func _local_path_clear(world: WorldState, actor: Dictionary, path: Array, query: RouteClearance = null) -> bool:
	if query==null: query=space.navigation.structural_clearance(world,actor,int(actor.location.floor_id))
	var origin: Vector2=ConvoyTrail.point(actor.location.cell)
	var sample: Dictionary=actor.duplicate()
	var previous: Rect2=space._actor_rect(actor,origin)
	for point: Dictionary in path:
		var target: Vector2=ConvoyTrail.point(point.cell)
		if origin==target: continue
		if origin.x!=target.x and origin.y!=target.y: return false
		if not query.sweep_reason(origin,target).is_empty(): return false
		sample.facing=atan2(target.x-origin.x,target.y-origin.y)
		var first: Vector2=_step_toward(origin,target,space.walking_speed(actor)*WorldState.TICK_SECONDS)
		for next: Vector2 in [first,target]:
			if next==origin: continue
			var sweep: BodyIndex.Record=BodyIndex.Record.new()
			sweep.id=actor.id;sweep.sweep_from=previous;sweep.sweep_to=space._actor_rect(sample,next)
			var sweeps: Array[BodyIndex.Record]=[sweep]
			var contact: MotionResult=MotionResult.new()
			_movement_contacts(world,actor.id,int(actor.location.floor_id),previous.merge(sweep.sweep_to),sweeps,[actor.id],contact)
			if contact.blocked: return false
			origin=next;previous=sweep.sweep_to
	return true

# Local motion owns only a current same-floor walking segment. Transit,
# support departure, pending routes and exhausted paths retain their owner.
func _local_floor_segment(actor: Dictionary, movement: Dictionary) -> bool:
	if actor.get("location",{}).get("kind")!="floor" or movement.get("route_pending",false): return false
	var cursor: int=int(movement.get("cursor",-1))
	var path: Array=movement.get("path",[])
	if cursor<0 or cursor>=path.size(): return false
	var point: Dictionary=path[cursor]
	return point.get("kind")=="floor" and point.get("floor_id")==actor.location.floor_id

func _local_movable(world:WorldState,actor:Dictionary,journey:Dictionary)->bool:
	if not _local_floor_segment(actor,journey) or journey.has("convoy") or journey.get("members",[actor.id]).size()!=1 or actor.get("posture")!="standing": return false
	# A real optional trip already owns this ground walk. Its life task is
	# not a stationary working body; local avoidance keeps that same trip.
	var life: Dictionary=world.facts.staff.get(actor.id,{}).get("life_task",{})
	if not str(life.get("id","")).is_empty() and journey.get("waiting_seat_id","")==life.id and life.get("phase","") in ["area_travel","local_travel","returning","release","exiting"]:
		var job: Dictionary=world.facts.get("training_jobs",{}).get(world.facts.staff[actor.id].get("training_job_id",""),{})
		return not HospitalClinicalDevelopment.safe_busy(world,actor.id) and not job.get("state","") in ["travelling","working"]
	return not (world.facts.staff.has(actor.id) and _staff_has_movement_responsibility(world,actor.id))

func _local_choose(world: WorldState, actor: Dictionary, movement: Dictionary, motion: Vector2) -> bool:
	return _local_choose_options(world,actor,movement,motion,[])

func _local_choose_options(world: WorldState, actor: Dictionary, movement: Dictionary, motion: Vector2, fixed: Array) -> bool:
	if motion.length()<0.001 or not _local_floor_segment(actor,movement): return false
	var forward: Vector2 = Vector2(signf(motion.x),0) if absf(motion.x)>=absf(motion.y) else Vector2(0,signf(motion.y))
	var side: Vector2 = Vector2(-forward.y,forward.x)
	var origin: Vector2 = ConvoyTrail.point(actor.location.cell)
	for direction: Vector2 in [side,-side,-forward]:
		var target: Vector2 = origin+direction*space.clearance(actor)
		if direction==-forward:
			# With no reached checkpoint behind us, aim at the adjacent grid
			# cell, not a new fractional grid rooted at the collision position.
			var span: int=space.clearance(actor)
			if direction.x>0.0: target.x=floorf(origin.x)+span
			elif direction.x<0.0: target.x=ceilf(origin.x)-span
			elif direction.y>0.0: target.y=floorf(origin.y)+span
			else: target.y=ceilf(origin.y)-span
			for index: int in range(movement.travelled.size()-1,-1,-1):
				var visited: Dictionary = movement.travelled[index]
				if visited.kind!="floor" or int(visited.floor_id)!=int(actor.location.floor_id): break
				var past: Vector2 = ConvoyTrail.point(visited.cell)
				var delta: Vector2 = past-origin
				if delta.dot(direction)>0.001 and absf(delta.cross(direction))<0.00001:
					# A near-collinear binary32 checkpoint supplies retreat distance,
					# not a lateral snap. Keep the current real axis exactly.
					target=Vector2(past.x,origin.y) if direction.x!=0.0 else Vector2(origin.x,past.y)
					break
		var path: Array = [_floor_point(actor,target)]
		if not _bed_local_path_blocker(world,actor,movement,path).is_empty(): continue
		if direction==-forward:
			if not _retreat_intention_clear(world,actor,movement,path): continue
		elif not _local_path_clear(world,actor,path): continue
		elif not fixed.is_empty() and not _local_side_exit(world,actor,movement,target,fixed): continue
		var rect: Rect2 = space._actor_rect(actor,target)
		var in_door: bool = false
		for door: Dictionary in space.movement_doors(world,actor,rect,[]):
			if rect.intersects(space._door_rect(door,space._door_span(actor,door)),false): in_door=true;break
		if in_door: continue
		var route_origin: Array = movement.get("local_move",{}).get("origin",actor.location.cell).duplicate()
		var rejoin: Dictionary = movement.get("local_move",{}).get("rejoin",{})
		movement.local_move={"target":path[0],"origin":route_origin}
		if not rejoin.is_empty(): movement.local_move.rejoin=rejoin
		if direction==-forward: movement.local_move.retreat=true
		return true
	return false

func _local_goal_contact_wait(world: WorldState, actor: Dictionary, movement: Dictionary, contact: MotionResult) -> bool:
	if actor.get("posture","standing")=="lying" or int(movement.target_floor)!=int(actor.location.floor_id): return false
	# Every upright arrival facing contains this square. Check only bodies
	# actually touched now, never the future connector or a moving journey.
	var dimensions: Dictionary=space.body(actor)
	var side: float=minf(float(dimensions.width_m),float(dimensions.depth_m))/HospitalSpace.CELL_METERS
	var target: Vector2=ConvoyTrail.point(movement.target_cell)
	var center: Vector2=space._actor_rect(actor,target).get_center()
	var unavoidable:=Rect2(center-Vector2.ONE*side*0.5,Vector2.ONE*side)
	for id: String in contact.blocker_actor_ids:
		if world.facts.moves.has(id) or not _member_owner(world,id).is_empty(): continue
		if unavoidable.intersects(space._actor_index.rectangle(id),false):
			movement.waiting_reason="等待实际占用目的地的身体离开"
			space.query_counts["local_goal_contact_waits"]=int(space.query_counts.get("local_goal_contact_waits",0))+1
			return true
	return false

func _local_collision(world: WorldState, actor: Dictionary, movement: Dictionary, contact: MotionResult) -> void:
	if not contact.static_reason.is_empty():
		_replan_goal(world,movement,true)
		return
	if _local_goal_contact_wait(world,actor,movement,contact): return
	# While the contacted body's actual local step is clear, this event
	# need not start a second manoeuvre. No endpoint or future right is held.
	for id: String in contact.blocker_actor_ids:
		var other: Dictionary = world.facts.actors.get(id,{})
		var journey: Dictionary = world.facts.moves.get(id,{})
		if other.is_empty() or not journey.has("local_move") or other.location.kind!="floor" or int(other.location.floor_id)!=int(actor.location.floor_id): continue
		var origin: Vector2 = ConvoyTrail.point(other.location.cell)
		# Finish a reached-sidepoint handoff before treating it as a second
		# collision episode. This changes only intent, never the other body.
		if origin==ConvoyTrail.point(journey.local_move.target.cell) and not journey.local_move.has("rejoin"):
			_local_try_return(world,other,journey)
		var next: Vector2 = _step_toward(origin,ConvoyTrail.point(journey.local_move.target.cell),space.walking_speed(other)*WorldState.TICK_SECONDS)
		# Reaching a local endpoint and handing it back occur on adjacent
		# movement turns. Do not start a second bypass in that handoff gap.
		if next==origin and journey.local_move.has("rejoin"): return
		# An intention alone cannot clear this contact. Only an actually clear
		# next step lets the other body leave without another local manoeuvre.
		if next!=origin and _local_path_clear(world,other,[_floor_point(other,next)]): return
	if movement.get("local_move",{}).has("rejoin") and not bool(movement.local_move.get("retreat",false)):
		# A blocked B is an attempted target, not earned route progress. Try C
		# only after the existing single local mover has been considered.
		var changed: bool=_local_try_return(world,actor,movement,true,contact.requested_motion)
		if not changed:
			var link: Dictionary=movement.local_move.rejoin
			changed=_local_return(world,actor,movement,space.navigation.structural_clearance(world,actor,int(actor.location.floor_id)),int(link.index),ConvoyTrail.point(link.cell),contact.requested_motion)
		if changed:
			var next: Vector2=ConvoyTrail.point(movement.local_move.target.cell)-ConvoyTrail.point(actor.location.cell)
			if next.cross(contact.requested_motion)==0.0 and next.dot(contact.requested_motion)>0.0:
				var fixed: Array=[]
				for id: String in contact.blocker_actor_ids:
					var other: Dictionary=world.facts.actors.get(id,{})
					if other.get("location",{}).get("kind")!="floor" or other.location.floor_id!=actor.location.floor_id: continue
					if not _local_movable(world,other,world.facts.moves.get(id,{})): fixed.append(id)
				if fixed.is_empty(): _local_choose(world,actor,movement,next)
				else: _local_choose_options(world,actor,movement,next,fixed)
			return
	# The subject of this collision is picked once; no actor is moved here.
	if bool(movement.get("local_move",{}).get("retreat",false)):
		var start: Vector2 = ConvoyTrail.point(actor.location.cell)
		var sample: Dictionary = actor.duplicate();sample.facing=atan2(contact.requested_motion.x,contact.requested_motion.y)
		for id: String in contact.blocker_actor_ids:
			var other: Dictionary = world.facts.actors.get(id,{})
			var journey: Dictionary = world.facts.moves.get(id,{})
			if other.is_empty() or other.location.kind!="floor" or int(other.location.floor_id)!=int(actor.location.floor_id): continue
			var body: Rect2 = space._actor_rect(other,ConvoyTrail.point(other.location.cell))
			if not BodySweep.intersects(space._actor_rect(actor,start),space._actor_rect(sample,start+contact.requested_motion),body,body): continue
			if journey.get("route_pending",false): continue
			if not _local_movable(world,other,journey):
				continue
			var toward: Vector2 = -contact.requested_motion
			if journey.has("local_move"): toward=ConvoyTrail.point(journey.local_move.target.cell)-ConvoyTrail.point(other.location.cell)
			elif int(journey.cursor)<journey.path.size() and journey.path[int(journey.cursor)].kind=="floor": toward=ConvoyTrail.point(journey.path[int(journey.cursor)].cell)-ConvoyTrail.point(other.location.cell)
			_local_choose(world,other,journey,toward)
			return
		# Fixed bodies retain their place. Local movement keeps this request.
		return
	var fixed:Array=[]
	for id:String in contact.blocker_actor_ids:
		var other:Dictionary=world.facts.actors.get(id,{})
		var journey:Dictionary=world.facts.moves.get(id,{})
		if not _local_movable(world,other,journey):fixed.append(id)
	if fixed.is_empty():_local_choose(world,actor,movement,contact.requested_motion)
	else:_local_choose_options(world,actor,movement,contact.requested_motion,fixed)

# A real fixed-body collision must not select a side pocket whose only exit
# returns through that same body. Check local connectors, not a floor graph.
func _local_side_exit(world:WorldState,actor:Dictionary,movement:Dictionary,side:Vector2,fixed:Array)->bool:
	var sample:Dictionary=actor.duplicate(true)
	sample.location.cell=[side.x,side.y]
	var start:Vector2=ConvoyTrail.point(actor.location.cell)
	var side_facing:float=atan2(side.x-start.x,side.y-start.y)
	var query:RouteClearance=space.navigation.structural_clearance(world,actor,int(actor.location.floor_id))
	var scan:Dictionary={"path":movement.path,"search":{"previous":movement.get("local_move",{}).get("origin",actor.location.cell).duplicate(),"index":int(movement.cursor)}}
	while true:
		var candidate:Dictionary=_next_rejoin_candidate(actor,scan)
		if candidate.is_empty():break
		var target:Vector2=ConvoyTrail.point(candidate.cell)
		if not _local_return_endpoint_clear(world,sample,query,target):continue
		for corner:Vector2 in [Vector2(target.x,side.y),Vector2(side.x,target.y)]:
			if not query.sweep_reason(side,corner).is_empty() or not query.sweep_reason(corner,target).is_empty():continue
			sample.facing=side_facing
			var path: Array=[_floor_point(actor,corner),_floor_point(actor,target)]
			if not _bed_local_path_blocker(world,sample,movement,path).is_empty():continue
			if _local_fixed_path_clear(world,sample,path,fixed):return true
	return false

# Geometry of the current nearby stationary bodies only. Moving walkers and
# accepted sweeps remain real-step contacts, never a future corridor proof.
func _local_fixed_path_clear(world: WorldState, actor: Dictionary, path: Array, fixed: Array) -> bool:
	if fixed.is_empty(): return true
	var bodies: Array[Rect2]=[]
	for id: String in fixed:
		var other: Dictionary=world.facts.actors[id]
		bodies.append(space._actor_rect(other,ConvoyTrail.point(other.location.cell)))
	var sample: Dictionary=actor.duplicate()
	var origin: Vector2=ConvoyTrail.point(actor.location.cell)
	var previous: Rect2=space._actor_rect(actor,origin)
	for point: Dictionary in path:
		var target: Vector2=ConvoyTrail.point(point.cell)
		if origin==target: continue
		sample.facing=atan2(target.x-origin.x,target.y-origin.y)
		var first: Vector2=_step_toward(origin,target,space.walking_speed(actor)*WorldState.TICK_SECONDS)
		for next: Vector2 in [first,target]:
			if next==origin: continue
			var after: Rect2=space._actor_rect(sample,next)
			for body: Rect2 in bodies:
				if BodySweep.intersects(previous,after,body,body): return false
			origin=next;previous=after
	return true

func _local_resume(world: WorldState, actor: Dictionary, movement: Dictionary) -> bool:
	var local: Dictionary = movement.local_move
	var origin: Vector2 = ConvoyTrail.point(actor.location.cell)
	if local.has("rejoin") and origin==ConvoyTrail.point(local.rejoin.cell):
		var cell: Vector2 = ConvoyTrail.point(local.rejoin.cell)
		var index: int = int(local.rejoin.index)
		movement.cursor=index+1 if cell==ConvoyTrail.point(movement.path[index].cell) else index
		movement.erase("local_move")
		_route_checks.erase(actor.id)
		return true
	if origin!=ConvoyTrail.point(local.target.cell): return true
	if not local.get("corners",[]).is_empty():
		local.target=local.corners.pop_front()
		if local.corners.is_empty(): local.erase("corners")
		local.erase("retreat")
		return true
	if bool(local.get("retreat",false)):
		if _local_try_return(world,actor,movement): return true
		var toward: Vector2=ConvoyTrail.point(local.rejoin.cell if local.has("rejoin") else movement.path[int(movement.cursor)].cell)-origin
		if _local_choose(world,actor,movement,toward): return true
	elif _local_try_return(world,actor,movement): return true
	# No floor search or another side step without a real collision.
	movement.waiting_reason="等待原路线局部连接空出"
	return false

# One current original-route target. Static geometry selects its connector;
# only an actual blocked move advances the attempted target, never the route.
func _local_try_return(world: WorldState, actor: Dictionary, movement: Dictionary, advance: bool = false, blocked_motion: Vector2 = Vector2.ZERO) -> bool:
	var local:Dictionary=movement.local_move
	var query:RouteClearance=space.navigation.structural_clearance(world,actor,int(actor.location.floor_id))
	var previous: Array=local.origin
	var index: int=int(movement.cursor)
	if local.has("rejoin"):
		var point: Vector2=ConvoyTrail.point(local.rejoin.cell)
		index=int(local.rejoin.index)
		if not advance:
			if _local_return(world,actor,movement,query,index,point,blocked_motion): return true
			# The attempted point earned no route progress. After an actual
			# side/retreat, earlier unearned points can be connectable again.
			index=int(movement.cursor)
		else:
			previous=local.rejoin.cell
			if point==ConvoyTrail.point(movement.path[index].cell): index+=1
	var scan:Dictionary={"path":movement.path,"search":{"previous":previous,"index":index}}
	while true:
		index=int(scan.search.index)
		var candidate:Dictionary=_next_rejoin_candidate(actor,scan)
		if candidate.is_empty():break
		var target:Vector2=ConvoyTrail.point(candidate.cell)
		if _local_return(world,actor,movement,query,index,target,blocked_motion):return true
	return false

func _local_return_endpoint_clear(_world: WorldState, actor: Dictionary, query: RouteClearance, target: Vector2) -> bool:
	return target!=ConvoyTrail.point(actor.location.cell) and query.position_reason(target).is_empty()

func _local_return(world: WorldState, actor: Dictionary, movement: Dictionary, query: RouteClearance, index: int, target: Vector2, blocked_motion: Vector2 = Vector2.ZERO) -> bool:
	if not query.position_reason(target).is_empty(): return false
	var origin: Vector2 = ConvoyTrail.point(actor.location.cell)
	if target==origin:return false
	var corners: Array[Vector2]=[Vector2(target.x,origin.y),Vector2(origin.x,target.y)]
	# Continue around the obstruction after a real side step, rather than
	# immediately undoing that step. A contact supplies the blocked heading;
	# otherwise the last actually walked heading supplies the local bend.
	var heading: Vector2=blocked_motion
	if heading==Vector2.ZERO: heading=Vector2(sin(float(actor.facing)),cos(float(actor.facing)))
	if absf(heading.x)>absf(heading.y): corners.reverse()
	var reverse: Dictionary={}
	for corner: Vector2 in corners:
		if not query.sweep_reason(origin,corner).is_empty() or not query.sweep_reason(corner,target).is_empty(): continue
		if not _bed_local_path_blocker(world,actor,movement,[_floor_point(actor,corner),_floor_point(actor,target)]).is_empty(): continue
		var next: Vector2 = target if corner==origin or corner==target else corner
		var choice: Dictionary={"origin":movement.local_move.origin,"target":_floor_point(actor,next),"rejoin":{"index":index,"cell":[target.x,target.y]}}
		if movement.local_move.get("retreat",false) and (next-origin).dot(heading)>0.00001: choice.retreat=true
		if origin!=ConvoyTrail.point(movement.local_move.origin) and (next-origin).dot(heading)<-0.00001:
			if reverse.is_empty(): reverse=choice
			continue
		movement.local_move=choice
		return true
	if _local_return_around_nearby(world,actor,movement,query,index,target): return true
	if not reverse.is_empty():
		movement.local_move=reverse
		return true
	return false

# Use indexed geometry around the actual position and the intended endpoint.
# These are a few continuous connectors, not a floor grid or a new journey.
# Retain only this short connector's remaining corners. Losing a later
# obstacle from the neighbourhood must not forget a turn already proved.
# Actual steps still recheck geometry; the original cursor advances on rejoin.
func _local_return_around_nearby(world: WorldState, actor: Dictionary, movement: Dictionary, query: RouteClearance, index: int, target: Vector2) -> bool:
	var origin: Vector2=ConvoyTrail.point(actor.location.cell)
	var width: float=float(space.clearance(actor))
	var near: Rect2=space._actor_rect(actor,origin).grow(width)
	var floor_id: int=int(actor.location.floor_id)
	var facilities: BodyIndex=space._navigation.facility_index(space,world,floor_id)
	var obstacles: Array[Rect2]=[]
	var fixed: Array=[]
	var facility_ids: Array[String]=facilities.candidates(floor_id,near)
	# The connection can also bend around the target's static furniture.
	# Both endpoint neighbourhoods use the loaded index, never a floor scan.
	for id: String in facilities.candidates(floor_id,Rect2(target,Vector2.ONE*width).grow(width)):
		if not id in facility_ids: facility_ids.append(id)
	for id: String in facility_ids: obstacles.append(facilities.rectangle(id))
	var target_body: Rect2=space._actor_rect(actor,target)
	var actor_ids: Array[String]=space._actor_index.candidates(floor_id,near,[actor.id])
	for id: String in space._actor_index.candidates(floor_id,Rect2(target,Vector2.ONE*width).grow(width),[actor.id]):
		if not id in actor_ids and not world.facts.moves.has(id): actor_ids.append(id)
	for id: String in actor_ids:
		var rect: Rect2=space._actor_index.rectangle(id)
		obstacles.append(rect)
		# Occupying the intended endpoint still requires a real attempt at B.
		# Nearby stationary obstacles on the way can shape the short connector.
		if not world.facts.moves.has(id) and not target_body.intersects(rect,false): fixed.append(id)
	var xs: Array[float]=[]
	var ys: Array[float]=[]
	for rect: Rect2 in obstacles:
		for x: float in [floorf(rect.position.x)-width,ceilf(rect.end.x)]:
			if not x in xs: xs.append(x)
		for y: float in [floorf(rect.position.y)-width,ceilf(rect.end.y)]:
			if not y in ys: ys.append(y)
	var links: Array=[]
	for x: float in xs: links.append([Vector2(x,origin.y),Vector2(x,target.y),target])
	for y: float in ys: links.append([Vector2(origin.x,y),Vector2(target.x,y),target])
	for x: float in xs:
		for y: float in ys:
			links.append([Vector2(x,origin.y),Vector2(x,y),Vector2(target.x,y),target])
			links.append([Vector2(origin.x,y),Vector2(x,y),Vector2(x,target.y),target])
	var heading: Vector2=Vector2(sin(float(actor.facing)),cos(float(actor.facing)))
	var reverse: Array=[]
	var chosen: Array=[]
	for link: Array in links:
		var path: Array=[]
		var previous: Vector2=origin
		var direction: Vector2=Vector2.ZERO
		for point: Vector2 in link:
			if point==previous: continue
			if direction!=Vector2.ZERO and direction.dot(point-previous)!=0.0:
				path.clear();break
			path.append(_floor_point(actor,point))
			direction=point-previous
			previous=point
		if path.is_empty() or not _bed_local_path_blocker(world,actor,movement,path).is_empty(): continue
		var clear: bool=true
		previous=origin
		for point: Dictionary in path:
			var next: Vector2=ConvoyTrail.point(point.cell)
			if not query.sweep_reason(previous,next).is_empty(): clear=false;break
			previous=next
		if not clear or not _local_fixed_path_clear(world,actor,path,fixed): continue
		if (ConvoyTrail.point(path[0].cell)-origin).dot(heading)<-0.00001:
			if reverse.is_empty(): reverse=path
			continue
		chosen=path
		break
	if chosen.is_empty(): chosen=reverse
	if chosen.is_empty(): return false
	var retreat: bool=bool(movement.local_move.get("retreat",false)) and (ConvoyTrail.point(chosen[0].cell)-origin).dot(heading)>0.00001
	movement.local_move={"origin":movement.local_move.origin,"target":chosen[0],"rejoin":{"index":index,"cell":[target.x,target.y]}}
	if retreat: movement.local_move.retreat=true
	if chosen.size()>2: movement.local_move.corners=chosen.slice(1,chosen.size()-1)
	return true

func _start_detour(world: WorldState, actor: Dictionary, movement: Dictionary) -> void:
	if not movement.has("convoy") and movement.get("members",[actor.id]).size()==1:
		if int(movement.cursor)<movement.path.size():
			_local_choose(world,actor,movement,ConvoyTrail.point(movement.path[int(movement.cursor)].cell)-ConvoyTrail.point(actor.location.cell))
		return
	if movement.has("detour") or int(movement.cursor)>=movement.path.size(): return
	var first: Dictionary = movement.path[int(movement.cursor)]
	if first.kind!="floor" or int(first.floor_id)!=int(actor.location.floor_id): return
	var delta: Vector2 = ConvoyTrail.point(first.cell)-ConvoyTrail.point(actor.location.cell)
	if delta.length()<0.001: return
	var direction: Vector2 = Vector2(signf(delta.x),0) if absf(delta.x)>=absf(delta.y) else Vector2(0,signf(delta.y))
	var history: Array = _local_travelled(movement,int(actor.location.floor_id))
	movement.detour = {"phase":"back","original_path":movement.path.slice(int(movement.cursor)).duplicate(true),"direction":[direction.x,direction.y],"backtrack":history,"back_cursor":history.size()-1,"prefix_size":0,"resume_index":-1}
	space.query_counts.yield_attempts += 1
	if _detour_side(world,actor,movement): return
	# The same local return used at each retreat checkpoint can also leave
	# the current corner. Do not take a partial backward step first: that
	# consumes a queue's spacing without clearing its own occupied trail.
	if movement.has("convoy"):
		var link: Dictionary = _detour_return_path(world,actor,movement,ConvoyTrail.point(actor.location.cell))
		if not link.is_empty():
			_set_detour_prefix(movement,link.path,"rejoin",int(link.index))
			return
	if not _detour_back(world,actor,movement): movement.erase("detour")

func _set_detour_prefix(movement: Dictionary, path: Array, phase: String, resume_index: int = -1) -> void:
	movement.detour.phase = phase
	movement.detour.prefix_size = path.size()
	movement.detour.resume_index = resume_index
	movement.path = path
	if phase=="rejoin": movement.path.append_array(movement.detour.original_path.slice(resume_index+1))
	movement.cursor = 0
	movement.blocked_since = -1
	movement.erase("waiting_reason")
	_route_checks.erase(movement.actor_id)

# Group/convoy traffic retains its existing leader-owned controller.
func _detour_obstruction(_world: WorldState, _actor: Dictionary, movement: Dictionary, _contact: MotionResult) -> bool:
	if movement.detour.phase!="back": _set_detour_prefix(movement,[],"aside")
	return false

func _detour_side(world: WorldState, actor: Dictionary, movement: Dictionary) -> bool:
	return _detour_side_full(world,actor,movement)

func _detour_side_full(world: WorldState, actor: Dictionary, movement: Dictionary) -> bool:
	var origin: Vector2 = ConvoyTrail.point(actor.location.cell)
	var forward: Vector2 = ConvoyTrail.point(movement.detour.direction)
	# After retracing a bend, left/right follow that local corridor rather
	# than the heading at the original collision several cells away.
	if movement.detour.phase=="back" and int(movement.detour.prefix_size)>0:
		for index: int in range(int(movement.detour.back_cursor),-1,-1):
			var reverse: Vector2 = ConvoyTrail.point(movement.detour.backtrack[index].cell)-origin
			if reverse.length()>0.001:
				forward = -reverse.normalized()
				break
	var side: Vector2 = Vector2(-forward.y,forward.x)
	var width: float = float(movement.convoy.size) if movement.has("convoy") else float(space.clearance(actor))
	var waiting_side: Array = []
	for sign_value: float in [1.0,-1.0]:
		var target: Vector2 = origin+side*sign_value*width
		var path: Array = [_floor_point(actor,target)]
		if not _bed_path_stop_blocker(world,actor,movement,path).is_empty(): continue
		if not _detour_path_clear(world,actor,movement,path): continue
		# Prefer a side from which a local return is presently possible.
		# This avoids stepping into a doorway pocket when the other side
		# already provides a complete passing link. No actor gets priority.
		if not _detour_return_path(world,actor,movement,target,path).is_empty():
			_set_detour_prefix(movement,path,"aside")
			return true
		# Do not stop a local retreat inside a doorway: retaining its owner
		# there would prevent the approaching body from ever passing.
		var proxy: Dictionary = ConvoyTrail.proxy(world,movement) if movement.has("convoy") else actor
		var footprint: Rect2 = Rect2(target+Vector2.ONE*float(movement.convoy.shift),Vector2.ONE*int(movement.convoy.size)) if movement.has("convoy") else space._actor_rect(actor,target)
		var in_door: bool = false
		for door: Dictionary in space.movement_doors(world,proxy,footprint,[]):
			if footprint.intersects(space._door_rect(door,space._door_span(proxy,door)),false): in_door = true;break
		if waiting_side.is_empty() and not in_door: waiting_side = path
	if waiting_side.is_empty(): return false
	_set_detour_prefix(movement,waiting_side,"aside")
	return true

func _detour_back(world: WorldState, actor: Dictionary, movement: Dictionary) -> bool:
	var state: Dictionary = movement.detour
	var origin: Vector2 = ConvoyTrail.point(actor.location.cell)
	while int(state.back_cursor)>=0:
		var index: int = int(state.back_cursor)
		var past: Dictionary = state.backtrack[index]
		if ConvoyTrail.point(past.cell).distance_to(origin)<0.001:
			state.back_cursor = index-1
			continue
		var path: Array = [past.duplicate(true)]
		if not _retreat_intention_clear(world,actor,movement,path): return false
		state.back_cursor = index-1
		_set_detour_prefix(movement,path,"back")
		return true
	# A just-started journey may have no earlier checkpoint. Test one real
	# step directly behind, then retry the sides at that reached point.
	# A convoy cannot reverse its leader into its own occupied tail.
	var width: float = float(movement.convoy.size) if movement.has("convoy") else float(space.clearance(actor))
	var path: Array = [_floor_point(actor,origin-ConvoyTrail.point(state.direction)*width)]
	if _retreat_intention_clear(world,actor,movement,path):
		_set_detour_prefix(movement,path,"back")
		return true
	return false

# Retreat is an intention: fixed geometry must permit it, but a present
# body is handled by the actual movement contact without reversing again.
func _retreat_intention_clear(world: WorldState, actor: Dictionary, movement: Dictionary, path: Array) -> bool:
	if not _bed_path_stop_blocker(world,actor,movement,path).is_empty(): return false
	if movement.has("convoy") or movement.get("members",[actor.id]).size()!=1:
		return _detour_path_clear(world,actor,movement,path)
	var query: RouteClearance = space.navigation.structural_clearance(world,actor,int(actor.location.floor_id))
	var origin: Vector2 = ConvoyTrail.point(actor.location.cell)
	for segment: Dictionary in path:
		var target: Vector2 = ConvoyTrail.point(segment.cell)
		if not query.sweep_reason(origin,target).is_empty(): return false
		origin=target
	return true

# React only to a current body still crossing this actual retreat step.
# Set a local intention, never move another body or recurse through traffic.
func _continue_detour(world: WorldState, actor: Dictionary, movement: Dictionary) -> void:
	_continue_detour_full(world,actor,movement)

func _continue_detour_full(world: WorldState, actor: Dictionary, movement: Dictionary) -> void:
	var state: Dictionary = movement.detour
	if int(movement.cursor)<int(state.prefix_size): return
	if state.phase=="rejoin":
		movement.erase("detour")
		return
	if state.phase=="back":
		var resumed: Dictionary = _detour_return_path(world,actor,movement,ConvoyTrail.point(actor.location.cell))
		if not resumed.is_empty():
			_set_detour_prefix(movement,resumed.path,"rejoin",int(resumed.index))
			return
		# First retreat only along the path already walked. At each reached
		# point try its two sides, without searching the rest of the journey.
		if _detour_side(world,actor,movement) or _detour_back(world,actor,movement): return
		movement.waiting_reason = "等待实际侧方或后退通路"
		return
	var link: Dictionary = _detour_return_path(world,actor,movement,ConvoyTrail.point(actor.location.cell))
	if not link.is_empty():
		_set_detour_prefix(movement,link.path,"rejoin",int(link.index))
		return
	movement.waiting_reason = "等待原路线最近可达格"

func _detour_return_path(world: WorldState, actor: Dictionary, movement: Dictionary, origin: Vector2, prefix: Array = []) -> Dictionary:
	# Choose the nearest currently unoccupied original point whose local
	# same-axis link can start. Future steps are intentions, never passage grants.
	# Compound/convoy movement retains its original full trail proof.
	var query: RouteClearance = null
	# One synchronous owner; failed trials only read these private records.
	# A successful path escapes once, after which this buffer is never rewritten.
	var path: Array = prefix.duplicate(true)
	var prefix_size: int = path.size()
	var points: Array[Dictionary] = []
	for index: int in movement.detour.original_path.size():
		var segment: Dictionary = movement.detour.original_path[index]
		if segment.kind!="floor" or int(segment.floor_id)!=int(actor.location.floor_id): break
		if query==null:
			var proxy: Dictionary = ConvoyTrail.proxy(world,movement) if movement.has("convoy") else actor
			query = space.navigation.structural_clearance(world,proxy,int(actor.location.floor_id))
		var target: Vector2 = ConvoyTrail.point(segment.cell)
		# Try the original blocked cell first, then its original successors.
		# Check fixed orthogonal local links, never a global route.
		var links: Array = [[Vector2(target.x,origin.y),target],[Vector2(origin.x,target.y),target]]
		if not movement.has("convoy") and movement.get("members",[]).size()<=1 and absf(float(movement.detour.get("direction",[1,0])[1]))>0.5: links.reverse()
		if not movement.has("convoy") and movement.get("members",[actor.id]).size()==1: links.resize(1)
		if movement.has("convoy") or movement.get("members",[actor.id]).size()>1:
			# Four fixed outside links handle a nearby corner/passing pocket.
			# A queue's margin also clears its own tail before returning.
			var margin: float = float(movement.convoy.spacing) if movement.has("convoy") else float(space.clearance(actor))
			var outside_x: Array = [maxf(origin.x,target.x)+margin,minf(origin.x,target.x)-margin]
			var outside_y: Array = [maxf(origin.y,target.y)+margin,minf(origin.y,target.y)-margin]
			for x: float in outside_x: links.append([Vector2(x,origin.y),Vector2(x,target.y),target])
			for y: float in outside_y: links.append([Vector2(origin.x,y),Vector2(target.x,y),target])
			# A pocket beside furniture may need one outside bend on each axis
			# to reach the side of a doorway. Try these fixed links for this
			# original cell before considering a farther one; never redispatch.
			for x: float in outside_x:
				for y: float in outside_y:
					links.append([Vector2(x,origin.y),Vector2(x,y),Vector2(target.x,y),target])
					links.append([Vector2(origin.x,y),Vector2(x,y),Vector2(x,target.y),target])
		for link: Array in links:
			path.resize(prefix_size)
			var point_index: int = 0
			var previous: Vector2 = origin
			for point: Vector2 in link:
				if previous.distance_to(point)>0.001:
					if point_index==points.size(): points.append(_floor_point(actor,point))
					else:
						points[point_index].cell[0] = point.x
						points[point_index].cell[1] = point.y
					path.append(points[point_index])
					point_index += 1
				previous = point
			if path.is_empty(): path.append(segment.duplicate(true))
			if _return_link_can_start(world,actor,movement,path,query): return {"path":path,"index":index}
	return {}

# A return intention is not permission to traverse its future path. Every
# real movement step retains the normal sweep/door/reservation checks.
func _return_link_can_start(world: WorldState, actor: Dictionary, movement: Dictionary, path: Array, query: RouteClearance) -> bool:
	var origin: Vector2 = ConvoyTrail.point(actor.location.cell)
	var first: Vector2 = origin
	var previous: Vector2 = origin
	var target: Vector2 = origin
	var heading: Vector2 = Vector2.ZERO
	for point: Dictionary in path:
		target = ConvoyTrail.point(point.cell)
		if previous.distance_to(target)>0.001:
			heading = target-previous
			if first==origin: first=target
		previous=target
	if movement.has("convoy") or movement.get("members",[actor.id]).size()>1:
		# Keep the existing trail proof until leader-only local-turn cases have
		# separately established a safe incremental implementation.
		return _detour_path_clear(world,actor,movement,path,query)
	space._ensure_actor_index(world)
	var sample: Dictionary=actor.duplicate(true)
	if heading.length()>0.001: sample.facing=atan2(heading.x,heading.y)
	if not query.position_reason(target).is_empty(): return false
	var target_rect: Rect2=space._actor_rect(sample,target)
	var sweep:=BodyIndex.Record.new();sweep.sweep_from=target_rect;sweep.sweep_to=target_rect
	var sweeps: Array[BodyIndex.Record]=[sweep]
	var occupied:=MotionResult.new();occupied.first_contact_only=true
	_movement_contacts(world,actor.id,int(actor.location.floor_id),target_rect,sweeps,movement.get("members",[actor.id]),occupied)
	if occupied.blocked: return false
	if first==origin: return true
	var next: Vector2=_step_toward(origin,first,space.walking_speed(actor)*WorldState.TICK_SECONDS)
	return _detour_path_clear(world,actor,movement,[_floor_point(actor,next)],query)

# Only the return-search owner can capture this exact entry state. A known
# first-segment failure can reject this candidate before building its path;
# unknown/positive/capped-out proofs still execute the complete predicate.
func _detour_first_segment_failed(world: WorldState, actor: Dictionary, link_origin: Vector2, prefix: Array, link: Array, fallback: Dictionary, proof: Dictionary) -> bool:
	if not proof.has("_entry"): return false
	var first: Vector2
	if not prefix.is_empty():
		first = ConvoyTrail.point(prefix[0].cell)
	else:
		var previous: Vector2 = link_origin
		var found: bool = false
		for point: Vector2 in link:
			if previous.distance_to(point)>0.001:
				first = point
				found = true
				break
			# The original builder advances even when this point is not appended.
			previous = point
		if not found: first = ConvoyTrail.point(fallback.cell)
	var entry: Dictionary = proof._entry
	var origin: Vector2 = entry.origin
	if absf(first.x-origin.x)>0.001 and absf(first.y-origin.y)>0.001: return false
	if origin.distance_to(first)<=0.001: return false
	var key: Array = [origin,first,entry.rect]
	if not proof.segments.has(key) or not proof.segments[key].is_empty(): return false
	# A first-segment negative memo returns before any trial-facing change.
	# Keep its original index/shape side effects, using the same actor fields
	# as the fresh sample. A surprising rectangle change takes full fallback.
	space._ensure_actor_index(world)
	return space._actor_rect(actor,origin)==entry.rect

func _floor_point(actor: Dictionary, point: Vector2) -> Dictionary:
	return {"kind":"floor","floor_id":int(actor.location.floor_id),"cell":[point.x,point.y]}

# Read-only local proof. A convoy has one fixed leader proxy; its members only
# inherit the proven trail. No follower gets an independent passage query.
func _detour_path_clear(world: WorldState, actor: Dictionary, movement: Dictionary, path: Array, query: RouteClearance = null, proof: Dictionary = {}) -> bool:
	space._ensure_actor_index(world)
	var floor_id: int = int(actor.location.floor_id)
	var proxy: Dictionary = ConvoyTrail.proxy(world,movement) if movement.has("convoy") else actor
	if query==null: query = space.navigation.structural_clearance(world,proxy,floor_id)
	var trial: Dictionary = movement.convoy.duplicate(true) if movement.has("convoy") else {}
	var shift: Vector2 = Vector2.ONE*float(trial.shift) if not trial.is_empty() else Vector2.ZERO
	var origin: Vector2 = ConvoyTrail.point(actor.location.cell)
	var sample: Dictionary = proof._return_sample if proof.has("_return_sample") else actor.duplicate(true)
	# Pruned candidates leave private scratch untouched; full trials reset it.
	sample.facing = actor.facing
	var previous: Rect2 = space._actor_rect(sample,origin) if trial.is_empty() else Rect2(origin+shift,Vector2.ONE*int(trial.size))
	if proof.get("_capture_entry",false) and not proof.has("_entry"):
		proof._entry = {"origin":origin,"rect":previous}
	var members: Array = movement.get("members",[actor.id])
	var reuse_contact: bool = proof.has("_return_sample") and not movement.has("convoy")
	var contact_scratch: ReturnContactScratch = proof.get("_return_contact_scratch") if reuse_contact else null
	for segment: Dictionary in path:
		var target: Vector2 = ConvoyTrail.point(segment.cell)
		if absf(target.x-origin.x)>0.001 and absf(target.y-origin.y)>0.001: return false
		var segment_key: Array = []
		var remember_segment: bool = false
		if proof.has("segments") and origin.distance_to(target)>0.001:
			segment_key = [origin,target,previous]
			if proof.segments.has(segment_key):
				var proven: Array = proof.segments[segment_key]
				if proven.is_empty(): return false
				# The quarter loop can stop within tolerance, short of target.
				origin = proven[0]
				previous = proven[1]
				continue
			# This map has the same single-call lifetime as the sweep proofs.
			# Its cap limits storage only; every uncached leg still runs below.
			remember_segment = proof.segments.size()<4096
			if remember_segment: proof.segments[segment_key] = []
		while origin.distance_to(target)>0.001:
			var next: Vector2 = origin.move_toward(target,0.25)
			var proof_key: Array = []
			var next_rect: Rect2
			var remember: bool = false
			if not proof.is_empty():
				sample.facing = atan2(target.x-origin.x,target.y-origin.y)
				next_rect = space._actor_rect(sample,next)
				# Keep exact points and both real rectangles: near-axis floats can
				# round to the same next point while retaining a different facing.
				proof_key = [origin,next,previous,next_rect]
				if proof.sweeps.has(proof_key):
					if not proof.sweeps[proof_key]: return false
					previous = next_rect
					origin = next
					continue
				# Bound scratch memory only; never limit candidates or sweep work.
				remember = proof.sweeps.size()<4096
				if remember: proof.sweeps[proof_key] = false
			if not query.sweep_reason(origin+shift,next+shift).is_empty(): return false
			# Allocate lazily: memo hits and static failures create no scratch.
			if reuse_contact and contact_scratch==null:
				contact_scratch = ReturnContactScratch.new()
				if proof.get("_cache_contacts",false): contact_scratch.queries = {"regions":{}}
				proof._return_contact_scratch = contact_scratch
			var sweep: BodyIndex.Record = contact_scratch.sweep if reuse_contact else BodyIndex.Record.new()
			sweep.id = actor.id
			sweep.sweep_from = previous
			if not trial.is_empty():
				var proposal: Dictionary = ConvoyTrail.propose(trial,next)
				if not proposal.ok: return false
				trial.points = proposal.points
				sweep.sweep_to = Rect2(next+shift,Vector2.ONE*int(trial.size))
			else:
				if proof.is_empty():
					sample.facing = atan2(target.x-origin.x,target.y-origin.y)
					next_rect = space._actor_rect(sample,next)
				sweep.sweep_to = next_rect
			var contact: MotionResult = contact_scratch.result if reuse_contact else MotionResult.new()
			if reuse_contact:
				contact.requested_motion = Vector2.ZERO
				contact.actual_motion = Vector2.ZERO
				contact.door_id = ""
				contact.blocker_actor_ids.clear()
				contact.reservation_ids.clear()
			if reuse_contact:
				_movement_contacts(world,actor.id,floor_id,sweep.sweep_from.merge(sweep.sweep_to),contact_scratch.sweeps,members,contact,contact_scratch.queries)
			else:
				var sweeps: Array[BodyIndex.Record] = [sweep]
				_movement_contacts(world,actor.id,floor_id,sweep.sweep_from.merge(sweep.sweep_to),sweeps,members,contact)
			if contact.blocked: return false
			if remember: proof.sweeps[proof_key] = true
			previous = sweep.sweep_to
			origin = next
		if remember_segment: proof.segments[segment_key] = [origin,previous]
	return true

func _staff_has_movement_responsibility(world: WorldState, staff_id: String, context: Dictionary = {}) -> bool:
	var staff: Dictionary = world.facts.staff.get(staff_id,{})
	if staff.is_empty() or HospitalClinicalDevelopment.safe_busy(world,staff_id):
		return true
	if not staff.get("base_task",{}).is_empty() or not str(staff.get("training_job_id","")).is_empty() or staff.get("life_task",{"phase":"idle"}).get("phase","idle")!="idle":
		return true
	if not context.has("owners"):
		var owners: Dictionary = {}
		for stay: Dictionary in world.facts.ward_stays.values():
			if not stay.get("phase","") in ["release_wait","complete"]:
				for id: String in [stay.get("nurse_id",""),stay.get("round_doctor_id",""),stay.get("escort_id","")]: owners[id] = true
		for reservation: Dictionary in world.facts.adaptations.values():
			owners[reservation.get("actor_id","")] = true
			for id: String in reservation.get("staff_ids",[]): owners[id] = true
		for reservation: Dictionary in world.facts.get("staff_life",{}).get("reservations",{}).values():
			for id: String in reservation.get("staff_ids",[]): owners[id] = true
		for job: Dictionary in world.facts.get("training_jobs",{}).values():
			if not HospitalClinicalDevelopment.terminal(job):
				owners[job.get("staff_id","")] = true
				owners[job.get("mentor_id","")] = true
		context.owners = owners
	return context.owners.has(staff_id)

func _courtesy_clearance(world: WorldState, actor: Dictionary, members: Array = [], offsets: Dictionary = {}) -> RouteClearance:
	var floor_id: int = int(actor.location.floor_id)
	# Borrow only resident, source-validated static geometry. Current members
	# and reservation permissions remain query-local; a miss builds no graph.
	var geometry: RouteClearance = space._navigation.cached_static_geometry(space,world,floor_id,actor)
	var counter: String = "courtesy_static_geometry_hits" if geometry!=null else "courtesy_static_geometry_misses"
	space.query_counts[counter] = int(space.query_counts.get(counter,0))+1
	return RouteClearance.new(space,world,actor,floor_id,members,offsets,true,space._navigation.floor_source(space,world,floor_id),geometry)

func _narrow(world: WorldState, actor: Dictionary, origin: Vector2i, checker: RouteClearance = null) -> bool:
	var available: int = 0
	if checker==null: checker = _courtesy_clearance(world,actor)
	for offset: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
		if checker.reason(origin+offset).is_empty():
			available += 1
	return available<=2

func _move_convoy(world: WorldState, actor: Dictionary, movement: Dictionary, segment: Dictionary) -> MotionResult:
	var result: MotionResult=MotionResult.new()
	var target: Vector2=ConvoyTrail.point(segment.cell)
	var start: Vector2=ConvoyTrail.point(actor.location.cell)
	var speed: float=space.walking_speed(world.facts.actors[movement.actor_id])
	var next: Vector2=_step_toward(start,target,speed*WorldState.TICK_SECONDS)
	result.requested_motion=next-start
	space.query_counts["convoy_leader_checks"]=int(space.query_counts.get("convoy_leader_checks",0))+1
	var proposal: Dictionary=ConvoyTrail.propose(movement.convoy,next)
	if not proposal.ok:
		movement.waiting_reason=proposal.reason
		_queue_local_route(world,actor,movement)
		return result
	var proxy: Dictionary=ConvoyTrail.proxy(world,movement)
	var shift: Vector2=Vector2.ONE*float(movement.convoy.shift)
	var query: RouteClearance=space.navigation.structural_clearance(world,proxy,int(actor.location.floor_id))
	var reason: String=query.sweep_reason(start+shift,next+shift)
	if not reason.is_empty(): movement.waiting_reason=reason;return result
	var sweep: BodyIndex.Record=BodyIndex.Record.new()
	sweep.id=actor.id;sweep.sweep_from=Rect2(start+shift,Vector2.ONE*int(movement.convoy.size));sweep.sweep_to=Rect2(next+shift,Vector2.ONE*int(movement.convoy.size))
	var sweeps: Array[BodyIndex.Record]=[sweep]
	var doors: Array[Dictionary]=space.movement_doors(world,proxy,proposal.front,[])
	_movement_contacts(world,actor.id,int(actor.location.floor_id),proposal.front,sweeps,movement.members,result)
	if result.blocked: return result
	if not _reserve_doors(world,proxy,movement,proposal.front,doors,result): return result
	movement.convoy.points=proposal.points
	var facing: float=atan2(next.x-start.x,next.y-start.y) if next!=start else float(actor.facing)
	var poses: Dictionary=ConvoyTrail.positions(movement.convoy,movement.members,facing)
	# O(member count) publication only; no member route/collision permissions.
	for id: String in movement.members:
		world.facts.actors[id].location.cell=poses[id].cell
		world.facts.actors[id].facing=poses[id].facing
		space._sync_actor(world,id)
	space._sync_convoy(world,movement)
	sweep.regions=proposal.history
	_accepted_sweeps[actor.id]=sweep
	_sweep_index.update_compound(actor.id,int(actor.location.floor_id),proposal.history)
	_mark_door_use(world,int(actor.location.floor_id),proposal.front,doors)
	result.actual_motion=next-start
	movement.blocked_since=-1
	movement.erase("waiting_reason")
	if next==target:
		movement.travelled.append({"kind":"floor","floor_id":actor.location.floor_id,"cell":segment.cell.duplicate()})
		movement.cursor+=1
	return result

# A portal frame is one atomic compound leader trajectory. Half-size proof
# milestones may split it, but never discard the remaining walking budget.
func _move_convoy_portal(world: WorldState, actor: Dictionary, movement: Dictionary, targets: Array, floor_id: int, connector_id: String) -> MotionResult:
	var result: MotionResult=MotionResult.new()
	var start: Vector2=ConvoyTrail.point(movement.convoy.points[-1])
	space.query_counts["convoy_leader_checks"]=int(space.query_counts.get("convoy_leader_checks",0))+1
	space.query_counts["convoy_portal_proposals"]=int(space.query_counts.get("convoy_portal_proposals",0))+1
	var proposal: Dictionary=ConvoyPortal.propose_step(movement.convoy,targets,int(movement.convoy.portal.cursor),space.walking_speed(world.facts.actors[movement.actor_id])*WorldState.TICK_SECONDS)
	if not proposal.ok: movement.waiting_reason=proposal.reason;return result
	space.query_counts["convoy_portal_subsegments"]=int(space.query_counts.get("convoy_portal_subsegments",0))+int(proposal.segment_count)
	var next: Vector2=ConvoyTrail.point(proposal.points[-1])
	result.requested_motion=next-start
	var proxy: Dictionary=ConvoyTrail.proxy(world,movement)
	var shift: Vector2=Vector2.ONE*float(movement.convoy.shift)
	proxy.location={"kind":"floor","floor_id":floor_id,"cell":[start.x+shift.x,start.y+shift.y]}
	var source: Dictionary=space._navigation.floor_source(space,world,floor_id).duplicate()
	source.connectors=source.connectors.duplicate()
	source.connectors.erase(connector_id)
	var query: RouteClearance=RouteClearance.new(space,world,proxy,floor_id,[],{},false,source)
	for index: int in range(1,proposal.path.size()):
		var reason: String=query.sweep_reason(ConvoyTrail.point(proposal.path[index-1])+shift,ConvoyTrail.point(proposal.path[index])+shift)
		if not reason.is_empty(): movement.waiting_reason=reason;return result
	# A static swept-front region for each piece is conservative for the whole
	# frame. Comparing each piece as a separate full-speed frame would mistime
	# ordinary actors' accepted sweeps and could miss a contact at a corner.
	var sweeps: Array[BodyIndex.Record]=[]
	for front: Rect2 in proposal.fronts:
		var piece: BodyIndex.Record=BodyIndex.Record.new()
		piece.id=actor.id;piece.sweep_from=front;piece.sweep_to=front
		sweeps.append(piece)
	_movement_contacts(world,actor.id,floor_id,proposal.front,sweeps,movement.members,result)
	if result.blocked: movement.waiting_reason="队列登离舱前端受阻，保持当前连接所有权";return result
	var doors: Array[Dictionary]=[]
	var seen: Dictionary={}
	for front: Rect2 in proposal.fronts:
		for door: Dictionary in space.movement_doors(world,proxy,front,[],floor_id):
			if seen.has(door.id) or not front.intersects(space._door_rect(door,space._door_span(proxy,door)),false): continue
			var quote: Dictionary=space.door_quote(world,proxy,floor_id,door,[])
			if not quote.ok or not front.intersects(space._door_rect(door,int(quote.span)),false): continue
			seen[door.id]=true
			doors.append(door)
	# _reserve_doors stages every reservation before committing any of them.
	if not _reserve_doors(world,proxy,movement,proposal.front,doors,result): return result
	movement.convoy.points=proposal.points
	movement.convoy.portal.cursor=int(proposal.cursor)
	# A compound frame can turn: its final accepted subsegment, not the net
	# displacement across the corner, determines the singleton's final heading.
	var tangent: Vector2=ConvoyTrail.point(proposal.path[-1])-ConvoyTrail.point(proposal.path[-2])
	var poses: Dictionary = ConvoyTrail.positions(movement.convoy,movement.members,atan2(tangent.x,tangent.y))
	for id: String in movement.members:
		world.facts.actors[id].location.queue_cell = poses[id].cell
		world.facts.actors[id].facing = poses[id].facing
		space._sync_actor(world,id)
	space._sync_convoy(world,movement)
	var sweep: BodyIndex.Record = BodyIndex.Record.new()
	sweep.id = actor.id
	sweep.regions = proposal.history
	_accepted_sweeps[actor.id] = sweep
	_sweep_index.update_compound(actor.id,floor_id,proposal.history)
	_mark_door_use(world,floor_id,proposal.front,doors)
	result.actual_motion = next-start
	movement.blocked_since = -1
	movement.erase("waiting_reason")
	return result

func _active_convoy_route_clear(world: WorldState, actor: Dictionary, movement: Dictionary) -> bool:
	var sequence: int = int(movement.get("request_sequence",0))
	var record: Dictionary = _route_checks.get(actor.id,{})
	var floor_versions: Dictionary = {}
	var connection_basis: Array = space.navigation.connection_basis(world)
	if int(record.get("sequence",-1))==sequence:
		var unchanged: bool = record.get("connections",[])==connection_basis
		for floor_key: int in record.get("floors",{}):
			floor_versions[floor_key] = space._navigation.floor_static_version(space,world,floor_key)
			if floor_versions[floor_key]!=record.floors[floor_key]: unchanged = false
		if unchanged: return true
	var proxy: Dictionary = ConvoyTrail.proxy(world,movement)
	var shift: Vector2 = Vector2.ONE*float(movement.convoy.shift)
	var floor_id: int = int(actor.location.floor_id)
	var current: Vector2 = ConvoyTrail.point(actor.location.cell)+shift
	var query: RouteClearance = space.navigation.structural_clearance(world,proxy,floor_id)
	for segment: Dictionary in movement.path.slice(int(movement.cursor)):
		if segment.kind=="connector":
			var connection: Dictionary = world.facts.connectors.get(segment.connector_id,{})
			if connection.is_empty() or not HospitalTransit.fits(space,world,connection,actor.id,movement.members).ok: return false
			floor_id = int(segment.to)
			var p: Dictionary = ConvoyPortal.plan(space,world,connection,actor.id,movement.members,movement.convoy)
			current = ConvoyTrail.point(p.egress)+shift if p.get("ok",false) else ConvoyTrail.point(connection.anchor)+shift
			query = space.navigation.structural_clearance(world,proxy,floor_id)
		else:
			var target: Vector2 = ConvoyTrail.point(segment.cell)+shift
			if int(segment.floor_id)!=floor_id or not query.sweep_reason(current,target).is_empty(): return false
			current = target
	for segment: Dictionary in movement.path.slice(int(movement.cursor)):
		if segment.kind=="floor": floor_versions[int(segment.floor_id)] = space._navigation.floor_static_version(space,world,int(segment.floor_id))
	_route_checks[actor.id] = {"floors":floor_versions,"connections":connection_basis,"sequence":sequence}
	return true

# A rejected destination cannot change a journey, ticket, or ownership.
# Only static geometry defines admission; temporary people and the queue's
# present tail may occupy a valid future destination.
func _convoy_goal_reason(world: WorldState, movement: Dictionary, floor_id: int, target: Array) -> String:
	if floor_id<1 or not ConvoyTrail._finite_point(target): return "队列目标楼层或坐标无效"
	var goal: Vector2 = ConvoyTrail.point(target)
	if goal.x<0.0 or goal.y<0.0 or goal.x>=FloorNavigation.SIDE or goal.y>=FloorNavigation.SIDE: return "队列目标超出楼层范围"
	var proxy: Dictionary = ConvoyTrail.proxy(world,movement)
	var origin: Vector2 = goal+Vector2.ONE*float(movement.convoy.shift)
	var blocked_bed: String=space.bed_destination_blocker(world,str(movement.actor_id),floor_id,space._actor_rect(proxy,origin),movement.members)
	if not blocked_bed.is_empty(): return "护理床岗位已有使用预约："+blocked_bed
	return space.navigation.structural_clearance(world,proxy,floor_id).sweep_reason(origin,origin)
