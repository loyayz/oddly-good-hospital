extends SceneTree
var ROOT: String = ""
var suite = preload("res://tests/acceptance/space.gd").new()
var rows: Array = []
var trace: Array = []
func _initialize() -> void: call_deferred("run")
func save(suffix: String, value: Variant) -> void: FileAccess.open(ROOT+suffix+".json",FileAccess.WRITE).store_string(JSON.stringify(value,"  "))
func rect_raw(r: Rect2) -> Array: return [r.position.x,r.position.y,r.size.x,r.size.y]
func overlaps_members(sim: HospitalSimulation, members: Array, door_rect: Rect2, skip_head: bool = false) -> Array:
 var ids: Array=[]
 for id: String in members:
  if skip_head and id==members[0]: continue
  if sim.space.body_rectangle(sim.world.facts.actors[id]).intersects(door_rect,false): ids.append(id)
 return ids
# Independent live trail: retain last fixed separation from observed head history.
func live_regions(history: Array, length: float, shift: float, size: float) -> Array:
 var result: Array=[];var left: float=length
 for i: int in range(history.size()-1,0,-1):
  var end: Vector2=ConvoyTrail.point(history[i]);var start: Vector2=ConvoyTrail.point(history[i-1]);var span: float=start.distance_to(end)
  if span<0.0000001: continue
  var retained: Vector2=end+(start-end)*minf(1.0,left/span)
  result.append(Rect2(retained+Vector2.ONE*shift,Vector2.ONE*size).merge(Rect2(end+Vector2.ONE*shift,Vector2.ONE*size)))
  left-=span
  if left<=0.0000001: break
 if result.is_empty(): result.append(Rect2(ConvoyTrail.point(history[-1])+Vector2.ONE*shift,Vector2.ONE*size))
 return result
func state(sim: HospitalSimulation, members: Array, door: Dictionary, label: String, extra: Dictionary={}) -> void:
 var actors: Dictionary={}
 for id: String in members: actors[id]=sim.world.facts.actors[id].duplicate(true)
 trace.append({"case":label,"tick":sim.world.sim_tick,"actors":actors,"moves":sim.world.facts.moves.duplicate(true),"adaptations":sim.world.facts.adaptations.duplicate(true),"door":door.duplicate(true),"extra":extra})
func journey(label: String, giant: bool, corner: bool, replace: bool) -> void:
 var sim: HospitalSimulation=suite._fixture();var w: WorldState=sim.world
 var members: Array=["head","tail"] if giant else ["head","middle","tail"]
 var build: CommandResult
 if giant:
  suite._command(sim,"build_land",{"plot":[1,1],"floor_id":1})
  build=suite._command(sim,"build_room",suite._room("room",[42,62],[18,16]))
  suite._add_actor(sim,"head","S49",[45,81]);suite._add_actor(sim,"tail","S59",[44,90])
 else:
  build=suite._command(sim,"build_room",suite._room("room",[35,68],[8,8]))
  suite._add_actor(sim,"head","S49",[36,73]);suite._add_actor(sim,"middle","S49",[36,71]);suite._add_actor(sim,"tail","S49",[36,69])
 var door: Dictionary=suite._doors(w,"room")[0]
 var goal: Array=[45,65] if giant else ([40,84] if corner else [36,84])
 var checks: Dictionary={"built":build.accepted,"legal_input":w.validate(suite.content).is_empty()}
 save("."+label+".input",w.freeze())
 var reason: String=sim.space.request_group_move(w,"head",members,{},1,goal)
 checks.request=reason.is_empty()
 var initial: Dictionary=w.facts.moves.get("head",{}).duplicate(true)
 if initial.is_empty(): rows.append({"case":label,"ok":false,"checks":checks,"reason":reason});sim.dispose();return
 var history: Array=initial.convoy.points.duplicate(true)
 var span: int=sim.space.door_quote(w,ConvoyTrail.proxy(w,initial),1,door).get("span",0)
 var opening: Rect2=sim.space._door_rect(door,span)
 var acquired: bool=false;var hold_frames: int=0;var after_head_frames: int=0;var releases: Array=[];var errors: Array=[];var turns: int=0;var last_direction: Vector2=Vector2.ZERO;var cancelled: bool=false
 for step: int in 700:
  var old_positions: Dictionary={}
  for id: String in members: old_positions[id]=w.facts.actors[id].location.cell.duplicate()
  var old_head: Vector2=ConvoyTrail.point(w.facts.actors.head.location.cell)
  var had: bool=w.facts.adaptations.has(door.id)
  suite._movement_tick(sim)
  var new_head: Vector2=ConvoyTrail.point(w.facts.actors.head.location.cell)
  if old_head.distance_to(new_head)>0.000001:
   history.append([new_head.x,new_head.y])
   var direction: Vector2=(new_head-old_head).normalized()
   if last_direction!=Vector2.ZERO and not last_direction.is_equal_approx(direction): turns+=1
   last_direction=direction
  var actual_overlap: Array=overlaps_members(sim,members,opening)
  var tail_overlap: Array=overlaps_members(sim,members,opening,true)
  var remaining_regions: Array=live_regions(history,float(initial.convoy.spacing)*(members.size()-1),float(initial.convoy.shift),float(initial.convoy.size))
  var trail_inside: bool=false
  for r: Rect2 in remaining_regions:
   if r.intersects(opening,false): trail_inside=true
  var held: bool=w.facts.adaptations.has(door.id)
  acquired=acquired or held
  if held: hold_frames+=1
  if held and not sim.space.body_rectangle(w.facts.actors.head).intersects(opening,false) and trail_inside: after_head_frames+=1
  if acquired and trail_inside and not held and not cancelled: errors.append({"kind":"premature_trail_release","tick":w.sim_tick})
  if had and not held: releases.append({"tick":w.sim_tick,"trail_inside":trail_inside,"actual_body_overlap":actual_overlap})
  var permission: Dictionary={}
  if held:
   for id: String in members: permission[id]=sim.space._dynamic_clear(w,id,1,opening,members,true)
   permission.outsider=sim.space._dynamic_clear(w,"outsider",1,opening,[],true)
   if permission.values().slice(0,members.size()).has(false) or permission.outsider: errors.append({"kind":"permission","tick":w.sim_tick,"values":permission})
  var validation: String=w.validate(suite.content)
  if not validation.is_empty(): errors.append({"kind":"validation","tick":w.sim_tick,"reason":validation})
  for id: String in members:
   if ConvoyTrail.point(old_positions[id]).distance_to(ConvoyTrail.point(w.facts.actors[id].location.cell))>sim.space.walking_speed(w.facts.actors.head)*WorldState.TICK_SECONDS+0.0001: errors.append({"kind":"step_budget","actor":id,"tick":w.sim_tick})
  for a: int in members.size():
   for b: int in range(a+1,members.size()):
    if sim.space.body_rectangle(w.facts.actors[members[a]]).intersects(sim.space.body_rectangle(w.facts.actors[members[b]]),false): errors.append({"kind":"body_overlap","tick":w.sim_tick})
  state(sim,members,door,label,{"held":held,"trail_inside":trail_inside,"body_overlap":actual_overlap,"permission":permission})
  if replace and not cancelled and held and not sim.space.body_rectangle(w.facts.actors.head).intersects(opening,false) and not tail_overlap.is_empty():
   save("."+label+".before-cancel",w.freeze())
   var before: Dictionary=w.facts.actors.duplicate(true)
   checks.cancel=sim.space.cancel_ground_move(w,"head")
   checks.cancel_no_motion=before==w.facts.actors
   if label in ["cancel_then_follower_exit","cancel_then_new_singleton","mixed_cancel_exit"]:
    var original: Dictionary=w.facts.adaptations[door.id].duplicate(true)
    var exit_member: String="tail" if giant else "middle"
    var exit_goal: Array=[44,70] if giant else [36,81]
    var head_goal: Array=[50,65] if giant else [40,84]
    checks.head_request=(sim.space.request_move(w,"head",1,head_goal) if label=="cancel_then_follower_exit" else sim.space.request_group_move(w,"head",["head"],{},1,head_goal)).is_empty()
    checks.new_request_no_motion=before==w.facts.actors
    # The old member is deliberately stationary during the owner's first
    # new step. This is the original premature-release reproducer.
    suite._movement_tick(sim)
    checks.old_member_still_inside=not overlaps_members(sim,members,opening,true).is_empty()
    checks.old_record_retained=w.facts.adaptations.get(door.id,{})==original
    save("."+label+".after-replacement",w.freeze())
    state(sim,members,door,label+"_new_owner_step",{})
    checks.member_request=sim.space.request_move(w,exit_member,1,exit_goal).is_empty()
    var member_start: Array=w.facts.actors[exit_member].location.cell.duplicate()
    # A fresh runtime and actual JSON restore must retain the original
    # participants/envelope even though their current journeys differ.
    var frozen: Dictionary=w.freeze()
    var restored: WorldState=WorldState.new(json_restore(frozen,label))
    checks.restored_valid=restored.validate(suite.content).is_empty()
    sim.dispose();sim=HospitalSimulation.new(restored,suite.content);w=sim.world
    checks.restored_reservation=w.facts.adaptations.get(door.id,{})==original
    var held_reuse_steps: int=0;var original_released: bool=false
    for trial: int in 180:
     var before_step: Dictionary=w.freeze()
     var prior: Dictionary=w.facts.adaptations.get(door.id,{}).duplicate(true)
     suite._movement_tick(sim)
     errors.append_array(motion_errors(sim,before_step,members))
     var overlap: Array=overlaps_members(sim,members,opening)
     if not overlap.is_empty() and not w.facts.adaptations.has(door.id): errors.append({"kind":"cancelled_body_premature_release","tick":w.sim_tick})
     if w.facts.adaptations.has(door.id) and not original_released:
      held_reuse_steps+=1
      if w.facts.adaptations[door.id]!=original: errors.append({"kind":"original_record_replaced","tick":w.sim_tick})
     elif not w.facts.adaptations.has(door.id) and not prior.is_empty():
      original_released=true
      releases.append({"tick":w.sim_tick,"actual_body_overlap":overlap})
     var valid: String=w.validate(suite.content)
     if not valid.is_empty(): errors.append({"kind":"restored_validation","tick":w.sim_tick,"reason":valid})
     state(sim,members,door,label+"_actual_exit",{})
     if w.facts.moves.is_empty(): break
    checks.member_actually_moved=w.facts.actors[exit_member].location.cell!=member_start
    checks.member_actually_departed=sim.space.at(w,exit_member,1,exit_goal) and not w.facts.moves.has(exit_member)
    checks.head_actually_departed=sim.space.at(w,"head",1,head_goal) and not w.facts.moves.has("head")
    checks.held_reuse_observed=held_reuse_steps>0
    checks.released_after_actual_exit=not w.facts.adaptations.has(door.id) and overlaps_members(sim,members,opening).is_empty()
    cancelled=true
    break
   elif label=="cancel_restart_same_group":
    var restart_before: Dictionary=w.freeze()
    var restart_reason: String=sim.space.request_group_move(w,"head",members,{},1,goal)
    checks.same_group_refused_in_door=restart_reason=="必须离开门口后完整成队"
    checks.refusal_atomic=restart_before==w.freeze()
    checks.restart_no_motion=before==w.facts.actors
    state(sim,members,door,label+"_cancel_restart",{"restart_reason":restart_reason})
    save("."+label+".after-replacement",w.freeze())
    cancelled=true
    break
  if not errors.is_empty() or not w.facts.moves.has("head"): break
 if not replace:
  suite._movement_tick(sim)
  checks.real_arrival=not w.facts.moves.has("head") and sim.space.at(w,"head",1,goal)
  checks.tail_bodies_clear=overlaps_members(sim,members,opening).is_empty()
  checks.released=not w.facts.adaptations.has(door.id)
  checks.after_head_clear_protection=after_head_frames>0
  if corner: checks.actual_turn=turns>0
 else: checks.reached_actual_cancel_boundary=cancelled
 checks.acquired=acquired;checks.no_motion_safety_or_permission_errors=errors.is_empty()
 save("."+label+".final",w.freeze())
 var row: Dictionary={"case":label,"ok":not checks.values().has(false),"checks":checks,"errors":errors,"door_span":span,"hold_frames":hold_frames,"after_head_clear_frames":after_head_frames,"turns":turns,"releases":releases,"remaining":w.facts.moves.duplicate(true)}
 rows.append(row);print(JSON.stringify(row));sim.dispose()
func run() -> void:
 var args: PackedStringArray=OS.get_cmdline_user_args()
 if args.size()!=2:
  push_error("Expected output prefix and comma-separated selected cases");quit(2);return
 ROOT=args[0]
 suite.content=HospitalContent.new()
 var selected: PackedStringArray=args[1].split(",")
 for label: String in selected:
  match label:
   "normal_three_straight": journey(label,false,false,false)
   "normal_three_corner": journey(label,false,true,false)
   "mixed_large_reverse": journey(label,true,false,false)
   "cancel_then_new_singleton", "cancel_then_follower_exit", "cancel_restart_same_group": journey(label,false,false,true)
   "mixed_cancel_exit": journey(label,true,false,true)
   "permissions": permission_boundary()
   "atomic_acquisition": atomic_acquisition()
   "held_fit_boundary": held_fit_boundary()
   "authorized_regroup_tail": authorized_regroup_tail()
   "serialized_obligations": serialized_obligations()
   _:
    push_error("Unknown selected case: "+label);quit(2);return
 save(".trace",trace)
 var ok: bool=true
 for row: Dictionary in rows: ok=ok and row.ok
 save(".result",{"ok":ok,"rows":rows,"selected":Array(selected),"tick_seconds":WorldState.TICK_SECONDS,"scope":"Selected door lifecycle regressions, not a full suite"})
 quit(0 if ok else 1)

# Legal initial inputs only. The tested reservation is acquired by actual motion.
func cancelled_boundary(outsider: bool = false) -> Dictionary:
 var sim: HospitalSimulation=suite._fixture();var w: WorldState=sim.world
 var build: CommandResult=suite._command(sim,"build_room",suite._room("room",[35,68],[8,8]))
 suite._add_actor(sim,"head","S49",[36,73]);suite._add_actor(sim,"middle","S49",[36,71]);suite._add_actor(sim,"tail","S49",[36,69])
 if outsider: suite._add_actor(sim,"outsider","S49",[36,79.5999908447266])
 var members: Array=["head","middle","tail"]
 var door: Dictionary=suite._doors(w,"room")[0]
 var checks: Dictionary={"built":build.accepted,"legal_input":w.validate(suite.content).is_empty(),"request":sim.space.request_group_move(w,"head",members,{},1,[36,84]).is_empty()}
 var found: bool=false
 for i: int in 80:
  suite._movement_tick(sim)
  var opening: Rect2=sim.space._door_rect(door,int(w.facts.adaptations.get(door.id,{"span":door.span}).span))
  if w.facts.adaptations.has(door.id) and not sim.space.body_rectangle(w.facts.actors.head).intersects(opening,false) and not overlaps_members(sim,members,opening,true).is_empty(): found=true;break
 if outsider: suite._movement_tick(sim)
 checks.actual_boundary=found
 var before: Dictionary=w.facts.actors.duplicate(true)
 checks.cancel=sim.space.cancel_ground_move(w,"head")
 checks.cancel_no_motion=before==w.facts.actors
 return {"sim":sim,"members":members,"door":door,"checks":checks}

func permission_boundary() -> void:
 var f: Dictionary=cancelled_boundary(true);var sim: HospitalSimulation=f.sim;var w: WorldState=sim.world
 var checks: Dictionary=f.checks;var door: Dictionary=f.door;var original: Dictionary=w.facts.adaptations.get(door.id,{}).duplicate(true)
 var opening: Rect2=sim.space._door_rect(door,int(original.get("span",door.span)))
 # Move the retained middle aside within the actual opening, rather than
 # teleporting it or letting a physical blocker mask reservation denials.
 checks.middle_aside_request=sim.space.request_move(w,"middle",1,[37,76]).is_empty()
 for i: int in 30:
  suite._movement_tick(sim)
  if not w.facts.moves.has("middle"): break
 checks.middle_really_aside=sim.space.at(w,"middle",1,[37,76])
 checks.held=w.facts.adaptations.get(door.id,{})==original
 save(".permissions.input",w.freeze())
 var no_sweeps: Dictionary=w.freeze()
 checks.original_member_allowed=RouteClearance.reservation_allows(original,"middle",["middle"])
 checks.outsider_denied=not RouteClearance.reservation_allows(original,"outsider",["outsider"])
 checks.owner_plus_outsider_denied=not RouteClearance.reservation_allows(original,"head",["head","outsider"])
 checks.outsider_plus_owner_denied=not RouteClearance.reservation_allows(original,"outsider",["outsider","head"])
 checks.dynamic_owner_plus_outsider_denied=not sim.space._dynamic_clear(w,"head",1,opening,["head","outsider"],true)
 checks.dynamic_outsider_plus_owner_denied=not sim.space._dynamic_clear(w,"outsider",1,opening,["outsider","head"],true)
 checks.permission_queries_readonly=no_sweeps==w.freeze()
 var reasons: Array=[]
 # A legal replacement group forms outside the door, but must not inherit
 # permission merely because its leader owned an earlier convoy.
 checks.new_group_request=sim.space.request_group_move(w,"head",["head","outsider"],{},1,[36,73]).is_empty()
 var witness: Dictionary=actual_denial(sim,"head",door,"permissions_new_group")
 var saw_reservation_denial: bool=witness.get("denied",false)
 var no_body_mask: bool=witness.get("body_ids",["missing"]).is_empty()
 var atomic: bool=witness.get("unchanged",false)
 reasons.append(witness)
 checks.actual_new_group_denied=saw_reservation_denial
 checks.no_physical_blocker_mask=no_body_mask
 checks.rejected_step_atomic=atomic
 checks.original_record_unchanged=w.facts.adaptations.get(door.id,{})==original
 checks.cancel_new_group=sim.space.cancel_ground_move(w,"head")
 checks.head_exit_request=sim.space.request_move(w,"head",1,[40,84]).is_empty()
 for i: int in 100:
  suite._movement_tick(sim)
  if not w.facts.moves.has("head"): break
 checks.head_really_clear=sim.space.at(w,"head",1,[40,84])
 checks.outsider_request=sim.space.request_move(w,"outsider",1,[36,74]).is_empty()
 var outsider_witness: Dictionary=actual_denial(sim,"outsider",door,"permissions_outsider")
 checks.actual_outsider_denied=outsider_witness.get("denied",false)
 checks.outsider_rejection_atomic=outsider_witness.get("unchanged",false)
 reasons.append(outsider_witness)
 checks.final_valid=w.validate(suite.content).is_empty()
 save(".permissions.final",w.freeze())
 var row: Dictionary={"case":"permissions","ok":not checks.values().has(false),"checks":checks,"denials":reasons}
 rows.append(row);print(JSON.stringify(row));sim.dispose()

func atomic_acquisition() -> void:
 var sim: HospitalSimulation=suite._fixture();var w: WorldState=sim.world
 suite._command(sim,"build_room",suite._room("first",[35,68],[8,8]))
 suite._command(sim,"build_room",suite._room("second",[45,68],[8,8]))
 suite._add_actor(sim,"actor","S49",[36,73]);suite._add_actor(sim,"other","S49",[46,73])
 var doors: Array[Dictionary]=[suite._doors(w,"first")[0],suite._doors(w,"second")[0]]
 var checks: Dictionary={"legal_input":w.validate(suite.content).is_empty()}
 # This declared pre-step boundary tests atomic multi-door acquisition only.
 # It does not claim a single body can move between these doors in one tick.
 var second: Rect2=sim.space._door_rect(doors[1],2)
 var held: HospitalMovement.MotionResult=HospitalMovement.MotionResult.new()
 checks.held_other=sim.space.movement._reserve_doors(w,w.facts.actors.other,{"actor_id":"other"},second,[doors[1]],held)
 var before: Dictionary=w.freeze()
 var motion: HospitalMovement.MotionResult=HospitalMovement.MotionResult.new()
 var broad: Rect2=sim.space._door_rect(doors[0],2).merge(second)
 checks.bundle_refused=not sim.space.movement._reserve_doors(w,w.facts.actors.actor,{"actor_id":"actor"},broad,doors,motion)
 checks.bundle_atomic=before==w.freeze() and not w.facts.adaptations.has(doors[0].id)
 checks.final_valid=w.validate(suite.content).is_empty()
 var row: Dictionary={"case":"atomic_acquisition","ok":not checks.values().has(false),"checks":checks,"denied_door":motion.door_id}
 rows.append(row);print(JSON.stringify(row));sim.dispose()

func serialized_obligations() -> void:
 var f: Dictionary=cancelled_boundary();var sim: HospitalSimulation=f.sim;var w: WorldState=sim.world
 var checks: Dictionary=f.checks;var door: Dictionary=f.door
 var snapshot: Dictionary=json_restore(w.freeze(),"serialized")
 checks.roundtrip_valid=WorldState.new(snapshot).validate(suite.content).is_empty()
 var variants: Array=[]
 for label: String in ["unchanged","integer_region","mixed_region","duplicate_participant","owner_not_repeated","missing_participant","wrong_region","small_envelope","short_envelope","tiny_insufficient_height"]:
  var candidate: Dictionary=snapshot.duplicate(true)
  var reservation: Dictionary=candidate.adaptations[door.id]
  var expected_valid: bool=label in ["unchanged","integer_region","mixed_region","duplicate_participant","owner_not_repeated"]
  match label:
   "integer_region":
    for axis: int in 4: reservation.regions[0][axis]=int(reservation.regions[0][axis])
   "mixed_region":
    for axis: int in [0,2]: reservation.regions[0][axis]=int(reservation.regions[0][axis])
   "duplicate_participant": reservation.staff_ids.append("middle")
   "owner_not_repeated": reservation.staff_ids.erase("head")
   "missing_participant": reservation.staff_ids.append("nonexistent_actor")
   "wrong_region": reservation.regions[0][0]+=1
   "small_envelope": reservation.convoy_envelope.size=0
   "short_envelope": reservation.convoy_envelope.height=0.1
   "tiny_insufficient_height": reservation.convoy_envelope.height=float(reservation.convoy_envelope.height)-0.0000005
  var world: WorldState=WorldState.new(json_restore(candidate,"serialized_"+label))
  var before: Dictionary=world.freeze()
  var error: String=world.validate(suite.content)
  var validation_readonly: bool=before==world.freeze()
  var passed: bool=error.is_empty()==expected_valid and validation_readonly
  var continuation: Dictionary={}
  if expected_valid and error.is_empty():
   var restored: HospitalSimulation=HospitalSimulation.new(world,suite.content)
   var held: Dictionary=world.facts.adaptations[door.id].duplicate(true)
   var errors: Array=[]
   var request_head: String=restored.space.request_move(world,"head",1,[40,84])
   var request_middle: String=restored.space.request_move(world,"middle",1,[36,81])
   for tick: int in 100:
    var before_step: Dictionary=world.freeze()
    suite._movement_tick(restored)
    errors.append_array(motion_errors(restored,before_step,f.members))
    var validation: String=world.validate(suite.content)
    if not validation.is_empty(): errors.append(validation)
    if world.facts.adaptations.has(door.id) and world.facts.adaptations[door.id]!=held: errors.append("Held representation was overwritten")
    if world.facts.moves.is_empty(): break
   var arrived: bool=restored.space.at(world,"head",1,[40,84]) and restored.space.at(world,"middle",1,[36,81]) and world.facts.moves.is_empty()
   continuation={"head_request":request_head,"middle_request":request_middle,"actual_arrival":arrived,"released":not world.facts.adaptations.has(door.id),"errors":errors,"final_tick":world.sim_tick}
   passed=passed and request_head.is_empty() and request_middle.is_empty() and arrived and continuation.released and errors.is_empty()
   restored.dispose()
  checks[label]=passed;variants.append({"case":label,"ok":passed,"expected_valid":expected_valid,"validation":error,"readonly":validation_readonly,"continuation":continuation})
 var empty_staff: Dictionary=single_owner_empty_staff()
 checks.single_owner_empty_staff=empty_staff.ok
 variants.append(empty_staff)
 var row: Dictionary={"case":"serialized_obligations","ok":not checks.values().has(false),"checks":checks,"variants":variants}
 rows.append(row);print(JSON.stringify(row));sim.dispose()

func json_restore(facts: Dictionary, label: String) -> Dictionary:
 var encoder: HospitalJsonStream=HospitalJsonStream.new()
 var path: String=ROOT+"."+label+".restore.json"
 if not encoder.encode(path,facts,func(_bytes:int)->bool:return true):
  push_error(encoder.error);return {}
 var decoder: HospitalJsonStream=HospitalJsonStream.new()
 var decoded: Dictionary=decoder.decode(path,encoder.bytes,encoder.digest,func(_bytes:int)->bool:return true)
 if not decoded.ok:
  push_error(decoder.error);return {}
 return decoded.value

func actual_denial(sim: HospitalSimulation, actor_id: String, door: Dictionary, label: String) -> Dictionary:
 var w: WorldState=sim.world
 for step: int in 80:
  var movement: Dictionary=w.facts.moves.get(actor_id,{})
  if movement.is_empty(): return {"denied":false,"reason":"Unexpected arrival"}
  if movement.path.is_empty() or int(movement.cursor)>=movement.path.size() or movement.get("route_pending",false):
   suite._movement_tick(sim)
   continue
  var segment: Dictionary=movement.path[int(movement.cursor)]
  if segment.kind!="floor": return {"denied":false,"reason":"Unexpected non-floor segment"}
  # Execute the actual dispatched route one fixed step at a time so that
  # the denial witness is captured before courtesy/detour bookkeeping.
  sim.space.movement._sweep_index.clear();sim.space.movement._accepted_sweeps.clear();sim.space._ensure_actor_index(w)
  var before: Dictionary=w.freeze()
  var motion: HospitalMovement.MotionResult=sim.space.movement._move_step(w,w.facts.actors[actor_id],movement,segment)
  if not motion.reservation_ids.is_empty():
   return {"denied":door.id in motion.reservation_ids,"unchanged":before==w.freeze(),"body_ids":motion.blocker_actor_ids,"reservation_ids":motion.reservation_ids,"actual_motion":[motion.actual_motion.x,motion.actual_motion.y],"tick":w.sim_tick,"valid":w.validate(suite.content).is_empty()}
  sim.space.release_adaptations(w);w.facts.sim_tick+=1;w.touch();sim.space.finish_boundary(w)
  state(sim,Array(w.facts.actors.keys()),door,label,{"validation":w.validate(suite.content)})
 return {"denied":false,"reason":"No reservation denial observed"}

func held_fit_boundary() -> void:
 var f: Dictionary=cancelled_boundary();var sim: HospitalSimulation=f.sim;var w: WorldState=sim.world
 var checks: Dictionary=f.checks;var door: Dictionary=f.door
 var held: Dictionary=w.facts.adaptations[door.id].duplicate(true)
 var opening: Rect2=sim.space._door_rect(door,int(held.span))
 var probes: Array=[]
 # These are pure held-opening admission calculations, not new actor/body
 # world facts or a claim of physical crossing by fabricated dimensions.
 for axis: String in ["equal","height","width"]:
  var proxy: Dictionary=w.facts.actors.head.duplicate(true)
  proxy._convoy_size=1
  proxy._convoy_body={"width_m":float(held.clear_width_m)-0.1,"depth_m":float(held.clear_width_m)-0.1,"height_m":float(held.clear_height_m)-0.1}
  if axis=="height": proxy._convoy_body.height_m+=0.0000005
  if axis=="width": proxy._convoy_body.width_m+=0.0000005
  var quote: Dictionary=sim.space.door_quote(w,proxy,1,door)
  var before: Dictionary=w.freeze()
  var motion: HospitalMovement.MotionResult=HospitalMovement.MotionResult.new()
  var accepted: bool=sim.space.movement._reserve_doors(w,proxy,{"actor_id":"head","members":["head"]},opening,[door],motion)
  checks[axis]=accepted==(axis=="equal") and before==w.freeze()
  probes.append({"axis":axis,"accepted":accepted,"quote":quote,"held_width":held.clear_width_m,"held_height":held.clear_height_m,"unchanged":before==w.freeze()})
 var row: Dictionary={"case":"held_fit_boundary","ok":not checks.values().has(false),"checks":checks,"probes":probes}
 rows.append(row);print(JSON.stringify(row));sim.dispose()

func authorized_regroup_tail() -> void:
 var sim: HospitalSimulation=suite._fixture();var w: WorldState=sim.world
 var built: CommandResult=suite._command(sim,"build_room",suite._room("room",[35,64],[8,12]))
 var members: Array=["head","middle","third","fourth"]
 for i: int in members.size(): suite._add_actor(sim,members[i],"S49",[36,73-2*i])
 var door: Dictionary=suite._doors(w,"room")[0]
 var checks: Dictionary={"built":built.accepted,"legal_input":w.validate(suite.content).is_empty(),"request":sim.space.request_group_move(w,"head",members,{},1,[36,84]).is_empty()}
 save(".authorized_regroup_tail.input",w.freeze())
 for i: int in 60:
  suite._movement_tick(sim)
  if float(w.facts.actors.third.location.cell[1])>=75.5: break
 var original: Dictionary=w.facts.adaptations.get(door.id,{}).duplicate(true)
 var opening: Rect2=sim.space._door_rect(door,int(original.get("span",door.span)))
 checks.acquired=not original.is_empty()
 checks.cancel=sim.space.cancel_ground_move(w,"head")
 checks.third_aside_request=sim.space.request_move(w,"third",1,[37,76]).is_empty()
 for i: int in 30:
  suite._movement_tick(sim)
  if not w.facts.moves.has("third"): break
 checks.third_still_inside=sim.space.at(w,"third",1,[37,76]) and sim.space.body_rectangle(w.facts.actors.third).intersects(opening,false)
 checks.original_record_before_regroup=w.facts.adaptations.get(door.id,{})==original
 checks.new_authorized_group=sim.space.request_group_move(w,"middle",["middle","head"],{},1,[36,70]).is_empty()
 checks.third_exit=sim.space.request_move(w,"third",1,[40,79]).is_empty()
 checks.fourth_exit=sim.space.request_move(w,"fourth",1,[40,70]).is_empty()
 var errors: Array=[];var gap_witness: Dictionary={};var final_release: int=-1
 for i: int in 180:
  var before_step: Dictionary=w.freeze()
  var had: bool=w.facts.adaptations.has(door.id)
  suite._movement_tick(sim)
  errors.append_array(motion_errors(sim,before_step,members))
  var bodies: Array=overlaps_members(sim,members,opening)
  var journey: Dictionary=w.facts.moves.get("middle",{})
  var intersects: bool=false
  if journey.has("convoy"):
   for region: Rect2 in ConvoyTrail.regions(journey.convoy):
    if region.intersects(opening,false): intersects=true
  if intersects and not w.facts.adaptations.has(door.id): errors.append({"kind":"new_leader_trail_released","tick":w.sim_tick})
  if intersects and bodies.is_empty(): gap_witness={"tick":w.sim_tick,"held":w.facts.adaptations.has(door.id),"current_leader":"middle","original_owner":original.get("actor_id"),"bodies_inside":bodies,"trail":journey.convoy.duplicate(true)}
  if w.facts.adaptations.has(door.id) and w.facts.adaptations[door.id]!=original: errors.append({"kind":"record_replaced","tick":w.sim_tick})
  if had and not w.facts.adaptations.has(door.id):
   final_release=w.sim_tick
   if intersects or not bodies.is_empty(): errors.append({"kind":"premature_release","tick":w.sim_tick})
  var error: String=w.validate(suite.content)
  if not error.is_empty(): errors.append({"kind":"validation","reason":error,"tick":w.sim_tick})
  state(sim,members,door,"authorized_regroup_tail",{"body_overlap":bodies,"new_trail_inside":intersects})
  if w.facts.moves.is_empty(): break
 checks.new_leader_gap_protected=not gap_witness.is_empty() and gap_witness.held
 checks.real_arrival=sim.space.at(w,"middle",1,[36,70]) and w.facts.moves.is_empty()
 checks.released=final_release>=0 and not w.facts.adaptations.has(door.id)
 checks.no_errors=errors.is_empty()
 save(".authorized_regroup_tail.final",w.freeze())
 var row: Dictionary={"case":"authorized_regroup_tail","ok":not checks.values().has(false),"checks":checks,"gap_witness":gap_witness,"release_tick":final_release,"errors":errors}
 rows.append(row);print(JSON.stringify(row));sim.dispose()

func motion_errors(sim: HospitalSimulation, before: Dictionary, members: Array) -> Array:
 var errors: Array=[];var budgets: Dictionary={}
 for id: String in members: budgets[id]=sim.space.walking_speed(before.actors[id])*WorldState.TICK_SECONDS
 for journey: Dictionary in before.moves.values():
  if journey.has("convoy"):
   for id: String in journey.members: budgets[id]=sim.space.walking_speed(before.actors[journey.actor_id])*WorldState.TICK_SECONDS
 for a: int in members.size():
  var actor: Dictionary=sim.world.facts.actors[members[a]]
  if ConvoyTrail.point(before.actors[members[a]].location.cell).distance_to(ConvoyTrail.point(actor.location.cell))>float(budgets[members[a]])+0.0001: errors.append({"kind":"step_budget","actor":members[a],"tick":sim.world.sim_tick})
  for b: int in range(a+1,members.size()):
   if sim.space.body_rectangle(actor).intersects(sim.space.body_rectangle(sim.world.facts.actors[members[b]]),false): errors.append({"kind":"body_overlap","actors":[members[a],members[b]],"tick":sim.world.sim_tick})
 return errors

func single_owner_empty_staff() -> Dictionary:
 var sim: HospitalSimulation=suite._fixture();var w: WorldState=sim.world
 var built: CommandResult=suite._command(sim,"build_room",suite._room("single_room",[35,68],[8,8]))
 suite._add_actor(sim,"only_owner","S49",[36,73])
 var door: Dictionary=suite._doors(w,"single_room")[0]
 var checks: Dictionary={"built":built.accepted,"legal_input":w.validate(suite.content).is_empty(),"request":sim.space.request_group_move(w,"only_owner",["only_owner"],{},1,[36,84]).is_empty()}
 var found: bool=false
 for tick: int in 80:
  suite._movement_tick(sim)
  if not w.facts.adaptations.has(door.id): continue
  var opening: Rect2=sim.space._door_rect(door,int(w.facts.adaptations[door.id].span))
  if sim.space.body_rectangle(w.facts.actors.only_owner).intersects(opening,false): found=true;break
 checks.actual_held_boundary=found
 if not found: sim.dispose();return {"case":"single_owner_empty_staff","ok":false,"checks":checks}
 checks.cancel=sim.space.cancel_ground_move(w,"only_owner")
 var facts: Dictionary=w.freeze()
 checks.genuine_single_owner=facts.adaptations[door.id].staff_ids==["only_owner"]
 facts.adaptations[door.id].staff_ids=[]
 var restored: WorldState=WorldState.new(json_restore(facts,"single_owner_empty_staff"))
 var before: Dictionary=restored.freeze()
 checks.restored_valid=restored.validate(suite.content).is_empty()
 checks.validation_readonly=before==restored.freeze()
 var invalid: Dictionary=restored.freeze()
 invalid.adaptations[door.id].convoy_envelope.height-=0.0000005
 var invalid_world: WorldState=WorldState.new(invalid)
 checks.implicit_owner_height_protected=not invalid_world.validate(suite.content).is_empty()
 sim.dispose();sim=HospitalSimulation.new(restored,suite.content);w=sim.world
 var held: Dictionary=w.facts.adaptations[door.id].duplicate(true)
 checks.departure_requested=sim.space.request_move(w,"only_owner",1,[36,84]).is_empty()
 var errors: Array=[]
 for tick: int in 100:
  var before_step: Dictionary=w.freeze()
  suite._movement_tick(sim)
  errors.append_array(motion_errors(sim,before_step,["only_owner"]))
  var validation: String=w.validate(suite.content)
  if not validation.is_empty(): errors.append(validation)
  if w.facts.adaptations.has(door.id) and w.facts.adaptations[door.id]!=held: errors.append("Empty staff list was overwritten")
  if w.facts.moves.is_empty(): break
 checks.actual_arrival=sim.space.at(w,"only_owner",1,[36,84]) and w.facts.moves.is_empty()
 checks.released=not w.facts.adaptations.has(door.id)
 checks.no_errors=errors.is_empty()
 var result: Dictionary={"case":"single_owner_empty_staff","ok":not checks.values().has(false),"checks":checks,"errors":errors,"final_tick":w.sim_tick}
 sim.dispose();return result
