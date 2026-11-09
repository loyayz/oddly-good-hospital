extends RefCounted
func run(content:HospitalContent)->Dictionary:
 var h:RefCounted=load("res://tests/acceptance/space.gd").new();h.content=content
 var cases:Array=[_first_step(h),_root(h)];return {"ok":cases[0].ok and cases[1].ok,"cases":cases}
func _first_step(h:RefCounted)->Dictionary:
 var sim:HospitalSimulation=h._fixture();h._add_actor(sim,"walker","S49",[40,74]);h._add_actor(sim,"blocker","S49",[35,80])
 var actor:Dictionary=sim.world.facts.actors.walker;var blocker:Dictionary=sim.world.facts.actors.blocker;var found:bool=false;var evidence:Dictionary={}
 for binding:Dictionary in h.content.catalog.treatment_bindings:
  var sample:Dictionary=actor.duplicate(true);sample.species_id=binding.species_id;sample.body_binding_id=binding.id;sample.facing=0.0
  if sim.space.clearance(sample)>2 or sim.space.body(sample).height_m>6.5:continue
  var turned:Dictionary=sample.duplicate(true);turned.facing=PI*0.5
  var start:=Vector2(40,74);var end:=Vector2(41,74)
  var first:Vector2=sim.space.movement._step_toward(start,end,sim.space.walking_speed(sample)*WorldState.TICK_SECONDS)
  var before:Rect2=sim.space._actor_rect(sample,start);var after:Rect2=sim.space._actor_rect(turned,end);var turn:Rect2=sim.space._actor_rect(turned,first)
  var old:Rect2=before.merge(after);var real:Rect2=before.merge(turn)
  for ix:int in range(760,860):
   for iy:int in range(1420,1540):
    var pos:=Vector2(float(ix)/20.0,float(iy)/20.0);var rect:Rect2=sim.space._actor_rect(blocker,pos)
    if rect.intersects(old,false) or not rect.intersects(real,false):continue
    # AABB overlap alone can be a corner-only false positive. Require the
    # same continuous rectangle narrow sweep used by real movement.
    if not BodySweep.intersects(before,turn,rect,rect):continue
    actor.species_id=binding.species_id;actor.body_binding_id=binding.id;actor.facing=0.0;blocker.location.cell=[pos.x,pos.y]
    evidence={"old_endpoint_merge_clear":true,"first_real_step_blocked":true,"before":str(before),"end":str(after),"first":str(turn),"blocker":str(rect),"binding":binding.id};found=true;break
   if found:break
  if found:break
 if not found:sim.dispose();return {"ok":false,"case":"first_rotation_step","reason":"No legal fresh-input witness found."}
 sim.world.touch(false);sim.space.sync_actor(sim.world,"walker");sim.space.sync_actor(sim.world,"blocker")
 var request:String=sim.space.request_move(sim.world,"walker",1,[41,74]);var move:Dictionary=sim.world.facts.moves.get("walker",{})
 if move.is_empty():sim.dispose();return {"ok":false,"case":"first_rotation_step","request_error":request}
 var before_facts:Dictionary=actor.duplicate(true)
 var contact:RefCounted=sim.space.movement._move_step(sim.world,actor,move,{"kind":"floor","floor_id":1,"cell":[41,74]})
 var dynamic:Dictionary=sim.space._dynamic_route_query(sim.world,actor,1,[],{})
 var turned:Dictionary=actor.duplicate();turned.facing=PI*0.5
 var allowed:bool=sim.space.movement._local_path_clear(sim.world,actor,[{"kind":"floor","floor_id":1,"cell":[41,74]}])
 var result:Dictionary={"ok":request.is_empty() and contact.blocked and contact.blocker_actor_ids.has("blocker") and contact.actual_motion==Vector2.ZERO and actor==before_facts and not allowed and sim.world.validate(h.content).is_empty(),"case":"first_rotation_step","evidence":evidence,"contact_ids":contact.blocker_actor_ids,"actual_motion":str(contact.actual_motion),"planner_leg_allowed":allowed,"scope":"Real _move_step contact, not a fabricated MotionResult. No request for successful passage through this blocked edge."}
 sim.dispose();return result
func _root(h:RefCounted)->Dictionary:
 var sim:HospitalSimulation=h._fixture()
 h._add_actor(sim,"walker","S49",[40,74])
 var ids:Array=["walker"]
 var cells:Array=[[39,74],[41,74],[40,73],[40,75]]
 for i:int in cells.size():
  var id:String="guard_%d"%i;ids.append(id);h._add_actor(sim,id,"S49",cells[i])
 sim.world.touch(false)
 for id:String in ids:sim.space.sync_actor(sim.world,id)
 var actor:Dictionary=sim.world.facts.actors.walker;var target:Array=[40.1,74]
 var quote:Dictionary={"ok":sim.space.movement._local_path_clear(sim.world,actor,[{"kind":"floor","floor_id":1,"cell":target}])};quote.erase("static_proof")
 var graph:Dictionary=sim.space._navigation.query_graphs(sim.space,sim.world,1,actor,[],{})
 var node:int=FloorNavigation._id(Vector2i(40,74));var active_neighbors:int=0
 var from_body:Rect2=sim.space.body_rectangle(actor)
 var edge_evidence:Array=[]
 for next:int in graph.graph.get_point_connections(node):
  var target_cell:Vector2=Vector2(FloorNavigation._cell(next))
  var sample:Dictionary=actor.duplicate();sample.facing=atan2(target_cell.x-40.0,target_cell.y-74.0)
  var to_body:Rect2=sim.space._actor_rect(sample,target_cell)
  var blocked:bool=false
  for id:String in ids:
   if id=="walker":continue
   var obstacle:Rect2=sim.space.body_rectangle(sim.world.facts.actors[id])
   if BodySweep.intersects(from_body,to_body,obstacle,obstacle):blocked=true
  if not blocked:active_neighbors+=1
  edge_evidence.append({"cell":[target_cell.x,target_cell.y],"narrow_blocked":blocked})
 var request:String=sim.space.request_move(sim.world,"walker",1,target)
 var move:Dictionary=sim.world.facts.moves.get("walker",{})
 if move.is_empty():sim.dispose();return {"ok":false,"case":"virtual_root_isolated_fractional_terminal","request_error":request,"quote":quote}
 var seq:int=move.request_sequence
 move.path=[{"kind":"floor","floor_id":1,"cell":target}];move.cursor=0;move.route_pending=false;move.local_move={"origin":[39.9,74],"target":{"kind":"floor","floor_id":1,"cell":[40,74]}}
 var observer:RefCounted=load("res://tests/acceptance/unified_local_behavior.gd").new();var errors:Array=[];var kept:bool=true
 for tick:int in 20:
  var error:String=observer._tick(h,sim,ids)
  if not error.is_empty():errors.append(error);break
  move=sim.world.facts.moves.get("walker",{})
  if move.is_empty():break
  kept=kept and move.request_sequence==seq and ConvoyTrail.point(move.target_cell)==ConvoyTrail.point(target)
 var result:Dictionary={"ok":request.is_empty() and active_neighbors==0 and quote.get("ok",false) and errors.is_empty() and kept and move.is_empty() and sim.space.at(sim.world,"walker",1,target),"case":"virtual_root_isolated_fractional_terminal","active_neighbors":active_neighbors,"edge_evidence":edge_evidence,"scope":"Integer root has zero dynamically traversable graph edges; static walls are not used to invalidate the legal fractional destination.","quote":quote,"errors":errors,"final":actor.location.cell.duplicate(),"remaining":move.duplicate(true)}
 sim.dispose();return result
