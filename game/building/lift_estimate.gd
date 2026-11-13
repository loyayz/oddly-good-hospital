class_name LiftEstimate
extends RefCounted

# A finite, conditional itinerary over a private snapshot, not a reservation.
# No simulation, landing sync, release, RNG, receipt or real movement is run.
static func unknown(reason: String) -> Dictionary:
 return {"ok":false,"status":"estimate_unknown","reason":reason}

static func quote(space: HospitalSpace, world: WorldState, connection: Dictionary, actor_id: String, from: int, to: int, at_landing: int, members: Array=[], _offsets: Dictionary={}) -> Dictionary:
 if at_landing<0: return unknown("到队时间未知")
 var c: Dictionary=connection.duplicate(true)
 var snapshot: WorldState=WorldState.new(world.freeze())
 var ids: Array=members.duplicate() if not members.is_empty() else [actor_id]
 var query: Dictionary={}
 for g: Dictionary in c.passenger_groups:
  if actor_id in g.members or g.get("pending_boarding",[]).any(func(p:Dictionary)->bool:return p.actor_id==actor_id): query=g;break
 var aboard: bool=not query.is_empty()
 var enqueued: bool=aboard
 if not aboard:
  for key: String in c.landing_queues:
   for g: Dictionary in c.landing_queues[key]:
    if actor_id in g.members: query=g;enqueued=true;break
 if query.is_empty():
  if ids.size()!=1 and not snapshot.facts.moves.get(actor_id,{}).has("convoy"): return unknown("同行组尚无可核对的实际移动拥有者")
  query={"actor_id":actor_id,"leader_ids":[actor_id],"members":ids,"floor_id":from,"destination":to,"direction":signi(to-from),"arrived_tick":world.sim_tick+at_landing,"owner_cells":{},"cell":connection.anchor.duplicate()}
  if not snapshot.facts.moves.has(actor_id): snapshot.facts.moves[actor_id]={"actor_id":actor_id}
 var query_id: String=query.actor_id
 if aboard: from=int(query.from);to=int(query.to)
 var elapsed: int=0
 var boarded_at: int=0 if aboard else -1
 var empty_ticks: int=0
 var phases: Array=[]
 var total: int=c.passenger_groups.size()+1
 for line: Array in c.landing_queues.values(): total+=line.size()
 # Every event boards/unloads a known group or moves to a finite demanded
 # floor. Repetition cannot silently turn into an unbounded ETA calculation.
 var seen: Dictionary={}
 for event: int in maxi(32,total*16+16):
  if not enqueued and elapsed>=at_landing:
   var key: String="%d:%d"%[from,signi(to-from)]
   if not c.landing_queues.has(key): c.landing_queues[key]=[]
   var occupied: Array=[]
   for line: Array in c.landing_queues.values():
    for queued: Dictionary in line:
     if int(queued.get("floor_id",-1))!=from: continue
     for owner: String in queued.get("leader_ids",[queued.actor_id]):
      var cell: Array=queued.get("owner_cells",{}).get(owner,queued.get("cell",[]))
      if cell.is_empty(): return unknown("既有队位缺失")
      occupied.append(LiftController.Landing._body(space,snapshot,snapshot.facts.moves[owner],cell))
   var slots: Dictionary=LiftController.Landing._group_slots(space,snapshot,c,query,occupied,false)
   if slots.is_empty(): return unknown("查询者没有合法可达队位")
   query.owner_cells=slots.cells
   query.cell=slots.cells[query_id]
   c.landing_queues[key].append(query.duplicate(true));enqueued=true
  if c.phase in ["riding","empty_riding"]:
   var duration: int=int(c.remaining_ticks)
   if duration<0: return unknown("当前行驶余量无效")
   phases.append({"phase":c.phase,"from":c.from,"to":c.to,"ticks":duration})
   if c.phase=="empty_riding": empty_ticks+=duration
   elapsed=HospitalTransit._add(elapsed,duration);c.floor_id=c.to;c.phase="idle";c.remaining_ticks=0
   continue
  if c.phase in ["boarding","alighting"]:
   var g: Dictionary=LiftController.group(c,str(c.active_group))
   if g.is_empty(): return unknown("当前上下客组缺失")
   var duration: int=_phase_ticks(space,snapshot,c,g,c.phase,true)
   if c.phase=="alighting" and _ordinary_query(snapshot,g,actor_id) and _mixed(snapshot,g): duration=maxi(1,int(c.remaining_ticks))
   if duration<0: return unknown("当前上下客真实余程不可确定")
   if c.phase=="alighting" and not _exit_clear(space,snapshot,c,g): return unknown("当前下客出口被占用或阻挡")
   elapsed=HospitalTransit._add(elapsed,duration);phases.append({"phase":c.phase,"actor_id":g.actor_id,"ticks":duration})
   if c.phase=="alighting":
    c.passenger_groups.erase(g)
    if g.actor_id==query_id: return _result(world,elapsed,boarded_at,at_landing,empty_ticks,phases)
   else:
    # The projected manifest acquires companions only after the extra real
    # boarding stage has elapsed, never by mutating their real movement.
    for pending: Dictionary in g.get("pending_boarding",[]):
     g.leader_ids.append(pending.actor_id);g.members.append(pending.actor_id)
     g.cabin_positions[pending.actor_id]=pending.cabin_positions[pending.actor_id]
    g.erase("pending_boarding")
    if g.actor_id==query_id and boarded_at<0: boarded_at=0
   c.phase="idle";c.active_group="";continue
  if elapsed<0: return unknown("交通预计超出可表示时间")
  var exits: Array=[]
  for g: Dictionary in c.passenger_groups:
   if int(g.to)==int(c.floor_id): exits.append(g)
  if not exits.is_empty():
   var g: Dictionary=exits[0]
   if not _exit_clear(space,snapshot,c,g): return unknown("已知乘员的目的层出口当前被占用或阻挡")
   var duration: int=_phase_ticks(space,snapshot,c,g,"alighting",false)
   if g.actor_id==query_id and _ordinary_query(snapshot,g,actor_id) and _mixed(snapshot,g): duration=HospitalTransit._alighting(space.content.definition("vertical_connectors",c.definition_id))
   if duration<0: return unknown("已知乘员离舱时间不可确定")
   elapsed=HospitalTransit._add(elapsed,duration);phases.append({"phase":"alighting","actor_id":g.actor_id,"floor":c.floor_id,"ticks":duration})
   c.passenger_groups.erase(g)
   if g.actor_id==query_id: return _result(world,elapsed,boarded_at,at_landing,empty_ticks,phases)
   continue
  var committed: bool=not c.passenger_groups.is_empty() and (c.get("pending_failure",false) or LiftController._service_blocked(c))
  var schedule: Dictionary=c.duplicate(true)
  if committed: schedule.landing_queues={}
  elif LiftController._service_blocked(c): return unknown("等待维修或升级完成，完成时间未知")
  elif c.get("pending_failure",false):
   c.failed=true;c.pending_failure=false;schedule.failed=true;schedule.pending_failure=false
  c.direction=-1 if c.get("failed",false) and not c.passenger_groups.is_empty() and not committed else LiftController.choose_direction(schedule)
  schedule.direction=c.direction
  var entry: Dictionary={} if committed else LiftController.head(c,int(c.floor_id),int(c.direction))
  if not entry.is_empty():
   var fit: Dictionary=LiftController.placement(space,snapshot,c,entry)
   if fit.ok:
    var approach: int=_approach_ticks(space,snapshot,c,entry)
    if approach<0: return unknown("队首到入口的实际通路或同行组会合时间不可确定")
    var duration: int=_phase_ticks(space,snapshot,c,entry,"boarding",false)
    if duration<0: return unknown("队首完整组登舱时间不可确定")
    var boarded: Dictionary=entry.duplicate(true)
    boarded.from=int(c.floor_id);boarded.to=int(entry.destination);boarded.cabin_positions=fit.positions;boarded.exclusive=fit.exclusive
    c.landing_queues["%d:%d"%[int(c.floor_id),int(c.direction)]].pop_front()
    c.passenger_groups.append(boarded)
    if entry.actor_id==query_id: boarded_at=elapsed+approach
    elapsed=HospitalTransit._add(elapsed,HospitalTransit._add(approach,duration))
    phases.append({"phase":"boarding","actor_id":entry.actor_id,"floor":c.floor_id,"approach_ticks":approach,"ticks":duration})
    continue
   if c.passenger_groups.is_empty(): return unknown(str(fit.get("reason","队首完整组不能登梯")))
  var target: int=LiftController.next_stop(schedule)
  if target==int(c.floor_id) and (not HospitalTransit._lowering(c) or c.passenger_groups.is_empty()):
   c.direction=-int(c.direction);schedule.direction=c.direction;target=LiftController.next_stop(schedule)
  if target==int(c.floor_id):
   if not enqueued:
    elapsed=maxi(elapsed,at_landing);continue
   return unknown("已知需求没有可完成的下一站")
  var signature: String=JSON.stringify([c.floor_id,c.direction,c.passenger_groups,c.landing_queues,enqueued])
  if seen.has(signature): return unknown("已知队列无法取得有限调度进展")
  seen[signature]=true
  var duration: int=HospitalTransit._travel_ticks(space,c,int(c.floor_id),target,committed)
  if duration<0: return unknown("交通行程时间不可确定")
  c.from=int(c.floor_id);c.to=target;c.remaining_ticks=duration;c.phase="empty_riding" if c.passenger_groups.is_empty() else "riding"
 return unknown("已知需求预测超过有限事件边界")

static func _ordinary_query(world: WorldState, g: Dictionary, actor_id: String) -> bool:
 return actor_id in g.get("leader_ids",[g.actor_id]) and not world.facts.moves.get(actor_id,{}).has("convoy")

static func _mixed(world: WorldState, g: Dictionary) -> bool:
 var convoy: bool=false
 var ordinary: bool=not g.get("pending_boarding",[]).is_empty()
 for owner: String in g.get("leader_ids",[g.actor_id]):
  if world.facts.moves.get(owner,{}).has("convoy"): convoy=true
  else: ordinary=true
 return convoy and ordinary

static func _phase_ticks(space: HospitalSpace, world: WorldState, c: Dictionary, g: Dictionary, phase: String, remainder: bool) -> int:
 var definition: Dictionary=space.content.definition("vertical_connectors",c.definition_id)
 var result: int=0
 var companions_stage: bool=remainder and phase=="alighting" and g.get("exit_stage","")=="companions"
 for owner: String in g.get("leader_ids",[g.actor_id]):
  if companions_stage and not world.facts.moves.get(owner,{}).has("convoy"): continue
  var ticks: int=HospitalTransit._unit_phase_ticks(space,world,c,owner,phase,remainder and not companions_stage)
  if ticks<0: return -1
  result=maxi(result,ticks)
 if companions_stage: return HospitalTransit._add(maxi(1,int(c.remaining_ticks)),result)
 if remainder: result=maxi(1,result)
 if phase=="boarding" and (not g.get("pending_boarding",[]).is_empty() or not remainder and _mixed(world,g)):
  result=HospitalTransit._add(result,HospitalTransit._boarding(definition))
 if phase=="alighting" and not remainder and _mixed(world,g):
  result=HospitalTransit._add(result,HospitalTransit._alighting(definition))
 return result

static func _exit_clear(space: HospitalSpace, world: WorldState, c: Dictionary, g: Dictionary) -> bool:
 for owner: String in g.get("leader_ids",[g.actor_id]):
  var m: Dictionary=world.facts.moves.get(owner,{})
  var proxy: Dictionary=c.duplicate(true)
  if not m.has("convoy"): proxy.anchor=g.get("entry_cells",{}).get(owner,c.anchor)
  if not HospitalTransit.egress_clear(space,world,proxy,owner,int(g.to),m.get("members",[owner]),m.get("offsets",{})): return false
 return true

static func _approach_ticks(space: HospitalSpace, world: WorldState, c: Dictionary, g: Dictionary) -> int:
 var result: int=0
 var offset: int=0
 var normal: Vector2i=LiftController.Landing._normal(c)
 var side: Vector2i=Vector2i(normal.y,-normal.x)
 for owner: String in g.get("leader_ids",[g.actor_id]):
  var actor: Dictionary=world.facts.actors[owner]
  var m: Dictionary=world.facts.moves.get(owner,{})
  if m.has("local_move") or m.has("detour"): return -1
  var start: Array=g.get("owner_cells",{}).get(owner,g.get("cell",c.anchor))
  if m.has("lift_boarding_call"):
   if m.get("route_pending",false) or actor.location.kind!="floor": return -1
   var point: Vector2=ConvoyTrail.point(actor.location.cell)
   var distance: float=0.0
   var reached: bool=false
   for index: int in range(int(m.get("cursor",0)),m.get("path",[]).size()):
    var segment: Dictionary=m.path[index]
    if segment.kind=="connector":
     reached=segment.connector_id==c.id
     break
    if segment.kind!="floor" or int(segment.floor_id)!=int(actor.location.floor_id): return -1
    var next: Vector2=ConvoyTrail.point(segment.cell)
    distance+=point.distance_to(next);point=next
   if not reached: return -1
   result=maxi(result,HospitalTransit.walking_ticks(space,actor,m.get("members",[owner]),distance))
   offset+=maxi(1,space.clearance(actor))
   continue
  var target: Array=[float(c.anchor[0])+side.x*offset,float(c.anchor[1])+side.y*offset]
  if m.has("convoy"):
   var plan: Dictionary=ConvoyPortal.plan(space,world,c,owner,m.members,m.convoy)
   if not plan.ok: return -1
   # A not-yet-released convoy must first align its full real trail. A
   # point shortest path cannot represent that; use the actual approach.
   if actor.location.kind!="floor" or ConvoyTrail.point(actor.location.cell).distance_to(ConvoyTrail.point(start))>0.001: return -1
   var proxy: Dictionary=ConvoyTrail.proxy(world,m)
   var approach: Dictionary=space.navigation._convoy_portal_approach(world,proxy,int(actor.location.floor_id),{"cell":ConvoyTrail.point(proxy.location.cell),"convoy":m.convoy},plan)
   if not approach.ok: return -1
   var point: Vector2=ConvoyTrail.point(proxy.location.cell)
   var distance: float=0.0
   for segment: Dictionary in approach.path:
    var next: Vector2=ConvoyTrail.point(segment.cell)
    distance+=point.distance_to(next);point=next
   result=maxi(result,HospitalTransit.walking_ticks(space,actor,m.members,distance))
   offset+=maxi(1,space.clearance(actor))
   continue
  if float(start[0])!=floorf(float(start[0])) or float(start[1])!=floorf(float(start[1])): return -1
  var route: Dictionary=space._floor_route(world,actor,int(g.get("floor_id",g.get("from",c.floor_id))),Vector2i(int(start[0]),int(start[1])),Vector2i(int(target[0]),int(target[1])),m.get("members",[owner]),{})
  if not route.get("ok",false): return -1
  var ticks: int=HospitalTransit.walking_ticks(space,actor,m.get("members",[owner]),float(route.walking_distance))
  result=maxi(result,ticks);offset+=maxi(1,space.clearance(actor))
 return result

static func _result(world: WorldState, elapsed: int, boarded: int, arrival: int, empty: int, phases: Array) -> Dictionary:
 return {"ok":true,"status":"complete","arrival_ticks":elapsed,"queue_ticks":maxi(0,boarded-arrival),"empty_ticks":empty,"group_ticks":elapsed-maxi(0,boarded),"quoted_tick":world.sim_tick,"reason":"","conditional":true,"assumptions":"仅按当前已知队列及查询者预计到队计算；无新增需求、未来人物通路畅通，不构成预约或到达保证","itinerary":phases}
