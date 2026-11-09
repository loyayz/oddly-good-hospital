extends RefCounted
func run(content:HospitalContent)->Dictionary:
 var h:RefCounted=load("res://tests/acceptance/space.gd").new();h.content=content
 var sim:HospitalSimulation=h._fixture()
 h._add_actor(sim,"walker","S49",[40,75]);h._add_actor(sim,"obstacle","S49",[35,80])
 var actor:Dictionary=sim.world.facts.actors.walker;var obstacle:Dictionary=sim.world.facts.actors.obstacle
 var found:bool=false;var evidence:Dictionary={}
 # Fresh fixture body selection only. No actor is moved during tested ticks.
 for binding:Dictionary in content.catalog.treatment_bindings:
  var sample:Dictionary=actor.duplicate(true);sample.species_id=binding.species_id;sample.body_binding_id=binding.id;sample.facing=PI
  if sim.space.clearance(sample)>2 or float(sim.space.body(sample).height_m)>6.5:continue
  var turned:Dictionary=sample.duplicate(true);turned.facing=PI*0.5
  var corner:=Vector2(40,74);var destination:=Vector2(41,74)
  var initial:Rect2=sim.space._actor_rect(sample,Vector2(40,75))
  var before:Rect2=sim.space._actor_rect(sample,corner)
  var fixed_end:Rect2=sim.space._actor_rect(sample,destination)
  var turned_end:Rect2=sim.space._actor_rect(turned,destination)
  if fixed_end.size==turned_end.size:continue
  var old_sweep:Rect2=before.merge(fixed_end);var turn_sweep:Rect2=before.merge(turned_end)
  var approach:Rect2=initial.merge(before)
  for ix:int in range(760,880):
   for iy:int in range(1420,1540):
    var point:=Vector2(float(ix)/20.0,float(iy)/20.0)
    var body:Rect2=sim.space._actor_rect(obstacle,point)
    if body.intersects(initial,false) or body.intersects(approach,false) or body.intersects(old_sweep,false) or not body.intersects(turn_sweep,false):continue
    actor.species_id=binding.species_id;actor.body_binding_id=binding.id;actor.facing=PI
    obstacle.location.cell=[point.x,point.y]
    evidence={"binding":binding.id,"obstacle_cell":obstacle.location.cell.duplicate(),"obstacle_body":str(body),"old_fixed_sweep":str(old_sweep),"real_turn_sweep":str(turn_sweep),"old_fixed_clear":true,"rotated_sweep_blocked":true,"initial_approach_clear":true}
    found=true;break
   if found:break
  if found:break
 if not found:
  sim.dispose();return {"ok":false,"case":"non_square_real_turn","reason":"No legal non-square witness in fresh fixture search; not covered."}
 sim.world.touch(false);sim.space.sync_actor(sim.world,"walker");sim.space.sync_actor(sim.world,"obstacle")
 var request:String=sim.space.request_move(sim.world,"walker",1,[45,74])
 var move:Dictionary=sim.world.facts.moves.walker;var sequence:int=move.request_sequence
 move.path=[{"kind":"floor","floor_id":1,"cell":[45,74]}];move.cursor=0;move.route_pending=true;move.live_floor_route=true;move.rejoin_origin=[40,74]
 var validation:String=sim.world.validate(content)
 var observer:RefCounted=load("res://tests/acceptance/unified_local_behavior.gd").new()
 var errors:Array=[];var kept:bool=true;var trace:Array=[];var returned_path:Array=[]
 for tick:int in 300:
  var error:String=observer._tick(h,sim,["walker","obstacle"])
  if not error.is_empty():errors.append(error);break
  move=sim.world.facts.moves.get("walker",{})
  if not move.is_empty():
   kept=kept and move.request_sequence==sequence and ConvoyTrail.point(move.target_cell)==Vector2(45,74)
   if not move.get("route_pending",false) and returned_path.is_empty():returned_path=move.path.duplicate(true)
  kept=kept and ConvoyTrail.point(obstacle.location.cell)==ConvoyTrail.point(evidence.obstacle_cell) and not sim.world.facts.moves.has("obstacle")
  trace.append({"tick":tick,"position":actor.location.cell.duplicate(),"facing":actor.facing,"pending":move.get("route_pending",false),"reason":move.get("waiting_reason","")})
  if move.is_empty():break
 var arrived:bool=move.is_empty() and sim.space.at(sim.world,"walker",1,[45,74])
 # This open-floor fixture must have an alternative; do not green a timeout as
 # "reasonable no route". A genuine no-path variant needs independent closure.
 var result:Dictionary={"ok":request.is_empty() and validation.is_empty() and kept and errors.is_empty() and arrived and not returned_path.is_empty(),"case":"non_square_real_turn_alternative","evidence":evidence,"validation":validation,"errors":errors,"arrived":arrived,"returned_path":returned_path,"trace":trace,"final_moves":sim.world.facts.moves.duplicate(true),"scope":"Fixed-angle edge counterexample, followed by real orientation-aware dispatch and movement; no synthetic displacement after initial input."}
 sim.dispose();return result
