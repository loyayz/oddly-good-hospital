extends RefCounted

const SpaceSuite = preload("res://tests/acceptance/space.gd")

# Entry, boarding, empty-car dispatch and departure are actual production phases.
func run(suite) -> Dictionary:
	var results: Dictionary = {}
	var passed: bool = true
	for upgrade: bool in [false,true]:
		for waiting: bool in [false,true]:
			var key: String = ("upgrade" if upgrade else "repair")+("_waiting" if waiting else "_riding")
			results[key] = _scenario(suite,upgrade,waiting)
			passed = passed and results[key].ok
	return {"ok":passed,"details":results}

func _scenario(suite, upgrade: bool, waiting: bool) -> Dictionary:
	var helper = SpaceSuite.new()
	helper.content = suite._content
	var sim: HospitalSimulation = helper._transit_fixture()
	var f: Dictionary = {"s":sim,"w":sim.world,"errors":[]}
	var connector_id: String = helper._connection(sim)
	if waiting:
		# Put the car upstairs by delivering a real passenger, never by editing it.
		helper._add_actor(sim,"inventory_transit_passenger","S49",[36,76])
		sim.space.request_move(sim.world,"inventory_transit_passenger",2,[46,85])
		var delivered: bool = helper._wait(sim,func() -> bool: return sim.space.at(sim.world,"inventory_transit_passenger",2,[46,85]) and not sim.world.facts.moves.has("inventory_transit_passenger"),300,helper._movement_tick.bind(sim))
		if not delivered: return helper._done(sim,false,{"boundary":"passenger_delivery"})
	var built: CommandResult = suite._command(f,"build_facility",{"id":"inventory_transit_machine","definition_id":"M09","floor_id":2,"cell":[45,80]})
	if not built.accepted: return helper._done(sim,false,{"build":built.to_record()})
	var ordered: CommandResult
	if upgrade:
		sim.world.facts.research.append("R12")
		ordered = suite._command(f,"upgrade_order",{"facility_id":"inventory_transit_machine","target_level":1})
	else:
		sim.world.facts.facilities.inventory_transit_machine.failed = true
		sim.world.facts.facilities.inventory_transit_machine.condition = 18.0
		sim.services.maintenance.boundaries(sim.world)
		ordered = CommandResult.new(true,"applied","",[sim.world.facts.facilities.inventory_transit_machine.maintenance_order_id],sim.world.revision)
	if not ordered.accepted: return helper._done(sim,false,{"order":ordered.to_record()})
	var collection: String = "upgrades" if upgrade else "jobs"
	var job_id: String = ordered.changed_ids[0]
	var reached: bool = false
	for tick: int in 600:
		suite._work_tick(f,"maintenance")
		var id: String = sim.world.facts.maintenance[collection][job_id].worker_id
		if id.is_empty(): continue
		var c: Dictionary = sim.world.facts.connectors[connector_id]
		if waiting:
			var entry: Dictionary = helper._directional_queue_entry(c,id)
			# Empty transit commits to the pickup floor, not a person. Observe
			# the worker's physical, upward queue row independently of the car.
			reached = c.phase=="empty_riding" and int(c.from)==2 and int(c.to)==1 and int(c.remaining_ticks)>0 and c.riders.is_empty() and sim.world.facts.actors[id].location.kind=="floor" and int(entry.get("floor_id",-1))==1 and int(entry.get("direction",0))==1 and int(entry.get("destination",-1))==2 and entry.get("leader_ids",[])==[id]
		else:
			reached = c.phase=="riding" and sim.world.facts.actors[id].location.kind=="transit" and c.riders.has(id)
		if reached: break
	if not reached: return helper._done(sim,false,{"boundary":"waiting_empty_car" if waiting else "boarded","job":sim.world.facts.maintenance[collection][job_id].duplicate(true),"connector":sim.world.facts.connectors[connector_id].duplicate(true)})
	var job: Dictionary = sim.world.facts.maintenance[collection][job_id]
	var worker_id: String = job.worker_id
	var original: Dictionary = job.duplicate(true)
	var actor: Dictionary = sim.world.facts.actors[worker_id].duplicate(true)
	var movement: Dictionary = sim.world.facts.moves[worker_id].duplicate(true)
	var connection: Dictionary = sim.world.facts.connectors[connector_id].duplicate(true)
	var ledger: Dictionary = sim.world.facts.ledger.duplicate(true)
	var store: CommandResult = suite._command(f,"build_store",{"target_id":"inventory_transit_machine"})
	job = sim.world.facts.maintenance[collection][job_id]
	var after_connection: Dictionary = sim.world.facts.connectors[connector_id]
	var ownership: bool = store.accepted and job.phase=="inventory" and job.worker_id=="" and sim.world.facts.maintenance.contractors[worker_id].phase=="leaving" and sim.world.facts.actors[worker_id]==actor
	var commitment: bool
	if waiting:
		var expected_connection: Dictionary = connection.duplicate(true)
		# Remove only the real waiting entry and its optional unavailable-head
		# record; exact equality protects all other car and landing state.
		var landing: Array = expected_connection.landing_queues["1:1"]
		for index: int in range(landing.size()-1,-1,-1):
			if landing[index].actor_id==worker_id: landing.remove_at(index)
		expected_connection.get("unavailable_heads",{}).erase(worker_id)
		commitment = not sim.world.facts.moves.has(worker_id) and helper._directional_queue_entry(after_connection,worker_id).is_empty() and after_connection==expected_connection
	else:
		commitment = sim.world.facts.moves.get(worker_id,{})==movement and after_connection==connection
	var immediate_validation: String = sim.world.validate(suite._content)
	var restored: HospitalSimulation = HospitalSimulation.new(WorldState.new(sim.world.freeze()),suite._content)
	sim.dispose()
	sim = restored
	f = {"s":sim,"w":sim.world,"errors":[]}
	var restore_validation: String = sim.world.validate(suite._content)
	var empty_arrived: bool = not waiting
	var departed: bool = false
	for tick: int in 1000:
		suite._work_tick(f,"maintenance")
		var c: Dictionary = sim.world.facts.connectors[connector_id]
		if waiting and c.phase=="idle" and int(c.floor_id)==1 and c.riders.is_empty(): empty_arrived = true
		if sim.world.facts.maintenance.contractors[worker_id].phase=="departed":
			departed = true
		if departed and empty_arrived: break
	job = sim.world.facts.maintenance[collection][job_id]
	var retained: bool = job.remaining_milli==original.remaining_milli and sim.world.facts.ledger==ledger
	if upgrade:
		retained = retained and job.stages==original.stages
	else:
		retained = retained and job.completed_milli==original.completed_milli and job.paid_parts==original.paid_parts and job.contributions==original.contributions and not job.started
	var validation: String = sim.world.validate(suite._content)
	var ok: bool = ownership and commitment and immediate_validation.is_empty() and restore_validation.is_empty() and departed and empty_arrived and retained and job.phase=="inventory" and job.worker_id=="" and sim.world.facts.actors[worker_id].location.kind=="outside" and not sim.world.facts.moves.has(worker_id) and validation.is_empty()
	return helper._done(sim,ok,{"reached_boundary":reached,"ownership_released":ownership,"transport_commitment_retained":commitment,"empty_car_arrived":empty_arrived,"actual_departure":departed,"progress_payment_unchanged":retained,"immediate_validation":immediate_validation,"restore_validation":restore_validation,"validation":validation,"store":store.to_record(),"original_connection":connection,"final_connection":sim.world.facts.connectors[connector_id].duplicate(true),"job":job.duplicate(true)})
