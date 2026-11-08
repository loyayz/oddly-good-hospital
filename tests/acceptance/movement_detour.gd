extends RefCounted

# Explicit movement boundaries. Actors are placed only when declaring inputs;
# every tested retreat, side step, return and arrival is a real movement tick.
func run(suite: RefCounted) -> Dictionary:
 var rows: Array=[]
 rows.append(_head_on(suite,false))
 rows.append(_head_on(suite,true))
 rows.append(_head_on(suite,false,true))
 rows.append(_stationary(suite,false))
 rows.append(_stationary(suite,true))
 rows.append(_backward(suite,false,false))
 rows.append(_backward(suite,true,false))
 rows.append(_backward(suite,true,true))
 rows.append(_backward(suite,true,false,true))
 rows.append(_convoy_cannot_back_into_tail(suite))
 rows.append(_double_corner_rejoin(suite))
 rows.append(preload("res://tests/acceptance/detour_geometry_reuse.gd").new().run(suite))
 var ok: bool=true
 for row: Dictionary in rows: ok=ok and bool(row.ok)
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

func _head_on(suite: RefCounted, swap: bool, repeat_target: bool=false) -> Dictionary:
 var sim: HospitalSimulation=suite._fixture()
 var start_a: Array=[34,88] if not swap else [40,80]
 var start_b: Array=[34,92] if not swap else [42,80]
 var goal_a: Array=[34,94] if not swap else start_b
 var goal_b: Array=[34,66] if not swap else start_a
 suite._add_actor(sim,"a","S49",start_a)
 suite._add_actor(sim,"b","S49",start_b)
 var requests: Array=[sim.space.request_move(sim.world,"a",1,goal_a),sim.space.request_move(sim.world,"b",1,goal_b)]
 var sequences: Dictionary={"a":sim.world.facts.moves.a.request_sequence,"b":sim.world.facts.moves.b.request_sequence}
 var errors: Array=[];var unilateral: bool=true;var order_kept: bool=true;var bypass_seen: bool=false;var resumed_before_partner_finished: bool=false
 var samples: Dictionary={};var first_detouring: String="";var steps: int=0
 for tick: int in 350:
  if repeat_target:
   if sim.world.facts.moves.has("a"): sim.space.request_move(sim.world,"a",1,goal_a)
   if sim.world.facts.moves.has("b"): sim.space.request_move(sim.world,"b",1,goal_b)
  var before: Dictionary={}
  for id: String in ["a","b"]: before[id]=sim.world.facts.actors[id].location.cell.duplicate()
  var error: String=_tick(suite,sim,["a","b"])
  if not error.is_empty(): errors.append(error);break
  steps=tick+1
  var count: int=0
  for id: String in ["a","b"]:
   var move: Dictionary=sim.world.facts.moves.get(id,{})
   if move.is_empty(): continue
   order_kept=order_kept and move.request_sequence==sequences[id] and not move.has("yield_partner") and not move.get("yielding",false)
   if move.has("detour"):
    count+=1;bypass_seen=true
    if first_detouring.is_empty(): first_detouring=id
    var phase: String=move.detour.phase
    if not samples.has(phase): samples[phase]=_restore_boundary(suite,sim,id,["a","b"])
    if phase=="rejoin" and before[id]!=sim.world.facts.actors[id].location.cell and sim.world.facts.moves.has("b" if id=="a" else "a"): resumed_before_partner_finished=true
  unilateral=unilateral and count<=1
  if sim.world.facts.moves.is_empty(): break
 var arrived: bool=sim.space.at(sim.world,"a",1,goal_a) and sim.space.at(sim.world,"b",1,goal_b) and sim.world.facts.moves.is_empty()
 var saves_ok: bool=not samples.is_empty()
 for result: Dictionary in samples.values(): saves_ok=saves_ok and result.ok
 var dispatches: int=int(sim.space.query_counts.get("route_dispatches",0))
 var result: Dictionary={"case":"same_goal_reissued_every_tick" if repeat_target else "exchange_current_goals" if swap else "equal_head_on_long_other_journey","ok":requests==["",""] and errors.is_empty() and unilateral and order_kept and bypass_seen and resumed_before_partner_finished and arrived and saves_ok and dispatches==2,"requests":requests,"errors":errors,"one_actor_detours":unilateral,"original_sequences_preserved":order_kept,"local_detour_observed":bypass_seen,"resumed_while_other_still_moving":resumed_before_partner_finished,"both_arrived":arrived,"ticks":steps,"global_route_dispatches":dispatches,"restored_phases":samples,"remaining":sim.world.facts.moves.duplicate(true)}
 sim.dispose();return result

func _stationary(suite: RefCounted, release: bool) -> Dictionary:
 var sim: HospitalSimulation=suite._fixture()
 suite._add_actor(sim,"walker","S49",[35,70])
 var request: String=sim.space.request_move(sim.world,"walker",1,[45,70])
 suite._movement_tick(sim)
 var sequence: int=int(sim.world.facts.moves.walker.request_sequence)
 suite._add_actor(sim,"blocker","S49",[40,70])
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
   if move.has("detour"):
    var phase: String=move.detour.phase
    if not samples.has(phase): samples[phase]=_restore_boundary(suite,sim,"walker",["walker","blocker"])
    if release and not release_sent:
     release_error=sim.space.request_move(sim.world,"blocker",1,[40,67]);release_sent=true
    if phase=="rejoin" and choices.is_empty(): choices=move.detour.original_path[int(move.detour.resume_index)].cell.duplicate()
  if move.is_empty(): break
 var expected: Array=[40,70] if release else [41,70]
 var arrived: bool=not sim.world.facts.moves.has("walker") and sim.space.at(sim.world,"walker",1,[45,70])
 var saves_ok: bool=not samples.is_empty()
 for result: Dictionary in samples.values(): saves_ok=saves_ok and result.ok
 var dispatches: int=int(sim.space.query_counts.get("route_dispatches",0))
 var result: Dictionary={"case":"return_original_blocked_cell_when_freed" if release else "skip_occupied_return_to_first_reachable_successor","ok":request.is_empty() and errors.is_empty() and original and arrived and choices.size()==2 and rejoin.size()==2 and ConvoyTrail.point(choices).distance_to(ConvoyTrail.point(expected))<0.0001 and ConvoyTrail.point(rejoin).distance_to(ConvoyTrail.point(expected))<0.0001 and saves_ok and dispatches==(2 if release else 1) and release_error.is_empty(),"errors":errors,"original_goal_and_sequence":original,"rejoin_choice":choices,"actual_first_rejoin":rejoin,"expected_first_rejoin":expected,"arrived":arrived,"global_route_dispatches":dispatches,"release_error":release_error,"restored_phases":samples,"remaining":sim.world.facts.moves.duplicate(true)}
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
 var errors: Array=[];var back_seen: bool=false;var actual_back: bool=false;var released: bool=false;var before_back: float=0;var restored: Dictionary={};var initial: Array=sim.world.facts.actors.walker.location.cell.duplicate()
 for tick: int in 220:
  var before: Array=sim.world.facts.actors.walker.location.cell.duplicate()
  var error: String=_tick(suite,sim,ids)
  if not error.is_empty(): errors.append(error);break
  var move: Dictionary=sim.world.facts.moves.get("walker",{})
  if move.has("detour") and move.detour.phase=="back":
   back_seen=true
   if before_back==0: before_back=float(before[0])
   if restored.is_empty(): restored=_restore_boundary(suite,sim,"walker",ids)
  actual_back=actual_back or float(sim.world.facts.actors.walker.location.cell[0])<float(before[0])-0.001
  if actual_back and not released:
   sim.space.request_move(sim.world,"left",1,[36,68] if crossing_release else [40,67])
   sim.space.request_move(sim.world,"right",1,[36,73] if crossing_release else [40,74])
   released=true
  if sealed and tick==30: break
  if move.is_empty(): break
 var arrived: bool=not sim.world.facts.moves.has("walker") and sim.space.at(sim.world,"walker",1,[45,70])
 var unchanged: bool=sim.world.facts.actors.walker.location.cell==initial
 var ok: bool=request.is_empty() and errors.is_empty() and (unchanged and not actual_back if sealed else back_seen and actual_back and arrived and restored.get("ok",false))
 var result: Dictionary={"case":"second_mover_crosses_existing_detour" if crossing_release else "three_sides_sealed_waits_safely" if sealed else "fresh_start_without_history_checks_back" if no_history else "both_sides_blocked_retreats_before_bypass","ok":ok,"errors":errors,"back_phase_seen":back_seen,"actual_backward_step":actual_back,"actual_arrival":arrived,"sealed_position_unchanged":unchanged,"restored_back_phase":restored,"remaining":sim.world.facts.moves.duplicate(true)}
 sim.dispose();return result

func _restore_boundary(suite: RefCounted, sim: HospitalSimulation, id: String, ids: Array) -> Dictionary:
 var input: Dictionary=sim.world.freeze()
 var encoder: HospitalJsonStream=HospitalJsonStream.new()
 var path: String="user://movement-detour-current.json"
 if not encoder.encode(path,input,func(_bytes:int)->bool:return true): return {"ok":false,"error":encoder.error}
 var decoder: HospitalJsonStream=HospitalJsonStream.new()
 var decoded: Dictionary=decoder.decode(path,encoder.bytes,encoder.digest,func(_bytes:int)->bool:return true)
 if not decoded.ok: return {"ok":false,"error":decoder.error}
 var restored: WorldState=WorldState.new(decoded.value)
 var validation: String=restored.validate(suite.content)
 var exact: bool=restored.freeze()==input
 var a: HospitalSimulation=HospitalSimulation.new(WorldState.new(input.duplicate(true)),suite.content)
 var b: HospitalSimulation=HospitalSimulation.new(restored,suite.content)
 var first: String=_tick(suite,a,ids)
 var second: String=_tick(suite,b,ids)
 var continued: bool=first.is_empty() and second.is_empty() and a.world.freeze()==b.world.freeze()
 a.dispose();b.dispose()
 var rejected: Array=[];var accepted_bad: Array=[]
 var probes: Array=["bad_phase","empty_original","diagonal","nonfinite_direction","fractional_back_cursor","fractional_resume","huge_prefix","foreign_prefix","false_completed_prefix","pending_route","back_other_floor","bad_original_segment","missing_connector","old_yielding","old_partner"]
 if input.moves[id].detour.phase=="rejoin": probes.append_array(["wrong_rejoin_endpoint","changed_suffix"])
 for probe: String in probes:
  var snapshot: Dictionary=input.duplicate(true)
  var move: Dictionary=snapshot.moves[id]
  var state: Dictionary=move.detour
  match probe:
   "bad_phase": state.phase="winner"
   "empty_original": state.original_path=[]
   "diagonal": state.direction=[1,1]
   "nonfinite_direction": state.direction=[NAN,0]
   "fractional_back_cursor": state.back_cursor=-0.5
   "fractional_resume": state.resume_index=-0.5
   "huge_prefix": state.prefix_size=move.path.size()+1
   "foreign_prefix":
    if int(state.prefix_size)>0: move.path[0].floor_id=999
    else: state.prefix_size=1;move.path=[{"kind":"floor","floor_id":999,"cell":[40,70]}]
   "false_completed_prefix":
    state.phase="aside";state.resume_index=-1;state.prefix_size=1;move.cursor=1;move.path=[{"kind":"floor","floor_id":1,"cell":[60,70]}]
   "pending_route": move.route_pending=true
   "back_other_floor": state.backtrack=[{"kind":"floor","floor_id":999,"cell":[40,70]}];state.back_cursor=0
   "bad_original_segment": state.original_path[0]=false
   "missing_connector": state.original_path.append({"kind":"connector","connector_id":"missing","from":1,"to":2})
   "old_yielding": move.yielding=true
   "old_partner": move.yield_partner=id
   "wrong_rejoin_endpoint": move.path[int(state.prefix_size)-1]={"kind":"floor","floor_id":1,"cell":[60,70]}
   "changed_suffix": move.path.append({"kind":"floor","floor_id":1,"cell":[60,70]})
  var world: WorldState=WorldState.new(snapshot)
  var error: String=world.validate(suite.content)
  if error.is_empty(): accepted_bad.append(probe)
  else: rejected.append(probe)
 return {"ok":validation.is_empty() and exact and continued and accepted_bad.is_empty(),"phase":input.moves[id].detour.phase,"stream_exact":exact,"validation":validation,"same_safe_next_real_tick":continued,"next_errors":[first,second],"rejected_corrupt_states":rejected,"accepted_bad_states":accepted_bad}

func _convoy_cannot_back_into_tail(suite: RefCounted) -> Dictionary:
 var sim: HospitalSimulation=suite._fixture()
 suite._add_actor(sim,"head","S49",[44,82])
 suite._add_actor(sim,"tail","S49",[42,82])
 var request: String=sim.space.request_group_move(sim.world,"head",["head","tail"],{},1,[48,82])
 suite._movement_tick(sim)
 suite._add_actor(sim,"front","S49",[45.1,82])
 suite._add_actor(sim,"left","S49",[44.2,81])
 suite._add_actor(sim,"right","S49",[44.2,83])
 var original: Dictionary=sim.world.facts.moves.head.convoy.duplicate(true)
 var frozen: Dictionary=sim.world.freeze()
 var back_target: Array=[float(sim.world.facts.actors.head.location.cell[0])-2.0,82.0]
 var rejects_tail: bool=not sim.space.movement._detour_path_clear(sim.world,sim.world.facts.actors.head,sim.world.facts.moves.head,[{"kind":"floor","floor_id":1,"cell":back_target}])
 var query_readonly: bool=frozen==sim.world.freeze()
 var poses: Dictionary={"head":sim.world.facts.actors.head.location.duplicate(true),"tail":sim.world.facts.actors.tail.location.duplicate(true)}
 var safe: bool=true;var leader_only: bool=true;var errors: Array=[]
 for tick: int in 35:
  var count: int=int(sim.space.query_counts.get("convoy_leader_checks",0))
  var error: String=_tick(suite,sim,["head","tail","front","left","right"])
  if not error.is_empty(): errors.append(error);safe=false;break
  leader_only=leader_only and int(sim.space.query_counts.get("convoy_leader_checks",0))-count<=1
 var unchanged: bool=sim.world.facts.moves.has("head") and sim.world.facts.moves.head.convoy==original and sim.world.facts.actors.head.location==poses.head and sim.world.facts.actors.tail.location==poses.tail
 var dispatches: int=int(sim.space.query_counts.get("route_dispatches",0))
 var result: Dictionary={"case":"convoy_back_cannot_enter_own_tail","ok":request.is_empty() and safe and rejects_tail and query_readonly and leader_only and dispatches==1,"errors":errors,"blocked_group_positions_and_trail_unchanged":unchanged,"rejects_direct_reverse_into_own_tail":rejects_tail,"reverse_proof_readonly":query_readonly,"one_leader_check_per_tick":leader_only,"global_route_dispatches":dispatches}
 sim.dispose();return result

# A legal room entrance is around both an idle body and public furniture.
# Reaching its nearest original route cell needs bends on both axes; no
# global route request or displacement of the stationary actor is allowed.
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
   if movement.has("detour") and movement.detour.phase=="rejoin" and choice.is_empty():
    choice=movement.detour.original_path[int(movement.detour.resume_index)].cell.duplicate()
    restored=_restore_boundary(suite,sim,"walker",["walker","blocker","patient"])
  if tick%25==0 or movement.is_empty(): trace.append({"tick":tick,"position":sim.world.facts.actors.walker.location.cell.duplicate(),"phase":movement.get("detour",{}).get("phase","")})
  if movement.is_empty(): break
 var arrived: bool=sim.space.at(sim.world,"walker",1,[47,86]) and not sim.world.facts.moves.has("walker")
 var nearest: bool=choice.size()==2 and ConvoyTrail.point(choice).distance_to(Vector2(44,90))<0.0001
 var dispatches: int=int(sim.space.query_counts.get("route_dispatches",0))
 var result: Dictionary={"case":"nearest_return_around_furniture_and_entrance","ok":request.is_empty() and errors.is_empty() and exact and nearest and arrived and restored.get("ok",false) and dispatches>=1 and dispatches<=2,"request":request,"errors":errors,"original_goal_and_stationary_blocker_preserved":exact,"nearest_rejoin":choice,"arrived":arrived,"global_route_dispatches":dispatches,"restore":restored,"trace":trace,"original_path":original,"remaining":sim.world.facts.moves.duplicate(true)}
 sim.dispose();return result
