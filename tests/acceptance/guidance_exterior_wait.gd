extends "res://tests/acceptance/guidance_fixed_queue.gd"
const EntryExterior=preload("res://game/operations/guidance_queue_entry.gd")
const RoutesExterior=preload("res://game/operations/guidance_queue_routes.gd")

func run_exterior(content:HospitalContent)->Dictionary:
 _content=content
 var rows:Array=[_exterior_case(false),_exterior_case(true),_exterior_case(false,true),_owner_and_shapes()]
 # Existing real arrival and departure workflows must remain functional.
 var ordinary:Dictionary=load("res://tests/acceptance/floor_guidance.gd").new().run_cases(content,["GUIDE-REAL-ARRIVAL","GUIDE-EXIT-BYPASS"])
 rows.append({"case":"ordinary_entry_and_departure","ok":ordinary.ok,"details":ordinary})
 var ok:bool=true
 for row:Dictionary in rows:ok=ok and row.ok
 return {"ok":ok,"cases":rows}

func _touches_entry(x:Dictionary,ctx:Dictionary,actor:Dictionary,path:Array,start:Vector2)->bool:
 var previous:Vector2=start
 var before:Rect2=x.space._actor_rect(actor,start)
 for point:Dictionary in path:
  if point.kind!="floor" or int(point.floor_id)!=1:return true
  var next:Vector2=ConvoyTrail.point(point.cell)
  var sample:Dictionary=actor.duplicate()
  if next!=previous:sample.facing=atan2(next.x-previous.x,next.y-previous.y)
  var after:Rect2=x.space._actor_rect(sample,next)
  var swept:Rect2=before.merge(after)
  if swept.intersects(ctx.room_bounds,false):return true
  for door:Rect2 in ctx.door_bounds:
   if swept.intersects(door,false):return true
  previous=next;before=after
 return false

func _exterior_case(sealed:bool,collision:bool=false)->Dictionary:
 var x:Dictionary=_base()
 HospitalFactory._add_room(x.world,{"id":"entry_room","type":"gp","anchor":[49,71],"size":[8,8],"door":{"definition_id":"DR04","offset":3}},_content)
 _facility(x,"guide","SE01",[50,73],"entry_room")
 _facility(x,"entry_water","FUR17",[54,73],"entry_room")
 x.world.touch()
 var staffed:bool=false
 for tick:int in 600:
  x.g.dispatch(x.world);x.space.advance(x.world);x.g.advance(x.world)
  x.world.facts.sim_tick+=1;x.world.touch(false)
  if x.g._desk_usable(x.world,"guide"):staffed=true;break
 var ctx:Dictionary=EntryExterior.context(x.space,x.world,"guide")
 if ctx.is_empty() or not staffed:_dispose(x);return {"case":"exterior_setup","ok":false,"reason":"Dedicated staffed desk context missing"}
 # Declared current occupied bodies, not invented admission/ticket receipts.
 var slots:Array=x.g._queue_slots(x.world,"guide",1)
 for i:int in slots.size():_visit(x,"occupant_%d"%i,slots[i])
 if sealed:
  # All exterior exits from the rounded start are sealed, leaving only
  # the north door direction. It must not fall back through the entry.
  for cell:Array in [[52,80],[54,80],[53,81]]:HospitalFactory._put_cell(x.world.facts.floors.overrides["1"].blocked,cell)
  x.world.touch()
 var visit:Dictionary=_visit(x,"exterior",[53,79.7999878])
 x.g.prepare(x.world,visit,x.world.facts.tickets[visit.ticket_id])
 var row:Dictionary=x.g.state(x.world,visit.id)
 x.g._move(x.world,visit,row,1,[53,83])
 var move:Dictionary=x.world.facts.moves.get(visit.actor_id,{})
 var actor:Dictionary=x.world.facts.actors[visit.actor_id]
 var origin:Vector2=ConvoyTrail.point(actor.location.cell)
 var goal:Vector2=Vector2(53,83)
 var initial:Dictionary={"phase":row.get("phase",""),"owner":move.get("floor_guidance_visit_id",""),"start_outside":not EntryExterior.is_inside(ctx,x.space,actor,origin),"goal_outside":not EntryExterior.is_inside(ctx,x.space,actor,goal)}
 var generic_move:Dictionary=move.duplicate(true);generic_move.erase("floor_guidance_visit_id");generic_move.erase("floor_guidance_key")
 var old_quote:Dictionary=RoutesExterior.quote(x.space,x.world,generic_move,1,[53,83])
 # Captured from the earlier 20-person failure, not claimed reproduced by
 # the reduced fixture's generic quote (which can legitimately be empty).
 var captured:Array=[]
 for cell:Array in [[53,80],[53,79],[52,79],[52,80],[52,81],[53,81],[54,81],[54,82],[54,83],[53,83]]:captured.append({"kind":"floor","floor_id":1,"cell":cell})
 var captured_crosses:bool=_touches_entry(x,ctx,actor,captured,origin)
 var quote:Dictionary=RoutesExterior.quote(x.space,x.world,move,1,[53,83])
 var capacity_denied:bool=not EntryExterior.capacity_available(x.space,x.world,x.g,visit.actor_id,"guide")
 var entry_denied:bool=EntryExterior.block_entry(x.space,x.world,x.g,visit.actor_id,move,origin,Vector2(53,79.6))
 var safe:bool=true;var outside:bool=true;var nurse_fixed:bool=true;var no_number:bool=true;var target_kept:bool=true;var errors:Array=[]
 var nurse_location:Dictionary=x.world.facts.actors.guide_nurse.location.duplicate(true)
 var sequence:int=int(move.get("request_sequence",-1));var ticks:int=0;var sequence_trace:Array=[]
 var introduced:bool=false;var local_seen:bool=false;var local_safe:bool=true;var obstruction:Dictionary={};var blocker_cell:Array=[];var collision_setup:Dictionary={}
 for tick:int in (8 if sealed else 220):
  var active:Dictionary=x.world.facts.moves.get(visit.actor_id,{})
  if collision and not introduced and not active.get("route_pending",true) and int(active.cursor)<active.path.size():
   var next_point:Dictionary=active.path[int(active.cursor)]
   var position:Vector2=ConvoyTrail.point(actor.location.cell)
   if next_point.kind=="floor" and position!=ConvoyTrail.point(next_point.cell):
    var direction:Vector2=position.direction_to(ConvoyTrail.point(next_point.cell))
    var step_length:float=minf(position.distance_to(ConvoyTrail.point(next_point.cell)),x.space.walking_speed(actor)*WorldState.TICK_SECONDS)
    var moving:Dictionary=actor.duplicate();moving.facing=atan2(direction.x,direction.y)
    var obstacle_sample:Dictionary=actor.duplicate();obstacle_sample.facing=0.0
    var start_body:Rect2=x.space._actor_rect(actor,position)
    var turn_body:Rect2=x.space._actor_rect(moving,position)
    var envelope:Rect2=start_body.merge(turn_body)
    var obstacle_at_origin:Rect2=x.space._actor_rect(obstacle_sample,position)
    var separation:float=0.0
    if direction.x>0:separation=envelope.end.x-obstacle_at_origin.position.x
    elif direction.x<0:separation=obstacle_at_origin.end.x-envelope.position.x
    elif direction.y>0:separation=envelope.end.y-obstacle_at_origin.position.y
    else:separation=obstacle_at_origin.end.y-envelope.position.y
    # Bodies start disjoint, but this tick's intended step truly contacts it.
    var proposed:Vector2=position+direction*(separation+step_length*0.25)
    var obstacle_body:Rect2=x.space._actor_rect(obstacle_sample,proposed)
    var end_body:Rect2=x.space._actor_rect(moving,position+direction*step_length)
    var free:bool=not EntryExterior.is_inside(ctx,x.space,obstacle_sample,proposed) and not envelope.intersects(obstacle_body,false)
    for other:Dictionary in x.world.facts.actors.values():
     if other.location.kind=="floor" and int(other.location.floor_id)==1:
      free=free and not obstacle_body.intersects(x.space.body_rectangle(other),false)
    if free and BodySweep.intersects(start_body,end_body,obstacle_body,obstacle_body):
     blocker_cell=[proposed.x,proposed.y]
     collision_setup={"actor_cell":actor.location.cell.duplicate(),"obstacle_cell":blocker_cell.duplicate(),"axis_separation":separation,"actual_step_length":step_length,"clearance_gap":step_length*0.25,"initial_bodies_disjoint":free,"next_intended_step_contacts":BodySweep.intersects(start_body,end_body,obstacle_body,obstacle_body)}
     obstruction=_visit(x,"local_obstacle",blocker_cell)
     # _visit is a pre-boundary fixture helper; publish this mid-run spawn
     # just as the real arrival flow does before the next movement phase.
     x.world.touch(false)
     x.space.sync_actor(x.world,obstruction.actor_id)
     introduced=true
  var before:Rect2=x.space.body_rectangle(actor)
  x.space.advance(x.world);x.world.facts.sim_tick+=1;x.world.touch(false);x.space.finish_boundary(x.world)
  var after:Rect2=x.space.body_rectangle(actor);ticks=tick+1
  safe=safe and not _overlap(x,visit.actor_id) and before.get_center().distance_to(after.get_center())<=x.space.walking_speed(actor)*WorldState.TICK_SECONDS+0.0001
  outside=outside and not EntryExterior.is_inside(ctx,x.space,actor,ConvoyTrail.point(actor.location.cell))
  nurse_fixed=nurse_fixed and x.world.facts.actors.guide_nurse.location==nurse_location and not x.world.facts.moves.has("guide_nurse")
  no_number=no_number and not row.has("queue_seq")
  var current:Dictionary=x.world.facts.moves.get(visit.actor_id,{})
  if current.has("local_move"):
   local_seen=true
   var path:Array=[current.local_move.target]
   if current.local_move.has("rejoin"):path.append({"kind":"floor","floor_id":1,"cell":current.local_move.rejoin.cell})
   local_safe=local_safe and not _touches_entry(x,ctx,actor,path,ConvoyTrail.point(actor.location.cell))
  sequence_trace.append({"tick":tick,"sequence":current.get("request_sequence",-1),"target":current.get("target_cell",[]).duplicate()})
  target_kept=target_kept and (x.space.at(x.world,visit.actor_id,1,[53,83]) if current.is_empty() else current.target_cell==[53,83] and int(current.request_sequence)==sequence)
  var validation:String=x.world.validate(_content)
  if not validation.is_empty():errors.append(validation);break
  if current.is_empty():break
 var arrived:bool=x.space.at(x.world,visit.actor_id,1,[53,83]) and not x.world.facts.moves.has(visit.actor_id)
 var checks:Dictionary={"own_seek_both_endpoints_outside":initial.phase=="seek" and initial.owner==visit.id and initial.start_outside and initial.goal_outside,"captured_regression_path_crosses_entry":captured_crosses,"capacity_and_entry_still_denied":capacity_denied and entry_denied,"normal_collision_and_speed":safe,"all_actual_steps_outside":outside,"fixed_nurse_and_no_advance_number":nurse_fixed and no_number,"original_goal_and_sequence":target_kept,"valid_world":errors.is_empty(),"route_behavior":not quote.is_empty() and not quote.get("ok",false) and not arrived and actor.location.cell==[53,79.7999878] if sealed else quote.get("ok",false) and not _touches_entry(x,ctx,actor,quote.path,origin) and arrived}
 if collision:
  checks["real_obstruction_created"]=introduced
  checks["actual_local_action_observed"]=local_seen
  checks["entire_local_intention_stays_outside"]=local_safe
  checks["stationary_obstruction_preserved"]=introduced and x.space.at(x.world,obstruction.actor_id,1,blocker_cell) and not x.world.facts.moves.has(obstruction.actor_id)
 var ok:bool=true
 for value:bool in checks.values():ok=ok and value
 var result:Dictionary={"case":"exterior_actual_local_collision" if collision else ("exterior_no_path_no_inside_fallback" if sealed else "exterior_real_walk_avoids_room_and_door"),"ok":ok,"checks":checks,"initial":initial,"generic_quote_in_reduced_fixture":old_quote,"captured_regression_path":captured,"collision_setup":collision_setup,"initial_sequence":sequence,"sequence_trace":sequence_trace,"quote":quote,"errors":errors,"ticks":ticks,"location":actor.location.duplicate(true),"remaining":x.world.facts.moves.get(visit.actor_id,{}).duplicate(true)}
 _dispose(x);return result

func _owner_and_shapes()->Dictionary:
 var x:Dictionary=_base()
 HospitalFactory._add_room(x.world,{"id":"entry_room","type":"gp","anchor":[49,71],"size":[8,8],"door":{"definition_id":"DR04","offset":3}},_content)
 _facility(x,"guide","SE01",[50,73],"entry_room");x.world.touch()
 var owner:Dictionary=_visit(x,"owner",[53,82]);var other:Dictionary=_visit(x,"other",[56,82])
 x.g.prepare(x.world,owner,x.world.facts.tickets[owner.ticket_id])
 var state:Dictionary=x.g.state(x.world,owner.id)
 var ctx:Dictionary=EntryExterior.context(x.space,x.world,"guide")
 var tagged:Dictionary={"actor_id":other.actor_id,"floor_guidance_visit_id":owner.id,"floor_guidance_key":state.get("request_key","")}
 var ordinary:Dictionary={"actor_id":other.actor_id}
 var expected:Dictionary=RoutesExterior.quote(x.space,x.world,ordinary,1,[56,84])
 var actual:Dictionary=RoutesExterior.quote(x.space,x.world,tagged,1,[56,84])
 var actor:Dictionary=x.world.facts.actors[owner.actor_id].duplicate(true)
 actor.species_id="S03";actor.erase("body_binding_id")
 var shapes:Array=[];var all_safe:bool=true;var readonly:bool=true
 for facing:float in [0.0,PI/2,PI,-PI/2]:
  actor.facing=facing
  var before:Dictionary=x.world.freeze()
  var quote:Dictionary=RoutesExterior._exterior_wait(x.space,x.world,actor,1,Vector2(53,82),Vector2(56,84),ctx)
  var safe:bool=quote.get("ok",false) and not _touches_entry(x,ctx,actor,quote.path,Vector2(53,82))
  all_safe=all_safe and safe;readonly=readonly and before==x.world.freeze()
  shapes.append({"facing":facing,"safe":safe,"quote":quote})
 var result:Dictionary={"case":"owner_and_non_square_four_headings","ok":not ctx.is_empty() and state.get("phase","")=="seek" and not str(state.get("request_key","")).is_empty() and actual==expected and all_safe and readonly,"checks":{"owner_row_seek":state.get("phase","")=="seek","foreign_visit_does_not_apply_constraint":actual==expected,"four_headings_real_body_sweeps_outside":all_safe,"quotes_leave_facts_unchanged":readonly},"foreign_quote":actual,"ordinary_quote":expected,"shapes":shapes}
 _dispose(x);return result
