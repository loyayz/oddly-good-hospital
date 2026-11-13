extends SceneTree
func _initialize()->void:
 var suite=load("res://tests/acceptance/space.gd").new();suite.content=HospitalContent.new()
 var sim:HospitalSimulation=suite._transit_fixture()
 suite._history_height(sim,3);suite._command(sim,"connector_extend",{"connection_id":suite._connection(sim),"floor_id":3})
 var c:Dictionary=sim.world.facts.connectors[suite._connection(sim)];LiftController.ensure(c);c.direction=1
 # Declared quote boundary: two already boarded independent bodies, own
 # destinations 2 and 3. No boarding time is charged again.
 for i:int in 2:
  var id:String="rider%d"%i;suite._add_actor(sim,id,"S49",[40+i,72])
  sim.world.facts.moves[id]={"actor_id":id}
  sim.world.facts.actors[id].location={"kind":"transit","connector_id":c.id,"from":1,"to":2+i,"cabin_cell":[i,0]}
  c.passenger_groups.append({"actor_id":id,"leader_ids":[id],"members":[id],"from":1,"to":2+i,"cabin_positions":{id:[i,0]},"exclusive":false});c.riders.append(id)
 var before:Dictionary=sim.world.freeze()
 var rows:Dictionary={"multiple":LiftEstimate.quote(sim.space,sim.world,c,"rider1",1,3,0)}
 rows.multiple_expected=50 # 10 to2 +15 exit A +10 to3 +15 exit B
 rows.multiple_unchanged=before==sim.world.freeze()
 # Nine 1x1 bodies fill the 3x3 cabin. A waiting head cannot fit and must
 # await all nine exits at 2, empty return, and its ordinary trip.
 for id:String in ["rider0","rider1"]:
  sim.world.facts.moves.erase(id);sim.world.facts.actors.erase(id)
 c.passenger_groups=[];c.riders=[]
 for i:int in 9:
  var id:String="full%d"%i;suite._add_actor(sim,id,"S49",[45+i,72])
  sim.world.facts.moves[id]={"actor_id":id}
  sim.world.facts.actors[id].location={"kind":"transit","connector_id":c.id,"from":1,"to":2,"cabin_cell":[i%3,i/3]}
  c.passenger_groups.append({"actor_id":id,"leader_ids":[id],"members":[id],"from":1,"to":2,"cabin_positions":{id:[i%3,i/3]},"exclusive":false});c.riders.append(id)
 suite._add_actor(sim,"head","S49",[39,76]);sim.world.facts.moves.head={"actor_id":"head"}
 c.landing_queues={"1:1":[{"actor_id":"head","leader_ids":["head"],"members":["head"],"floor_id":1,"direction":1,"destination":2,"arrived_tick":0,"cell":[39,76],"owner_cells":{"head":[39,76]}}]}
 before=sim.world.freeze()
 rows.full=LiftEstimate.quote(sim.space,sim.world,c,"head",1,2,0)
 rows.full_expected=210 # 10+9*15+10+15+15+10+15
 rows.full_unchanged=before==sim.world.freeze()
 # Leave one cabin cell free. A two-owner FIFO head cannot fit; the
 # single follower may not use that spare cell ahead of it.
 c.passenger_groups.pop_back();c.riders.pop_back()
 sim.world.facts.moves.erase("full8");sim.world.facts.actors.erase("full8")
 for id:String in ["partner","follower"]:
  suite._add_actor(sim,id,"S49",[41 if id=="partner" else 43,76]);sim.world.facts.moves[id]={"actor_id":id}
 c.landing_queues["1:1"][0].leader_ids=["head","partner"]
 c.landing_queues["1:1"][0].members=["head","partner"]
 c.landing_queues["1:1"][0].owner_cells={"head":[39,76],"partner":[41,76]}
 c.landing_queues["1:1"].append({"actor_id":"follower","leader_ids":["follower"],"members":["follower"],"floor_id":1,"direction":1,"destination":2,"arrived_tick":0,"cell":[43,76],"owner_cells":{"follower":[43,76]}})
 rows.fifo=LiftEstimate.quote(sim.space,sim.world,c,"follower",1,2,0)
 rows.fifo_expected=265 # 10+8*15+10+20+15+35+15+10+15+15
 # The real persisted family phases exercise production portal plans/cursors.
 rows.family=[]
 for stage:String in ["family_pending_outside","family_boarding","family_exits_first","nursing_exits_after_family"]:
  var f=FileAccess.open("/workspace/scratch/6962cc21ddf3/elevator-validation/family-vc02-cold-r2/"+stage+".bin",FileAccess.READ)
  var raw:Dictionary=f.get_var(false);f.close()
  var w=WorldState.new(raw.get("facts",raw));var actual=HospitalSimulation.new(w,suite.content)
  for car:Dictionary in w.facts.connectors.values():
   if car.get("active_group","").is_empty():continue
   var g:Dictionary=LiftController.group(car,car.active_group)
   var original:Dictionary=w.freeze()
   var row:Dictionary={"stage":stage,"phase":car.phase,"remaining":car.remaining_ticks,"pending":g.get("pending_boarding",[]).size(),"exit_stage":g.get("exit_stage",""),"phase_quote":LiftEstimate._phase_ticks(actual.space,w,car,g,car.phase,true),"unchanged":original==w.freeze()}
   # Bounded real phase execution from the untouched saved state. This is
   # a controller-phase test, not a whole clinical or performance run.
   var count:int=0
   while car.phase==row.phase and count<120:
    w.facts.sim_tick+=1
    LiftController.advance(actual.space,w,car)
    count+=1
   row.actual_phase_ticks=count
   row.phase_finished=car.phase!=row.phase
   rows.family.append(row)
  actual.dispose()
 var family_ok:bool=rows.family.size()==4 and rows.family.all(func(r:Dictionary)->bool:return r.unchanged and r.phase_finished and r.phase_quote==r.actual_phase_ticks)
 rows.family_assertions=family_ok
 var f=FileAccess.open("/workspace/scratch/6962cc21ddf3/lift-estimate-multi-probe.json",FileAccess.WRITE);f.store_string(JSON.stringify(rows,"\t"));f.close()
 sim.dispose()
 quit(0 if rows.multiple.get("arrival_ticks",-1)==50 and rows.full.get("arrival_ticks",-1)==210 and rows.multiple_unchanged and rows.full_unchanged and rows.fifo.get("arrival_ticks",-1)==265 and family_ok else 1)
