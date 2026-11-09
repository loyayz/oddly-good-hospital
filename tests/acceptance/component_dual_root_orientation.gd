extends RefCounted
func run(content:HospitalContent)->Dictionary:
 var h:RefCounted=load("res://tests/acceptance/space.gd").new();h.content=content
 var sim:HospitalSimulation=h._fixture()
 h._add_actor(sim,"walker","S49",[40.2,74.2]);h._add_actor(sim,"blocker","S49",[35,80])
 var actor:Dictionary=sim.world.facts.actors.walker;var blocker:Dictionary=sim.world.facts.actors.blocker
 var actual:=Vector2(40.2,74.2);var root:=Vector2(41,75);var next:=Vector2(42,75)
 var found:bool=false;var evidence:Dictionary={}
 # Search only fresh fixture inputs. All checks below use exact orientation-
 # changing first-step BodySweep, not just merged endpoint bounding boxes.
 for binding:Dictionary in content.catalog.treatment_bindings:
  var sample:Dictionary=actor.duplicate(true);sample.species_id=binding.species_id;sample.body_binding_id=binding.id;sample.facing=0.0
  if sim.space.clearance(sample)>2 or float(sim.space.body(sample).height_m)>6.5:continue
  var vertical:Dictionary=sample.duplicate();vertical.facing=0.0
  var horizontal:Dictionary=sample.duplicate();horizontal.facing=PI*0.5
  if sim.space._actor_rect(vertical,root).size==sim.space._actor_rect(horizontal,root).size:continue
  for ix:int in range(780,880):
   for iy:int in range(1460,1560):
    var pos:=Vector2(float(ix)/20.0,float(iy)/20.0)
    var body:Rect2=sim.space._actor_rect(blocker,pos)
    if sim.space._actor_rect(sample,actual).intersects(body,false):continue
    var first:Dictionary=_legs(sim,sample,actual,[Vector2(root.x,actual.y),root],body)
    if not first.clear:continue
    var second:Dictionary=_legs(sim,sample,actual,[Vector2(actual.x,root.y),root],body)
    if not second.clear:continue
    if first.facing==second.facing:continue
    var a:Dictionary=sample.duplicate();a.facing=first.facing
    var b:Dictionary=sample.duplicate();b.facing=second.facing
    var bad_step:Dictionary=_legs(sim,a,root,[next],body)
    var good_step:Dictionary=_legs(sim,b,root,[next],body)
    if bad_step.clear or not bad_step.get("first_blocked",false) or not good_step.clear:continue
    actor.species_id=binding.species_id;actor.body_binding_id=binding.id;actor.facing=0.0
    blocker.location.cell=[pos.x,pos.y]
    evidence={"binding":binding.id,"actual":[actual.x,actual.y],"root":[root.x,root.y],"next":[next.x,next.y],"blocker_cell":blocker.location.cell.duplicate(),"first_L":first,"second_L":second,"first_continuation_clear":false,"second_continuation_clear":true};found=true;break
   if found:break
  if found:break
 if not found:
  sim.dispose();return {"ok":false,"case":"dual_root_orientation","reason":"No genuine narrow-sweep witness found in fresh fixture grid; not covered."}
 sim.world.touch(false);sim.space.sync_actor(sim.world,"walker");sim.space.sync_actor(sim.world,"blocker")
 # Check the production stub collection itself, not only later reachability.
 var query:RouteClearance=sim.space.navigation.structural_clearance(sim.world,actor,1)
 var dynamic:Dictionary=sim.space._dynamic_route_query(sim.world,actor,1,[],{})
 var facts_before:Dictionary=sim.world.freeze()
 var choices:Array=sim.space.navigation._component_stubs(sim.world,actor,1,actual,root,query,dynamic,sim.space._actor_rect(actor,Vector2.ZERO))
 var expected_shapes:Array=[]
 for facing:float in [float(evidence.first_L.facing),float(evidence.second_L.facing)]:
  var expected_actor:Dictionary=actor.duplicate();expected_actor.facing=facing
  expected_shapes.append(sim.space._actor_rect(expected_actor,Vector2.ZERO))
 var stubs_match:bool=choices.size()==2 and expected_shapes[0]!=expected_shapes[1]
 var returned_shapes:Array=[];var stubs_report:Array=[]
 for choice:Dictionary in choices:
  stubs_match=stubs_match and choice.get("ok",false) and choice.shape in expected_shapes and choice.shape not in returned_shapes
  returned_shapes.append(choice.shape)
  var selected:Dictionary=actor.duplicate()
  selected.facing=float(evidence.first_L.facing) if choice.shape==expected_shapes[0] else float(evidence.second_L.facing)
  var end_cell:Array=choice.path.back().cell if not choice.path.is_empty() else []
  stubs_match=stubs_match and end_cell.size()==2 and ConvoyTrail.point(end_cell)==root
  stubs_report.append({"shape":str(choice.shape),"path":choice.path.duplicate(true),"expected_facing":selected.facing})
 stubs_match=stubs_match and sim.world.freeze()==facts_before
 evidence.production_stubs=stubs_report
 evidence.production_retains_both_distinct_shapes=stubs_match
 # Same original request, explicit pending checkpoint. Both prefixes remain
 # alternatives; test never installs either chosen path into production.
 var request:String=sim.space.request_move(sim.world,"walker",1,[45,75])
 var move:Dictionary=sim.world.facts.moves.get("walker",{})
 if move.is_empty():sim.dispose();return {"ok":false,"case":"dual_root_orientation","request":request,"evidence":evidence}
 var sequence:int=move.request_sequence
 move.path=[{"kind":"floor","floor_id":1,"cell":[45,75]}];move.cursor=0;move.route_pending=true;move.live_floor_route=true;move.rejoin_origin=[41,75]
 var validation:String=sim.world.validate(content)
 var observer:RefCounted=load("res://tests/acceptance/unified_local_behavior.gd").new()
 var errors:Array=[];var kept:bool=true;var trace:Array=[];var path:Array=[]
 for tick:int in 300:
  var error:String=observer._tick(h,sim,["walker","blocker"])
  if not error.is_empty():errors.append(error);break
  move=sim.world.facts.moves.get("walker",{})
  if not move.is_empty():
   kept=kept and move.request_sequence==sequence and ConvoyTrail.point(move.target_cell)==Vector2(45,75)
   if not move.get("route_pending",false) and path.is_empty():path=move.path.duplicate(true)
  kept=kept and ConvoyTrail.point(blocker.location.cell)==ConvoyTrail.point(evidence.blocker_cell) and not sim.world.facts.moves.has("blocker")
  trace.append({"tick":tick,"cell":actor.location.cell.duplicate(),"facing":actor.facing})
  if move.is_empty():break
 var result:Dictionary={"ok":stubs_match and request.is_empty() and validation.is_empty() and errors.is_empty() and kept and move.is_empty() and sim.space.at(sim.world,"walker",1,[45,75]),"case":"dual_root_orientation","evidence":evidence,"validation":validation,"errors":errors,"selected_path":path,"trace":trace,"scope":"Both L prefixes and continuation difference verified by real body sweep geometry; final displacement is real movement. Open-floor case does not alone prove that every alternate virtual root is unusable."}
 sim.dispose();return result
func _legs(sim:HospitalSimulation,actor:Dictionary,start:Vector2,points:Array,obstacle:Rect2)->Dictionary:
 var sample:Dictionary=actor.duplicate();var current:Vector2=start;var records:Array=[]
 for target:Vector2 in points:
  if target==current:continue
  var before:Rect2=sim.space._actor_rect(sample,current)
  sample.facing=atan2(target.x-current.x,target.y-current.y)
  var first:Vector2=sim.space.movement._step_toward(current,target,sim.space.walking_speed(sample)*WorldState.TICK_SECONDS)
  var turn:Rect2=sim.space._actor_rect(sample,first);var end:Rect2=sim.space._actor_rect(sample,target)
  var first_hit:bool=BodySweep.intersects(before,turn,obstacle,obstacle)
  var hit:bool=first_hit or BodySweep.intersects(turn,end,obstacle,obstacle)
  records.append({"from":[current.x,current.y],"to":[target.x,target.y],"before":str(before),"turn":str(turn),"end":str(end),"blocked":hit})
  if hit:return {"clear":false,"first_blocked":first_hit,"facing":sample.facing,"legs":records}
  current=target
 return {"clear":true,"facing":sample.facing,"legs":records}
