extends RefCounted

func run(content:HospitalContent)->Dictionary:
 var suite:RefCounted=load("res://tests/acceptance/space.gd").new();suite.content=content
 var observer:RefCounted=load("res://tests/acceptance/unified_local_behavior.gd").new()
 var sim:HospitalSimulation=suite._fixture()
 suite._add_actor(sim,"walker","S49",[35,70])
 var request:String=sim.space.request_move(sim.world,"walker",1,[45,70])
 suite._movement_tick(sim)
 var sequence:int=int(sim.world.facts.moves.walker.request_sequence)
 suite._add_actor(sim,"blocker","S49",[40,70])
 var edited:bool=false;var safe:bool=true;var kept:bool=true;var errors:Array=[];var boundary:Dictionary={};var restored:Dictionary={};var trace:Array=[]
 var wall:Rect2=Rect2(42,70,1,1)
 for tick:int in 300:
  var move:Dictionary=sim.world.facts.moves.get("walker",{})
  var actor:Dictionary=sim.world.facts.actors.walker
  # Observe a real arrival before the next advance invokes _local_resume.
  if not edited and move.has("local_move") and move.local_move.has("rejoin") and actor.location.cell==move.local_move.rejoin.cell and actor.location.cell==move.local_move.target.cell:
   boundary={"cell":actor.location.cell.duplicate(),"move":move.duplicate(true)}
   HospitalFactory._put_cell(sim.world.facts.floors.overrides["1"].blocked,[42,70]);sim.world.touch()
   edited=true
   restored=observer._restore_boundary(suite,sim,"walker",["walker","blocker"])
  var before:Rect2=sim.space.body_rectangle(actor)
  var error:String=observer._tick(suite,sim,["walker","blocker"])
  if not error.is_empty():errors.append(error);break
  var after:Rect2=sim.space.body_rectangle(actor)
  if edited:safe=safe and not after.intersects(wall,false) and not BodySweep.intersects(before,after,wall,wall)
  move=sim.world.facts.moves.get("walker",{})
  if not move.is_empty():kept=kept and move.target_cell==[45,70] and int(move.request_sequence)==sequence
  if edited:trace.append({"tick":tick,"cell":actor.location.cell.duplicate(),"pending":move.get("route_pending",false),"local":move.get("local_move",{}).duplicate(true)})
  if move.is_empty():break
 var checks:Dictionary={"real_rejoin_boundary_observed":edited and ConvoyTrail.point(boundary.get("cell",[0,0]))==Vector2(41,70),"request_succeeded":request.is_empty(),"no_static_swept_crossing":safe,"valid_safe_actual_steps":errors.is_empty(),"original_goal_sequence_preserved":kept,"save_restore_next_step_identical":restored.get("ok",false),"rerouted_and_arrived":sim.space.at(sim.world,"walker",1,[45,70]) and not sim.world.facts.moves.has("walker"),"stationary_blocker_unchanged":sim.space.at(sim.world,"blocker",1,[40,70])}
 var ok:bool=true
 for value:bool in checks.values():ok=ok and value
 var result:Dictionary={"ok":ok,"checks":checks,"boundary":boundary,"restore":restored,"errors":errors,"trace":trace,"remaining":sim.world.facts.moves.duplicate(true)}
 sim.dispose();return result
