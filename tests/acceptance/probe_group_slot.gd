extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
 var args:=OS.get_cmdline_user_args()
 var s:=HospitalSimulation.new(WorldState.new(FileAccess.open(args[0],FileAccess.READ).get_var(false)),HospitalContent.new())
 var rows:Array=[]
 print("FAMILY_ROUTE ",JSON.stringify(s.space.route(s.world,"max_family",1,[51,60],[],{},true)))
 print("FAMILY_ACTOR ",JSON.stringify(s.world.facts.actors.max_family))
 for c:Dictionary in s.world.facts.connectors.values():
  for g:Dictionary in LiftLandingQueue._groups(s.world,c.id).values():
   var slots:Dictionary=LiftLandingQueue._group_slots(s.space,s.world,c,g,[],false)
   var singles:Array=[];var used:Array=[]
   for id:String in g.leader_ids:
    var counts:Dictionary={"static":0,"side":0,"occupied":0,"passage":0,"route":0,"examples":[]}
    var slot:Dictionary=diagnose(s.space,s.world,c,s.world.facts.moves[id],int(g.floor_id),int(g.direction),used,false,counts)
    singles.append({"id":id,"slot":slot,"counts":counts})
    if not slot.is_empty():used.append(slot.body)
   rows.append({"group":g,"slots":slots,"singles":singles})
 FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify(rows,"\t"));print(JSON.stringify(rows));s.dispose();quit(0)

func diagnose(space: HospitalSpace, world: WorldState, connection: Dictionary, movement: Dictionary, floor_id: int, direction: int, occupied: Array, dynamic: bool, counts: Dictionary) -> Dictionary:
 var actor: Dictionary=world.facts.actors[movement.actor_id]
 var members: Array=movement.get("members",[actor.id])
 var offsets: Dictionary=movement.get("offsets",{})
 var normal: Vector2i=LiftLandingQueue._normal(connection)
 var side: Vector2i=Vector2i(normal.y,-normal.x)*direction
 var anchor: Vector2i=Vector2i(int(connection.anchor[0]),int(connection.anchor[1]))
 # Two disjoint half-planes leave a three-cell clear doorway corridor.
 # The bounded local search never invents a capacity or crosses geometry.
 # A legal maximum nursing waiting envelope can itself be 25 cells
 # wide. A fixed 24-cell search must not exclude every adjacent family
 # slot. Scale the finite local search to actual existing envelopes;
 # all ownership, passage, room and route checks remain unchanged.
 var extent: int=24
 for rect: Rect2 in occupied:
  extent=maxi(extent,ceili(maxf(rect.size.x,rect.size.y))+space.clearance(actor)+6)
 for distance: int in range(3,mini(95,extent)+1):
  for lateral: int in range(3,distance+1):
   var cell: Vector2i=anchor+side*lateral+normal*(distance-lateral)
   if cell.x<0 or cell.y<0 or cell.x>=96 or cell.y>=96: continue
   if movement.has("convoy"):
    var proxy: Dictionary=ConvoyTrail.proxy(world,movement)
    if not space.static_reason(world,proxy,floor_id,cell).is_empty(): counts.static+=1;continue
   else:
    if not space.static_reason(world,actor,floor_id,cell,members,offsets).is_empty(): counts.static+=1;continue
   var body: Rect2=LiftLandingQueue._body(space,world,movement,[cell.x,cell.y])
   var near: Vector2=body.position-Vector2(anchor)
   var far: Vector2=body.end-Vector2(anchor)
   var side_min: float=minf(near.dot(Vector2(side)),far.dot(Vector2(side)))
   if side_min<3.0: counts.side+=1;continue
   var free: bool=true
   for rect: Rect2 in occupied:
    if body.intersects(rect.grow(0.05),false): free=false;break
   if not free: counts.occupied+=1;continue
   # Waiting bodies must not spill into treatment rooms or the lift.
   for room: Dictionary in world.facts.rooms.values():
    if int(room.floor_id)==floor_id and body.intersects(Rect2(float(room.origin[0]),float(room.origin[1]),float(room.size[0]),float(room.size[1])),false): free=false;break
   if not free: counts.occupied+=1;continue
   if dynamic and not space._dynamic_clear(world,actor.id,floor_id,body,members): continue
   if not LiftLandingQueue._preserves_passage(space,world,floor_id,body,occupied): counts.passage+=1;continue
   if movement.has("convoy"):
    if not space.navigation.convoy_local_route(world,movement,floor_id,[cell.x,cell.y]).ok: continue
   elif not space.can_reach(world,actor.id,floor_id,[cell.x,cell.y],members,offsets,true): counts.route+=1;counts.examples.append([cell.x,cell.y]);continue
   return {"floor_id":floor_id,"cell":[cell.x,cell.y],"body":body}
 return {}
