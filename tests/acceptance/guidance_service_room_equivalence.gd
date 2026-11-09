extends "res://tests/acceptance/guidance_fixed_queue.gd"
func run_service_labels(content:HospitalContent)->Dictionary:
 _content=content
 var rows:Array=[]
 for mode:String in ["associated","unlabelled","changed_use"]:rows.append(_service(mode))
 var baseline:Dictionary=rows[0]
 var equivalent:bool=true
 for row:Dictionary in rows:
  equivalent=equivalent and row.ok and row.quote==baseline.quote and row.completion==baseline.completion
 var boundary:Dictionary=_boundaries()
 return {"ok":equivalent and boundary.ok,"same_quote_and_real_completion":equivalent,"cases":rows,"boundaries":boundary}
func _service(mode:String)->Dictionary:
 var x:Dictionary=_base()
 HospitalFactory._add_room(x.world,{"id":"guide_room","type":"gp","anchor":[49,71],"size":[8,8],"door":{"definition_id":"DR04","offset":3}},_content)
 _facility(x,"guide","SE01",[50,73],"guide_room")
 if mode=="unlabelled":x.world.facts.facilities.guide.erase("room_id")
 if mode=="changed_use":
  x.world.facts.rooms.guide_room.kind="physical"
  x.world.facts.rooms.guide_room.room_type_id="physical"
 x.world.touch()
 var visit:Dictionary=_visit(x,"service_probe",[52,83])
 var ticket:String=visit.ticket_id
 var original_position:Array=x.world.facts.actors[visit.actor_id].location.cell.duplicate()
 var raw:Dictionary=x.world.freeze()
 var full:Dictionary=x.space.facility_quote(x.world,"guide",visit.actor_id,["guide_nurse"])
 var readonly:bool=raw==x.world.freeze()
 var quote:Dictionary={}
 for key:String in ["ok","floor_id","footprint","patient_cell","operator_cells","repair_cell","regions","reason"]:
  if full.has(key):quote[key]=full[key]
 var safe:bool=true;var real_service:bool=true;var early:bool=false;var work_ticks:int=0;var ticks:int=0;var errors:Array=[]
 for tick:int in 900:
  _step(x);ticks=tick+1
  safe=safe and not _overlap(x,visit.actor_id)
  var row:Dictionary=x.g.state(x.world,visit.id)
  if row.get("phase","")=="working":
   work_ticks+=1
   var layout:Dictionary=x.space.facility_layout(x.world,"guide")
   real_service=real_service and x.space.at(x.world,visit.actor_id,1,layout.patient_cell) and x.space.at(x.world,"guide_nurse",1,layout.operator_cells[0]) and not x.world.facts.moves.has("guide_nurse")
  if row.get("phase","")!="ready":early=early or x.world.facts.adaptations.has("diagnosis") or not x.world.facts.sessions.is_empty()
  var validation:String=x.world.validate(_content)
  if not validation.is_empty():errors.append(validation);break
  if row.get("phase","")=="ready":break
 var state:Dictionary=x.g.state(x.world,visit.id)
 var complete:bool=state.get("phase","")=="ready" and state.get("receipts",[]).size()==1 and work_ticks>0
 var completion:Dictionary={"ticks":ticks,"work_ticks":work_ticks,"receipts":state.get("receipts",[]).duplicate(true),"location":x.world.facts.actors[visit.actor_id].location.duplicate(true)}
 var checks:Dictionary={"full_quote_accepted":full.get("ok",false),"quote_readonly":readonly,"real_guidance_completed":complete,"patient_really_walked":original_position!=x.world.facts.actors[visit.actor_id].location.cell,"patient_and_nurse_physically_at_service":real_service,"safe_body_steps":safe,"no_early_clinical_claim":not early,"original_ticket":visit.ticket_id==ticket,"valid_world":errors.is_empty()}
 var ok:bool=true
 for value:bool in checks.values():ok=ok and value
 var result:Dictionary={"case":mode,"ok":ok,"checks":checks,"quote":quote,"completion":completion,"errors":errors,"state":state.duplicate(true)}
 _dispose(x);return result
func _boundaries()->Dictionary:
 var x:Dictionary=_base()
 var guide:Dictionary=x.world.facts.facilities.guide
 var clinical:Dictionary=x.world.facts.facilities.diagnosis
 var room:Dictionary=x.world.facts.rooms.clinic
 # Same actual free region lies outside the clinical room. Desk operation
 # does not inherit room membership, while clinical furniture still does.
 var area:Array=[60,85,1,1];var rect:Rect2=Rect2(60,85,1,1)
 var desk_reason:String=x.space._facility_region_reason(x.world,guide,room,area,rect)
 var clinic_reason:String=x.space._facility_region_reason(x.world,clinical,room,area,rect)
 # The left clinic wall has real collision cells at x=33. An operating
 # rectangle crossing it is rejected regardless of the desk's room label.
 var wall_area:Array=[33,70,2,1];var wall_rect:Rect2=Rect2(33,70,2,1)
 var wall_reason:String=x.space._facility_region_reason(x.world,guide,{},wall_area,wall_rect)
 var checks:Dictionary={"SE01_free_region_not_restricted_by_room_label":desk_reason.is_empty(),"non_SE01_original_room_constraint_retained":clinic_reason.contains("超出本房间"),"SE01_real_wall_crossing_rejected":not wall_reason.is_empty()}
 var ok:bool=true
 for value:bool in checks.values():ok=ok and value
 var result:Dictionary={"ok":ok,"checks":checks,"desk_reason":desk_reason,"clinical_reason":clinic_reason,"wall_reason":wall_reason,"scope":"Explicit operation-region safety boundary; full quote and actual service are verified above."}
 _dispose(x);return result
