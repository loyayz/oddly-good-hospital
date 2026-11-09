extends RefCounted
func _p(x:float,y:float,floor_id:int=1)->Dictionary:
 return {"kind":"floor","floor_id":floor_id,"cell":[x,y],"test_metadata":{"value":"preserved"}}
func run(content:HospitalContent)->Dictionary:
 var suite:RefCounted=load("res://tests/acceptance/space.gd").new();suite.content=content
 var rows:Array=[]
 rows.append(_flow(suite,false));rows.append(_flow(suite,true))
 rows.append(_boundary(suite,false));rows.append(_boundary(suite,true))
 var compressed:Dictionary=load("res://tests/acceptance/unified_compressed_rejoin.gd").new().run(content)
 var ok:bool=compressed.ok
 for row:Dictionary in rows:ok=ok and row.ok
 return {"ok":ok,"cases":rows,"compressed_real_collision":compressed,"scope":"Original compressed/fractional/turned route inputs retained verbatim; actual local steps and nearest return, plus connector stopping boundary. No synthetic expanded-path requirement."}
func _flow(suite:RefCounted,fractional:bool)->Dictionary:
 var sim:HospitalSimulation=suite._fixture()
 var start:Array=[35.25,71.5] if fractional else [35,70]
 var goal:Array=[38.25,73.75] if fractional else [45,70]
 suite._add_actor(sim,"walker","S49",start)
 var request:String=sim.space.request_move(sim.world,"walker",1,goal)
 var move:Dictionary=sim.world.facts.moves.walker
 var original:Array=[_p(35.75,71.5),_p(38.25,71.5),_p(38.25,73.75)] if fractional else [_p(45,70)]
 move.path=original.duplicate(true);move.cursor=0;move.route_pending=false
 # Explicit local side-step input boundary. All subsequent motion is real;
 # original path must never be expanded, copied into prefixes or rewritten.
 move.local_move={"origin":start.duplicate(),"target":_p(float(start[0]),float(start[1])+1)}
 var sequence:int=move.request_sequence
 var ids:Array=["walker"]
 if not fractional:suite._add_actor(sim,"far_occupant","S49",[45,70]);ids.append("far_occupant")
 var errors:Array=[];var first_rejoin:Array=[];var departed:bool=false;var kept:bool=true;var trace:Array=[];var max_side:float=0.0
 var probe:RefCounted=load("res://tests/acceptance/movement_detour.gd").new()
 for tick:int in 150:
  var error:String=probe._tick(suite,sim,ids)
  if not error.is_empty():errors.append(error);break
  var cell:Array=sim.world.facts.actors.walker.location.cell
  max_side=maxf(max_side,absf(float(cell[1])-float(start[1])))
  departed=departed or float(cell[1])!=float(start[1])
  if departed and first_rejoin.is_empty() and float(cell[1])==float(start[1]):first_rejoin=cell.duplicate()
  move=sim.world.facts.moves.get("walker",{})
  if not move.is_empty():kept=kept and move.path==original and move.target_cell==goal and move.request_sequence==sequence
  trace.append(cell.duplicate())
  if not fractional and not first_rejoin.is_empty():break
  if move.is_empty():break
 var expected:Array=[35.75,71.5] if fractional else [36,70]
 var checks:Dictionary={"request":request.is_empty(),"safe_real_steps":errors.is_empty(),"no_drift_before_near_return":fractional or max_side<=1.001,"metadata_route_goal_sequence_preserved":kept,"nearest_actual_rejoin":first_rejoin.size()==2 and ConvoyTrail.point(first_rejoin).distance_to(ConvoyTrail.point(expected))<0.0001,"fractional_short_turn_completed":not fractional or sim.space.at(sim.world,"walker",1,goal) and not sim.world.facts.moves.has("walker"),"far_occupant_unchanged":fractional or sim.space.at(sim.world,"far_occupant",1,[45,70]) and not sim.world.facts.moves.has("far_occupant")}
 var ok:bool=true
 for value:bool in checks.values():ok=ok and value
 sim.dispose();return {"case":"fractional_short_then_turn" if fractional else "far_occupied_endpoint_keeps_near_return","ok":ok,"checks":checks,"errors":errors,"first_rejoin":first_rejoin,"trace":trace}
func _boundary(suite:RefCounted,connector:bool)->Dictionary:
 var sim:HospitalSimulation=suite._fixture()
 suite._add_actor(sim,"walker","S49",[35,71]);suite._add_actor(sim,"near_occupant","S49",[36,70])
 var marker:Dictionary={"kind":"connector","connector_id":"predicate_boundary_only","from":1,"to":2}
 var path:Array=[_p(36,70),marker,_p(37,70,2)] if connector else [_p(36,70),_p(37,70)]
 var saved:Array=path.duplicate(true)
 var move:Dictionary={"actor_id":"walker","path":path,"cursor":0,"travelled":[],"local_move":{"origin":[35,70],"target":_p(35,71)}}
 var before:Dictionary=sim.world.facts.actors.duplicate(true)
 sim.space.movement._local_resume(sim.world,sim.world.facts.actors.walker,move)
 var link:Dictionary=move.local_move.get("rejoin",{})
 var checks:Dictionary={"connector_not_crossed_or_nearest_successor":link.is_empty() if connector else link.get("index",-1)==1 and link.get("cell",[]).size()==2 and ConvoyTrail.point(link.cell).distance_to(Vector2(37,70))<0.0001,"original_metadata_marker_and_suffix_unchanged":path==saved,"no_displacement_during_decision":sim.world.facts.actors==before}
 var ok:bool=true
 for value:bool in checks.values():ok=ok and value
 sim.dispose();return {"case":"connector_boundary" if connector else "occupied_nearest_successor_boundary","ok":ok,"checks":checks,"local":move.local_move}
