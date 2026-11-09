extends "res://tests/acceptance/floor_guidance.gd"

class Probe extends HospitalFloorGuidance:
 var watched:String=""
 var calls:Array=[]
 func _queue_point(world:WorldState,actor_id:String,desk_id:String,visit_id:String="")->Dictionary:
  var p:Dictionary=super._queue_point(world,actor_id,desk_id,visit_id)
  if actor_id==watched:calls.append({"tick":world.sim_tick,"at":world.facts.actors[actor_id].location.cell.duplicate(),"target":p.get("cell",[]).duplicate(),"moving":world.facts.moves.has(actor_id)})
  return p

func run_rules(database:HospitalContent)->Dictionary:
 _content=database
 var cases:Array=[_changing_tail(),_changing_tail(true),_blocked_boundary(),_leave_rejoin(),_nurse_pause()]
 return {"ok":cases.all(func(c:Dictionary)->bool:return c.ok),"cases":cases}

func _changing_tail(long_service:bool=false)->Dictionary:
 var old_registry:ContentRegistry=_content.registry
 if long_service:
  var fixture_data:Dictionary=_content.registry._data.duplicate(true)
  fixture_data.rules.guidance.nurse_seconds=9.0
  _content.registry=ContentRegistry.new(fixture_data)
 var x:Dictionary=_base()
 x.g=Probe.new(_content,x.space);x.g.clinic=x.c;x.g.waiting=x.l;x.c.floor_guidance=x.g;x.l.floor_guidance=x.g
 var near:Dictionary=_visit(x,"near",[48,85])
 if long_service:
  for tick:int in 500:
   _step(x)
   if x.g.state(x.world,near.id).get("phase","")=="working":break
 var far:Dictionary=_visit(x,"far",[35,94])
 x.g.watched=far.actor_id
 var joins:int=0;var leaves:int=0;var stable:bool=true;var checks:int=0;var prior:Array=x.g._desk_queue(x.world,"guide").duplicate()
 for tick:int in 700:
  var state:Dictionary=x.g.state(x.world,far.id)
  var before:Dictionary=x.world.facts.moves.get(far.actor_id,{}).duplicate(true)
  var underway:bool=not before.is_empty() and state.get("phase","")=="seek" and before.get("floor_guidance_key","")==state.get("request_key","")
  var calls:int=x.g.calls.size()
  if underway:
   x.g.prepare(x.world,far,x.world.facts.tickets[far.ticket_id]);checks+=1
   stable=stable and x.g.calls.size()==calls and x.world.facts.moves.get(far.actor_id,{}).get("target_cell",[])==before.target_cell and not state.has("queue_seq")
  _step(x)
  var queue:Array=x.g._desk_queue(x.world,"guide").duplicate()
  if underway:
   if near.id in queue and not near.id in prior:joins+=1
   if near.id in prior and not near.id in queue:leaves+=1
  prior=queue
  if not x.g.state(x.world,far.id).get("receipts",[]).is_empty():break
 var checks_out:Dictionary={"other_patient_really_joined_during_trip":joins>0 or long_service,"other_patient_really_left_during_trip":leaves>0,"no_lookup_retarget_or_preclaim_during_trip":checks>0 and stable,"far_completed_service":not x.g.state(x.world,far.id).get("receipts",[]).is_empty(),"valid":x.world.validate(_content).is_empty()}
 # Every later lookup must occur at the preceding recorded endpoint; no fake tail mutation.
 var arrived_before_lookup:bool=true
 for i:int in range(1,x.g.calls.size()):
  var a:Dictionary=x.g.calls[i-1];var b:Dictionary=x.g.calls[i]
  arrived_before_lookup=arrived_before_lookup and not b.moving and ConvoyTrail.point(b.at).distance_to(ConvoyTrail.point(a.target))<0.01
 checks_out.arrival_precedes_next_tail_lookup=arrived_before_lookup
 if long_service:
  var changed_after_arrival:bool=false
  for i:int in range(1,x.g.calls.size()):
   if x.g.calls[i-1].target!=x.g.calls[i].target:changed_after_arrival=true
  checks_out.different_tail_still_present_at_arrival=changed_after_arrival
 var out:Dictionary={"case":"real-long-service-tail" if long_service else "real-changing-tail","ok":checks_out.values().all(func(v:Variant)->bool:return v==true),"checks":checks_out,"joins":joins,"leaves":leaves,"observed_steps":checks,"lookups":x.g.calls.duplicate(true)}
 _dispose(x);_content.registry=old_registry;return out

# Boundary test of the actual failure handler, not a claim of physical full-queue integration.
func _blocked_boundary()->Dictionary:
 var x:Dictionary=_base()
 for tick:int in 500:
  x.g.dispatch(x.world);x.space.advance(x.world);x.g.advance(x.world);x.world.facts.sim_tick+=1
  if x.g._desk_usable(x.world,"guide"):break
 var v:Dictionary=_visit(x,"blocked",[40,90])
 x.g.prepare(x.world,v,x.world.facts.tickets[v.ticket_id])
 var s:Dictionary=x.g.state(x.world,v.id)
 x.g._cancel_own_move(x.world,v.actor_id,s);s.erase("queue_trip")
 x.g._queue_blocked(x.world,v,s)
 var waiting:bool=s.get("desk_id","")=="guide" and s.has("blocked_queue_revision") and not s.has("queue_seq")
 var revision:int=int(s.get("blocked_queue_revision",-1))
 for i:int in 5:x.g._approach_desk(x.world,v,x.world.facts.tickets[v.ticket_id],s)
 var no_retry:bool=not x.world.facts.moves.has(v.actor_id) and s.get("blocked_queue_revision",-2)==revision
 # Add real staffed alternate; then repeated blocked decisions can return to an earlier desk.
 HospitalFactory._add_staff(x.world,"nurse2","护士","nurse",[58,90],_content)
 x.d.ensure(x.world);x.s.ensure(x.world);x.w.ensure(x.world);x.r.ensure(x.world);x.f.ensure(x.world)
 _facility(x,"guide2","SE01",[58,83]);x.world.touch()
 for tick:int in 500:
  x.g.dispatch(x.world);x.space.advance(x.world);x.g.advance(x.world);x.world.facts.sim_tick+=1
  if x.g._desk_usable(x.world,"guide2"):break
 x.g._queue_blocked(x.world,v,s)
 var switched:bool=s.get("desk_id","")=="guide2" and not s.has("blocked_queue_revision")
 x.g._queue_blocked(x.world,v,s)
 var returned:bool=s.get("desk_id","")=="guide"
 var out:Dictionary={"case":"blocked-handler-boundaries","ok":waiting and no_retry and switched and returned,"sole_desk_wait":waiting,"no_retry_without_progress":no_retry,"alternate_staffed":x.g._desk_usable(x.world,"guide2"),"switch_other":switched,"can_return_no_attempt_history":returned}
 _dispose(x);return out

func _leave_rejoin()->Dictionary:
 var x:Dictionary=_base()
 var v:Dictionary=_visit(x,"leave",[50,85])
 var admitted:Dictionary={"ok":false}
 for tick:int in 600:
  _step(x)
  var q:Dictionary=x.g.state(x.world,v.id)
  if q.has("queue_seq") and q.get("phase","") in ["desk_queue","to_counter"]:
   admitted.ok=true
   break
 # External activity takes movement ownership after natural admission.
 x.g._cancel_own_move(x.world,v.actor_id,x.g.state(x.world,v.id))
 x.world.facts.staff.guide_nurse.on_shift=false
 var s:Dictionary=x.g.state(x.world,v.id)
 var number:int=int(s.get("queue_seq",-1))
 var reason:String=x.space.request_move(x.world,v.actor_id,1,[53,89])
 var removed:bool=false
 for tick:int in 400:
  x.space.advance(x.world);x.g.dispatch(x.world);x.world.facts.sim_tick+=1
  if not s.has("queue_seq"):removed=true
  if not x.world.facts.moves.has(v.actor_id):break
 var reached:bool=x.space.at(x.world,v.actor_id,1,[53,89])
 var staffed:bool=_restaff_only(x)
 var new_number:int=-1
 for tick:int in 700:
  _step(x)
  if s.has("queue_seq"):new_number=int(s.queue_seq);break
 var out:Dictionary={"case":"real-departure-rejoin","ok":admitted.ok and reason.is_empty() and removed and reached and staffed and new_number>number,"admitted":admitted.ok,"admission_detail":admitted,"external_move_error":reason,"physically_left_and_reached":reached,"old_number_removed":removed,"old_number":number,"new_number":new_number}
 _dispose(x);return out

func _nurse_pause()->Dictionary:
 var x:Dictionary=_base()
 var v:Dictionary=_visit(x,"nurse_pause_v2",[50,85])
 var admitted:bool=false
 for tick:int in 600:
  _step(x)
  var row:Dictionary=x.g.state(x.world,v.id)
  if row.has("queue_seq") and row.get("phase","") in ["desk_queue","to_counter"]:
   admitted=true;break
 var row:Dictionary=x.g.state(x.world,v.id)
 var number:int=int(row.get("queue_seq",-1))
 x.world.facts.staff.guide_nurse.on_shift=false
 var preserved:bool=admitted
 for tick:int in 150:
  _step(x)
  preserved=preserved and int(row.get("queue_seq",-2))==number and row.get("receipts",[]).is_empty()
 var paused:bool=not x.g._desk_usable(x.world,"guide")
 x.world.facts.staff.guide_nurse.on_shift=true
 var completed:bool=false
 var trace:Array=[]
 for tick:int in 700:
  _step(x)
  if tick>=680:
   var nm:Dictionary=x.world.facts.moves.get("guide_nurse",{})
   trace.append({"tick":x.world.sim_tick,"nurse_cell":x.world.facts.actors.guide_nurse.location.cell.duplicate(),"patient_cell":x.world.facts.actors[v.actor_id].location.cell.duplicate(),"target":nm.get("target_cell",[]).duplicate(),"sequence":nm.get("request_sequence",-1),"local":nm.get("local_move",{}).duplicate(true)})
  if not row.get("receipts",[]).is_empty():completed=true;break
 var out:Dictionary={"case":"natural-admission-nurse-pause","ok":admitted and preserved and paused and completed,"admitted":admitted,"number":number,"preserved_through_pause":preserved,"actually_unstaffed":paused,"last_twenty_steps":trace,"resumed_completed":completed,"validation":x.world.validate(_content),"state":row.duplicate(true),"nurse":x.world.facts.staff.guide_nurse.duplicate(true),"moves":x.world.facts.moves.duplicate(true)}
 _dispose(x);return out
