class_name LiftGroupReroute
extends RefCounted

const Landing = preload("res://game/building/lift_landing_queue.gd")

# Called only after an empty car has rejected its actual complete FIFO head.
# Quotes are read-only; no owner changes until every route is proved together.
static func try_route(space: HospitalSpace, world: WorldState, connection: Dictionary, entry: Dictionary) -> Dictionary:
	var owners: Array=entry.get("leader_ids",[entry.actor_id])
	for owner: String in owners:
		var m: Dictionary=world.facts.moves.get(owner,{})
		var a: Dictionary=world.facts.actors.get(owner,{})
		if m.is_empty() or a.is_empty(): return _blocked(entry,"同行组原移动义务已变化")
		if a.location.kind!="floor" or a.get("posture","standing")!="standing" or a.has("support_facility_id") or float(a.location.get("height_m",0))!=0: return _blocked(entry,"等待同行组全部真实落地")
		if m.has("local_move") or m.has("detour") or m.has("lift_boarding_call") or m.get("route_pending",false) or m.get("convoy",{}).has("portal"): return _blocked(entry,"等待当前安全移动或登离舱段完成")
		if int(m.cursor)<m.path.size() and m.path[int(m.cursor)].kind=="support_exit": return _blocked(entry,"等待真实离床完成")
		for member: String in m.get("members",[owner]):
			var body: Dictionary=world.facts.actors[member]
			if body.location.kind!="floor" or int(body.location.floor_id)!=int(a.location.floor_id): return _blocked(entry,"等待完整同行组落在同层")
	var signature: String=_signature(space,world,owners,entry)
	if entry.get("reroute_basis","")==signature:
		return {"ok":false,"blocked":true,"cached":true,"reason":entry.get("reroute_reason","完整同行组无可用跨层通路")}
	var controller: Script=load("res://game/building/lift_controller.gd")
	var original_empty: Dictionary=connection.duplicate();original_empty.passenger_groups=[]
	var original_fit: Dictionary=controller.placement(space,world,original_empty,entry)
	if original_fit.ok or original_fit.get("awaiting_companion",false): return _blocked(entry,"当前不是完整组空舱能力不足")
	var excluded: Array=[]
	for id: String in world.ids("connectors"):
		var candidate: Dictionary=world.facts.connectors[id]
		var definition: Dictionary=space.content.definition("vertical_connectors",candidate.definition_id)
		if definition.kind!="lift":
			# Independent clinical owners cannot be silently turned into a new
			# stair convoy. A single existing convoy retains its normal proof.
			excluded.append(id)
			continue
		var empty: Dictionary=candidate.duplicate();empty.passenger_groups=[]
		var fit: Dictionary=controller.placement(space,world,empty,entry)
		if not fit.ok: excluded.append(id)
	var route_filter: Dictionary={"excluded_connectors":excluded,"group_signature":signature}
	var quotes: Dictionary={}
	var common: Array=[]
	for owner: String in owners:
		var m: Dictionary=world.facts.moves[owner]
		var quote: Dictionary=space.route(world,owner,int(m.target_floor),m.target_cell,m.get("members",[]),m.get("offsets",{}),false,route_filter)
		if not quote.ok: return _remember(entry,signature,"完整同行组无可用跨层通路："+str(quote.get("reason","")))
		var chain: Array=[]
		for segment: Dictionary in quote.path:
			if segment.kind=="connector": chain.append([segment.connector_id,int(segment.from),int(segment.to)])
		if quotes.is_empty(): common=chain
		elif chain!=common: return _remember(entry,signature,"同行组没有共同的可用跨层连接路线，保持原义务等待")
		quotes[owner]=quote
	# Publish only after all independent original owners have compatible proofs.
	for owner: String in owners:
		var m: Dictionary=world.facts.moves[owner]
		m.path=quotes[owner].path.duplicate(true)
		m.cursor=0
		m.route_filter=route_filter.duplicate(true)
		m.route_pending=false
		m.blocked_since=-1
		for key: String in ["route_waypoint","lift_queue_target","lift_queue_standby","lift_queue_wait_basis","lift_capability_error","waiting_reason","route_retry_tick","route_capability_error","live_floor_route","rejoin_origin"]: m.erase(key)
		space.movement._route_checks.erase(owner)
		space.movement._route_failures.erase(owner)
		space.movement._pending_routes.erase(owner)
	Landing.remove(connection,str(entry.actor_id))
	return {"ok":true,"blocked":false,"reason":"完整同行组已改走共同可达路线","connector_chain":common,"excluded_connectors":excluded}

static func _blocked(entry: Dictionary, reason: String) -> Dictionary:
	entry.reroute_reason=reason
	return {"ok":false,"blocked":true,"reason":reason}

static func _remember(entry: Dictionary, signature: String, reason: String) -> Dictionary:
	entry.reroute_basis=signature
	return _blocked(entry,reason)

static func _signature(space: HospitalSpace, world: WorldState, owners: Array, entry: Dictionary) -> String:
	var floors: Array=[]
	var candidates: Dictionary={}
	for owner: String in owners:
		var m: Dictionary=world.facts.moves[owner]
		candidates.merge(HospitalTransit._routing_candidates(world,int(world.facts.actors[owner].location.floor_id),int(m.target_floor)))
	var floor_ids: Array=candidates.keys();floor_ids.sort()
	for floor_id: int in floor_ids:
		floors.append([floor_id,space._navigation.floor_static_version(space,world,floor_id)])
	var bodies: Array=[]
	for owner: String in owners:
		var m: Dictionary=world.facts.moves[owner]
		bodies.append([owner,m.get("request_sequence",0),m.target_floor,m.target_cell,m.get("members",[owner]),m.get("offsets",{}),m.get("convoy",{}),world.facts.actors[owner].location])
	for member: String in entry.members:
		bodies.append([member,space.body(world.facts.actors[member]),space.clearance(world.facts.actors[member])])
	return JSON.stringify([space.navigation.connection_basis(world),floors,bodies],"",true,true)
