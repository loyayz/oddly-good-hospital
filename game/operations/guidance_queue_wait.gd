extends RefCounted

# A waiting point is a present physical choice, never a place reservation or a
# queue number. The existing movement owns the walk and collision checks.
static func allowed(space: HospitalSpace, world: WorldState, actor_id: String, context: Dictionary, cell: Array) -> bool:
 if context.is_empty():return false
 var actor: Dictionary=world.facts.actors[actor_id]
 var point:=Vector2(float(cell[0]),float(cell[1]))
 var body: Rect2=space._actor_rect(actor,point)
 if body.intersects(context.room_bounds,false):return false
 for door: Rect2 in context.door_bounds:
  if body.intersects(door.grow(2.0),false):return false
 if not space.public_areas.safe_wait(world,actor_id,int(context.floor_id),cell):return false
 # Do not turn a one-body-wide passage into an overflow waiting area. A
 # static bypass around this body's envelope must exist on at least one side.
 var fixed: RouteClearance=space.navigation.structural_clearance(world,actor,int(context.floor_id))
 var width: float=float(space.clearance(actor))
 for forward: Vector2 in [Vector2.RIGHT,Vector2.DOWN]:
  var side:=Vector2(-forward.y,forward.x)
  for sign: float in [-1.0,1.0]:
   var a: Vector2=point-forward*width
   var b: Vector2=a+side*width*sign
   var c: Vector2=point+forward*width+side*width*sign
   var d: Vector2=point+forward*width
   if fixed.sweep_reason(a,b).is_empty() and fixed.sweep_reason(b,c).is_empty() and fixed.sweep_reason(c,d).is_empty():return true
 return false

static func choose(space: HospitalSpace, world: WorldState, actor_id: String, context: Dictionary) -> Dictionary:
 if context.is_empty():return {}
 var actor: Dictionary=world.facts.actors[actor_id]
 if actor.location.kind!="floor" or int(actor.location.floor_id)!=int(context.floor_id):return {}
 var origin:=Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))
 if allowed(space,world,actor_id,context,actor.location.cell):return {"floor_id":int(context.floor_id),"cell":actor.location.cell.duplicate()}
 # Bounded local fallback. A hospital with no nearby safe exterior space
 # keeps the request pending; it does not park someone inside a doorway.
 var center:=Vector2i(origin.round())
 for radius: int in range(1,13):
  for dx: int in range(-radius,radius+1):
   var dy: int=radius-absi(dx)
   var ys: Array=[dy] if dy==0 else [dy,-dy]
   for y: int in ys:
    var cell: Array=[center.x+dx,center.y+y]
    if not allowed(space,world,actor_id,context,cell):continue
    if space.can_reach(world,actor_id,int(context.floor_id),cell,[],{},true):return {"floor_id":int(context.floor_id),"cell":cell}
 return {}
