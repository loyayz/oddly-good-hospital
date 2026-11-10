extends "res://tests/acceptance/staff_fixtures.gd"

# A screen has no real user or maintenance task. Compare its presence with
# its absence, while retaining all actual geometry, bodies and reservations.
func run_cases(content: HospitalContent) -> Dictionary:
 _content=content
 var rows:Array=[]
 for restore:bool in [false,true]:rows.append(_portable(restore))
 rows.append(_safety())
 return {"passed":rows.all(func(row:Dictionary)->bool:return row.ok),"cases":rows}

func _screens(x:Dictionary)->void:
 for y:int in range(81,88):
  for xx:int in range(42,49):_facility(x,"panel_%d_%d"%[xx,y],"FUR23",[xx,y])
 x.world.touch()

func _portable(restore:bool)->Dictionary:
 var x:Dictionary=_fixture();_screens(x)
 var visit:Dictionary=_visit(x,"screen_wait",[45,85])
 var actor:Dictionary=x.world.facts.actors[visit.actor_id]
 var initial:String=x.world.validate(_content)
 var ticket_id:String=visit.ticket_id
 var waited:int=x.world.facts.tickets[ticket_id].waited_ticks
 var anger:float=visit.anger
 var definition:Dictionary=_content.facility_definition("FUR23")
 var no_work:bool=not definition.blocks_movement and definition.environment_function=="noise_barrier" and not definition.has("fit_profile_id") and not "FUR23" in _content.balance.equipment.maintained_definition_ids
 var safe:bool=x.space.public_areas.safe_wait(x.world,actor.id,1,actor.location.cell)
 var before_fields:int=int(x.space.query_counts.get("native_field_requests",0))
 x.l._begin_need(x.world,visit)
 var need:Dictionary=x.world.facts.waiting_life.needs[visit.id]
 var started:int=need.started_tick
 var start_ok:bool=need.phase=="fallback" and need.remaining_ticks==80 and not x.world.facts.moves.has(actor.id)
 var errors:Array=[];var premature:bool=false;var restored:bool=not restore;var before_restore_no_search:bool=true
 for tick:int in 80:
  if restore and tick==31:
   before_restore_no_search=int(x.space.query_counts.get("native_field_requests",0))==before_fields and int(x.space.query_counts.get("entry_order_builds",0))==0
   var saved:Dictionary=x.world.freeze()
   x.a.dispose();x=_bind(WorldState.new(saved))
   visit=x.world.facts.visits.screen_wait;actor=x.world.facts.actors[visit.actor_id]
   need=x.world.facts.waiting_life.needs[visit.id]
   restored=need.phase=="fallback" and need.remaining_ticks==49 and need.started_tick==started and visit.ticket_id==ticket_id and x.world.facts.tickets[ticket_id].waited_ticks==waited and x.world.facts.tickets[ticket_id].pause_reasons.need_service==need.id and visit.anger==anger and actor.location.cell==[45,85]
  if not x.world.facts.waiting_life.needs.has(visit.id):premature=true
  x.space.advance(x.world);x.l.advance(x.world);x.world.facts.sim_tick+=1;x.world.touch(false)
  var reason:String=x.world.validate(_content)
  if not reason.is_empty():errors.append(reason)
 var complete:bool=not x.world.facts.waiting_life.needs.has(visit.id)
 var unique:bool=visit.anger==anger+5.0 and x.world.facts.waiting_life.clocks[visit.id].next_purpose=="water"
 var resumed:bool=visit.ticket_id==ticket_id and x.world.facts.tickets[ticket_id].waited_ticks==waited and x.world.facts.tickets[ticket_id].pause_reasons.is_empty()
 var no_search:bool=before_restore_no_search and int(x.space.query_counts.get("native_field_requests",0))==before_fields and int(x.space.query_counts.get("entry_order_builds",0))==0
 var row:Dictionary={"case":"portable_restore" if restore else "portable_current_position","ok":initial.is_empty() and no_work and safe and start_ok and complete and unique and resumed and restored and not premature and errors.is_empty() and no_search and actor.location.cell==[45,85],"initial_validation":initial,"safe_current":safe,"started_without_move":start_ok,"actual_work_ticks":80,"no_early_completion":not premature,"completed":complete,"unique_effect":unique,"ticket_resumed":resumed,"restored_progress":restored,"no_standing_search":no_search,"errors":errors}
 x.l.advance(x.world)
 row.effect_still_unique=visit.anger==anger+5.0
 row.ok=row.ok and row.effect_still_unique
 x.a.dispose();return row

func _safety()->Dictionary:
 var x:Dictionary=_fixture()
 HospitalFactory._add_room(x.world,{"id":"waiting","type":"waiting","anchor":[34,66],"size":[10,12],"door":{"definition_id":"DR04","offset":3}},_content)
 _facility(x,"desk","FUR02",[38,80])
 _facility(x,"screen","FUR23",[45,85])
 var visit:Dictionary=_visit(x,"safety",[45,90])
 x.world.facts.actors.blocker={"id":"blocker","name":"blocker","species_id":"S49","facing":0.0,"posture":"standing","location":{"kind":"floor","floor_id":1,"cell":[46,86],"height_m":0.0}}
 x.world.touch()
 var without:WorldState=WorldState.new(x.world.freeze());without.facts.facilities.erase("screen");without.touch()
 var other:HospitalSpace=HospitalSpace.new(_content)
 var actor:Dictionary=x.world.facts.actors[visit.actor_id]
 var rows:Array=[];var equal:bool=true
 var points:Array=[[45,86],[46,85],[44,85],[45.25,86.125],[46,86],[39,81],[38,79],[40,80],[37,78],[37,77],[37,79],[34,65],[33,67],[48,95],[48,94],[32,64]]
 for species:String in ["S49","S02","S01"]:
  for facing:float in [0.0,PI*0.25,-0.62]:
   actor.species_id=species;actor.erase("body_binding_id");actor.facing=facing
   without.facts.actors[actor.id]=actor.duplicate(true)
   x.space.sync_actor(x.world,actor.id);other.sync_actor(without,actor.id)
   x.world.touch(false);without.touch(false)
   for point:Array in points:
    var a:bool=x.space.public_areas.safe_wait(x.world,actor.id,1,point)
    var b:bool=other.public_areas.safe_wait(without,actor.id,1,point)
    equal=equal and a==b;rows.append({"species":species,"facing":facing,"point":point,"with_screen":a,"without_screen":b})
 actor.species_id="S49";actor.facing=0.0;x.space.sync_actor(x.world,actor.id);x.world.touch(false)
 var protected:Dictionary={}
 for label:String in {"body":[46,86],"patient":[39,81],"operator":[38,79],"repair":[40,80],"door":[37,78],"wall":[34,65]}:
  var point:Array={"body":[46,86],"patient":[39,81],"operator":[38,79],"repair":[40,80],"door":[37,78],"wall":[34,65]}[label]
  protected[label]=not x.space.public_areas.safe_wait(x.world,actor.id,1,point)
 var allowed:bool=x.space.public_areas.safe_wait(x.world,actor.id,1,[45,86])
 var result:Dictionary={"case":"screen_does_not_relax_other_safety","ok":equal and allowed and not protected.values().has(false),"comparisons":rows.size(),"equal_to_no_screen":equal,"screen_nearby_allowed":allowed,"protected":protected,"observations":rows,"scope":"Read-only legal position/body input corpus; actual use and recovery are covered by the portable cases and existing affected acceptance cases."}
 x.a.dispose();return result
