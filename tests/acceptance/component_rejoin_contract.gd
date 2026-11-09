extends RefCounted
func run(content:HospitalContent)->Dictionary:
 var h:RefCounted=load("res://tests/acceptance/space.gd").new();h.content=content
 var rows:Array=[_nearest(h,false),_nearest(h,true),_release(h),_budget(h),_nearest(h,false,true)]
 var ok:bool=true
 for row:Dictionary in rows:ok=ok and row.ok
 return {"ok":ok,"cases":rows}
func _pending(sim:HospitalSimulation,id:String,origin:Array,target:Array)->Dictionary:
 sim.space.request_move(sim.world,id,1,target)
 var m:Dictionary=sim.world.facts.moves[id]
 m.path=[{"kind":"floor","floor_id":1,"cell":target.duplicate()}];m.cursor=0;m.route_pending=true;m.live_floor_route=true;m.rejoin_origin=origin.duplicate()
 return m
func _observer()->RefCounted:return load("res://tests/acceptance/unified_local_behavior.gd").new()
func _nearest(h:RefCounted,fractional:bool,completed_local:bool=false)->Dictionary:
 var sim:HospitalSimulation=h._fixture()
 if not fractional:
  for cell:Array in [[40,71],[41,71]]:HospitalFactory._put_cell(sim.world.facts.floors.overrides["1"].blocked,cell)
 sim.world.touch()
 h._add_actor(sim,"walker","S49",[40.25,72.25] if fractional else [40,72])
 var actor:Dictionary=sim.world.facts.actors.walker
 var nonsquare:bool=not fractional
 if fractional:
  for binding:Dictionary in h.content.catalog.treatment_bindings:
   var probe:Dictionary=actor.duplicate(true);probe.species_id=binding.species_id;probe.body_binding_id=binding.id
   var shape:Rect2=sim.space.body_rectangle(probe)
   if shape.size.x!=shape.size.y and sim.space.clearance(probe)<=2 and sim.space.body(probe).height_m<=6.5:
    actor.species_id=binding.species_id;actor.body_binding_id=binding.id;nonsquare=true;break
  sim.world.touch(false);sim.space.sync_actor(sim.world,"walker")
 var y:float=70.25 if fractional else 70.0
 var goal:Array=[45.25,y] if fractional else [45,y]
 var m:Dictionary=_pending(sim,"walker",[40.25,y] if fractional else [40,y],goal)
 var topology:Dictionary={}
 if completed_local:
  m.route_pending=false;m.erase("live_floor_route");m.erase("rejoin_origin")
  m.local_move={"origin":[40,70],"target":{"kind":"floor","floor_id":1,"cell":[40,72]}}
  var q:RouteClearance=sim.space.navigation.structural_clearance(sim.world,actor,1)
  var start:=Vector2(40,72);var near:=Vector2(41,70);var far:=Vector2(42,70)
  topology.near_horizontal_first_blocked=not q.sweep_reason(Vector2(41,72),near).is_empty()
  topology.near_vertical_first_blocked=not q.sweep_reason(start,Vector2(40,70)).is_empty()
  topology.far_L_clear=q.sweep_reason(start,Vector2(42,72)).is_empty() and q.sweep_reason(Vector2(42,72),far).is_empty()
  topology.near_two_corner_clear=q.sweep_reason(start,Vector2(39,72)).is_empty() and q.sweep_reason(Vector2(39,72),Vector2(39,70)).is_empty() and q.sweep_reason(Vector2(39,70),near).is_empty()
 var sequence:int=m.request_sequence
 var validation:String=sim.world.validate(h.content)
 var malformed:Array=[];var rejects:bool=true
 for bad:Variant in [null,{},[1],["x",70]]:
  var copy:Dictionary=sim.world.freeze();copy.moves.walker.rejoin_origin=bad
  var reason:String=WorldState.new(copy).validate(h.content)
  rejects=rejects and not reason.is_empty();malformed.append(reason)
 var observer:RefCounted=_observer();var restored:Dictionary=observer._restore_boundary(h,sim,"walker",["walker"])
 var errors:Array=[];var first:Array=[];var trace:Array=[];var kept:bool=true
 for tick:int in 300:
  var before:Vector2=ConvoyTrail.point(actor.location.cell)
  var error:String=observer._tick(h,sim,["walker"])
  if not error.is_empty():errors.append(error);break
  var pos:Vector2=ConvoyTrail.point(actor.location.cell)
  if first.is_empty():
   var hit:Variant=Geometry2D.segment_intersects_segment(before,pos,Vector2(41,y),ConvoyTrail.point(goal))
   if hit!=null:first=[hit.x,hit.y]
   elif absf(pos.y-y)<0.00001 and pos.x>=41 and pos.x<=float(goal[0]):first=[pos.x,pos.y]
  m=sim.world.facts.moves.get("walker",{})
  if not m.is_empty():kept=kept and m.request_sequence==sequence and ConvoyTrail.point(m.target_cell)==ConvoyTrail.point(goal)
  trace.append({"tick":tick,"position":actor.location.cell.duplicate()})
  if m.is_empty():break
 var arrived:bool=sim.space.at(sim.world,"walker",1,goal) and m.is_empty()
 var control_ok:bool=true
 if completed_local:
  for value:bool in topology.values():control_ok=control_ok and value
  control_ok=control_ok and int(sim.space.query_counts.get("rejoin_component_queries",0))>0
 var result:Dictionary={"case":"completed_local_nearest_requires_component" if completed_local else ("fractional_non_square" if fractional else "near_two_corners_before_far_L"),"topology":topology,"component_queries":sim.space.query_counts.get("rejoin_component_queries",0),"ok":control_ok and validation.is_empty() and rejects and nonsquare and restored.ok and errors.is_empty() and kept and arrived and first.size()==2 and ConvoyTrail.point(first).distance_to(Vector2(41,y))<0.00001,"validation":validation,"malformed":malformed,"restore":restored,"errors":errors,"first_actual_reentry":first,"trace":trace,"arrived":arrived,"nonsquare":nonsquare,"scope":"Authored legal pending boundary; subsequent movement real, forward original segment begins at x41."}
 sim.dispose();return result
func _release(h:RefCounted)->Dictionary:
 var sim:HospitalSimulation=h._fixture()
 for xx:int in 96:
  for yy:int in [69,71]:HospitalFactory._put_cell(sim.world.facts.floors.overrides["1"].blocked,[xx,yy])
 sim.world.touch();h._add_actor(sim,"walker","S49",[35,70]);h._add_actor(sim,"blocker","S49",[40,70])
 var move:Dictionary=_pending(sim,"walker",[40,70],[60,70]);var seq:int=move.request_sequence
 var observer:RefCounted=_observer();var errors:Array=[];var retry_trace:Array=[];var kept:bool=true
 for tick:int in 60:
  var error:String=observer._tick(h,sim,["walker","blocker"])
  if not error.is_empty():errors.append(error);break
  move=sim.world.facts.moves.get("walker",{})
  kept=kept and move.get("request_sequence",-1)==seq and move.get("route_pending",false)
  retry_trace.append({"tick":sim.world.sim_tick,"queries":sim.space.query_counts.get("rejoin_component_queries",0),"retry":move.get("route_retry_tick",0)})
 var before_release:int=int(sim.space.query_counts.get("rejoin_component_queries",0))
 var release:String=sim.space.request_move(sim.world,"blocker",1,[62,70])
 for tick:int in 500:
  var error:String=observer._tick(h,sim,["walker","blocker"])
  if not error.is_empty():errors.append(error);break
  move=sim.world.facts.moves.get("walker",{})
  if not move.is_empty():kept=kept and move.request_sequence==seq and ConvoyTrail.point(move.target_cell)==Vector2(60,70)
  if sim.world.facts.moves.is_empty():break
 var arrived:bool=sim.space.at(sim.world,"walker",1,[60,70]) and sim.space.at(sim.world,"blocker",1,[62,70]) and sim.world.facts.moves.is_empty()
 var result:Dictionary={"case":"real_dynamic_release_requeries","ok":kept and release.is_empty() and errors.is_empty() and arrived and int(sim.space.query_counts.get("rejoin_component_queries",0))>before_release,"arrived":arrived,"errors":errors,"release":release,"retry_trace":retry_trace,"final_actors":sim.world.facts.actors.duplicate(true),"final_moves":sim.world.facts.moves.duplicate(true)}
 sim.dispose();return result
func _budget(h:RefCounted)->Dictionary:
 var sim:HospitalSimulation=h._fixture();var ids:Array=[];var sequences:Dictionary={}
 for i:int in 9:
  var id:String="request_%02d"%i;ids.append(id)
  h._add_actor(sim,id,"S49",[35,70+2*i])
  sequences[id]=_pending(sim,id,[35,70+2*i],[45,70+2*i]).request_sequence
 var observer:RefCounted=_observer();var errors:Array=[];var trace:Array=[];var budget_ok:bool=true;var kept:bool=true;var first_pending:int=0
 var budget:int=maxi(int(h.content.balance.pathfinding.minimum_actor_requests_per_tick),ceili(9.0/float(h.content.balance.pathfinding.actors_per_request)))
 for tick:int in 200:
  var before:int=int(sim.space.query_counts.get("rejoin_component_queries",0))
  var error:String=observer._tick(h,sim,ids)
  if not error.is_empty():errors.append(error);break
  var used:int=int(sim.space.query_counts.get("rejoin_component_queries",0))-before
  budget_ok=budget_ok and used<=budget
  var pending:int=0
  for id:String in ids:
   var move:Dictionary=sim.world.facts.moves.get(id,{})
   if not move.is_empty():
    kept=kept and move.request_sequence==sequences[id] and ConvoyTrail.point(move.target_cell)==Vector2(45,70+2*ids.find(id))
    if move.get("route_pending",false):pending+=1
  if tick==0:first_pending=pending
  trace.append({"tick":tick,"used":used,"pending":pending})
  if sim.world.facts.moves.is_empty():break
 var arrived:bool=sim.world.facts.moves.is_empty()
 for i:int in ids.size():arrived=arrived and sim.space.at(sim.world,ids[i],1,[45,70+2*i])
 var result:Dictionary={"case":"nine_requests_existing_budget","ok":budget_ok and first_pending>=maxi(0,9-budget) and kept and errors.is_empty() and arrived,"budget":budget,"first_pending":first_pending,"trace":trace,"errors":errors,"arrived":arrived}
 sim.dispose();return result
