extends RefCounted

func run(content:HospitalContent)->Dictionary:
 var suite:RefCounted=load("res://tests/acceptance/space.gd").new();suite.content=content
 var rows:Array=[_case(suite,false),_case(suite,true)]
 var ok:bool=true
 for row:Dictionary in rows:ok=ok and row.ok
 return {"ok":ok,"cases":rows,"scope":"All local actions must arise from real request_move and actual blocked ticks. No local_move/detour is injected."}

func _case(suite:RefCounted,swap:bool)->Dictionary:
 var sim:HospitalSimulation=suite._fixture()
 var probe:RefCounted=load("res://tests/acceptance/unified_local_behavior.gd").new()
 var a:String="z" if swap else "a";var b:String="a" if swap else "z"
 suite._add_actor(sim,a,"S49",[40,70]);suite._add_actor(sim,b,"S49",[39.4,70])
 # Both routes meet actual front bodies; each side and the intended reverse
 # are occupied. This previously prevented a retreat intention from existing.
 suite._add_actor(sim,"front_a","S49",[40.6,70]);suite._add_actor(sim,"front_b","S49",[38.8,70])
 var side_starts:Dictionary={"upper_a":[40,69.3],"upper_b":[39.4,69.3],"lower_a":[40,70.7],"lower_b":[39.4,70.7]}
 var side_goals:Dictionary={"upper_a":[40,66],"upper_b":[39.4,66],"lower_a":[40,74],"lower_b":[39.4,74]}
 for id:String in side_starts:suite._add_actor(sim,id,"S49",side_starts[id])
 var ids:Array=[a,b,"front_a","front_b"]+side_starts.keys()
 var goals:Dictionary={a:[45,70],b:[35,70]}
 var requests:Array=[sim.space.request_move(sim.world,a,1,goals[a]),sim.space.request_move(sim.world,b,1,goals[b])]
 var sequences:Dictionary={a:sim.world.facts.moves[a].request_sequence,b:sim.world.facts.moves[b].request_sequence}
 var reservations:Dictionary=sim.world.facts.adaptations.duplicate(true)
 var saw_a:bool=false;var saw_b:bool=false;var both_before_release:bool=false;var released:bool=false;var kept:bool=true;var fixed:bool=true;var errors:Array=[];var release_errors:Array=[];var trace:Array=[];var ticks:int=0
 for tick:int in 300:
  var error:String=probe._tick(suite,sim,ids);ticks=tick+1
  if not error.is_empty():errors.append(error);break
  var ma:Dictionary=sim.world.facts.moves.get(a,{})
  var mb:Dictionary=sim.world.facts.moves.get(b,{})
  var la:Dictionary=ma.get("local_move",{});var lb:Dictionary=mb.get("local_move",{})
  # Observe direction of the actual pending target, not a phase label.
  var retreat_a:bool=not la.is_empty() and float(la.target.cell[0])<float(sim.world.facts.actors[a].location.cell[0])-0.001
  var retreat_b:bool=not lb.is_empty() and float(lb.target.cell[0])>float(sim.world.facts.actors[b].location.cell[0])+0.001
  saw_a=saw_a or retreat_a;saw_b=saw_b or retreat_b
  if retreat_a and retreat_b and not released:
   both_before_release=true
   for id:String in side_goals:
    release_errors.append(sim.space.request_move(sim.world,id,1,side_goals[id]))
    goals[id]=side_goals[id]
    if sim.world.facts.moves.has(id):sequences[id]=sim.world.facts.moves[id].request_sequence
   released=true
  for id:String in goals:
   var move:Dictionary=sim.world.facts.moves.get(id,{})
   kept=kept and (sim.space.at(sim.world,id,1,goals[id]) if move.is_empty() else move.target_cell==goals[id] and move.request_sequence==sequences.get(id,-1))
  kept=kept and reservations==sim.world.facts.adaptations
  fixed=fixed and sim.space.at(sim.world,"front_a",1,[40.6,70]) and sim.space.at(sim.world,"front_b",1,[38.8,70]) and not sim.world.facts.moves.has("front_a") and not sim.world.facts.moves.has("front_b")
  if tick%10==0:trace.append({"tick":tick,"a":sim.world.facts.actors[a].location.cell.duplicate(),"b":sim.world.facts.actors[b].location.cell.duplicate(),"local_a":la.duplicate(true),"local_b":lb.duplicate(true)})
  if sim.world.facts.moves.is_empty():break
 var arrived:bool=sim.world.facts.moves.is_empty()
 for id:String in goals:arrived=arrived and sim.space.at(sim.world,id,1,goals[id])
 var release_ok:bool=true
 for error:String in release_errors:release_ok=release_ok and error.is_empty()
 var checks:Dictionary={"requests":requests==["",""],"safe_steps_and_world":errors.is_empty(),"both_retreats_created_by_actual_collision":saw_a and saw_b and both_before_release,"side_bodies_released_only_by_real_requests":released and release_ok,"all_requested_actors_arrived":arrived,"goals_sequences_reservations":kept,"fixed_front_bodies_not_displaced":fixed}
 var ok:bool=true
 for value:bool in checks.values():ok=ok and value
 var result:Dictionary={"case":"natural_dual_retreat_swapped_ids" if swap else "natural_dual_retreat","ok":ok,"checks":checks,"ticks":ticks,"errors":errors,"release_errors":release_errors,"trace":trace,"remaining":sim.world.facts.moves.duplicate(true)}
 sim.dispose();return result
