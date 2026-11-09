extends RefCounted
# Same established geometries, observed through actual motion and local_move.
# No tested actor is relocated; newly introduced blockers are input boundaries.
func run(content:HospitalContent)->Dictionary:
 var suite:RefCounted=load("res://tests/acceptance/space.gd").new();suite.content=content
 var rows:Array=[_stationary(suite,false),_stationary(suite,true),_stationary(suite,false,true),_backward(suite,true,false,true),_double_corner_rejoin(suite),_head_on_local(suite,false),_head_on_local(suite,true)]
 var ok:bool=true
 for row:Dictionary in rows:ok=ok and row.ok
 return {"ok":ok,"cases":rows}

func _tick(suite: RefCounted, sim: HospitalSimulation, ids: Array) -> String:
 var before: Dictionary={}
 for id: String in ids: before[id]=sim.space.body_rectangle(sim.world.facts.actors[id])
 suite._movement_tick(sim)
 for i: int in ids.size():
  var id: String=ids[i]
  var actor: Dictionary=sim.world.facts.actors[id]
  var after: Rect2=sim.space.body_rectangle(actor)
  if before[id].get_center().distance_to(after.get_center())>sim.space.walking_speed(actor)*WorldState.TICK_SECONDS+0.0001: return "Step exceeded real walking budget: "+id
  for j: int in range(i+1,ids.size()):
   var other: String=ids[j]
   var end: Rect2=sim.space.body_rectangle(sim.world.facts.actors[other])
   if after.intersects(end,false) or BodySweep.intersects(before[id],after,before[other],end): return "Body/swept overlap: "+id+"/"+other
 return sim.world.validate(suite.content)

func _stationary(suite: RefCounted, release: bool, fixed: bool=false) -> Dictionary:
 var sim: HospitalSimulation=suite._fixture()
 suite._add_actor(sim,"walker","S49",[35,70])
 var request: String=sim.space.request_move(sim.world,"walker",1,[45,70])
 suite._movement_tick(sim)
 var sequence: int=int(sim.world.facts.moves.walker.request_sequence)
 if fixed:
  suite._add_staff(sim,"blocker","nurse",[40,70])
  sim.services.development.ensure(sim.world)
  sim.services.scheduler.ensure(sim.world)
  sim.services.wellbeing.ensure(sim.world)
  sim.services.finance.ensure(sim.world)
  sim.world.facts.staff.blocker.active_job_id="floor_desk:protected"
 else:suite._add_actor(sim,"blocker","S49",[40,70])
 var departed: bool=false;var rejoin: Array=[];var errors: Array=[];var original: bool=true;var release_sent: bool=false;var release_error: String="";var choices: Array=[];var samples: Dictionary={}
 for tick: int in 180:
  var error: String=_tick(suite,sim,["walker","blocker"])
  if not error.is_empty(): errors.append(error);break
  var move: Dictionary=sim.world.facts.moves.get("walker",{})
  var cell: Array=sim.world.facts.actors.walker.location.cell
  if not is_equal_approx(float(cell[1]),70.0): departed=true
  if departed and rejoin.is_empty() and is_equal_approx(float(cell[1]),70.0): rejoin=cell.duplicate()
  if not move.is_empty():
   original=original and move.target_cell==[45,70] and int(move.request_sequence)==sequence
   if move.has("local_move"):
    var phase: String="pending" if not move.local_move.has("rejoin") else "return_target"
    if not samples.has(phase): samples[phase]=_restore_boundary(suite,sim,"walker",["walker","blocker"])
    if release and not release_sent:
     release_error=sim.space.request_move(sim.world,"blocker",1,[40,67]);release_sent=true
    if move.local_move.has("rejoin") and choices.is_empty(): choices=move.local_move.rejoin.cell.duplicate()
  if move.is_empty(): break
 var expected: Array=[40,70] if release else [41,70]
 var fixed_preserved:bool=not fixed or sim.space.at(sim.world,"blocker",1,[40,70]) and not sim.world.facts.moves.has("blocker") and sim.world.facts.staff.blocker.active_job_id=="floor_desk:protected"
 var arrived: bool=not sim.world.facts.moves.has("walker") and sim.space.at(sim.world,"walker",1,[45,70])
 var saves_ok: bool=not samples.is_empty()
 for result: Dictionary in samples.values(): saves_ok=saves_ok and result.ok
 var dispatches: int=int(sim.space.query_counts.get("route_dispatches",0))
 var result: Dictionary={"case":"fixed_post_not_moved" if fixed else "return_original_blocked_cell_when_freed" if release else "skip_occupied_return_to_first_reachable_successor","ok":fixed_preserved and request.is_empty() and errors.is_empty() and original and arrived and choices.size()==2 and rejoin.size()==2 and ConvoyTrail.point(choices).distance_to(ConvoyTrail.point(expected))<0.0001 and ConvoyTrail.point(rejoin).distance_to(ConvoyTrail.point(expected))<0.0001 and saves_ok and dispatches==(2 if release else 1) and release_error.is_empty(),"fixed_post_preserved":fixed_preserved,"errors":errors,"original_goal_and_sequence":original,"rejoin_choice":choices,"actual_first_rejoin":rejoin,"expected_first_rejoin":expected,"arrived":arrived,"global_route_dispatches":dispatches,"release_error":release_error,"restored_phases":samples,"remaining":sim.world.facts.moves.duplicate(true)}
 sim.dispose();return result

func _backward(suite: RefCounted, no_history: bool, sealed: bool, crossing_release: bool=false) -> Dictionary:
 var sim: HospitalSimulation=suite._fixture()
 var start: Array=[39.4,70] if no_history else [35,70]
 suite._add_actor(sim,"walker","S49",start)
 var request: String=sim.space.request_move(sim.world,"walker",1,[45,70])
 suite._movement_tick(sim)
 # Declare blockers only after the original route exists. No tested movement
 # or completed retreat is fabricated by this input boundary.
 suite._add_actor(sim,"front","S49",[40.2 if no_history else 40.0,70])
 suite._add_actor(sim,"left","S49",[39.6 if no_history else 39.4,69.3])
 suite._add_actor(sim,"right","S49",[39.6 if no_history else 39.4,70.7])
 var ids: Array=["walker","front","left","right"]
 if sealed:
  suite._add_actor(sim,"rear","S49",[39.0,70]);ids.append("rear")
 var expected_goals:Dictionary={"walker":[45,70]};var expected_sequences:Dictionary={"walker":sim.world.facts.moves.walker.request_sequence};var orders_kept:bool=true;var release_errors:Array=[]
 var errors: Array=[];var back_seen: bool=false;var actual_back: bool=false;var released: bool=false;var before_back: float=0;var restored: Dictionary={};var initial: Array=sim.world.facts.actors.walker.location.cell.duplicate()
 for tick: int in 220:
  var before: Array=sim.world.facts.actors.walker.location.cell.duplicate()
  var error: String=_tick(suite,sim,ids)
  if not error.is_empty(): errors.append(error);break
  var move: Dictionary=sim.world.facts.moves.get("walker",{})
  if move.has("local_move") and float(move.local_move.target.cell[0])<float(before[0])-0.001:
   back_seen=true
   if before_back==0: before_back=float(before[0])
   if restored.is_empty(): restored=_restore_boundary(suite,sim,"walker",ids)
  actual_back=actual_back or float(sim.world.facts.actors.walker.location.cell[0])<float(before[0])-0.001
  if actual_back and not released:
   expected_goals.left=[36,68] if crossing_release else [40,67]
   expected_goals.right=[36,73] if crossing_release else [40,74]
   for id:String in ["left","right"]:
    release_errors.append(sim.space.request_move(sim.world,id,1,expected_goals[id]))
    if sim.world.facts.moves.has(id):expected_sequences[id]=sim.world.facts.moves[id].request_sequence
   released=true
  if sealed and tick==30: break
  for id:String in expected_goals:
   var current:Dictionary=sim.world.facts.moves.get(id,{})
   orders_kept=orders_kept and (sim.space.at(sim.world,id,1,expected_goals[id]) if current.is_empty() else current.target_cell==expected_goals[id] and current.request_sequence==expected_sequences.get(id,-1))
  if sim.world.facts.moves.is_empty(): break
 var arrived: bool=not sim.world.facts.moves.has("walker") and sim.space.at(sim.world,"walker",1,[45,70])
 var all_arrived:bool=sim.world.facts.moves.is_empty()
 for id:String in expected_goals:all_arrived=all_arrived and sim.space.at(sim.world,id,1,expected_goals[id])
 var release_ok:bool=true
 for error:String in release_errors:release_ok=release_ok and error.is_empty()
 var unchanged: bool=sim.world.facts.actors.walker.location.cell==initial
 var ok: bool=request.is_empty() and errors.is_empty() and orders_kept and release_ok and (sealed or all_arrived) and (unchanged and not actual_back if sealed else back_seen and actual_back and arrived and restored.get("ok",false))
 var result: Dictionary={"case":"second_mover_crosses_existing_detour" if crossing_release else "three_sides_sealed_waits_safely" if sealed else "fresh_start_without_history_checks_back" if no_history else "both_sides_blocked_retreats_before_bypass","ok":ok,"all_movers_arrived":all_arrived,"orders_kept":orders_kept,"release_errors":release_errors,"errors":errors,"back_phase_seen":back_seen,"actual_backward_step":actual_back,"actual_arrival":arrived,"sealed_position_unchanged":unchanged,"restored_back_phase":restored,"remaining":sim.world.facts.moves.duplicate(true)}
 sim.dispose();return result

func _double_corner_rejoin(suite: RefCounted) -> Dictionary:
 var sim: HospitalSimulation=suite._fixture()
 HospitalFactory._add_room(sim.world,{"id":"corner_room","type":"physical","anchor":[42,84],"size":[6,6],"door":{"definition_id":"DR04","offset":2}},suite.content)
 HospitalFactory._add_facility(sim.world,{"id":"corner_workstation","definition_id":"FUR05","anchor":[43,92],"size":[2,1],"room_id":null},suite.content)
 HospitalFactory._add_facility(sim.world,{"id":"corner_chair","definition_id":"FUR09","anchor":[41,92],"size":[1,1],"room_id":null},suite.content)
 HospitalFactory._add_facility(sim.world,{"id":"corner_machine","definition_id":"M09","anchor":[45,85],"size":[2,2],"room_id":"corner_room"},suite.content)
 sim.world.touch()
 suite._add_actor(sim,"walker","S49",[40,91])
 var request: String=sim.space.request_move(sim.world,"walker",1,[47,86])
 suite._movement_tick(sim)
 var original: Array=sim.world.facts.moves.get("walker",{}).get("path",[]).duplicate(true)
 var sequence: int=int(sim.world.facts.moves.get("walker",{}).get("request_sequence",-1))
 suite._add_actor(sim,"blocker","S49",[44,91])
 suite._add_actor(sim,"patient","S49",[45,87])
 var errors: Array=[];var choice: Array=[];var exact: bool=true;var restored: Dictionary={};var trace: Array=[]
 for tick: int in 300:
  var error: String=_tick(suite,sim,["walker","blocker","patient"])
  if not error.is_empty(): errors.append(error);break
  var movement: Dictionary=sim.world.facts.moves.get("walker",{})
  exact=exact and sim.space.at(sim.world,"blocker",1,[44,91]) and not sim.world.facts.moves.has("blocker")
  if not movement.is_empty():
   exact=exact and int(movement.request_sequence)>=sequence and movement.target_cell==[47,86] and int(movement.target_floor)==1
   if movement.has("local_move") and movement.local_move.has("rejoin") and choice.is_empty():
    choice=movement.local_move.rejoin.cell.duplicate()
    restored=_restore_boundary(suite,sim,"walker",["walker","blocker","patient"])
  if tick%25==0 or movement.is_empty(): trace.append({"tick":tick,"position":sim.world.facts.actors.walker.location.cell.duplicate(),"local_move":movement.get("local_move",{}).duplicate(true)})
  if movement.is_empty(): break
 var arrived: bool=sim.space.at(sim.world,"walker",1,[47,86]) and not sim.world.facts.moves.has("walker")
 var nearest: bool=choice.size()==2 and ConvoyTrail.point(choice).distance_to(Vector2(44,90))<0.0001
 var dispatches: int=int(sim.space.query_counts.get("route_dispatches",0))
 var result: Dictionary={"case":"nearest_return_around_furniture_and_entrance","ok":request.is_empty() and errors.is_empty() and exact and nearest and arrived and restored.get("ok",false) and dispatches>=1 and dispatches<=2,"request":request,"errors":errors,"original_goal_and_stationary_blocker_preserved":exact,"nearest_rejoin":choice,"arrived":arrived,"global_route_dispatches":dispatches,"restore":restored,"trace":trace,"original_path":original,"remaining":sim.world.facts.moves.duplicate(true)}
 sim.dispose();return result

func _restore_boundary(suite:RefCounted,sim:HospitalSimulation,id:String,ids:Array)->Dictionary:
 var input:Dictionary=sim.world.freeze()
 var encoder:=HospitalJsonStream.new()
 var path:String="user://unified-local-behavior.json"
 if not encoder.encode(path,input,func(_bytes:int)->bool:return true):return {"ok":false,"error":encoder.error}
 var decoder:=HospitalJsonStream.new()
 var decoded:Dictionary=decoder.decode(path,encoder.bytes,encoder.digest,func(_bytes:int)->bool:return true)
 if not decoded.ok:return {"ok":false,"error":decoder.error}
 var restored:=WorldState.new(decoded.value)
 var validation:String=restored.validate(suite.content)
 var exact:bool=restored.freeze()==input
 var first:=HospitalSimulation.new(WorldState.new(input.duplicate(true)),suite.content)
 var second:=HospitalSimulation.new(restored,suite.content)
 var error_a:String=_tick(suite,first,ids)
 var error_b:String=_tick(suite,second,ids)
 var equal:bool=first.world.freeze()==second.world.freeze()
 first.dispose();second.dispose()
 return {"ok":validation.is_empty() and exact and error_a.is_empty() and error_b.is_empty() and equal,"stream_exact":exact,"validation":validation,"same_safe_next_real_tick":equal,"errors":[error_a,error_b],"local_move":input.moves.get(id,{}).get("local_move",{})}

func run_focus(content:HospitalContent)->Dictionary:
 var suite:RefCounted=load("res://tests/acceptance/space.gd").new();suite.content=content
 var rows:Array=[_stationary(suite,false,true),_head_on_local(suite,false),_head_on_local(suite,true)]
 var ok:bool=true
 for row:Dictionary in rows:ok=ok and row.ok
 return {"ok":ok,"cases":rows}

func _head_on_local(suite:RefCounted,swap:bool)->Dictionary:
 var sim:HospitalSimulation=suite._fixture()
 var a:String="z" if swap else "a";var b:String="a" if swap else "z"
 suite._add_actor(sim,a,"S49",[40,80]);suite._add_actor(sim,b,"S49",[42,80])
 var goals:Dictionary={a:[44,80],b:[38,80]}
 var requests:Array=[sim.space.request_move(sim.world,a,1,goals[a]),sim.space.request_move(sim.world,b,1,goals[b])]
 var sequences:Dictionary={a:sim.world.facts.moves[a].request_sequence,b:sim.world.facts.moves[b].request_sequence}
 var errors:Array=[];var one_local:bool=true;var observed:bool=false;var preserved:bool=true;var trace:Array=[];var ticks:int=0
 for tick:int in 160:
  var error:String=_tick(suite,sim,[a,b]);ticks=tick+1
  if not error.is_empty():errors.append(error);break
  var count:int=0
  for id:String in [a,b]:
   var move:Dictionary=sim.world.facts.moves.get(id,{})
   if move.has("local_move"):count+=1;observed=true
   preserved=preserved and (sim.space.at(sim.world,id,1,goals[id]) if move.is_empty() else move.target_cell==goals[id] and move.request_sequence==sequences[id] and not move.has("yield_partner") and not move.get("yielding",false))
  one_local=one_local and count<=1
  if count>1 or tick%10==0:trace.append({"tick":tick,"a":sim.world.facts.actors[a].location.cell.duplicate(),"b":sim.world.facts.actors[b].location.cell.duplicate(),"local_a":sim.world.facts.moves.get(a,{}).get("local_move",{}).duplicate(true),"local_b":sim.world.facts.moves.get(b,{}).get("local_move",{}).duplicate(true)})
  if sim.world.facts.moves.is_empty():break
 var arrived:bool=sim.world.facts.moves.is_empty() and sim.space.at(sim.world,a,1,goals[a]) and sim.space.at(sim.world,b,1,goals[b])
 var checks:Dictionary={"requests_succeeded":requests==["",""],"actual_steps_safe":errors.is_empty(),"only_one_actor_has_local_action":one_local,"local_action_observed":observed,"original_goals_sequences":preserved,"both_arrived":arrived}
 var ok:bool=true
 for value:bool in checks.values():ok=ok and value
 var result:Dictionary={"case":"head_on_swapped_ids" if swap else "head_on","ok":ok,"checks":checks,"ticks":ticks,"errors":errors,"trace":trace,"remaining":sim.world.facts.moves.duplicate(true)}
 sim.dispose();return result
