extends SceneTree

const EnvironmentService = preload("res://game/operations/environment_service.gd")
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var content: HospitalContent = HospitalContent.new()
	var world: WorldState = FeasibilityHospitals.create("stage19",false,content)
	var space: HospitalSpace = HospitalSpace.new(content)
	var environment: RefCounted = EnvironmentService.new(content,space)
	environment.ensure(world)
	var dirt_id: String = environment.spawn_dirt(world,"CL01","event-original","event-original:1",1,[34,91])
	_check("real_dirt_has_frozen_work",not dirt_id.is_empty() and int(world.facts.environment.dirt[dirt_id].remaining_milli)==4000)
	_check("same_source_does_not_duplicate",environment.spawn_dirt(world,"CL01","event-original","event-original:1",1,[34,91])==dirt_id and world.facts.environment.dirt.size()==1)
	var before: Dictionary = world.freeze()
	var cell: Array = world.facts.environment.dirt[dirt_id].cell
	var value: Dictionary = environment.environment_at(world,1,cell)
	var heatmap: Array = environment.heatmap(world,1,[cell,[35,92]])
	_check("heatmap_and_environment_read_only",before==world.freeze() and int(value.dirt)==1 and heatmap.size()==2)
	world.facts.sim_tick = 50000
	environment.dispatch(world)
	environment.advance(world)
	_check("dirt_never_expires_without_worker",world.facts.environment.dirt.has(dirt_id))
	_add_worker(world,"cleaner","cleaner",[34,94])
	for tick: int in 220:
		_step(world,space,environment)
		if world.facts.environment.dirt.is_empty():
			break
	_check("reachable_cleaner_really_finishes",world.facts.environment.dirt.is_empty() and world.facts.environment.receipts.size()==1)
	var receipt: Dictionary = world.facts.environment.receipts.values()[0]
	_check("cleanup_credit_from_actual_contributor",receipt.kind=="cleanup_completed" and receipt.staff_id=="cleaner" and int(receipt.standard_work_milli)==4000)
	_check("clean_environment_recovers",int(environment.environment_at(world,1,cell).value)==int(value.value)+12)
	world.facts.facilities.tool = {"id":"tool","definition_id":"SE02","floor_id":1,"cell":[34,88],"footprint":[1,1],"failed":false,"patient_cell":[34,89],"operator_cells":[[34,89]],"repair_cell":[35,88],"grade":0,"condition":100.0,"use_receipts":{}}
	_add_worker(world,"decorator","decorator",[34,86])
	var quote: Dictionary = {"floor_id":1,"material_id":"MAT01","unit_price":25,"units":[{"cell":[35,92]},{"cell":[36,92]}]}
	var balance: int = HospitalLedger.balance(world)
	var result: CommandResult = environment.execute(world,"renovation_order",quote)
	var order_id: String = result.changed_ids[0] if result.accepted else ""
	_check("paid_order_does_not_finish_surfaces",result.accepted and HospitalLedger.balance(world)==balance-50 and world.facts.environment.surfaces.is_empty())
	before = world.freeze()
	_check("overlapping_surface_rejected_atomically",not environment.execute(world,"renovation_order",quote).accepted and before==world.freeze())
	var started: bool = false
	for tick: int in 300:
		_step(world,space,environment)
		if world.facts.environment.orders[order_id].units[0].started:
			started = true
			break
	_check("decorator_collects_tools_and_walks_to_work",started and not world.facts.environment.orders[order_id].units[0].tool_id.is_empty())
	var order: Dictionary = world.facts.environment.orders[order_id]
	var first_remaining: int = int(order.units[0].remaining_milli)
	environment.execute(world,"renovation_pause",{"order_id":order_id})
	_step(world,space,environment)
	_check("pause_preserves_remaining_and_old_surface",int(order.units[0].remaining_milli)==first_remaining and world.facts.environment.surfaces.is_empty())
	var paused_cash: int = HospitalLedger.balance(world)
	environment.execute(world,"renovation_cancel",{"order_id":order_id})
	_check("cancel_refunds_only_unstarted_material",HospitalLedger.balance(world)==paused_cash+25 and order.paused and order.units[1].phase=="cancelled")
	before = world.freeze()
	environment.execute(world,"renovation_cancel",{"order_id":order_id})
	_check("cancel_refund_once",before==world.freeze() or HospitalLedger.balance(world)==paused_cash+25)
	environment.execute(world,"renovation_resume",{"order_id":order_id})
	for tick: int in 350:
		_step(world,space,environment)
		if order.phase=="cancelled":
			break
	_check("started_cancelled_unit_finishes_legitimately",order.phase=="cancelled" and world.facts.environment.surfaces.size()==1 and order.units[0].phase=="completed")
	var surface: Dictionary = world.facts.environment.surfaces.values()[0]
	_check("completed_material_has_paid_basis",surface.material_id=="MAT01" and int(surface.paid_cost)==25)
	var original_cash: int = HospitalLedger.balance(world)
	var replacement: CommandResult = environment.execute(world,"renovation_order",{"floor_id":1,"material_id":"MAT02","units":[{"cell":[35,92]}]})
	_check("replacement_does_not_refund_early",replacement.accepted and HospitalLedger.balance(world)==original_cash-35)
	for tick: int in 350:
		_step(world,space,environment)
	_check("replacement_returns_paid_old_material_once",HospitalLedger.balance(world)==original_cash-15 and world.facts.environment.surfaces.values()[0].material_id=="MAT02")
	var restored: WorldState = WorldState.new(world.freeze())
	environment.ensure(restored)
	_check("saved_orders_surfaces_and_receipts_validate",environment.validate(restored).is_empty() and restored.freeze()==world.freeze())
	print("STAGE19 checks="+str(checks)+" failures="+str(failures))
	quit(0 if failures.is_empty() else 1)

func _step(world: WorldState, space: HospitalSpace, service: RefCounted) -> void:
	service.dispatch(world)
	space.advance(world)
	service.advance(world)
	world.facts.sim_tick += 1
	world.touch()
	space.finish_boundary(world)

func _add_worker(world: WorldState, id: String, role: String, cell: Array) -> void:
	world.facts.actors[id] = {"id":id,"name":id,"species_id":"S49","location":{"kind":"floor","floor_id":1,"cell":cell,"height_m":0.0},"facing":0.0,"posture":"standing"}
	world.facts.staff[id] = {"id":id,"role":role,"on_shift":true,"energy":100.0,"skill":1,"stress_milli":0,"active_job_id":""}

func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print(("PASS " if ok else "FAIL ")+label)
