extends "res://tests/acceptance/lift_ground_cancel_runner.gd"

const CONTRACTOR: String = "release_contractor"
const NEIGHBOR: String = "neighbor"

# Quote/order through production. Declare the already assigned legal contractor
# at a ground boundary; only actual movement produces a queue or cabin membership.
func _add_contractor(sim: HospitalSimulation, cell: Array) -> String:
	var world: WorldState=sim.world
	var connector: String=suite._connection(sim)
	world.facts.connectors[connector].condition=60.0
	var result: CommandResult=suite._command(sim,"maintenance_order",{"facility_id":connector})
	if not result.accepted: return ""
	var id: String=str(result.changed_ids[0])
	suite._add_actor(sim,CONTRACTOR,"S49",cell)
	world.facts.actors[CONTRACTOR].service_role="mechanic"
	world.facts.maintenance.contractors[CONTRACTOR]={"id":CONTRACTOR,"job_id":id,"phase":"assigned"}
	var job: Dictionary=world.facts.maintenance.jobs[id]
	job.worker_id=CONTRACTOR
	job.phase="travelling"
	world.touch()
	return id

func _cancel_order(sim: HospitalSimulation, id: String) -> CommandResult:
	return sim.services.maintenance.execute(sim.world,"maintenance_cancel",{"job_id":id})

func _settled(before: Dictionary, after: Dictionary, id: String) -> bool:
	var jobs: Dictionary=before.maintenance.jobs.duplicate(true)
	jobs[id].worker_id=""
	jobs[id].phase="cancelled"
	var contractors: Dictionary=before.maintenance.contractors.duplicate(true)
	contractors[CONTRACTOR].phase="leaving"
	return after.maintenance.jobs==jobs and after.maintenance.contractors==contractors and after.ledger==before.ledger

func _line(sim: HospitalSimulation) -> Array:
	return sim.world.facts.connectors[suite._connection(sim)].get("landing_queues",{}).get("1:1",[])

func _release_queued() -> void:
	var sim: HospitalSimulation=suite._transit_fixture()
	var world: WorldState=sim.world
	suite._add_actor(sim,"car_positioner","S49",[36,76])
	var park_request: String=sim.space.request_move(world,"car_positioner",2,[46,85])
	var parked: bool=suite._wait(sim,func()->bool:return sim.space.at(world,"car_positioner",2,[46,85]) and not world.facts.moves.has("car_positioner"),300,suite._movement_tick.bind(sim))
	var job_id: String=_add_contractor(sim,[39,76])
	if job_id.is_empty():
		row("contractor_ground_release",{"order_accepted":false})
		sim.dispose()
		return
	suite._add_actor(sim,NEIGHBOR,"S49",[41,76])
	var worker_request: String=sim.space.request_move(world,CONTRACTOR,2,[48,82])
	var neighbor_request: String=sim.space.request_move(world,NEIGHBOR,2,[50,82])
	var before_line: Array=[]
	for step: int in 800:
		suite._movement_tick(sim)
		var ids: Array=_line(sim).map(func(entry: Dictionary)->String:return entry.actor_id)
		if CONTRACTOR in ids and NEIGHBOR in ids:
			before_line=_line(sim).duplicate(true)
			break
	var before: Dictionary=world.freeze()
	var checks: Dictionary={"both_actually_waiting":not before_line.is_empty(),"requests_accepted":worker_request.is_empty() and neighbor_request.is_empty(),"input_valid":world.validate(suite.content).is_empty(),"car_positioned_by_real_trip":park_request.is_empty() and parked}
	if not before_line.is_empty():
		var cancelled: CommandResult=_cancel_order(sim,job_id)
		var after: Dictionary=world.freeze()
		checks.owner_marked_leaving=world.facts.maintenance.contractors[CONTRACTOR].phase=="leaving"
		checks.worker_ground_move_removed=not world.facts.moves.has(CONTRACTOR)
		checks.neighbor_fifo_unchanged=_line(sim)==before_line.filter(func(entry: Dictionary)->bool:return entry.actor_id!=CONTRACTOR)
		checks.bodies_unchanged=after.actors==before.actors
		checks.order_cancelled_and_detached=cancelled.accepted and _settled(before,after,job_id)
		checks.valid=world.validate(suite.content).is_empty()
		var repeated: CommandResult=_cancel_order(sim,job_id)
		checks.second_release_idempotent=repeated.accepted and world.freeze()==after
	row("contractor_ground_release",checks,{"tick":world.sim_tick})
	sim.dispose()

func _release_in_cabin() -> void:
	var sim: HospitalSimulation=suite._transit_fixture()
	var world: WorldState=sim.world
	var job_id: String=_add_contractor(sim,[42,82])
	if job_id.is_empty():
		row("contractor_committed_crossing",{"order_accepted":false})
		sim.dispose()
		return
	var request: String=sim.space.request_move(world,CONTRACTOR,2,[48,82])
	var seen: Dictionary={}
	for step: int in 800:
		suite._movement_tick(sim)
		var lift: Dictionary=world.facts.connectors[suite._connection(sim)]
		if world.facts.actors[CONTRACTOR].location.kind=="transit" and lift.phase in ["boarding","riding"] and not seen.has(lift.phase):
			var phase: String=lift.phase
			var before: Dictionary=world.freeze()
			var branch: HospitalSimulation=restored(before)
			var cancelled: CommandResult=_cancel_order(branch,job_id)
			var after: Dictionary=branch.world.freeze()
			var lift_id: String=suite._connection(branch)
			var expected_lift: Dictionary=before.connectors[lift_id].duplicate(true)
			expected_lift.maintenance_order_id=""
			var retained: bool=after.actors==before.actors and after.moves==before.moves and after.connectors[lift_id]==expected_lift
			var detached: bool=cancelled.accepted and _settled(before,after,job_id) and branch.world.validate(suite.content).is_empty()
			var arrived: bool=suite._wait(branch,func()->bool:return branch.space.at(branch.world,CONTRACTOR,2,[48,82]) and not branch.world.facts.moves.has(CONTRACTOR),800,suite._movement_tick.bind(branch))
			seen[phase]=retained and detached and arrived and branch.world.validate(suite.content).is_empty()
			branch.dispose()
		if seen.size()==2 and sim.space.at(world,CONTRACTOR,2,[48,82]) and not world.facts.moves.has(CONTRACTOR):break
	row("contractor_committed_crossing",{"request_accepted":request.is_empty(),"real_boarding_retained":seen.get("boarding",false),"real_riding_retained":seen.get("riding",false),"actually_arrived":sim.space.at(world,CONTRACTOR,2,[48,82]),"valid":world.validate(suite.content).is_empty()},{"tick":world.sim_tick})
	sim.dispose()

func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=1:
		quit(2)
		return
	suite.content=HospitalContent.new()
	_release_queued()
	_release_in_cabin()
	pending_family()
	var passed: bool=rows.all(func(r: Dictionary)->bool:return r.passed)
	var result: Dictionary={"passed":passed,"rows":rows}
	FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result))
	quit(0 if passed else 1)
