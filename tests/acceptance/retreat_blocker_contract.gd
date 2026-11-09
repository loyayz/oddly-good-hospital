extends RefCounted
class ObserveMovement extends HospitalMovement:
 var triggered:bool=false
 var blocked_steps:int=0
 func _move_step(world:WorldState,actor:Dictionary,movement:Dictionary,segment:Dictionary)->MotionResult:
  var result:MotionResult=super._move_step(world,actor,movement,segment)
  if result.blocked:blocked_steps+=1
  return result
 func _init(geometry:HospitalSpace)->void:super(geometry)
 func _start_detour(world:WorldState,actor:Dictionary,movement:Dictionary)->void:
  triggered=true
  super._start_detour(world,actor,movement)
func _p(x:float,y:float)->Dictionary:return {"kind":"floor","floor_id":1,"cell":[x,y]}
func _journey(id:String,start:Array,goal:Array)->Dictionary:
 return {"actor_id":id,"path":[_p(goal[0],goal[1])],"cursor":0,"travelled":[_p(start[0],start[1])],"blocked_since":-1,"target_floor":1,"target_cell":goal.duplicate(),"request_sequence":101}
func run(content:HospitalContent)->Dictionary:
 var suite:RefCounted=load("res://tests/acceptance/space.gd").new();suite.content=content
 var rows:Array=[]
 for mode:String in ["active","departed_history","busy_staff","idle_staff","stationary","seated","convoy","third_both_sides"]:
  var sim:HospitalSimulation=suite._fixture()
  suite._add_actor(sim,"a","S49",[40,70])
  if mode in ["busy_staff","idle_staff"]:suite._add_staff(sim,"b","doctor",[39.4,70])
  else:suite._add_actor(sim,"b","S49",[39.4,70] if mode!="departed_history" else [39.4,73])
  # Explicit pending-retreat boundary, not a fabricated completed movement.
  var a:Dictionary=_journey("a",[40,70],[45,70]);a.path=[_p(39,70)]
  a.detour={"phase":"back","prefix_size":1,"resume_index":-1,"direction":[1,0],"original_path":[_p(41,70),_p(45,70)],"backtrack":[_p(39,70)],"back_cursor":-1}
  sim.world.facts.moves.a=a
  if mode!="stationary":sim.world.facts.moves.b=_journey("b",[39.4,70],[39.4,75])
  if mode=="busy_staff":sim.world.facts.staff.b.active_job_id="floor_desk:protected"
  if mode=="seated":sim.world.facts.actors.b.posture="sitting"
  if mode=="convoy":sim.world.facts.moves.b.members=["b","follower"];sim.world.facts.moves.b.convoy={}
  if mode=="third_both_sides":suite._add_actor(sim,"third","S49",[38.8,70])
  var original_a:Dictionary=a.duplicate(true)
  var original_b:Dictionary=sim.world.facts.moves.get("b",{}).duplicate(true)
  var bodies:Dictionary=sim.world.facts.actors.duplicate(true)
  var contact:=HospitalMovement.MotionResult.new();contact.requested_motion=Vector2(-0.2,0);contact.blocker_actor_ids.append("b")
  # All modes use the real body/sweep eligibility check. The departed case
  # explicitly models a contact ID retained from an earlier accepted sweep.
  var intersects:bool=BodySweep.intersects(sim.space.body_rectangle(sim.world.facts.actors.a),sim.space._actor_rect(sim.world.facts.actors.a,Vector2(39.8,70)),sim.space.body_rectangle(sim.world.facts.actors.b),sim.space.body_rectangle(sim.world.facts.actors.b))
  var static_intention:bool=sim.space.movement._retreat_intention_clear(sim.world,sim.world.facts.actors.a,a,a.path)
  sim.space.movement._detour_obstruction(sim.world,sim.world.facts.actors.a,a,contact)
  var b:Dictionary=sim.world.facts.moves.get("b",{})
  var expected:bool=mode in ["active","idle_staff","third_both_sides"]
  var arranged:bool=b.has("detour")
  var fallback_correct:bool=mode!="third_both_sides" or b.get("detour",{}).get("phase","")=="back"
  var preserved:bool=a==original_a and (b.is_empty() or b.target_cell==original_b.target_cell and b.request_sequence==original_b.request_sequence)
  var checks:Dictionary={"pending_retreat_and_original_goals_preserved":preserved,"no_immediate_displacement":sim.world.facts.actors==bodies,"static_legal_retreat_intention_retained":static_intention,"expected_blocker_action":arranged==expected,"two_sides_blocked_falls_back":fallback_correct,"nonselected_journey_unchanged":expected or b==original_b,"actual_current_body_contact":intersects==(mode!="departed_history")}
  var ok:bool=true
  for v:bool in checks.values():ok=ok and v
  rows.append({"case":mode,"ok":ok,"checks":checks,"blocker_journey":b.duplicate(true)})
  sim.dispose()
 rows.append(_dual_pending(suite,false))
 rows.append(_dual_pending(suite,true))
 rows.append(_dual_sealed(suite))
 rows.append(_turning_shape(suite))
 var ok:bool=true
 for r:Dictionary in rows:ok=ok and r.ok
 return {"ok":ok,"cases":rows,"scope":"Two explicit dual-retreat initial boundaries followed through real movement to both original destinations; remaining cases cover local contact/eligibility and preservation only, not universal liveness."}

func _dual_pending(suite:RefCounted,swap:bool)->Dictionary:
 var sim:HospitalSimulation=suite._fixture()
 var aid:String="z" if swap else "a"
 var bid:String="a" if swap else "z"
 suite._add_actor(sim,aid,"S49",[40,70])
 suite._add_actor(sim,bid,"S49",[39.4,70])
 var a:Dictionary=_journey(aid,[40,70],[45,70]);a.path=[_p(39,70)]
 a.detour={"phase":"back","prefix_size":1,"resume_index":-1,"direction":[1,0],"original_path":[_p(41,70),_p(45,70)],"backtrack":[_p(39,70)],"back_cursor":-1}
 var b:Dictionary=_journey(bid,[39.4,70],[35,70]);b.path=[_p(40.4,70)]
 b.detour={"phase":"back","prefix_size":1,"resume_index":-1,"direction":[-1,0],"original_path":[_p(38.4,70),_p(35,70)],"backtrack":[_p(40.4,70)],"back_cursor":-1}
 sim.world.facts.moves[aid]=a;sim.world.facts.moves[bid]=b
 var observer:=ObserveMovement.new(sim.space);sim.space.movement=observer
 var goals:Dictionary={aid:a.target_cell.duplicate(),bid:b.target_cell.duplicate()}
 var reservations:Dictionary=sim.world.facts.adaptations.duplicate(true)
 var checks:Dictionary={"real_steps_blocked":false,"collision_safe":true,"goals_sequences_reservations_preserved":true,"both_arrived":false,"no_repeating_state_cycle":true,"walking_budget":true}
 var seen:Dictionary={};var trace:Array=[];var cycle:Array=[]
 var steps:int=0
 for tick:int in 240:
  var before_a:Rect2=sim.space.body_rectangle(sim.world.facts.actors[aid])
  var before_b:Rect2=sim.space.body_rectangle(sim.world.facts.actors[bid])
  suite._movement_tick(sim)
  steps=tick+1
  var after_a:Rect2=sim.space.body_rectangle(sim.world.facts.actors[aid])
  var after_b:Rect2=sim.space.body_rectangle(sim.world.facts.actors[bid])
  checks.collision_safe=checks.collision_safe and not after_a.intersects(after_b,false) and not BodySweep.intersects(before_a,after_a,before_b,after_b)
  checks.walking_budget=checks.walking_budget and before_a.get_center().distance_to(after_a.get_center())<=sim.space.walking_speed(sim.world.facts.actors[aid])*WorldState.TICK_SECONDS+0.0001 and before_b.get_center().distance_to(after_b.get_center())<=sim.space.walking_speed(sim.world.facts.actors[bid])*WorldState.TICK_SECONDS+0.0001
  for id:String in [aid,bid]:
   var move:Dictionary=sim.world.facts.moves.get(id,{})
   checks.goals_sequences_reservations_preserved=checks.goals_sequences_reservations_preserved and (sim.space.at(sim.world,id,1,goals[id]) if move.is_empty() else move.target_cell==goals[id] and move.request_sequence==101)
  checks.goals_sequences_reservations_preserved=checks.goals_sequences_reservations_preserved and reservations==sim.world.facts.adaptations
  var state:Array=[]
  for id:String in [aid,bid]:
   var move:Dictionary=sim.world.facts.moves.get(id,{})
   state.append([sim.world.facts.actors[id].location.cell.duplicate(),move.get("cursor",-1),move.get("path",[]).duplicate(true),move.get("detour",{}).duplicate(true)])
  var key:String=JSON.stringify(state)
  if seen.has(key):
   checks.no_repeating_state_cycle=false;cycle=[seen[key],tick];break
  seen[key]=tick
  if tick%10==0:trace.append({"tick":tick,"state":state})
  if sim.world.facts.moves.is_empty():break
 checks.real_steps_blocked=observer.blocked_steps>0
 checks.both_arrived=not sim.world.facts.moves.has(aid) and not sim.world.facts.moves.has(bid) and sim.space.at(sim.world,aid,1,goals[aid]) and sim.space.at(sim.world,bid,1,goals[bid])
 var ok:bool=true
 for value:bool in checks.values():ok=ok and value
 var result:Dictionary={"case":"dual_pending_swapped_ids" if swap else "dual_pending","ok":ok,"checks":checks,"blocked_actual_steps":observer.blocked_steps,"ticks":steps,"cycle":cycle,"trace":trace,"remaining":sim.world.facts.moves.duplicate(true),"boundary":"Explicit opposing pending-retreat initial states; thereafter only real movement boundaries, both final arrivals required."}
 sim.dispose();return result

func _dual_sealed(suite:RefCounted)->Dictionary:
 var sim:HospitalSimulation=suite._fixture()
 suite._add_actor(sim,"a","S49",[40,70]);suite._add_actor(sim,"b","S49",[39.4,70])
 suite._add_actor(sim,"upper","S49",[39.4,69.4]);suite._add_actor(sim,"lower","S49",[39.4,70.6])
 var a:Dictionary=_journey("a",[40,70],[45,70]);a.path=[_p(39,70)]
 a.detour={"phase":"back","prefix_size":1,"resume_index":-1,"direction":[1,0],"original_path":[_p(45,70)],"backtrack":[_p(39,70)],"back_cursor":-1}
 var b:Dictionary=_journey("b",[39.4,70],[35,70]);b.path=[_p(40.4,70)]
 b.detour={"phase":"back","prefix_size":1,"resume_index":-1,"direction":[-1,0],"original_path":[_p(35,70)],"backtrack":[_p(40.4,70)],"back_cursor":0}
 sim.world.facts.moves.a=a;sim.world.facts.moves.b=b
 var before:Dictionary=sim.world.freeze()
 var contact:=HospitalMovement.MotionResult.new();contact.requested_motion=Vector2(-0.2,0);contact.blocker_actor_ids.append("b")
 sim.space.movement._detour_obstruction(sim.world,sim.world.facts.actors.a,a,contact)
 var unchanged:bool=before==sim.world.freeze()
 sim.dispose()
 return {"case":"dual_pending_sides_sealed","ok":unchanged,"checks":{"no_unreached_history_consumed_or_body_pushed":unchanged},"scope":"Safety boundary only; not counted as eventual arrival or acceptable permanent wait."}

func _turning_shape(suite:RefCounted)->Dictionary:
 var sim:HospitalSimulation=suite._fixture()
 suite._add_actor(sim,"a","S03",[40,70]);suite._add_actor(sim,"b","S49",[45,70])
 var actor:Dictionary=sim.world.facts.actors.a
 actor.facing=0.0;sim.space.sync_actor(sim.world,"a")
 var sample:Dictionary=actor.duplicate();sample.facing=-PI/2
 var first:Rect2=sim.space.body_rectangle(actor)
 var old_to:Rect2=sim.space._actor_rect(actor,Vector2(39.8,70))
 var new_to:Rect2=sim.space._actor_rect(sample,Vector2(39.8,70))
 var found:bool=false
 var pos:Vector2
 for ix:int in range(760,840):
  if found:break
  for iy:int in range(1360,1440):
   var point:Vector2=Vector2(ix*0.05,iy*0.05)
   var body:Rect2=sim.space._actor_rect(sim.world.facts.actors.b,point)
   if not first.intersects(body,false) and not BodySweep.intersects(first,old_to,body,body) and BodySweep.intersects(first,new_to,body,body):
    pos=point;found=true;break
 if not found:sim.dispose();return {"case":"non_square_turn","ok":false,"reason":"No separating real-body fixture found"}
 sim.world.facts.actors.b.location.cell=[pos.x,pos.y];sim.space.sync_actor(sim.world,"b")
 var a:Dictionary=_journey("a",[40,70],[45,70]);a.path=[_p(39,70)]
 a.detour={"phase":"back","prefix_size":1,"resume_index":-1,"direction":[1,0],"original_path":[_p(45,70)],"backtrack":[_p(39,70)],"back_cursor":-1}
 sim.world.facts.moves.a=a;sim.world.facts.moves.b=_journey("b",[pos.x,pos.y],[pos.x,75])
 var observer:=ObserveMovement.new(sim.space)
 var before:Dictionary=sim.world.facts.actors.duplicate(true)
 var contact:=HospitalMovement.MotionResult.new();contact.requested_motion=Vector2(-0.2,0);contact.blocker_actor_ids.append("b")
 observer._detour_obstruction(sim.world,actor,a,contact)
 var ok:bool=observer.triggered and before==sim.world.facts.actors
 var result:Dictionary={"case":"non_square_turn","ok":ok,"checks":{"new_facing_contact_selected":observer.triggered,"real_pose_unchanged":before==sim.world.facts.actors},"blocker_position":[pos.x,pos.y],"old_to":str(old_to),"actual_to":str(new_to)}
 sim.dispose();return result
