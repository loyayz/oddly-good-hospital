extends RefCounted
func run(content:HospitalContent)->Dictionary:
 var helper:RefCounted=load("res://tests/acceptance/space.gd").new();helper.content=content
 var cases:Array=[_case(helper,true),_case(helper,false)]
 return {"ok":cases[0].ok and cases[1].ok,"cases":cases}
func _case(helper:RefCounted,pending:bool)->Dictionary:
 var sim:HospitalSimulation=helper._fixture()
 var origin:Array=[50.3999977,80.6000061]
 var actual:Array=[50.3999977,81.6000061]
 helper._add_actor(sim,"walker","S49",actual)
 var request:String=sim.space.request_move(sim.world,"walker",1,[49,81])
 var move:Dictionary=sim.world.facts.moves.get("walker",{})
 if move.is_empty():sim.dispose();return {"ok":false,"request":request}
 var sequence:int=move.request_sequence
 move.path=[{"kind":"floor","floor_id":1,"cell":[50,81]},{"kind":"floor","floor_id":1,"cell":[49,81]}];move.cursor=0
 if pending:
  move.route_pending=true;move.live_floor_route=true;move.rejoin_origin=origin.duplicate()
 else:
  move.route_pending=false
  move.local_move={"origin":origin.duplicate(),"target":{"kind":"floor","floor_id":1,"cell":actual.duplicate()}}
 var validation:String=sim.world.validate(helper.content)
 # Iterator contract is independently checked on an invocation-local copy.
 # Synthetic connector boundary is never installed into the actual journey.
 var scan:Dictionary={"path":move.path.duplicate(true),"search":{"previous":origin.duplicate(),"index":0}}
 scan.path.append({"kind":"connector","connector_id":"iterator_only","from":1,"to":2})
 scan.path.append({"kind":"floor","floor_id":2,"cell":[48,81]})
 var actor:Dictionary=sim.world.facts.actors.walker
 var first:Dictionary=sim.space.movement._next_rejoin_candidate(actor,scan)
 var second:Dictionary=sim.space.movement._next_rejoin_candidate(actor,scan)
 var before_stop:Dictionary=scan.duplicate(true)
 var stop:Dictionary=sim.space.movement._next_rejoin_candidate(actor,scan)
 var exact_candidates:bool=first.has("cell") and second.has("cell") and ConvoyTrail.point(first.cell)==Vector2(50,81) and ConvoyTrail.point(second.cell)==Vector2(49,81) and int(first.resume)==1 and int(second.resume)==2 and stop.is_empty() and scan==before_stop
 var observer:RefCounted=load("res://tests/acceptance/unified_local_behavior.gd").new()
 var restored:Dictionary=observer._restore_boundary(helper,sim,"walker",["walker"])
 var errors:Array=[];var trace:Array=[];var kept:bool=true;var hit_first:int=-1;var hit_goal:int=-1
 for tick:int in 160:
  var error:String=observer._tick(helper,sim,["walker"])
  if not error.is_empty():errors.append(error);break
  var position:Vector2=ConvoyTrail.point(actor.location.cell)
  if position==Vector2(50,81) and hit_first<0:hit_first=tick
  if position==Vector2(49,81) and hit_goal<0:hit_goal=tick
  move=sim.world.facts.moves.get("walker",{})
  if not move.is_empty():kept=kept and int(move.request_sequence)==sequence and int(move.target_floor)==1 and ConvoyTrail.point(move.target_cell)==Vector2(49,81)
  trace.append({"tick":tick,"position":actor.location.cell.duplicate(),"cursor":move.get("cursor",-1),"pending":move.get("route_pending",false)})
  if move.is_empty():break
 var arrived:bool=move.is_empty() and sim.space.at(sim.world,"walker",1,[49,81])
 var checks:Dictionary={"legal_input":request.is_empty() and validation.is_empty(),"only_original_endpoints_no_connector_crossing":exact_candidates,"json_restore_same_next_step":restored.get("ok",false),"actual_first_endpoint_then_goal":hit_first>=0 and hit_goal>hit_first,"original_goal_sequence":kept,"real_step_safety":errors.is_empty(),"final_arrival":arrived}
 var ok:bool=true
 for value:bool in checks.values():ok=ok and value
 var result:Dictionary={"ok":ok,"case":"fractional_diagonal_pending" if pending else "fractional_diagonal_completed_local","checks":checks,"validation":validation,"errors":errors,"iterator_candidates":[first,second,stop],"restore":restored,"hit_first":hit_first,"hit_goal":hit_goal,"trace":trace,"remaining":move.duplicate(true),"scope":"Explicit legal saved control boundary; diagonal original stub endpoint preserved, subsequent physical movement real. Connector stop is iterator-only, not a transit journey."}
 sim.dispose();return result
