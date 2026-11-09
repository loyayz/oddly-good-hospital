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
 var before:Dictionary=sim.world.freeze()
 var sequence:int=int(move.request_sequence)
 var rejected:bool=true
 for direction:Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.DOWN,Vector2.UP]:
  rejected=rejected and not sim.space.movement._local_choose(sim.world,actor,move,direction)
 var unchanged:bool=before==sim.world.freeze()
 var ticket:Dictionary=move.transit_ticket.duplicate(true)
 var safe:bool=sim.world.validate(content).is_empty()
 var ordered:bool=true;var boarded:bool=false;var errors:Array=[]
 var dispatch_start:int=int(sim.space.query_counts.route_dispatches)
 var wait_preserved:bool=true
 for wait_tick:int in 12:
  suite._movement_tick(sim)
  var waiting:Dictionary=sim.world.facts.moves.get("traveler",{})
  wait_preserved=wait_preserved and not waiting.has("local_move") and int(waiting.get("request_sequence",-1))==sequence
 var no_repeat_dispatch:bool=int(sim.space.query_counts.route_dispatches)==dispatch_start
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
 var checks:Dictionary={"real_queue_setup":boarding and request.is_empty() and queued,"connector_owned_local_rejected":rejected,"queue_reservation_goal_all_facts_untouched_at_boundary":unchanged,"blocked_exit_wait_preserved":wait_preserved,"no_every_tick_replan":no_repeat_dispatch,"restored_boundary":restored.get("ok",false),"release_requested":release.is_empty(),"valid_every_actual_tick":safe,"same_goal_order_ticket":ordered,"actually_boarded":boarded,"actually_arrived":sim.space.at(sim.world,"traveler",2,[44,84]) and not sim.world.facts.moves.has("traveler")}
 var ok:bool=true
 for value:bool in checks.values():ok=ok and value
 var result:Dictionary={"ok":ok,"scope":"Real waiting/boarding/arrival plus direct local-intent boundary test; not a naturally produced retreat contact.","checks":checks,"restore":restored,"ticket":ticket,"errors":errors,"remaining":sim.world.facts.moves.duplicate(true)}
 sim.dispose();return result
