extends RefCounted
# Diagnostic boundary fixtures, not a legal complete transit journey. The
# connector marker must never be reached/executed in these bounded probes.
func _point(x: float,y: float) -> Dictionary:
 return {"kind":"floor","floor_id":1,"cell":[x,y]}
func _portal() -> Dictionary:
 return {"kind":"connector","connector_id":"predicate_boundary_only","from":1,"to":2}
func _setup(suite: RefCounted, blocker: Array, original: Array) -> Dictionary:
 var sim: HospitalSimulation=suite._fixture()
 suite._add_actor(sim,"walker","S49",[35,71])
 suite._add_actor(sim,"anchor_occupant","S49",blocker)
 var request: String=sim.space.request_move(sim.world,"walker",1,[45,70])
 var move: Dictionary=sim.world.facts.moves.walker
 # Explicit already-completed side-step state. No invented admission/service.
 move.path=[];move.cursor=0;move.route_pending=false
 move.travelled=[_point(35,70),_point(35,71)]
 move.detour={"phase":"aside","prefix_size":0,"resume_index":-1,"direction":[1,0],"original_path":original,"backtrack":move.travelled.duplicate(true),"back_cursor":1}
 return {"sim":sim,"move":move,"request":request}
func run(content: HospitalContent) -> Dictionary:
 var suite: RefCounted=load("res://tests/acceptance/space.gd").new();suite.content=content
 var x: Dictionary=_setup(suite,[45,70],[_point(45,70),_portal(),{"kind":"floor","floor_id":2,"cell":[45,70]}])
 var sim: HospitalSimulation=x.sim
 var actor: Dictionary=sim.world.facts.actors.walker
 var query: RouteClearance=sim.space.navigation.structural_clearance(sim.world,actor,1)
 var immediate_clear: bool=sim.space.movement._detour_path_clear(sim.world,actor,x.move,[_point(35.2,71)],query)
 var rejected: bool=sim.space.movement._detour_return_path(sim.world,actor,x.move,Vector2(35,71)).is_empty()
 var trace: Array=[];var overlap: bool=false
 for tick: int in 30:
  suite._movement_tick(sim)
  var body: Rect2=sim.space.body_rectangle(actor)
  overlap=overlap or body.intersects(sim.space.body_rectangle(sim.world.facts.actors.anchor_occupant),false)
  trace.append({"tick":sim.world.sim_tick,"cell":actor.location.cell.duplicate(),"phase":sim.world.facts.moves.get("walker",{}).get("detour",{}).get("phase","")})
 var drift: bool=float(actor.location.cell[1])>74.0 and absf(float(actor.location.cell[0])-35.0)<0.01
 var rows: Array=[{"case":"remote_occupied_anchor_rejects_clear_local_step","observed_current_behavior":immediate_clear and rejected and drift and not overlap,"immediate_step_clear":immediate_clear,"return_rejected":rejected,"sideways_drift":drift,"overlap":overlap,"trace":trace}]
 sim.dispose()
 for crossing: bool in [false,true]:
  var original: Array=[_point(36,70),_point(37,70)]
  if crossing:original=[_point(36,70),_portal(),_point(37,70)]
  x=_setup(suite,[36,70],original);sim=x.sim;actor=sim.world.facts.actors.walker
  var answer: Dictionary=sim.space.movement._detour_return_path(sim.world,actor,x.move,Vector2(35,71))
  var expected: bool=answer.is_empty() if crossing else not answer.is_empty() and int(answer.index)==1
  rows.append({"case":"cannot_skip_connector" if crossing else "occupied_near_point_skips_to_next_original_point","observed_current_behavior":expected,"answer":answer})
  sim.dispose()
 var ok: bool=true
 for row: Dictionary in rows:ok=ok and row.observed_current_behavior
 return {"ok":ok,"scope":"reproduction of current defect plus predicate controls; ok means defect reproduced, not gameplay acceptance; no actual transit claimed","cases":rows}
