extends RefCounted
func run(content:HospitalContent)->Dictionary:
 var helper:RefCounted=load("res://tests/acceptance/space.gd").new();helper.content=content
 var sim:HospitalSimulation=helper._fixture()
 helper._add_actor(sim,"walker","S49",[35,70]);helper._add_actor(sim,"occupant","S49",[40,70])
 var request:String=sim.space.request_move(sim.world,"walker",1,[40,70])
 var move:Dictionary=sim.world.facts.moves.get("walker",{})
 if move.is_empty():sim.dispose();return {"ok":false,"request":request,"reason":"No real move request created."}
 var sequence:int=int(move.request_sequence)
 # Explicit legal pending input; only original candidate is occupied [40,70].
 # Neither occupancy nor collision contacts are fabricated after this boundary.
 move.path=[{"kind":"floor","floor_id":1,"cell":[40,70]}];move.cursor=0
 move.route_pending=true;move.live_floor_route=true;move.rejoin_origin=[39,70]
 var validation:String=sim.world.validate(content)
 var observer:RefCounted=load("res://tests/acceptance/unified_local_behavior.gd").new()
 var nodes_start:int=int(sim.space.query_counts.get("rejoin_component_nodes",0))
 var edges_start:int=int(sim.space.query_counts.get("rejoin_component_edges",0))
 var dispatch_ticks:Array=[];var trace:Array=[];var errors:Array=[];var preserved:bool=true;var zero_work:bool=true;var pending:bool=true
 for tick:int in 120:
  var before_dispatch:int=int(sim.space.query_counts.get("route_dispatches",0));var now:int=sim.world.sim_tick
  var error:String=observer._tick(helper,sim,["walker","occupant"])
  if not error.is_empty():errors.append(error);break
  move=sim.world.facts.moves.get("walker",{})
  var dispatched:int=int(sim.space.query_counts.get("route_dispatches",0))-before_dispatch
  if dispatched>0:dispatch_ticks.append(now)
  zero_work=zero_work and int(sim.space.query_counts.get("rejoin_component_nodes",0))==nodes_start and int(sim.space.query_counts.get("rejoin_component_edges",0))==edges_start
  pending=pending and move.get("route_pending",false) and move.get("live_floor_route",false)
  preserved=preserved and int(move.get("request_sequence",-1))==sequence and move.has("target_cell") and ConvoyTrail.point(move.target_cell)==Vector2(40,70) and sim.space.at(sim.world,"walker",1,[35,70]) and sim.space.at(sim.world,"occupant",1,[40,70]) and not sim.world.facts.moves.has("occupant")
  trace.append({"tick":now,"dispatches":dispatched,"nodes":sim.space.query_counts.get("rejoin_component_nodes",0),"edges":sim.space.query_counts.get("rejoin_component_edges",0),"retry":move.get("route_retry_tick",0)})
 var throttled:bool=dispatch_ticks.size()>=2 and dispatch_ticks.size()<=3
 for i:int in range(1,dispatch_ticks.size()):throttled=throttled and int(dispatch_ticks[i])-int(dispatch_ticks[i-1])==50
 var release:String=sim.space.request_move(sim.world,"occupant",1,[40,73])
 var release_trace:Array=[];var actual_clear_seen:bool=false
 for tick:int in 300:
  var error:String=observer._tick(helper,sim,["walker","occupant"])
  if not error.is_empty():errors.append(error);break
  var a:Dictionary=sim.world.facts.actors.walker;var b:Dictionary=sim.world.facts.actors.occupant
  var destination:Rect2=sim.space._actor_rect(a,Vector2(40,70))
  if not destination.intersects(sim.space.body_rectangle(b),false):actual_clear_seen=true
  move=sim.world.facts.moves.get("walker",{})
  if not move.is_empty():preserved=preserved and int(move.request_sequence)==sequence and ConvoyTrail.point(move.target_cell)==Vector2(40,70)
  release_trace.append({"tick":sim.world.sim_tick,"walker":a.location.cell.duplicate(),"occupant":b.location.cell.duplicate(),"pending":move.get("route_pending",false)})
  if sim.world.facts.moves.is_empty():break
 var arrived:bool=sim.world.facts.moves.is_empty() and sim.space.at(sim.world,"walker",1,[40,70]) and sim.space.at(sim.world,"occupant",1,[40,73])
 var recomputed:bool=int(sim.space.query_counts.get("rejoin_component_nodes",0))>nodes_start
 var checks:Dictionary={"legal_pending":request.is_empty() and validation.is_empty(),"zero_BFS_nodes_and_edges_while_all_endpoints_occupied":zero_work,"pending_not_discarded":pending,"fifty_tick_retry_no_storm":throttled,"original_goal_sequence_and_initial_positions":preserved,"real_body_departure":release.is_empty() and actual_clear_seen,"fresh_component_after_release":recomputed,"both_actual_arrivals":arrived,"every_step_safe":errors.is_empty()}
 var ok:bool=true
 for value:bool in checks.values():ok=ok and value
 var result:Dictionary={"ok":ok,"checks":checks,"validation":validation,"errors":errors,"dispatch_ticks":dispatch_ticks,"blocked_trace":trace,"release_trace":release_trace,"release_reason":release,"final_moves":sim.world.facts.moves.duplicate(true),"scope":"Real occupied sole original endpoint, explicit pending boundary, real occupant departure and subsequent safe movement; no cross-tick failure cache."}
 sim.dispose();return result
