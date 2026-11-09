extends RefCounted

func run(content:HospitalContent)->Dictionary:
 var suite:RefCounted=load("res://tests/acceptance/space.gd").new();suite.content=content
 var rows:Array=[_case(suite,false),_case(suite,true)]
 var ok:bool=true
 for row:Dictionary in rows:ok=ok and row.ok
 return {"ok":ok,"cases":rows,"scope":"Equivalent straight original-route compression is declared before collision; bodies only move through real ticks."}

func _case(suite:RefCounted,release:bool)->Dictionary:
 var sim:HospitalSimulation=suite._fixture()
 var observer:RefCounted=load("res://tests/acceptance/unified_local_behavior.gd").new()
 suite._add_actor(sim,"walker","S49",[35,70])
 var request:String=sim.space.request_move(sim.world,"walker",1,[45,70])
 suite._movement_tick(sim)
 var move:Dictionary=sim.world.facts.moves.get("walker",{})
 if move.is_empty():sim.dispose();return {"case":"compressed_setup","ok":false,"reason":"Request did not establish a real journey"}
 var sequence:int=int(move.request_sequence)
 # An input-route representation change only: replace the remaining collinear
 # floor points with their identical terminal point. No actor is displaced.
 var collinear:bool=true
 for point:Dictionary in move.path.slice(int(move.cursor)):
  collinear=collinear and point.kind=="floor" and int(point.floor_id)==1 and float(point.cell[1])==70.0
 if not collinear:sim.dispose();return {"case":"compressed_setup","ok":false,"reason":"Fixture route not a straight line"}
 move.path=[{"kind":"floor","floor_id":1,"cell":[45,70]}];move.cursor=0
 var original:Array=move.path.duplicate(true)
 suite._add_actor(sim,"blocker","S49",[40,70])
 var expected:Array=[40,70] if release else [41,70]
 var errors:Array=[];var departed:bool=false;var rejoin:Array=[];var kept:bool=true;var no_skip:bool=true;var released:bool=false;var release_error:String="";var restored:Dictionary={};var trace:Array=[]
 for tick:int in 220:
  var error:String=observer._tick(suite,sim,["walker","blocker"])
  if not error.is_empty():errors.append(error);break
  move=sim.world.facts.moves.get("walker",{})
  var cell:Array=sim.world.facts.actors.walker.location.cell
  if float(cell[1])!=70.0:departed=true
  if departed and rejoin.is_empty() and float(cell[1])==70.0:rejoin=cell.duplicate()
  if not move.is_empty():
   kept=kept and move.target_cell==[45,70] and int(move.request_sequence)==sequence and move.path==original
   no_skip=no_skip and (int(move.cursor)==0 or sim.space.at(sim.world,"walker",1,[45,70]))
   if move.has("local_move"):
    if restored.is_empty():restored=observer._restore_boundary(suite,sim,"walker",["walker","blocker"])
    if release and not released:release_error=sim.space.request_move(sim.world,"blocker",1,[40,67]);released=true
  if tick%10==0 or not rejoin.is_empty():trace.append({"tick":tick,"position":cell.duplicate(),"cursor":move.get("cursor",-1),"local":move.get("local_move",{}).duplicate(true)})
  if sim.world.facts.moves.is_empty():break
 var checks:Dictionary={"request_succeeded":request.is_empty(),"safe_actual_steps":errors.is_empty(),"original_route_goal_sequence_preserved":kept,"segment_endpoint_not_skipped":no_skip,"nearest_actual_rejoin":rejoin.size()==2 and ConvoyTrail.point(rejoin).distance_to(ConvoyTrail.point(expected))<0.0001,"walker_arrived":sim.space.at(sim.world,"walker",1,[45,70]) and not sim.world.facts.moves.has("walker"),"dynamic_release_completed":not release or released and release_error.is_empty() and sim.space.at(sim.world,"blocker",1,[40,67]) and not sim.world.facts.moves.has("blocker"),"stationary_blocker_not_moved":release or sim.space.at(sim.world,"blocker",1,[40,70]) and not sim.world.facts.moves.has("blocker"),"restored_next_step_identical":restored.get("ok",false)}
 var ok:bool=true
 for value:bool in checks.values():ok=ok and value
 var result:Dictionary={"case":"compressed_freed_nearest" if release else "compressed_occupied_nearest_successor","ok":ok,"checks":checks,"errors":errors,"rejoin":rejoin,"expected":expected,"restore":restored,"trace":trace,"remaining":sim.world.facts.moves.duplicate(true)}
 sim.dispose();return result
