extends RefCounted
func _p(x: float,y: float,floor_id: int=1) -> Dictionary:
 return {"kind":"floor","floor_id":floor_id,"cell":[x,y],"test_metadata":{"value":"preserved"}}
func run(content: HospitalContent) -> Dictionary:
 var suite: RefCounted=load("res://tests/acceptance/space.gd").new();suite.content=content
 var sim: HospitalSimulation=suite._fixture()
 suite._add_actor(sim,"walker","S49",[35,70]);suite._add_actor(sim,"far_occupant","S49",[45,70])
 var request: String=sim.space.request_move(sim.world,"walker",1,[45,70])
 var actor: Dictionary=sim.world.facts.actors.walker
 var move: Dictionary=sim.world.facts.moves.walker
 var marker: Dictionary={"kind":"connector","connector_id":"predicate_boundary_only","from":1,"to":2}
 # Explicit compressed route boundary; portal is never executed in this test.
 move.path=[_p(45,70),marker,_p(45,72,2)];move.cursor=0;move.route_pending=false
 move.travelled=[_p(35,70)]
 sim.space.movement._start_detour(sim.world,actor,move)
 var captured: Array=move.detour.original_path.duplicate(true)
 var trace: Array=[];var arrived_near: bool=false;var overlap: bool=false;var max_side: float=0.0
 for tick: int in 35:
  suite._movement_tick(sim)
  overlap=overlap or sim.space.body_rectangle(actor).intersects(sim.space.body_rectangle(sim.world.facts.actors.far_occupant),false)
  max_side=maxf(max_side,absf(float(actor.location.cell[1])-70.0))
  trace.append(actor.location.cell.duplicate())
  if sim.space.at(sim.world,"walker",1,[36,70]):arrived_near=true;break
 var checks: Dictionary={"request_accepted":request.is_empty(),"actual_start_detour_captures_near":captured[0].cell==[36.0,70.0],"actual_steps_rejoin_near":arrived_near,"no_drift":max_side<=1.001,"no_overlap":not overlap,"far_occupant_unchanged":sim.space.at(sim.world,"far_occupant",1,[45,70])}
 sim.dispose()
 sim=suite._fixture();suite._add_actor(sim,"walker","S49",[35.25,71.5]);actor=sim.world.facts.actors.walker
 var original: Array=[_p(35.75,71.5),_p(38.25,71.5),_p(38.25,73.75),marker,_p(38.25,90,2)]
 var saved: Array=original.duplicate(true)
 var expanded: Array=sim.space.movement._detour_original_points(actor,original)
 var cells: Array=[];var metadata: bool=true
 for point: Dictionary in expanded:
  if point.kind=="floor":cells.append(point.cell);metadata=metadata and point.test_metadata.value=="preserved"
 var expected_cells: Array=[[35.75,71.5],[36.75,71.5],[37.75,71.5],[38.25,71.5],[38.25,72.5],[38.25,73.5],[38.25,73.75],[38.25,90.0]]
 checks.fractional_short_turn=cells.size()==expected_cells.size()
 for i: int in mini(cells.size(),expected_cells.size()):
  checks.fractional_short_turn=checks.fractional_short_turn and Vector2(float(cells[i][0]),float(cells[i][1])).distance_to(Vector2(float(expected_cells[i][0]),float(expected_cells[i][1])))<0.00001
 checks.connector_and_later_not_expanded=expanded.size()==9 and expanded[7]==marker and expanded[8]==original[4]
 checks.metadata_retained=metadata
 expanded[0].test_metadata.value="changed_copy"
 checks.original_readonly=original==saved
 sim.dispose()
 var controls: Array=[]
 for stop_at_connector: bool in [false,true]:
  sim=suite._fixture();suite._add_actor(sim,"walker","S49",[35,71]);suite._add_actor(sim,"near_occupant","S49",[36,70]);actor=sim.world.facts.actors.walker
  var remaining: Array=[_p(36,70),_p(37,70)] if not stop_at_connector else [_p(36,70),marker,_p(37,70)]
  var boundary: Dictionary={"actor_id":"walker","detour":{"direction":[1,0],"original_path":remaining}}
  var answer: Dictionary=sim.space.movement._detour_return_path(sim.world,actor,boundary,Vector2(35,71))
  var valid: bool=answer.is_empty() if stop_at_connector else not answer.is_empty() and int(answer.index)==1
  controls.append({"connector_boundary":stop_at_connector,"ok":valid,"answer":answer})
  sim.dispose()
 var ok: bool=true
 for value: bool in checks.values():ok=ok and value
 for row: Dictionary in controls:ok=ok and row.ok
 return {"ok":ok,"scope":"explicit compressed detour input, actual local steps; connector predicate boundary only, no transit claim","checks":checks,"fractional_cells":cells,"expected_fractional_cells":expected_cells,"trace":trace,"captured":captured,"controls":controls}
