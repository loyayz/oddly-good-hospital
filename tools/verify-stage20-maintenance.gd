extends SceneTree

const Maintenance = preload("res://game/operations/maintenance_service.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var content: HospitalContent = HospitalContent.new()
	var world: WorldState = FeasibilityHospitals.create("stage20",false,content)
	var space: HospitalSpace = HospitalSpace.new(content)
	var service: RefCounted = Maintenance.new(content,space)
	service.ensure(world)
	world.facts.maintenance.next_scan_tick = 99999999
	world.facts.facilities.chair = {"id":"chair","definition_id":"FUR06","floor_id":1,"cell":[34,89],"footprint":[1,1],"patient_cell":[34,90],"operator_cells":[],"grade":0,"failed":false}
	_check("ordinary_furniture_not_maintained",not service.execute(world,"maintenance_order",{"facility_id":"chair"}).accepted and not world.facts.facilities.chair.has("condition"))
	_check("healthy_equipment_cannot_farm_maintenance",not service.execute(world,"maintenance_order",{"facility_id":"treatment"}).accepted)
	var item: Dictionary = world.facts.facilities.treatment
	item.condition = 44.0
	service.boundaries(world)
	var job_id: String = item.maintenance_order_id
	service.boundaries(world)
	_check("auto_scan_has_one_real_order",not job_id.is_empty() and world.facts.maintenance.jobs.size()==1 and item.maintenance_order_id==job_id)
	var cash: int = HospitalLedger.balance(world)
	service.dispatch(world)
	service.advance(world)
	_check("no_mechanic_no_work_no_parts",not world.facts.maintenance.jobs[job_id].started and HospitalLedger.balance(world)==cash)
	_add_mechanic(world,[50,80])
	for tick: int in 150:
		_step(world,space,service)
		if world.facts.maintenance.jobs[job_id].started:
			break
	var job: Dictionary = world.facts.maintenance.jobs[job_id]
	_check("parts_charged_at_actual_work_start",job.started and HospitalLedger.balance(world)==cash-20 and int(job.completed_milli)>0)
	for tick: int in 79:
		_step(world,space,service)
	var work_before_failure: int = int(job.completed_milli)
	item.failed = true
	service.boundaries(world)
	_check("maintenance_fault_promotes_same_order",world.facts.maintenance.jobs.size()==1 and job.kind=="repair" and int(job.total_milli)==30000 and int(job.completed_milli)==work_before_failure)
	for tick: int in 600:
		_step(world,space,service)
		if job.phase=="completed":
			break
	_check("repair_difference_and_remaining_work_conserved",job.phase=="completed" and int(job.paid_parts)==40 and HospitalLedger.balance(world)==cash-40 and float(item.condition)==100.0 and not item.failed)
	_check("real_completion_once_with_grace",world.facts.maintenance.receipts.size()==1 and int(item.repair_grace_until)>world.sim_tick and world.facts.maintenance.receipts.values()[0].staff_id=="mechanic")
	item.ownership = "borrowed"
	_check("borrowed_upgrade_rejected",not service.execute(world,"upgrade_order",{"facility_id":"treatment"}).accepted)
	item.ownership = "gift"
	item.paid_cost = 0
	world.facts.research.append("R13")
	var quote: Dictionary = service.upgrade_quote(world,{"facility_id":"treatment","target_level":2})
	_check("gift_two_stages_use_original_base_price",quote.ok and int(quote.cost)==1050 and quote.stages.size()==2 and int(quote.stages[0].price)==420 and int(quote.stages[1].price)==630)
	var base_cash: int = HospitalLedger.balance(world)
	var result: CommandResult = service.execute(world,"upgrade_order",{"facility_id":"treatment","target_level":2,"cost":1050})
	var order_id: String = result.changed_ids[0] if result.accepted else ""
	_check("upgrade_paid_but_grade_frozen",result.accepted and int(item.grade)==0 and item.upgrading_block and HospitalLedger.balance(world)==base_cash-1050)
	var order: Dictionary = world.facts.maintenance.upgrades.get(order_id,{})
	for tick: int in 80:
		_step(world,space,service)
		if not order.is_empty() and order.stages[0].started:
			break
	var snapshot: Dictionary = world.freeze()
	_check("started_upgrade_not_refundable",not service.execute(world,"upgrade_cancel",{"order_id":order_id}).accepted and snapshot==world.freeze())
	var remaining: int = int(order.remaining_milli)
	service.execute(world,"upgrade_pause",{"order_id":order_id})
	for tick: int in 20:
		_step(world,space,service)
	_check("upgrade_pause_keeps_work_and_payment",int(order.remaining_milli)==remaining and int(item.grade)==0 and HospitalLedger.balance(world)==base_cash-1050)
	var restored: WorldState = WorldState.new(world.freeze())
	_check("half_work_restores_exactly",service.validate(restored).is_empty() and restored.facts.maintenance.upgrades[order_id].remaining_milli==remaining)
	service.execute(world,"upgrade_resume",{"order_id":order_id})
	for tick: int in 750:
		_step(world,space,service)
		if order.phase=="completed":
			break
	_check("two_real_stages_complete_and_paid_basis_only_once",order.phase=="completed" and int(item.grade)==2 and int(item.upgrade_level)==2 and int(item.completed_upgrade_paid_cost)==1050 and int(item.paid_cost)==0 and not item.upgrading_block and not item.get("ever_used",false))
	_check("upgrade_does_not_repair_or_rewrite_attempt",float(item.condition)==100.0 and world.facts.attempts.is_empty() and world.facts.maintenance.receipts.size()==3)
	var other: Dictionary = world.facts.facilities.exam
	var pending: CommandResult = service.execute(world,"upgrade_order",{"facility_id":"exam"})
	var before_cancel: int = HospitalLedger.balance(world)
	_check("unstarted_stage_cancel_refunds_once",pending.accepted and service.execute(world,"upgrade_cancel",{"order_id":pending.changed_ids[0]}).accepted and HospitalLedger.balance(world)==before_cancel+240)
	var after_cancel: int = HospitalLedger.balance(world)
	service.execute(world,"upgrade_cancel",{"order_id":pending.changed_ids[0]})
	_check("repeated_cancel_never_refunds_again",HospitalLedger.balance(world)==after_cancel and int(other.grade)==0)
	_check("all_orders_validate",service.validate(world).is_empty())
	print("STAGE20 checks="+str(checks)+" failures="+str(failures))
	quit(0 if failures.is_empty() else 1)

func _step(world: WorldState, space: HospitalSpace, service: RefCounted) -> void:
	service.boundaries(world)
	service.dispatch(world)
	space.advance(world)
	service.advance(world)
	world.facts.sim_tick += 1
	world.touch()
	space.finish_boundary(world)

func _add_mechanic(world: WorldState, cell: Array) -> void:
	world.facts.actors.mechanic = {"id":"mechanic","name":"维修员","species_id":"S49","location":{"kind":"floor","floor_id":1,"cell":cell,"height_m":0.0},"facing":0.0,"posture":"standing"}
	world.facts.staff.mechanic = {"id":"mechanic","role":"mechanic","on_shift":true,"energy":100.0,"skill":1,"active_job_id":""}

func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print(("PASS " if ok else "FAIL ")+label)
