extends "res://tests/acceptance/guidance_fixed_queue.gd"
const Packing=preload("res://game/operations/guidance_queue_layout.gd")
func run_connectors(content: HospitalContent)->Dictionary:
 _content=content
 var rows: Array=[]
 for kind: String in ["VC01","VC02"]:
  var x: Dictionary=_base(false,true)
  # Keep the original remote lift so stair removal preserves upper-floor access.
  _facility(x,"guide","SE01",[55,83]);x.world.touch()
  var visitor: Dictionary=_visit(x,"probe",[35,89])
  var spans: Array=[1,1,1,1,1]
  var valid: Callable=func(_i: int,cell: Array)->bool:return x.g._queue_position_allowed(x.world,visitor.actor_id,"guide",cell,1)
  var before: Dictionary=x.g._queue_context(x.world,"guide")
  var original: Dictionary=Packing.pack(before.facility,before.walls,before.bounds,spans,valid)
  var service:=HospitalConnectors.new(_content,x.space)
  var command: CommandResult=service.execute(x.world,"connector_build",{"definition_id":kind,"floor_id":1,"cell":[55,90],"rotation":2})
  x.world.touch()
  var ctx: Dictionary=x.g._queue_context(x.world,"guide")
  var after: Dictionary=Packing.pack(ctx.facility,ctx.walls,ctx.bounds,spans,valid)
  var solid_shortened: bool=not after.complete or after.placements[-1]!=original.placements[-1]
  var connection: Dictionary=x.world.facts.connectors.get(str(command.changed_ids[0]),{}) if command.accepted else {}
  var landing_allowed: bool=not connection.is_empty() and x.g._queue_position_allowed(x.world,visitor.actor_id,"guide",connection.anchor,1)
  var landing_bounds: bool=false
  if not connection.is_empty():
   var only:=WorldState.new(x.world.freeze())
   only.facts.connectors={connection.id:connection.duplicate(true)}
   var ports=preload("res://game/operations/guidance_queue_geometry.gd")
   var a:=Vector2(float(connection.anchor[0]),float(connection.anchor[1]))
   var size: int=int(_content.definition("vertical_connectors",kind).max_clearance_cells)
   landing_bounds=ports.overlaps_landing(only,_content,1,Rect2(a,Vector2.ONE)) and ports.overlaps_landing(only,_content,1,Rect2(a-Vector2(2,2),Vector2(3,3))) and not ports.overlaps_landing(only,_content,1,Rect2(a+Vector2(size,0),Vector2.ONE)) and not ports.overlaps_landing(only,_content,3,Rect2(a,Vector2.ONE))
  var removed: CommandResult=service.execute(x.world,"connector_remove",{"connection_id":connection.get("id","")})
  x.world.touch()
  var restored_context: Dictionary=x.g._queue_context(x.world,"guide")
  var restored: Dictionary=Packing.pack(restored_context.facility,restored_context.walls,restored_context.bounds,spans,valid)
  var recovered: bool=removed.accepted and restored.placements==original.placements
  rows.append({"ok":command.accepted and original.complete and solid_shortened and recovered and not landing_allowed and landing_bounds,"shortened_before_shaft":solid_shortened,"remove_command":removed.to_record(),"restores_after_demolish":recovered,"landing_bounds_large_overlap_edge_touch_other_floor":landing_bounds,"landing_queue_position_allowed":landing_allowed,"built_connection":connection,"kind":kind,"command":command.to_record(),"original":original.placements,"after":after.placements,"complete":after.complete,"connectors":x.world.facts.connectors.duplicate(true),"validation":x.world.validate(_content),"front_check":BuildService.new(_content,x.space).guidance_front_error(x.world,x.world.facts.facilities.guide)})
  _dispose(x)
 return {"passed":not rows.any(func(r: Dictionary)->bool:return not r.ok),"rows":rows}
