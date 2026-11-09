extends RefCounted
# Real transit queue setup and continuation; local-intent entry is invoked
# directly at that live boundary. This is NOT a synthetic full collision run.
func run(content:HospitalContent)->Dictionary:
 var suite:RefCounted=load("res://tests/acceptance/space.gd").new();suite.content=content
 var sim:HospitalSimulation=suite._transit_fixture()
 var id:String=suite._connection(sim)
 suite._add_actor(sim,"active","S49",[36,76])
 suite._add_actor(sim,"traveler","S49",[32,78])
 sim.space.request_move(sim.world,"active",2,[46,80])
 var boarding:bool=suite._wait(sim,func()->bool:return sim.world.facts.connectors[id].phase=="boarding",30,suite._movement_tick.bind(sim))
 suite._add_actor(sim,"exit_blocker","S49",[36,76],2)
 var request:String=sim.space.request_move(sim.world,"traveler",2,[44,84])
 var queued:bool=suite._wait(sim,func()->bool:return sim.world.facts.moves.get("traveler",{}).has("transit_ticket"),150,suite._movement_tick.bind(sim))
 var move:Dictionary=sim.world.facts.moves.get("traveler",{})
 var actor:Dictionary=sim.world.facts.actors.traveler
 var is_connector:bool=queued and int(move.cursor)<move.path.size() and move.path[int(move.cursor)].kind=="connector" and actor.location.kind=="floor"
 if not is_connector:
  var failure:Dictionary={"ok":false,"setup":false,"boarding":boarding,"queued":queued,"move":move.duplicate(true)}
  sim.dispose();return failure
 var sequence:int=int(move.request_sequence)
 var waiting_before:Dictionary=move.duplicate(true)
 var actor_before:Dictionary=actor.duplicate(true)
 var connector_before:Dictionary=sim.world.facts.connectors[id].duplicate(true)
 var reservations_before:Dictionary=sim.world.facts.adaptations.duplicate(true)
 var contact_case:Dictionary=_retreat_contact(suite,sim,actor)
 var rejected:bool=contact_case.get("ok",false)
 var unchanged:bool=move==waiting_before and actor==actor_before and sim.world.facts.connectors[id]==connector_before and sim.world.facts.adaptations==reservations_before
 var ticket:Dictionary=move.transit_ticket.duplicate(true)
 var safe:bool=sim.world.validate(content).is_empty()
 var ordered:bool=true;var boarded:bool=false;var errors:Array=[]
 var dispatch_start:int=int(sim.space.query_counts.route_dispatches)
 var wait_preserved:bool=true
 for wait_tick:int in 12:
  suite._movement_tick(sim)
  var waiting:Dictionary=sim.world.facts.moves.get("traveler",{})
  wait_preserved=wait_preserved and not waiting.has("local_move") and int(waiting.get("request_sequence",-1))==sequence
 var no_repeat_dispatch:bool=int(sim.space.query_counts.route_dispatches)-dispatch_start<=1
 var restored:Dictionary=load("res://tests/acceptance/unified_local_behavior.gd").new()._restore_boundary(suite,sim,"traveler",[])
 var release:String=sim.space.request_move(sim.world,"exit_blocker",2,[40,76])
 for tick:int in 750:
  suite._movement_tick(sim)
  var validation:String=sim.world.validate(content)
  if not validation.is_empty():errors.append(validation);safe=false;break
  move=sim.world.facts.moves.get("traveler",{})
  if not move.is_empty():
   ordered=ordered and int(move.request_sequence)==sequence and int(move.target_floor)==2 and ConvoyTrail.point(move.target_cell)==Vector2(44,84)
   if move.has("transit_ticket"):ordered=ordered and move.transit_ticket==ticket
   if int(move.cursor)<move.path.size() and move.path[int(move.cursor)].kind=="connector":safe=safe and not move.has("local_move")
  if actor.location.kind=="transit":boarded=true
  if sim.space.at(sim.world,"traveler",2,[44,84]) and move.is_empty():break
 var checks:Dictionary={"real_queue_setup":boarding and request.is_empty() and queued,"connector_owned_local_rejected":rejected,"queue_reservation_goal_all_facts_untouched_at_boundary":unchanged,"blocked_exit_wait_preserved":wait_preserved,"no_every_tick_replan":no_repeat_dispatch,"restored_boundary":restored.get("ok",false),"release_requested":release.is_empty(),"valid_every_actual_tick":safe,"same_goal_order_ticket":ordered,"actually_boarded":boarded,"actually_arrived":sim.space.at(sim.world,"traveler",2,[44,84]) and not sim.world.facts.moves.has("traveler"),"requester_arrived":sim.space.at(sim.world,"retreater",1,contact_case.get("goal",[0,0])) and not sim.world.facts.moves.has("retreater")}
 var ok:bool=true
 for value:bool in checks.values():ok=ok and value
 var result:Dictionary={"ok":ok,"scope":"Real queued traveler; caller-side route checkpoint and static edits are explicit fixture setup. Genuine _move_step contact then _local_collision; continuation uses real ticks.","checks":checks,"contact_case":contact_case,"restore":restored,"ticket":ticket,"errors":errors,"remaining":sim.world.facts.moves.duplicate(true)}
 sim.dispose();return result

func _retreat_contact(suite:RefCounted,sim:HospitalSimulation,waiting:Dictionary)->Dictionary:
 var landing:Vector2=ConvoyTrail.point(waiting.location.cell)
 var start:Vector2=landing+Vector2.RIGHT
 var goal:Array=[start.x+4,start.y]
 suite._add_actor(sim,"retreater","S49",[start.x,start.y])
 var request:String=sim.space.request_move(sim.world,"retreater",1,goal)
 sim.space.movement._dispatch_routes(sim.world,sim.world.present_actor_count())
 var move:Dictionary=sim.world.facts.moves.get("retreater",{})
 var actor:Dictionary=sim.world.facts.actors.retreater
 if move.is_empty() or move.get("route_pending",true):return {"ok":false,"reason":"Retreater route not ready","goal":goal}
 # Consume only already-reached start checkpoints, never a future position.
 while int(move.cursor)<move.path.size() and move.path[int(move.cursor)].kind=="floor" and ConvoyTrail.point(move.path[int(move.cursor)].cell)==start:move.cursor+=1
 var seq:int=int(move.request_sequence)
 var added:Array=[]
 var blocked:Array=sim.world.facts.floors.overrides["1"].blocked
 for x:int in range(int(start.x)-1,int(start.x)+6):
  for y:int in [int(start.y)-1,int(start.y)+1]:
   var cell:Array=[x,y]
   if not blocked.has(cell):blocked.append(cell);added.append(cell)
 var front:Array=[int(start.x)+1,int(start.y)]
 if not blocked.has(front):blocked.append(front);added.append(front)
 sim.world.touch()
 var picked:bool=sim.space.movement._local_choose(sim.world,actor,move,Vector2.RIGHT)
 var actual_contact:bool=false;var rejected_motion:bool=false;var try_return_false:bool=false;var ids:Array=[]
 if picked and move.get("local_move",{}).get("retreat",false):
  for attempt:int in 8:
   var before:Dictionary=actor.location.duplicate(true)
   var result:RefCounted=sim.space.movement._move_step(sim.world,actor,move,move.local_move.target)
   if result.blocked:
    ids=Array(result.blocker_actor_ids)
    actual_contact=ids.has(waiting.id)
    rejected_motion=actor.location==before and result.actual_motion==Vector2.ZERO
    # Test the real branch prerequisite; do not stub or forge a blocker list.
    try_return_false=not sim.space.movement._local_try_return(sim.world,actor,move)
    if try_return_false:sim.space.movement._local_collision(sim.world,actor,move,result)
    break
 var replanned:bool=move.get("route_pending",false) and not move.has("local_move") and int(move.request_sequence)==seq and ConvoyTrail.point(move.target_cell)==ConvoyTrail.point(goal)
 for cell:Array in added:blocked.erase(cell)
 sim.world.touch()
 return {"ok":request.is_empty() and picked and actual_contact and rejected_motion and try_return_false and replanned,"goal":goal,"selected":picked,"actual_contact":actual_contact,"blocker_ids":ids,"blocked_step_did_not_move":rejected_motion,"real_return_unavailable":try_return_false,"same_request_replanned":replanned}
