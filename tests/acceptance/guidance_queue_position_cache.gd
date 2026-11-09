extends "res://tests/acceptance/guidance_queue_entry_boundary.gd"
func run_checks()->Dictionary:
 _content=HospitalContent.new()
 var x: Dictionary=_entry_fixture();var v: Dictionary=_visit(x,"probe",[40,85]);var id: String=v.actor_id
 var rows: Array=[]
 _check(x,x.world,id,"initial",rows)
 x.world.facts.floors.height_intervals=[{"first":1,"last":1,"height_m":0.3}];x.world.touch()
 _check(x,x.world,id,"lower_ceiling",rows)
 x.world.facts.floors.height_intervals=[{"first":1,"last":1,"height_m":6.0}];x.world.touch()
 _check(x,x.world,id,"raise_ceiling",rows)
 x.world.facts.actors[id].posture="lying";x.world.touch(false)
 _check(x,x.world,id,"lying",rows)
 x.world.facts.actors[id].species_id="S01";x.world.facts.actors[id].erase("body_binding_id");x.world.touch(false)
 _check(x,x.world,id,"large_body",rows)
 var projected=WorldState.new(x.world.freeze())
 _check(x,projected,id,"projection",rows)
 x.space._navigation._entries.clear()
 _check(x,x.world,id,"evicted_graphs",rows)
 var actor: Dictionary=x.world.facts.actors[id]
 var geometry: RouteClearance=x.space.navigation.structural_clearance(x.world,actor,99)
 var source: Dictionary=x.space._navigation.floor_source(x.space,x.world,99)
 rows.append({"case":"empty_floor","equal":x.space._navigation._graph_key(x.space,x.world,99,actor,[],{},geometry.source)==x.space._navigation._graph_key(x.space,x.world,99,actor,[],{},source)})
 _dispose(x)
 return {"rows":rows,"ok":rows.all(func(row:Dictionary)->bool:return row.equal)}
func _check(x:Dictionary,w:WorldState,id:String,label:String,rows:Array)->void:
 x.g._queue_context(w,"guide")
 var before=w.freeze();var span:int=x.space.clearance(w.facts.actors[id]);var cases:Array=[]
 for cell:Array in [[51,74],[51,75],[51,76],[54,78],[50,80],[40,85]]:
  x.g._queue_valid.clear()
  var old:bool=_reference(x.g,w,id,"guide",cell,span)
  x.g._queue_valid.clear()
  var fresh:bool=x.g._queue_position_allowed(w,id,"guide",cell,span)
  var hot:bool=x.g._queue_position_allowed(w,id,"guide",cell,span)
  cases.append({"cell":cell,"old":old,"fresh":fresh,"hot":hot})
 rows.append({"case":label,"equal":cases.all(func(row:Dictionary)->bool:return row.old==row.fresh and row.fresh==row.hot) and before==w.freeze(),"values":cases})

# Independent pre-optimization position proof for cold/hot equivalence.
func _reference(provider: HospitalFloorGuidance, world: WorldState, actor_id: String, desk_id: String, slot: Array, span: int) -> bool:
 var space: HospitalSpace=provider.space
 var content: HospitalContent=provider.content
 var _queue_valid: Dictionary=provider._queue_valid
 var floor_id: int=int(world.facts.facilities[desk_id].floor_id)
 var actor: Dictionary=world.facts.actors[actor_id]
 var geometry: RouteClearance=space.navigation.structural_clearance(world,actor,floor_id)
 var key: String=desk_id+":"+str(span)+":"+str(slot)+":"+space._navigation._graph_key(space,world,floor_id,actor,[],{},geometry.source)
 if _queue_valid.has(key):return _queue_valid[key]
 var point:=Vector2i(int(slot[0]),int(slot[1]))
 # Culling static obstacles to the desk's room is sound only if every
 # accepted body stays inside its actual cells, including concave rooms.
 var room_cells: Dictionary=provider._queue_context(world,desk_id).get("room_cells",{})
 if not room_cells.is_empty():
  for xx: int in range(point.x,point.x+span):
   for yy: int in range(point.y,point.y+span):
    if not room_cells.has(Vector2i(xx,yy)):
     if _queue_valid.size()>=512:_queue_valid.clear()
     _queue_valid[key]=false
     return false
 space.public_areas._ensure(world,floor_id)
 var valid: bool=geometry.reason(point).is_empty() and not space.public_areas._cell_region(floor_id,point).is_empty()
 var rectangle:=Rect2(Vector2(point),Vector2.ONE*span)
 if valid and preload("res://game/operations/guidance_queue_geometry.gd").overlaps_landing(world,content,floor_id,rectangle):valid=false
 if valid:
  for door: Dictionary in world.facts.floors.overrides.get(str(floor_id),{}).get("doors",[]):
   if rectangle.intersects(space._door_rect(door,int(door.span)).grow(1.0),false):valid=false;break
 if valid:
  for facility: Dictionary in world.facts.facilities.values():
   if int(facility.floor_id)!=floor_id:continue
   var points: Array=facility.get("operator_cells",[]).duplicate()
   points.append(facility.repair_cell)
   if facility.id!=desk_id:points.append(facility.patient_cell)
   for work: Array in points:
    if rectangle.intersects(Rect2(Vector2(work[0],work[1]),Vector2.ONE),false):valid=false;break
   if not valid:break
 if _queue_valid.size()>=512:_queue_valid.clear()
 _queue_valid[key]=valid
 return valid

