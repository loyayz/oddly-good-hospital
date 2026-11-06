extends SceneTree

const Old = preload("res://baseline.gd")
const New = preload("res://current.gd")
const World = preload("res://world.gd")
var checks: int = 0

func check(value: bool) -> void:
 checks += 1
 assert(value)

func world_with_doors(size: int):
 var world = World.new()
 var doors: Array = []
 for i in range(size): doors.append({"id":"d"+str(i),"span":1,"x":i,"y":1,"marker":i})
 world.facts = {"actors":{"actor":{"id":"actor","width":1,"location":{"floor_id":2}},"member":{"id":"member","width":3}},"floors":{"overrides":{"2":{"doors":doors}}}}
 return world

func entry(service, world) -> Dictionary:
 service.movement_doors(world,world.facts.actors.actor,Rect2(0,0,1,1),["actor","member"])
 return service._door_views.values()[0]

func exercise(size: int, mode: int, explicit_floor: bool) -> void:
 var world = world_with_doors(size)
 var old = Old.new()
 var current = New.new()
 var oe: Dictionary = entry(old,world)
 var ne: Dictionary = entry(current,world)
 var wanted: Dictionary = {}
 for i in range(size):
  if mode==1 or (mode==2 and i%3==0):
   oe.index.selected.push_front("d"+str(i))
   ne.index.selected.push_front("d"+str(i))
   wanted["d"+str(i)] = true
 var reservations: Array = [{"reservation":{"kind":"door"},"reservation_id":"missing"}]
 for i in range(size):
  if mode==3 or (mode==2 and i%2==0):
   reservations.append({"reservation":{"kind":"door"},"reservation_id":"d"+str(i)})
   reservations.append(reservations.back())
   wanted["d"+str(i)] = true
  reservations.append({"reservation":{"kind":"facility"},"reservation_id":"d"+str(i)})
 old.regions = reservations
 current.regions = reservations
 var expected: Array[Dictionary] = []
 for door: Dictionary in world.facts.floors.overrides["2"].doors:
  if wanted.has(door.id): expected.append(door)
 var before: Dictionary = world.facts.duplicate(true)
 for repeat in range(3):
  var floor: int = 2 if explicit_floor else 0
  var a: Array[Dictionary] = old.movement_doors(world,world.facts.actors.actor,Rect2(1,2,3,4),["actor","member"],floor)
  var b: Array[Dictionary] = current.movement_doors(world,world.facts.actors.actor,Rect2(1,2,3,4),["actor","member"],floor)
  check(a==b)
  check(b==expected)
  check(old.query_counts==current.query_counts)
  check(old.region_calls==current.region_calls and old.clearance_calls==current.clearance_calls)
  check(oe.index.calls==ne.index.calls)
  check(world.facts==before)
 # Version changes rebuild the source view, and stale broadphase inputs must go.
 old._navigation.version += 1
 current._navigation.version += 1
 old.regions=[]
 current.regions=[]
 check(old.movement_doors(world,world.facts.actors.actor,Rect2())==current.movement_doors(world,world.facts.actors.actor,Rect2()))
 check(current._door_views.values()[0].version==2)
 check(old.query_counts==current.query_counts)

func _init() -> void:
 for size in [0,1,4,32]:
  for mode in range(4):
   for explicit_floor in [false,true]: exercise(size,mode,explicit_floor)
 var windows: Array = []
 for count in [0,1,4,32]:
  var world = world_with_doors(32)
  var old = Old.new()
  var current = New.new()
  var oe: Dictionary = entry(old,world)
  var ne: Dictionary = entry(current,world)
  for i in range(count):
   oe.index.selected.append("d"+str(i))
   ne.index.selected.append("d"+str(i))
  var actor: Dictionary = world.facts.actors.actor
  for service in [old,current]:
   for i in range(1000): service.movement_doors(world,actor,Rect2(0,0,1,1),["actor"])
  for side in [0,1,1,0,0,1,1,0,0,1,1,0]:
   var service = old if side==0 else current
   var count_before: int = service.query_counts.door_candidates
   var start: int = Time.get_ticks_usec()
   for i in range(20000): service.movement_doors(world,actor,Rect2(0,0,1,1),["actor"])
   var elapsed: int = Time.get_ticks_usec()-start
   check(service.query_counts.door_candidates-count_before==count*20000)
   windows.append({"candidates":count,"side":side,"elapsed_us":elapsed})
 print(JSON.stringify({"checks":checks,"calls_per_window":20000,"windows":windows,"scope":"real movement_doors; explicit spatial/floor input adapters; not movement integration"}))
 quit()
