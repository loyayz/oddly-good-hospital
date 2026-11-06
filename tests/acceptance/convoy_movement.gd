extends SceneTree
var suite = preload("res://tests/acceptance/space.gd").new()
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
 suite.content = HospitalContent.new()
 var rows: Array = []
 for size: int in [1,2,3,8]: rows.append(_journey(size))
 rows.append(_journey(3,[42,80]))
 rows.append(_journey(3,[58,86],true))
 rows.append(_journey(2,[58.25,86.5]))
 rows.append(_journey(2,[52,80]))
 rows.append(_door())
 rows.append(_atomic_block())
 rows.append(_trail_geometry())
 rows.append(_retarget_atomic())
 rows.append(_fractional_cross_floor())
 var ok: bool = true
 for row: Dictionary in rows:
  ok = ok and bool(row.ok)
  print(JSON.stringify(row))
 var out: Dictionary = {"ok":ok,"rows":rows}
 var args: PackedStringArray = OS.get_cmdline_user_args()
 if not args.is_empty(): FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(out,"  "))
 quit(0 if ok else 1)
func _group(size: int, mixed: bool = false) -> HospitalSimulation:
 var sim: HospitalSimulation = suite._fixture()
 var members: Array = []
 for i: int in size:
  var id: String = "queue_"+str(i)
  members.append(id)
  suite._add_actor(sim,id,"S02" if mixed and i==1 else "S49",[54-2*i,80])
 var form: Dictionary = ConvoyTrail.formation(sim.space,sim.world,members[0],members,Vector2.RIGHT)
 for id: String in members:
  sim.world.facts.actors[id].location.cell = form.targets[id]
  sim.space.sync_actor(sim.world,id)
 return sim
func _journey(size: int, target: Array = [58,86], mixed: bool = false) -> Dictionary:
 var sim: HospitalSimulation = _group(size,mixed)
 var world: WorldState = sim.world
 var members: Array = []
 for i: int in size: members.append("queue_"+str(i))
 var reason: String = sim.space.request_group_move(world,members[0],members,{},1,target)
 var errors: Array = []
 var steps: int = 0
 var proposals: int = 0
 var restored: bool = false
 for i: int in 600:
  if not reason.is_empty(): break
  var before: int = int(sim.space.query_counts.get("convoy_leader_checks",0))
  suite._movement_tick(sim)
  proposals += int(sim.space.query_counts.get("convoy_leader_checks",0))-before
  if int(sim.space.query_counts.get("convoy_leader_checks",0))-before>1: errors.append("More than one leader permission per frame")
  steps += 1
  var validation: String = world.validate(suite.content)
  if not validation.is_empty(): errors.append(validation)
  for a: int in size:
   for b: int in range(a+1,size):
    if sim.space.body_rectangle(world.facts.actors[members[a]]).intersects(sim.space.body_rectangle(world.facts.actors[members[b]]),false): errors.append("Group bodies overlap")
  if not restored and i==10 and world.facts.moves.has(members[0]):
   var copy: WorldState = WorldState.new(world.freeze())
   var save_reason: String = copy.validate(suite.content)
   if not save_reason.is_empty(): errors.append("Restore: "+save_reason)
   restored = save_reason.is_empty()
  if not errors.is_empty() or not world.facts.moves.has(members[0]): break
 var arrived: bool = sim.space.at(world,members[0],1,target) and not world.facts.moves.has(members[0])
 var result: Dictionary = {"case":"queue_"+str(size)+("_behind_goal" if target==[42,80] else "_mixed_bodies" if mixed else "_fractional_goal" if target==[58.25,86.5] else "_current_tail_goal" if target==[52,80] else ""),"ok":reason.is_empty() and errors.is_empty() and arrived and proposals>0,"request":reason,"steps":steps,"leader_proposals":proposals,"arrived":arrived,"errors":errors,"restored":restored,"movement":world.facts.moves.get(members[0],{}) if not arrived else {}}
 sim.dispose()
 return result
func _atomic_block() -> Dictionary:
 var sim: HospitalSimulation = _group(3)
 var world: WorldState = sim.world
 var members: Array = ["queue_0","queue_1","queue_2"]
 var reason: String = sim.space.request_group_move(world,"queue_0",members,{},1,[58,80])
 if not reason.is_empty(): sim.dispose();return {"case":"blocked_atomic","ok":false,"reason":reason}
 var movement: Dictionary = world.facts.moves.queue_0
 suite._add_actor(sim,"blocker","S49",[55,80])
 # Place the actual blocker face 0.05 cells beyond the stationary front,
 # inside the next real 0.2-cell sweep, without starting in overlap.
 var face: float = sim.space.body_rectangle(world.facts.actors.blocker).position.x
 world.facts.actors.blocker.location.cell[0] += 55.05-face
 sim.space.sync_actor(world,"blocker")
 var actors: Dictionary = world.facts.actors.duplicate(true)
 var trail: Dictionary = movement.convoy.duplicate(true)
 var reservations: Dictionary = world.facts.adaptations.duplicate(true)
 var motion: HospitalMovement.MotionResult = sim.space.movement._move_step(world,world.facts.actors.queue_0,movement,{"kind":"floor","floor_id":1,"cell":[55,80]})
 var rejected: bool = motion.blocked and motion.actual_motion==Vector2.ZERO
 var unchanged: bool = actors==world.facts.actors and trail==movement.convoy and reservations==world.facts.adaptations
 var history: Array[Rect2] = ConvoyTrail.regions(trail)
 var middle: Rect2 = history[0]
 var tail_protected: bool = not sim.space._dynamic_clear(world,"intruder",1,Rect2(middle.get_center(),Vector2.ONE*0.25),[])
 var result: Dictionary = {"case":"blocked_atomic","ok":rejected and unchanged and tail_protected,"rejected":rejected,"unchanged":unchanged,"tail_protected":tail_protected}
 sim.dispose()
 return result
func _trail_geometry() -> Dictionary:
 var sim: HospitalSimulation = _group(3)
 var m: Array = ["queue_0","queue_1","queue_2"]
 var made: Dictionary = ConvoyTrail.create(sim.space,sim.world,"queue_0",m)
 var before: Dictionary = made.convoy.duplicate(true)
 var rejected: bool = false
 var safe: bool = true
 for i: int in 30:
  var snapshot: Dictionary = made.convoy.duplicate(true)
  var reverse: Dictionary = ConvoyTrail.propose(made.convoy,ConvoyTrail.point(made.convoy.points[-1])-Vector2.RIGHT*0.2)
  if not reverse.ok:
   rejected = true
   safe = safe and snapshot==made.convoy
   break
  made.convoy.points = reverse.points
  var poses: Dictionary = ConvoyTrail.positions(made.convoy,m)
  for a: int in m.size():
   for b: int in range(a+1,m.size()):
    var aa: Dictionary = sim.world.facts.actors[m[a]].duplicate(true)
    var bb: Dictionary = sim.world.facts.actors[m[b]].duplicate(true)
    aa.location.cell = poses[m[a]].cell;aa.facing=poses[m[a]].facing
    bb.location.cell = poses[m[b]].cell;bb.facing=poses[m[b]].facing
    if sim.space.body_rectangle(aa).intersects(sim.space.body_rectangle(bb),false): safe=false
 var result: Dictionary = {"case":"no_reverse_overlap","ok":rejected and safe,"rejected_before_overlap":rejected,"safe":safe}
 sim.dispose()
 return result

func _door() -> Dictionary:
 var sim: HospitalSimulation = suite._fixture()
 var world: WorldState = sim.world
 var built: CommandResult = suite._command(sim,"build_room",suite._room("door_room",[35,68],[8,8]))
 if not built.accepted:
  sim.dispose()
  return {"ok":false,"case":"queue_door","reason":"fixture room failed"}
 var door: Dictionary = suite._doors(world,"door_room")[0]
 suite._add_actor(sim,"leader","S49",[36,73])
 suite._add_actor(sim,"member","S49",[36,71])
 var formation: Dictionary = ConvoyTrail.formation(sim.space,world,"leader",["leader","member"],Vector2.DOWN)
 world.facts.actors.member.location.cell = formation.targets.member.duplicate()
 sim.space.sync_actor(world,"member")
 var request: String = sim.space.request_group_move(world,"leader",["leader","member"],{},1,[36,80])
 var safe: bool = true
 var valid: bool = true
 var held: bool = false
 var premature: bool = false
 var arrived: bool = false
 var last_reason: String = ""
 var ticks: int = 0
 for index: int in 300:
  suite._movement_tick(sim)
  ticks += 1
  valid = valid and world.validate(suite.content).is_empty()
  safe = safe and not sim.space.body_rectangle(world.facts.actors.leader).intersects(sim.space.body_rectangle(world.facts.actors.member),false)
  held = held or world.facts.adaptations.has(door.id)
  var opening: Rect2 = sim.space._door_rect(door,int(world.facts.adaptations.get(door.id,{"span":door.span}).span))
  var head: Vector2 = Vector2(world.facts.actors.leader.location.cell[0],world.facts.actors.leader.location.cell[1])
  var tail: Vector2 = Vector2(world.facts.actors.member.location.cell[0],world.facts.actors.member.location.cell[1])
  var occupied: Rect2 = Rect2(tail,Vector2.ONE).merge(Rect2(head,Vector2.ONE))
  if held and occupied.intersects(opening,false) and not world.facts.adaptations.has(door.id): premature = true
  last_reason = world.facts.moves.get("leader",{}).get("waiting_reason","")
  if not world.facts.moves.has("leader") and sim.space.at(world,"leader",1,[36,80]):
   arrived = true
   break
 sim.space.release_adaptations(world)
 var released: bool = not world.facts.adaptations.has(door.id)
 var result: Dictionary = {"ok":request.is_empty() and safe and valid and held and not premature and arrived and released,"case":"queue_door","request":request,"safe":safe,"valid":valid,"held":held,"premature_release":premature,"actual_goal":arrived,"released":released,"ticks":ticks,"last_reason":last_reason,"leader":world.facts.actors.leader.location,"member":world.facts.actors.member.location}
 sim.dispose()
 return result

func _retarget_atomic() -> Dictionary:
 var sim: HospitalSimulation = _group(2)
 var world: WorldState = sim.world
 var members: Array = ["queue_0","queue_1"]
 var request: String = sim.space.request_group_move(world,"queue_0",members,{},1,[58,80])
 var cases: Array = [[1,[NAN,80]],[1,[INF,80]],[1,[80]],[1,[true,80]],[1,[-1,80]],[0,[58,80]],[1,[96,80]]]
 var safe: bool = request.is_empty()
 var rejected: int = 0
 for item: Array in cases:
  var before: Dictionary = world.freeze()
  var reason: String = sim.space.request_group_move(world,"queue_0",members,{},int(item[0]),item[1])
  if not reason.is_empty(): rejected+=1
  safe = safe and not reason.is_empty() and before==world.freeze()
 sim.dispose()
 return {"case":"invalid_retarget_atomic","ok":safe,"rejected":rejected,"cases":cases.size()}

func _fractional_cross_floor() -> Dictionary:
 var sim: HospitalSimulation = suite._transit_fixture()
 suite._add_actor(sim,"fractional_head","S49",[44.25,80.25])
 suite._add_actor(sim,"fractional_tail","S49",[42.25,80.25])
 var world: WorldState = sim.world
 var members: Array = ["fractional_head","fractional_tail"]
 var before: Dictionary = world.freeze()
 var quote: Dictionary = sim.space.route_cost(world,members[0],2,[46,84],members,{},true)
 var readonly: bool = before==world.freeze()
 var request: String = sim.space.request_group_move(world,members[0],members,{},2,[46,84])
 var safe: bool = true
 var bounded: bool = true
 var validation: String = ""
 var ticks: int = 0
 for tick: int in 600:
  if not request.is_empty() or not world.facts.moves.has(members[0]): break
  var head: Vector2 = ConvoyTrail.point(world.facts.moves[members[0]].convoy.points[-1])
  var checks: int = int(sim.space.query_counts.get("convoy_leader_checks",0))
  suite._movement_tick(sim)
  ticks = tick+1
  var actor: Dictionary = world.facts.actors[members[0]]
  var next: Vector2 = ConvoyTrail.point(world.facts.moves[members[0]].convoy.points[-1]) if world.facts.moves.has(members[0]) else ConvoyTrail.point(actor.location.cell)
  bounded = bounded and head.distance_to(next)<=sim.space.walking_speed(actor)*WorldState.TICK_SECONDS+0.0001 and int(sim.space.query_counts.get("convoy_leader_checks",0))-checks<=1
  var rectangles: Array = []
  for id: String in members:
   var member: Dictionary = world.facts.actors[id]
   var cell: Array = member.location.cell if member.location.kind=="floor" else member.location.queue_cell
   rectangles.append(sim.space._actor_rect(member,ConvoyTrail.point(cell)))
  safe = safe and not rectangles[0].intersects(rectangles[1],false)
  validation = world.validate(suite.content)
  if not validation.is_empty() or not safe or not bounded: break
 var arrived: bool = not world.facts.moves.has(members[0]) and sim.space.at(world,members[0],2,[46,84])
 var result: Dictionary = {"case":"fractional_start_cross_floor","ok":quote.get("ok",false) and readonly and request.is_empty() and arrived and safe and bounded and validation.is_empty(),"quote":quote,"readonly":readonly,"request":request,"arrived":arrived,"safe":safe,"bounded":bounded,"validation":validation,"ticks":ticks}
 sim.dispose()
 return result
