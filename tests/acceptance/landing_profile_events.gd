extends "res://tests/acceptance/directional_elevator_contract.gd"
func run()->void:
 suite.content=HospitalContent.new()
 var s:=fixture();var c:Dictionary=s.world.facts.connectors[suite._connection(s)];c.floor_id=4
 # Historical legal narrow public passage: walls leave y76..79 free.
 for x:int in range(32,65):
  s.world.facts.floors.overrides["1"].blocked.append([x,75])
  s.world.facts.floors.overrides["1"].blocked.append([x,79])
 s.world.touch()
 suite._add_actor(s,"small","S49",[48,77])
 var why:String=s.space.request_move(s.world,"small",2,[45,82]);var entry:Dictionary={}
 for i:int in 500:
  suite._movement_tick(s)
  entry=LiftLandingQueue.head(c,1,1)
  if not entry.is_empty() and not s.world.facts.moves.small.has("lift_boarding_call"):break
 var report:Dictionary={"request":why,"queue":entry.duplicate(true),"tick":s.world.sim_tick,"validation":s.world.validate(suite.content)}
 if not entry.is_empty():
  LiftLandingQueue.sync(s.space,s.world,c)
  var body:Rect2=LiftLandingQueue._body(s.space,s.world,s.world.facts.moves.small,entry.cell)
  report.before_safe=LiftLandingQueue._preserves_passage(s.space,s.world,1,body,[])
  report.before_basis=entry.get("layout_basis",[]).duplicate(true)
  var species:String=""
  for row:Dictionary in suite.content.catalog.species:
   var actor:Dictionary=suite._actor("probe",row.id,[48,76],1)
   if s.space.clearance(actor)==3 and float(s.space.body(actor).height_m)<4:species=row.id;break
  report.species=species
  suite._add_actor(s,"large",species,[48,76])
  report.large_legal=s.space.static_reason(s.world,s.world.facts.actors.large,1,Vector2i(48,76))
  report.after_safe=LiftLandingQueue._preserves_passage(s.space,s.world,1,body,[])
  var before:Dictionary=s.world.facts.actors.duplicate(true)
  LiftLandingQueue.sync(s.space,s.world,c)
  report.after_queue=LiftLandingQueue.head(c,1,1).duplicate(true)
  report.no_teleport=before==s.world.facts.actors
  report.after_validation=s.world.validate(suite.content)
  var initial_large: Array=s.world.facts.actors.large.location.cell.duplicate()
  report.large_move_request=s.space.request_move(s.world,"large",1,[34,76])
  var trace:Array=[];var overlaps:bool=false;var movement_errors:Array=[]
  for step:int in 180:
   suite._movement_tick(s)
   var move_validation:String=s.world.validate(suite.content)
   if not move_validation.is_empty():movement_errors.append(move_validation)
   overlaps=overlaps or s.space.body_rectangle(s.world.facts.actors.small).intersects(s.space.body_rectangle(s.world.facts.actors.large),false)
   if step%10==0:trace.append({"tick":s.world.sim_tick,"small":s.world.facts.actors.small.location.duplicate(true),"large":s.world.facts.actors.large.location.duplicate(true)})
  report.real_blocked_travel={"trace":trace,"no_overlap":not overlaps,"moved":s.world.facts.actors.large.location.cell!=initial_large,"completed":not s.world.facts.moves.has("large") and s.space.at(s.world,"large",1,[34,76]),"errors":movement_errors,"small_reason":s.world.facts.moves.small.get("waiting_reason","")}
  # End the ordinary test route before separate explicit publication events.
  s.space.movement.cancel_ground(s.world,"large")
  var signature:Array=s.space.passage_profile_signature(s.world,1).duplicate()
  var changes:int=s.space.passage_profile_changes
  s.world.facts.actors.large.location.cell=[49,76]
  s.space._sync_actor(s.world,"large")
  report.xy_no_rebuild=s.space.passage_profile_signature(s.world,1)==signature and s.space.passage_profile_changes==changes
  # Explicit event boundaries test derived-index invalidation, not journeys.
  suite._add_actor(s,"same_profile","S53",[54,76])
  report.same_profile_signature=s.space.passage_profile_signature(s.world,1)==signature
  var frozen:Dictionary=s.world.freeze()
  var cold:=HospitalSimulation.new(WorldState.new(frozen.duplicate(true)),suite.content)
  report.cold_signature=cold.space.passage_profile_signature(cold.world,1)==signature
  report.cold_queue=cold.world.facts.connectors[c.id].landing_queues==c.landing_queues
  report.cold_validation=cold.world.validate(suite.content)
  cold.dispose()
  # Removing the last profile on this floor changes the set; removing one
  # of two equivalent bodies does not. No entry is deleted or re-enqueued.
  s.world.facts.actors.same_profile.location={"kind":"outside"}
  s.space._sync_actor(s.world,"same_profile")
  report.duplicate_removal_stable=s.space.passage_profile_signature(s.world,1)==signature
  s.world.facts.actors.large.location.floor_id=2
  s.space._sync_actor(s.world,"large")
  report.cross_floor=s.space.passage_profile_signature(s.world,1)!=signature and s.space.passage_profile_signature(s.world,2).size()==1
  LiftLandingQueue.sync(s.space,s.world,c)
  var restored_entry:Dictionary=LiftLandingQueue.head(c,1,1)
  report.fifo_retained=restored_entry.get("arrived_tick",-1)==report.queue.arrived_tick and restored_entry.get("request_identity",[])==report.queue.request_identity
  report.queue_restored=not restored_entry.get("layout_blocked",false) and restored_entry.has("owner_cells")
  report.convoy_events=convoy_events()
  report.events_scope="Explicit legal body appearance/removal/floor-publication boundaries; not full admission or cross-floor journeys"
  report.blocked_head_unavailable=report.after_queue.get("layout_blocked",false) and not report.after_queue.has("owner_cells")
  report.ok=report.before_safe and not report.after_safe and report.large_legal.is_empty() and report.no_teleport and report.after_validation.is_empty() and report.xy_no_rebuild and report.same_profile_signature and report.cold_signature and report.cold_queue and report.cold_validation.is_empty() and report.duplicate_removal_stable and report.cross_floor and report.fifo_retained and report.queue_restored and report.blocked_head_unavailable and report.real_blocked_travel.no_overlap and report.real_blocked_travel.completed and report.real_blocked_travel.errors.is_empty() and report.convoy_events.ok
 var args:=OS.get_cmdline_user_args()
 if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
 print(JSON.stringify(report));s.dispose();quit(0 if report.get("ok",false) else 1)

func convoy_events()->Dictionary:
 var s:=fixture()
 suite._add_actor(s,"leader","S49",[45,86]);suite._add_actor(s,"follower","S49",[45,88])
 var before:Array=s.space.passage_profile_signature(s.world,1).duplicate()
 var requested:String=s.space.movement.request_group_move(s.world,"leader",["leader","follower"],{},1,[45,82])
 var during:Array=s.space.passage_profile_signature(s.world,1).duplicate()
 var original_semantics:bool=during.size()==2 and before[0] in during
 var errors:Array=[]
 for tick:int in 200:
  if not s.world.facts.moves.has("leader"):break
  suite._movement_tick(s)
  var err:String=s.world.validate(suite.content)
  if not err.is_empty():errors.append(err);break
 var complete:bool=not s.world.facts.moves.has("leader") and s.space.at(s.world,"leader",1,[45,82])
 var after:Array=s.space.passage_profile_signature(s.world,1).duplicate()
 var result:Dictionary={"ok":requested.is_empty() and original_semantics and complete and after==before and errors.is_empty(),"requested":requested,"original_follower_profile_kept":original_semantics,"complete":complete,"signature_restored":after==before,"errors":errors}
 s.dispose();return result
