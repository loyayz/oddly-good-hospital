extends RefCounted

# Read-only observation: dispatch and local control stay in production.
class ObservedMovement:
 extends HospitalMovement
 var corners: Array=[]
 func _init(s: HospitalSpace)->void:super(s)
 func _local_return_around_nearby(w: WorldState,a: Dictionary,m: Dictionary,q: RouteClearance,index: int,t: Vector2)->bool:
  var p: Array=a.location.cell.duplicate()
  var accepted: bool=super._local_return_around_nearby(w,a,m,q,index,t)
  if accepted and corners.size()<16:
   var record: Dictionary={"tick":w.sim_tick,"from":p,"first":m.local_move.target.cell.duplicate(),"rejoin_candidate":[t.x,t.y]}
   if w.facts.facilities.has("second"):
    var obstacle:=Rect2(44,71,1,2)
    record.second_obstacle_in_neighborhood=space.body_rectangle(a).grow(space.clearance(a)).intersects(obstacle,false)
    record.second_obstacle_at_first_corner=space._actor_rect(a,ConvoyTrail.point(m.local_move.target.cell)).grow(space.clearance(a)).intersects(obstacle,false)
    # Fixed independently specified feasible connector, not a search or motion driver.
    var points: Array=[Vector2(41,70),Vector2(41,73),Vector2(45,73),Vector2(45,70)]
    var previous: Rect2=space.body_rectangle(a)
    var previous_point: Vector2=ConvoyTrail.point(p)
    var legal: bool=true
    var rectangles: Array=[Rect2(42,69,2,1),Rect2(42,71,2,1),obstacle]
    for other: Dictionary in w.facts.actors.values():
     if other.id!=a.id:rectangles.append(space.body_rectangle(other))
    for point: Vector2 in points:
     var next: Rect2=space._actor_rect(a,point)
     legal=legal and q.sweep_reason(previous_point,point).is_empty()
     for rect: Rect2 in rectangles:
      legal=legal and not BodySweep.intersects(previous,next,rect,rect) and not next.intersects(rect,false)
     previous=next;previous_point=point
    record.four_leg_connector_clear=legal
    record.four_leg_connector=[[41,70],[41,73],[45,73],[45,70]]
   corners.append(record)
  return accepted

func run(content: HospitalContent, selected: Array)->Dictionary:
 var suite: RefCounted=load("res://tests/acceptance/space.gd").new();suite.content=content
 var rows: Array=[]
 for id: String in selected:
  rows.append(_case(suite,id) if id in ["LOCAL-CORNER-WIDE","LOCAL-CORNER-LOST"] else {"case":id,"ok":false,"error":"Unknown case"})
 var ok: bool=not rows.is_empty()
 for row: Dictionary in rows:ok=ok and row.ok
 return {"ok":ok,"cases":rows}

func _case(suite: RefCounted,id: String)->Dictionary:
 var started: int=Time.get_ticks_msec()
 var sim: HospitalSimulation=suite._fixture()
 var observer: ObservedMovement=ObservedMovement.new(sim.space);sim.space.movement=observer
 var furniture: Array=[]
 for item: Array in [["upper",[42,69]],["lower",[42,71]]]:
  HospitalFactory._add_facility(sim.world,{"id":item[0],"definition_id":"FUR05","anchor":item[1],"size":[2,1],"room_id":null},suite.content)
  furniture.append(Rect2(Vector2(item[1][0],item[1][1]),Vector2(2,1)))
 sim.world.touch()
 suite._add_actor(sim,"walker","S49",[41,70] if id=="LOCAL-CORNER-LOST" else [40,70])
 suite._add_actor(sim,"blocker","S49",[44,70])
 if id=="LOCAL-CORNER-LOST":
  # Legal initial geometry: a rotated two-cell desk extends the lower obstacle.
  HospitalFactory._add_facility(sim.world,{"id":"second","definition_id":"FUR05","anchor":[44,71],"size":[1,2],"room_id":null},suite.content)
  sim.world.facts.facilities.second.rotation=1
  furniture.append(Rect2(44,71,1,2))
  suite._add_actor(sim,"rear_guard","S49",[40,70])
  suite._add_actor(sim,"upper_guard","S49",[41,69])
  sim.world.touch()
 var initial_validation: String=sim.world.validate(suite.content)
 var request: String=sim.space.request_move(sim.world,"walker",1,[48,70])
 var sequence: int=int(sim.world.facts.moves.get("walker",{}).get("request_sequence",-1))
 var prepared: int=Time.get_ticks_msec()
 var result: Dictionary=_walk(suite,sim,furniture,sequence,true)
 result.fixture_ms=prepared-started;result.test_ms=Time.get_ticks_msec()-prepared;result.fixture_source="space.gd._fixture, ordinary desks and stationary people before request"
 result.case=id;result.request=request;result.initial_validation=initial_validation;result.corners=observer.corners
 result.ok=result.ok and request.is_empty() and initial_validation.is_empty() and not observer.corners.is_empty()
 if id=="LOCAL-CORNER-LOST":
  var witness: Dictionary=observer.corners[0] if not observer.corners.is_empty() else {}
  result.dropout_geometry_witness=witness.get("second_obstacle_in_neighborhood",false) and not witness.get("second_obstacle_at_first_corner",true) and witness.get("four_leg_connector_clear",false)
  result.ok=result.ok and result.dropout_geometry_witness and result.actual_dropout_corner_reached
 sim.dispose();return result

func _walk(suite: RefCounted,sim: HospitalSimulation,furniture: Array,sequence: int,save: bool)->Dictionary:
 var probe: RefCounted=load("res://tests/acceptance/unified_local_behavior.gd").new()
 var fixed_actors: Dictionary={}
 for actor_id: String in sim.world.facts.actors:
  if actor_id!="walker":fixed_actors[actor_id]=sim.world.facts.actors[actor_id].duplicate(true)
 var dropout: bool=false
 var malformed: Dictionary={}
 var errors: Array=[];var trace: Array=[];var preserved: bool=true;var cursor_ok: bool=true;var fixed: bool=true;var original: Array=[];var restored: Dictionary={};var local_count: int=0
 for tick: int in 350:
  var before: Dictionary=sim.world.facts.moves.get("walker",{}).duplicate(true)
  var before_cell: Vector2=ConvoyTrail.point(sim.world.facts.actors.walker.location.cell)
  var from: Rect2=sim.space.body_rectangle(sim.world.facts.actors.walker)
  var error: String=probe._tick(suite,sim,sim.world.facts.actors.keys())
  var body: Rect2=sim.space.body_rectangle(sim.world.facts.actors.walker)
  if not error.is_empty():errors.append(error)
  for rect: Rect2 in furniture:
   if body.intersects(rect,false) or BodySweep.intersects(from,body,rect,rect):errors.append("Static furniture body/sweep overlap")
  var move: Dictionary=sim.world.facts.moves.get("walker",{})
  var cell: Vector2=ConvoyTrail.point(sim.world.facts.actors.walker.location.cell)
  if original.is_empty() and not move.get("path",[]).is_empty():original=move.path.duplicate(true)
  if not move.is_empty():
   preserved=preserved and move.target_cell==[48,70] and int(move.request_sequence)==sequence and (original.is_empty() or move.path==original)
   if before.has("local_move") and int(move.cursor)>int(before.cursor):
    var rejoin: Dictionary=before.local_move.get("rejoin",{})
    cursor_ok=cursor_ok and not rejoin.is_empty() and Geometry2D.get_closest_point_to_segment(ConvoyTrail.point(rejoin.cell),before_cell,cell).distance_to(ConvoyTrail.point(rejoin.cell))<0.0001
   if move.has("local_move"):
    local_count+=1
    if save and malformed.is_empty() and move.local_move.get("corners",[]).size()==1:malformed=_invalid_corners(suite,sim)
    if sim.world.facts.facilities.has("second") and cell.distance_to(Vector2(41,70))<0.0001:
     dropout=not body.grow(sim.space.clearance(sim.world.facts.actors.walker)).intersects(Rect2(44,71,1,2),false)
    if save and restored.is_empty() and local_count==3:restored=_restore(suite,sim,furniture,sequence)
  for actor_id: String in fixed_actors:fixed=fixed and sim.world.facts.actors[actor_id]==fixed_actors[actor_id] and not sim.world.facts.moves.has(actor_id)
  if tick%10==0 or move.is_empty():trace.append({"tick":tick,"cell":[cell.x,cell.y],"cursor":move.get("cursor",-1),"local":move.get("local_move",{}).duplicate(true)})
  if not errors.is_empty() or move.is_empty():break
 var arrived: bool=sim.space.at(sim.world,"walker",1,[48,70]) and not sim.world.facts.moves.has("walker")
 var dispatches: int=int(sim.space.query_counts.get("route_dispatches",0))
 return {"ok":arrived and errors.is_empty() and preserved and cursor_ok and fixed and dispatches==(1 if save else 0) and (not save or restored.get("ok",false) and malformed.get("ok",false)),"arrived":arrived,"actual_dropout_corner_reached":dropout,"errors":errors,"goal_sequence_and_route":preserved,"cursor_only_at_real_rejoin":cursor_ok,"blocker_unchanged":fixed,"dispatches":dispatches,"restore":restored,"invalid_corner_states":malformed,"trace":trace,"remaining":sim.world.facts.moves.duplicate(true)}

func _restore(suite: RefCounted,sim: HospitalSimulation,furniture: Array,sequence: int)->Dictionary:
 var input: Dictionary=sim.world.freeze()
 var encoder:=HospitalJsonStream.new();var path: String="user://local-obstacle-corners.json"
 if not encoder.encode(path,input,func(_bytes: int)->bool:return true):return {"ok":false,"error":encoder.error}
 var decoder:=HospitalJsonStream.new()
 var decoded: Dictionary=decoder.decode(path,encoder.bytes,encoder.digest,func(_bytes: int)->bool:return true)
 if not decoded.ok:return {"ok":false,"error":decoder.error}
 var world:=WorldState.new(decoded.value)
 var exact: bool=world.freeze()==input and world.validate(suite.content).is_empty()
 var restored:=HospitalSimulation.new(world,suite.content)
 var result: Dictionary=_walk(suite,restored,furniture,sequence,false)
 result.stream_exact=exact;result.ok=result.ok and exact
 restored.dispose();return result

# Malformed saves start with an actually reached, valid live movement boundary.
# Each mutation is independent; no invalid world is used to drive motion.
func _invalid_corners(suite: RefCounted,sim: HospitalSimulation)->Dictionary:
 var input: Dictionary=sim.world.freeze()
 var reasons: Dictionary={}
 for kind: String in ["too_many","off_floor","diagonal","without_rejoin","repeated","reversing","rejoin_index"]:
  var changed: Dictionary=input.duplicate(true)
  var local: Dictionary=changed.moves.walker.local_move
  match kind:
   "too_many":
    while local.corners.size()<3:local.corners.append(local.corners[0].duplicate(true))
   "off_floor":local.corners[0].floor_id=2
   "diagonal":local.corners[0].cell[0]=float(local.corners[0].cell[0])+0.125
   "without_rejoin":local.erase("rejoin")
   "repeated":local.corners.append(local.corners[0].duplicate(true))
   "reversing":
    var backward: Dictionary=local.target.duplicate(true)
    backward.cell[0]=float(backward.cell[0])-1.0
    local.corners.push_front(backward)
   "rejoin_index":local.rejoin.index=changed.moves.walker.path.size()
  reasons[kind]=WorldState.new(changed).validate(suite.content)
 var ok: bool=WorldState.new(input).validate(suite.content).is_empty()
 for reason: String in reasons.values():ok=ok and not reason.is_empty()
 return {"ok":ok,"rejections":reasons}
