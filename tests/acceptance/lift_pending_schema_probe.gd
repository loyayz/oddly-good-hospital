extends SceneTree
func _initialize()->void:
 var suite=load("res://tests/acceptance/space.gd").new();suite.content=HospitalContent.new()
 var sim:HospitalSimulation=suite._transit_fixture()
 suite._add_actor(sim,"care","S49",[36,72]);suite._add_actor(sim,"family","S49",[37,72])
 var c:Dictionary=sim.world.facts.connectors[suite._connection(sim)]
 LiftController.ensure(c)
 c.phase="boarding";c.active_group="care";c.primary_actor_id="care";c.riders=["care"]
 c.passenger_groups=[{"actor_id":"care","leader_ids":["care"],"members":["care"],"from":1,"to":2,"receipt":"probe","cabin_positions":{"care":[0,0]},"entry_cells":{"family":[37,72]},"pending_boarding":[{"actor_id":"family","members":["family"],"entry_cell":[37,72],"cabin_positions":{"family":[2,0]}}]}]
 var rows:Dictionary={"shape":sim.world._validate_lift_shape(c)}
 var freeze:Dictionary=sim.world.freeze();var restored=WorldState.new(freeze)
 rows.roundtrip=restored.freeze()==freeze
 c.phase="riding";rows.bad_phase=sim.world._validate_lift_shape(c);c.phase="boarding"
 c.passenger_groups[0].pending_boarding.append(c.passenger_groups[0].pending_boarding[0].duplicate(true))
 rows.duplicate=sim.world._validate_lift_shape(c);c.passenger_groups[0].pending_boarding.pop_back()
 sim.world.facts.moves.care={"actor_id":"care","convoy":{}}
 sim.world.facts.moves.family={"actor_id":"family","lift_pending_boarding":{"connector_id":c.id,"group_leader":"care"}}
 sim.world.facts.actors.family.location.cell=[80,80]
 rows.remote=sim.world._validate_lift_manifest(c,suite.content.definition("vertical_connectors",c.definition_id),sim.space)
 var f=FileAccess.open("/workspace/scratch/6962cc21ddf3/lift-pending-schema-probe.json",FileAccess.WRITE);f.store_string(JSON.stringify(rows,"\t"));f.close()
 quit(0 if rows.shape.is_empty() and rows.roundtrip and not rows.bad_phase.is_empty() and not rows.duplicate.is_empty() and rows.remote=="电梯待登舱身体未在实际入口" else 1)
