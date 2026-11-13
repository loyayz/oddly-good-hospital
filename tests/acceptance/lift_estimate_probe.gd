extends SceneTree
func _initialize()->void:
 var suite=load("res://tests/acceptance/space.gd").new()
 suite.content=HospitalContent.new()
 var sim:HospitalSimulation=suite._transit_fixture()
 suite._add_actor(sim,"eta_query","S49",[40,72])
 var c:Dictionary=sim.world.facts.connectors[suite._connection(sim)]
 LiftController.ensure(c)
 var before:Dictionary=sim.world.freeze()
 var q:Dictionary=LiftEstimate.quote(sim.space,sim.world,c,"eta_query",1,2,0)
 var unchanged:bool=before==sim.world.freeze()
 var rows:Dictionary={"idle":q,"unchanged":unchanged}
 rows.delayed=LiftEstimate.quote(sim.space,sim.world,c,"eta_query",1,2,20)
 # Independent open floor distance is three grid cells from queue to door.
 var speed:float=sim.space.walking_speed(sim.world.facts.actors.eta_query)*WorldState.TICK_SECONDS
 var approach:int=int(ceil(3.0/speed))
 rows.expected_idle=approach+15+10+15
 var m:Dictionary={"actor_id":"eta_query","path":[{"kind":"floor","floor_id":1,"cell":[36,72]},{"kind":"connector","connector_id":c.id,"from":1,"to":2}],"cursor":0,"lift_boarding_call":{"connector_id":c.id}}
 sim.world.facts.moves.eta_query=m
 sim.world.facts.actors.eta_query.location.cell=[37.5,72]
 var g:Dictionary={"actor_id":"eta_query","leader_ids":["eta_query"],"members":["eta_query"],"floor_id":1,"cell":[39,72],"owner_cells":{"eta_query":[39,72]}}
 rows.approach_remaining=LiftEstimate._approach_ticks(sim.space,sim.world,c,g)
 rows.expected_remaining=int(ceil(1.5/speed))
 c.remaining_ticks=4
 rows.active_boarding=LiftEstimate._phase_ticks(sim.space,sim.world,c,g,"boarding",true)
 rows.active_alighting=LiftEstimate._phase_ticks(sim.space,sim.world,c,g,"alighting",true)
 # A real active manifest has its own destination; four remaining ticks
 # must not be replaced by a fresh fifteen-tick phase.
 c.passenger_groups=[{"actor_id":"eta_query","leader_ids":["eta_query"],"members":["eta_query"],"from":1,"to":2,"cabin_positions":{"eta_query":[0,0]},"exclusive":false}]
 c.riders=["eta_query"];c.active_group="eta_query";c.phase="boarding";c.direction=1;c.from=1;c.to=2
 var active_before:Dictionary=sim.world.freeze()
 rows.active_quote=LiftEstimate.quote(sim.space,sim.world,c,"eta_query",1,2,0)
 rows.active_unchanged=active_before==sim.world.freeze()
 c.floor_id=2;c.phase="alighting"
 rows.exit_quote=LiftEstimate.quote(sim.space,sim.world,c,"eta_query",1,2,0)
 var f=FileAccess.open("/workspace/scratch/6962cc21ddf3/lift-estimate-probe.json",FileAccess.WRITE)
 f.store_string(JSON.stringify(rows,"\t"));f.close()
 quit(0 if q.get("ok",false) and q.arrival_ticks==rows.expected_idle and unchanged and rows.approach_remaining==rows.expected_remaining and rows.active_boarding==4 and rows.active_alighting==4 and rows.delayed.get("arrival_ticks",-1)==75 and rows.active_quote.get("arrival_ticks",-1)==29 and rows.exit_quote.get("arrival_ticks",-1)==4 and rows.active_unchanged else 1)
