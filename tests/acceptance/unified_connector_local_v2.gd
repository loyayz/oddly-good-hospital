extends RefCounted
func run(content:HospitalContent)->Dictionary:
 var suite:RefCounted=load("res://tests/acceptance/space.gd").new();suite.content=content
 var rows:Array=[_ownership(suite),_future_connector(suite),_unavailable(suite)]
 var ok:bool=true
 for row:Dictionary in rows:ok=ok and row.ok
 return {"ok":ok,"cases":rows,"scope":"Ownership cases are direct local-selection calls; route/boarding cases use actual movement ticks."}
func _ownership(suite:RefCounted)->Dictionary:
 var sim:HospitalSimulation=suite._transit_fixture()
 suite._add_actor(sim,"actor","S49",[44,80])
 var actor:Dictionary=sim.world.facts.actors.actor
 var floor_point:Dictionary={"kind":"floor","floor_id":1,"cell":[46,80]}
 var variants:Dictionary={"empty":{"path":[],"cursor":0},"pending":{"path":[floor_point],"cursor":0,"route_pending":true},"support_exit":{"path":[{"kind":"support_exit","floor_id":1,"cell":[46,80]}],"cursor":0},"other_floor":{"path":[{"kind":"floor","floor_id":2,"cell":[46,80]}],"cursor":0},"exhausted":{"path":[floor_point],"cursor":1}}
 var rows:Array=[];var all_ok:bool=true
 for name:String in variants:
  var move:Dictionary=variants[name].duplicate(true);move.actor_id="actor";move.travelled=[]
  var before:Dictionary=move.duplicate(true);var facts:Dictionary=sim.world.freeze()
  var picked:bool=sim.space.movement._local_choose(sim.world,actor,move,Vector2.RIGHT)
  var ok:bool=not picked and move==before and facts==sim.world.freeze()
  all_ok=all_ok and ok;rows.append({"kind":name,"ok":ok,"picked":picked})
 sim.dispose();return {"case":"nonfloor_ownership_entry","ok":all_ok,"rows":rows}
func _future_connector(suite:RefCounted)->Dictionary:
 var sim:HospitalSimulation=suite._transit_fixture()
 suite._add_actor(sim,"actor","S49",[44,80])
 var request:String=sim.space.request_move(sim.world,"actor",2,[46,84])
 suite._movement_tick(sim)
 var move:Dictionary=sim.world.facts.moves.get("actor",{})
 var actor:Dictionary=sim.world.facts.actors.actor
 var floor_current:bool=not move.is_empty() and int(move.cursor)<move.path.size() and move.path[int(move.cursor)].kind=="floor"
 var later:bool=false
 for point:Dictionary in move.get("path",[]):later=later or point.kind=="connector"
 if not floor_current:sim.dispose();return {"case":"future_connector","ok":false,"setup":false}
 var sequence:int=int(move.request_sequence);var origin:Dictionary=actor.location.duplicate(true)
 var heading:Vector2=ConvoyTrail.point(move.path[int(move.cursor)].cell)-ConvoyTrail.point(actor.location.cell)
 if heading==Vector2.ZERO:heading=Vector2.LEFT
 var selected:bool=sim.space.movement._local_choose(sim.world,actor,move,heading)
 var no_jump:bool=actor.location==origin
 var ordered:bool=true;var safe:bool=true;var boarded:bool=false;var errors:Array=[]
 for tick:int in 750:
  suite._movement_tick(sim)
  var validation:String=sim.world.validate(suite.content)
  if not validation.is_empty():safe=false;errors.append(validation);break
  move=sim.world.facts.moves.get("actor",{})
  if not move.is_empty():ordered=ordered and int(move.request_sequence)==sequence and int(move.target_floor)==2 and ConvoyTrail.point(move.target_cell)==Vector2(46,84)
  boarded=boarded or actor.location.kind=="transit"
  if move.is_empty():break
 var result:Dictionary={"case":"current_floor_then_connector","ok":request.is_empty() and later and selected and no_jump and ordered and safe and boarded and sim.space.at(sim.world,"actor",2,[46,84]) and not sim.world.facts.moves.has("actor"),"selected":selected,"later_connector":later,"no_jump":no_jump,"ordered":ordered,"safe":safe,"boarded":boarded,"errors":errors,"remaining":move.duplicate(true)}
 sim.dispose();return result
func _unavailable(suite:RefCounted)->Dictionary:
 var sim:HospitalSimulation=suite._transit_fixture()
 var id:String=suite._connection(sim)
 # Explicit legal failed-elevator input, before a movement request is made.
 sim.world.facts.connectors[id].failed=true;sim.world.touch()
 suite._add_actor(sim,"actor","S49",[32,78])
 var initial_validation:String=sim.world.validate(suite.content)
 var quote:Dictionary=HospitalTransit.quote(sim.space,sim.world,sim.world.facts.connectors[id],"actor",1,2,0)
 var request:String=sim.space.request_move(sim.world,"actor",2,[44,84])
 var initial:Dictionary=sim.world.facts.moves.get("actor",{}).duplicate(true)
 var sequence:int=int(initial.get("request_sequence",-1));var original:Dictionary=sim.world.facts.actors.actor.location.duplicate(true)
 var stable:bool=true;var safe:bool=true;var errors:Array=[]
 var start_dispatch:int=int(sim.space.query_counts.route_dispatches)
 for tick:int in 12:
  suite._movement_tick(sim)
  var move:Dictionary=sim.world.facts.moves.get("actor",{})
  stable=stable and not move.has("local_move") and (move.is_empty() if initial.is_empty() else int(move.get("request_sequence",-2))==sequence and ConvoyTrail.point(move.target_cell)==Vector2(44,84))
  safe=safe and sim.world.facts.actors.actor.location==original
  var validation:String=sim.world.validate(suite.content)
  if not validation.is_empty():errors.append(validation)
 var no_spin:bool=int(sim.space.query_counts.route_dispatches)-start_dispatch<=1
 var restored:Dictionary=load("res://tests/acceptance/unified_local_behavior.gd").new()._restore_boundary(suite,sim,"actor",["actor"])
 var result:Dictionary={"case":"failed_lift_no_upward_travel","ok":initial_validation.is_empty() and not quote.get("ok",false) and stable and safe and no_spin and errors.is_empty() and restored.get("ok",false),"request":request,"initial_validation":initial_validation,"quote":quote,"stable":stable,"no_movement":safe,"no_per_tick_dispatch":no_spin,"restore":restored,"errors":errors}
 sim.dispose();return result
