extends "res://tests/acceptance/retreat_blocker_contract.gd"
func run_local(content:HospitalContent)->Dictionary:
 var suite:RefCounted=load("res://tests/acceptance/space.gd").new();suite.content=content
 var rows:Array=[_ring(suite,false),_ring(suite,true),_clear_return(suite)]
 return {"ok":rows.all(func(r:Dictionary)->bool:return r.ok),"cases":rows}
func _ring(suite:RefCounted,reverse_ids:bool)->Dictionary:
 var sim:HospitalSimulation=suite._fixture()
 var ids:Array=["a","b","c","d"]
 if reverse_ids:ids.reverse()
 var cells:Array=[[40.0,70.0],[40.6,70.0],[40.6,70.6],[40.0,70.6]]
 var goals:Dictionary={}
 for i:int in ids.size():suite._add_actor(sim,ids[i],"S49",cells[i])
 sim.world.facts.move_request_next=4
 for i:int in ids.size():
  var goal:Array=cells[(i+1)%4].duplicate();goals[ids[i]]=goal
  var m:Dictionary=_journey(ids[i],cells[i],goal);m.request_sequence=i+1
  m.local_move={"origin":cells[i].duplicate(),"target":_p(cells[i][0],cells[i][1])}
  sim.world.facts.moves[ids[i]]=m
 var initial:String=sim.world.validate(suite.content)
 var observer:=ObserveMovement.new(sim.space);sim.space.movement=observer
 var safe:bool=true;var budget:bool=true;var original:bool=true;var pending:bool=false;var ticks:int=0
 for tick:int in 200:
  var before:Dictionary={}
  for id:String in ids:before[id]=sim.space.body_rectangle(sim.world.facts.actors[id])
  sim.space.advance(sim.world)
  for i:int in ids.size():
   var id:String=ids[i];var rect:Rect2=sim.space.body_rectangle(sim.world.facts.actors[id])
   budget=budget and before[id].get_center().distance_to(rect.get_center())<=sim.space.walking_speed(sim.world.facts.actors[id])*WorldState.TICK_SECONDS+0.0001
   for j:int in range(i+1,4):safe=safe and not rect.intersects(sim.space.body_rectangle(sim.world.facts.actors[ids[j]]),false)
   var m:Dictionary=sim.world.facts.moves.get(id,{})
   original=original and (sim.space.at(sim.world,id,1,goals[id]) if m.is_empty() else m.target_cell==goals[id] and m.request_sequence==i+1)
   pending=pending or m.get("route_pending",false)
  sim.world.facts.sim_tick+=1;sim.world.touch(false);ticks=tick+1
  if sim.world.facts.moves.is_empty():break
 var final:String=sim.world.validate(suite.content)
 var checks:Dictionary={"initial_valid":initial.is_empty(),"final_valid":final.is_empty(),"all_arrived":sim.world.facts.moves.is_empty(),"safe":safe,"walking_budget":budget,"requests_kept":original,"no_rejoin_pending":not pending,"actual_collisions":observer.blocked_steps>0,"no_component_search":int(sim.space.query_counts.get("rejoin_component_queries",0))==0}
 var result:Dictionary={"case":"local_ring_reversed_ids" if reverse_ids else "local_ring","ok":checks.values().all(func(v:Variant)->bool:return v==true),"checks":checks,"initial_validation":initial,"final_validation":final,"ticks":ticks,"collisions":observer.blocked_steps,"remaining":sim.world.facts.moves.duplicate(true)}
 sim.dispose();return result
func _clear_return(suite:RefCounted)->Dictionary:
 var sim:HospitalSimulation=suite._fixture();suite._add_actor(sim,"a","S49",[40,71])
 var m:Dictionary=_journey("a",[40,70],[43,70]);m.request_sequence=1;m.local_move={"origin":[40,70],"target":_p(40,71)}
 sim.world.facts.move_request_next=1;sim.world.facts.moves.a=m
 var observer:=ObserveMovement.new(sim.space);sim.space.movement=observer
 for tick:int in 100:
  sim.space.advance(sim.world);sim.world.facts.sim_tick+=1;sim.world.touch(false)
  if sim.world.facts.moves.is_empty():break
 var result:Dictionary={"case":"clear_return_no_bypass","ok":sim.world.facts.moves.is_empty() and sim.space.at(sim.world,"a",1,[43,70]) and not observer.triggered and observer.blocked_steps==0 and sim.world.validate(suite.content).is_empty(),"no_new_bypass":not observer.triggered,"collisions":observer.blocked_steps,"validation":sim.world.validate(suite.content)}
 sim.dispose();return result
