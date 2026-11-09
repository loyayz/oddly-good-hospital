extends RefCounted
func run(content:HospitalContent)->Dictionary:
 var suite:RefCounted=load("res://tests/acceptance/space.gd").new();suite.content=content
 var rows:Array=[_gap(suite,false),_gap(suite,true)]
 var first:Vector2=Vector2(40,63.9999961853027)+Vector2(0,1)
 var last:Vector2=Vector2(45,64)+Vector2(0,1)
 var rounded_axis:bool=first.y==last.y and first.x!=last.x
 var ok:bool=rounded_axis
 for row:Dictionary in rows:ok=ok and row.ok
 return {"ok":ok,"cases":rows,"binary32_constructed_axis_preserved":rounded_axis}
func _gap(suite:RefCounted,reverse:bool)->Dictionary:
 var sim:HospitalSimulation=suite._fixture()
 var probe:RefCounted=load("res://tests/acceptance/unified_local_behavior.gd").new()
 var walker:String="z_walker" if reverse else "a_walker"
 suite._add_actor(sim,walker,"S49",[35,70])
 var request:String=sim.space.request_move(sim.world,walker,1,[45,70])
 var ids:Array=[walker];var inserted:bool=false;var errors:Array=[];var fixed:bool=true;var sequence:int=-1;var preserved:bool=true;var ticks:int=0
 var blockers:Dictionary={"front":[40,70],"up_front":[39.7,69.5],"down_front":[39.7,70.5],"up_back":[38.7,69.5],"down_back":[38.7,70.5]}
 for tick:int in 240:
  var error:String=probe._tick(suite,sim,ids);ticks=tick+1
  if not error.is_empty():errors.append(error);break
  var actor:Dictionary=sim.world.facts.actors[walker]
  var m:Dictionary=sim.world.facts.moves.get(walker,{})
  if sequence<0 and not m.is_empty():sequence=int(m.request_sequence)
  if not m.is_empty():preserved=preserved and int(m.request_sequence)==sequence and m.target_cell==[45,70]
  if not inserted and float(actor.location.cell[0])>=39.0-0.001:
   for id:String in blockers:suite._add_actor(sim,id,"S49",blockers[id]);ids.append(id)
   inserted=true
  if inserted:
   for id:String in blockers:fixed=fixed and sim.space.at(sim.world,id,1,blockers[id]) and not sim.world.facts.moves.has(id)
  if m.is_empty():break
 var arrived:bool=not sim.world.facts.moves.has(walker) and sim.space.at(sim.world,walker,1,[45,70])
 var result:Dictionary={"case":"mid_retreat_only_exit_reversed_ids" if reverse else "mid_retreat_only_exit","ok":request.is_empty() and inserted and errors.is_empty() and arrived and preserved and fixed,"arrived":arrived,"ticks":ticks,"errors":errors,"fixed_bodies":fixed,"goal_and_sequence":preserved}
 sim.dispose();return result
