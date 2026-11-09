extends RefCounted
const Layout=preload("res://game/operations/guidance_queue_layout.gd")

func run_checks()->Dictionary:
 var cases:Array=[]
 var desk:Dictionary={"cell":[10,20],"footprint":[6,2],"rotation":0}
 var unit:Dictionary=_body(1.0,1.0)
 var pack:Dictionary=Layout.snake(desk,[unit,unit,unit,unit,unit,unit,unit,unit,unit,unit,unit])
 var p:Array=pack.placements
 cases.append({"name":"center_right_then_reverse","ok":_same(p[0].local_rect,Rect2(-0.5,0,1,1)) and _same(p[1].local_rect,Rect2(0.5,0,1,1)) and _same(p[2].local_rect,Rect2(1.5,0,1,1)) and _same(p[3].local_rect,Rect2(2,1,1,1)) and _same(p[4].local_rect,Rect2(1,1,1,1)) and int(p[9].row)==2 and _same(p[9].local_rect,Rect2(-3,2,1,1))})
 cases.append({"name":"faces_predecessor","ok":is_zero_approx(angle_difference(float(p[0].facing),PI)) and is_zero_approx(angle_difference(float(p[1].facing),-PI*0.5)) and is_zero_approx(angle_difference(float(p[4].facing),PI*0.5))})
 var narrow:Dictionary=Layout.snake({"cell":[0,0],"footprint":[1,2]},[unit,_body(1.5,0.75),unit])
 var n:Array=narrow.placements
 cases.append({"name":"single_file_left_edges_actual_size","ok":n[1].single and is_equal_approx(n[0].local_rect.position.x,n[1].local_rect.position.x) and is_equal_approx(n[1].local_rect.position.x,n[2].local_rect.position.x) and is_equal_approx(n[1].local_rect.size.x,1.5) and is_equal_approx(n[2].local_rect.position.y,n[1].local_rect.end.y)})
 var mixed:Array=[_body(0.7,0.4),_body(1.4,0.8),_body(0.6,1.2),_body(2.1,0.9),unit,_body(0.4,0.3),unit,_body(1.9,1.2),unit,unit]
 var reference:Dictionary=Layout.snake(desk,mixed)
 for turn:int in range(4):
  var rotated:Dictionary={"cell":[10,20],"footprint":[6,2] if turn%2==0 else [2,6],"rotation":turn}
  var rotated_pack:Dictionary=Layout.snake(rotated,mixed)
  var safe:bool=true;var exact:bool=true;var equivalent:bool=true
  for index:int in range(rotated_pack.placements.size()):
   var item:Dictionary=rotated_pack.placements[index]
   var angle:int=posmod(roundi(float(item.facing)/(PI*0.5)),4)
   var shape:Rect2=mixed[index].shapes[angle]
   exact=exact and _same(Rect2(Vector2(item.cell[0],item.cell[1])+shape.position,shape.size),item.rect)
   equivalent=equivalent and _same(item.local_rect,reference.placements[index].local_rect)
   for other:int in range(index):
    safe=safe and not item.rect.intersects(rotated_pack.placements[other].rect,false)
  cases.append({"name":"mixed_actual_shapes_rotation_"+str(turn),"ok":safe and exact and equivalent,"safe":safe,"exact_engine_cell_offsets":exact,"rotation_equivalent":equivalent})
 for turn:int in range(4):
  var anchored:Dictionary={"cell":[10,20],"footprint":[6,2] if turn%2==0 else [2,6],"rotation":turn}
  var anchors:Array=[[10,22],[9,20],[15,19],[12,25]]
  anchored.queue_front_cell=anchors[turn]
  var small:Dictionary=_body(0.7,0.4)
  var empty:Dictionary=Layout.snake(anchored,[])
  var probe:Dictionary=Layout.snake_append(empty,small)
  var first:Dictionary=Layout.snake(anchored,[small]).placements[0]
  var front:Vector2=empty.front
  var anchor:Vector2=Vector2(anchors[turn][0],anchors[turn][1])
  var origin:Vector2=Vector2(probe.cell[0],probe.cell[1])
  var center:Vector2=probe.rect.get_center()
  cases.append({"name":"service_anchor_first_probe_rotation_"+str(turn),"ok":probe==first and is_equal_approx(origin.dot(front),anchor.dot(front)) and is_equal_approx((center-Vector2(empty.edge)).dot(empty.right),0.0) and empty.placements.is_empty()})
 var before:Dictionary=reference.duplicate(true)
 var next:Dictionary=Layout.snake_append(reference,_body(3.5,0.5))
 cases.append({"name":"probe_does_not_reserve_or_repack","ok":before==reference and not next.is_empty()})
 Layout.snake_accept(reference,next)
 cases.append({"name":"accepted_member_appended_only_once","ok":reference.placements.size()==before.placements.size()+1 and reference.placements.back()==next})
 var ok:bool=true
 for item:Dictionary in cases:ok=ok and item.ok
 return {"ok":ok,"cases":cases,"scope":"Pure geometry only; no movement, wall reachability, admission or service completion claimed."}

func _body(width:float,depth:float)->Dictionary:
 var span:float=ceilf(maxf(width,depth))
 var shapes:Array=[]
 for turn:int in range(4):
  var size:=Vector2(width,depth) if turn%2==0 else Vector2(depth,width)
  shapes.append(Rect2((Vector2.ONE*span-size)*0.5,size))
 return {"shapes":shapes}
func _same(a:Rect2,b:Rect2)->bool:return a.position.is_equal_approx(b.position) and a.size.is_equal_approx(b.size)
