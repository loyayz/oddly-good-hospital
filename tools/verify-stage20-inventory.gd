extends SceneTree

const Maintenance = preload("res://game/operations/maintenance_service.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var content: HospitalContent = HospitalContent.new()
	var world: WorldState = FeasibilityHospitals.create("stage20-inventory",false,content)
	for collection: String in ["actors","staff","visits","sessions","attempts","tickets","preparations","ward_stays","facilities","adaptations","moves","rooms"]:
		world.facts[collection].clear()
	world.facts.actors.mechanic = {"id":"mechanic","name":"维修员","species_id":"S49","location":{"kind":"floor","floor_id":1,"cell":[34,90],"height_m":0.0},"facing":0.0,"posture":"standing"}
	world.facts.staff.mechanic = {"id":"mechanic","role":"mechanic","on_shift":true,"energy":100.0,"skill":1,"active_job_id":""}
	var space: HospitalSpace = HospitalSpace.new(content)
	var service: RefCounted = Maintenance.new(content,space)
	var build: BuildService = BuildService.new(content,space)
	build.ensure(world)
	service.ensure(world)
	world.facts.maintenance.next_scan_tick = 99999999
	var placed: CommandResult = build.execute(world,"build_facility",{"id":"subject","definition_id":"M37","floor_id":1,"cell":[37,75]})
	_check("fixture_actual_purchase",placed.accepted)
	if not placed.accepted:
		print(placed.reason)
		quit(1)
		return
	world.facts.facilities.subject.condition = 44.0
	service.boundaries(world)
	var job_id: String = world.facts.facilities.subject.maintenance_order_id
	service.dispatch(world)
	service.advance(world)
	_check("maintenance_owns_real_travel",world.facts.moves.has("mechanic") and world.facts.moves.mechanic.get("owner_job_id","")==job_id)
	var frozen: Dictionary = world.freeze()
	var preview: Dictionary = build.preview(world,{"kind":"build_store","target_id":"subject"})
	_check("inventory_preview_is_fully_read_only",preview.ok and world.freeze()==frozen)
	var rejected: CommandResult = build.execute(world,"build_store",{"target_id":"subject","quote":{"kind":"changed-quote"}})
	_check("failed_confirmation_does_not_release_original_job_or_route",not rejected.accepted and frozen==world.freeze())
	world.facts.sessions["clinical-lock"] = {"facility_id":"subject"}
	frozen = world.freeze()
	_check("clinical_commitment_prevents_store_atomically",not build.execute(world,"build_store",{"target_id":"subject"}).accepted and frozen==world.freeze())
	world.facts.sessions.erase("clinical-lock")
	var original_actor: Dictionary = world.facts.actors.mechanic.duplicate(true)
	var original_remaining: int = int(world.facts.maintenance.jobs[job_id].remaining_milli)
	var original_cash: int = HospitalLedger.balance(world)
	var stored: CommandResult = build.execute(world,"build_store",{"target_id":"subject","record_key":"store-original"})
	_check("same_subject_moves_to_inventory_without_payment",stored.accepted and not world.facts.facilities.has("subject") and world.facts.inventory.build_items.has("subject") and HospitalLedger.balance(world)==original_cash)
	_check("same_order_suspended_with_remaining_and_worker_release",world.facts.maintenance.jobs[job_id].phase=="inventory" and int(world.facts.maintenance.jobs[job_id].remaining_milli)==original_remaining and world.facts.staff.mechanic.active_job_id=="" and not world.facts.moves.has("mechanic") and world.facts.actors.mechanic==original_actor)
	frozen = world.freeze()
	_check("duplicate_store_does_not_move_twice",build.execute(world,"build_store",{"target_id":"subject","record_key":"store-original"}).accepted and frozen==world.freeze())
	service.boundaries(world)
	service.dispatch(world)
	service.advance(world)
	_check("inventory_order_cannot_work_or_cancel_on_scan",world.facts.maintenance.jobs[job_id].phase=="inventory" and int(world.facts.maintenance.jobs[job_id].remaining_milli)==original_remaining and service.validate(world).is_empty())
	frozen = world.freeze()
	_check("invalid_replacement_keeps_inventory_and_orders",not build.execute(world,"build_facility",{"inventory_id":"subject","definition_id":"M37","cell":[34,90]}).accepted and frozen==world.freeze())
	var replaced: CommandResult = build.execute(world,"build_facility",{"inventory_id":"subject","definition_id":"M37","floor_id":1,"cell":[37,75]})
	_check("replacement_retains_full_record_and_order_identity",replaced.accepted and world.facts.facilities.subject.maintenance_order_id==job_id and world.facts.inventory.build_items.is_empty() and world.facts.maintenance.jobs.size()==1 and HospitalLedger.balance(world)==original_cash)
	service.dispatch(world)
	service.advance(world)
	_check("same_tick_replacement_does_not_resume_work",int(world.facts.maintenance.jobs[job_id].remaining_milli)==original_remaining and str(world.facts.maintenance.jobs[job_id].worker_id).is_empty())
	for tick: int in 400:
		_step(world,space,service)
		if world.facts.maintenance.jobs[job_id].started:
			break
	_check("replacement_reaches_actual_work_and_charges_once",world.facts.maintenance.jobs[job_id].started and HospitalLedger.balance(world)==original_cash-20)
	for tick: int in 20:
		_step(world,space,service)
	var paid_remaining: int = int(world.facts.maintenance.jobs[job_id].remaining_milli)
	var paid_cash: int = HospitalLedger.balance(world)
	_check("started_maintenance_can_store_safely",build.execute(world,"build_store",{"target_id":"subject"}).accepted and int(world.facts.maintenance.jobs[job_id].remaining_milli)==paid_remaining and int(world.facts.maintenance.jobs[job_id].paid_parts)==20)
	var saved: WorldState = WorldState.new(world.freeze())
	service.ensure(saved)
	_check("inventory_snapshot_keeps_same_job_and_paid_parts",saved.freeze()==world.freeze() and service.validate(saved).is_empty())
	build.execute(world,"build_facility",{"inventory_id":"subject","definition_id":"M37","cell":[42,75]})
	for tick: int in 500:
		_step(world,space,service)
		if world.facts.maintenance.jobs[job_id].phase=="completed":
			break
	_check("same_maintenance_finishes_without_rebuy_or_extra_parts",world.facts.maintenance.jobs[job_id].phase=="completed" and HospitalLedger.balance(world)==paid_cash and world.facts.maintenance.receipts.size()==1 and world.facts.maintenance.jobs.size()==1)
	if not "R13" in world.facts.research:
		world.facts.research.append("R13")
	var upgrade: CommandResult = service.execute(world,"upgrade_order",{"facility_id":"subject","target_level":2})
	_check("two_stage_upgrade_paid_once",upgrade.accepted)
	if not upgrade.accepted:
		print(upgrade.reason)
		quit(1)
		return
	var upgrade_id: String = upgrade.changed_ids[0]
	for tick: int in 100:
		_step(world,space,service)
		if world.facts.maintenance.upgrades[upgrade_id].stages[0].started:
			break
	var upgrade_remaining: int = int(world.facts.maintenance.upgrades[upgrade_id].remaining_milli)
	var upgrade_cost: int = int(world.facts.maintenance.upgrades[upgrade_id].cost)
	var upgrade_cash: int = HospitalLedger.balance(world)
	var upgrade_work: int = int(world.facts.maintenance.upgrades[upgrade_id].stages[0].completed_milli)
	_check("started_upgrade_store_keeps_frozen_paid_work",build.execute(world,"build_store",{"target_id":"subject"}).accepted and world.facts.maintenance.upgrades[upgrade_id].phase=="inventory" and int(world.facts.maintenance.upgrades[upgrade_id].remaining_milli)==upgrade_remaining and world.facts.inventory.build_items.subject.upgrading_block)
	service.boundaries(world)
	service.dispatch(world)
	service.advance(world)
	_check("inventory_upgrade_never_advances",int(world.facts.maintenance.upgrades[upgrade_id].stages[0].completed_milli)==upgrade_work and int(world.facts.maintenance.upgrades[upgrade_id].cost)==upgrade_cost)
	_check("upgrade_replacement_preserves_level_and_block",build.execute(world,"build_facility",{"inventory_id":"subject","definition_id":"M37","cell":[39,75]}).accepted and int(world.facts.facilities.subject.grade)==0 and world.facts.facilities.subject.upgrading_block and world.facts.maintenance.upgrades.size()==1)
	for tick: int in 900:
		_step(world,space,service)
		if world.facts.maintenance.upgrades[upgrade_id].phase=="completed":
			break
	_check("same_upgrade_finishes_after_real_relocation_without_new_payment",world.facts.maintenance.upgrades[upgrade_id].phase=="completed" and int(world.facts.facilities.subject.grade)==2 and int(world.facts.facilities.subject.completed_upgrade_paid_cost)==1050 and HospitalLedger.balance(world)==upgrade_cash and world.facts.maintenance.receipts.size()==3)
	_check("final_work_and_inventory_invariants",service.validate(world).is_empty() and build.validate(world).is_empty() and world.facts.inventory.build_items.is_empty())
	print("STAGE20 INVENTORY checks="+str(checks)+" failures="+str(failures))
	quit(0 if failures.is_empty() else 1)

func _step(world: WorldState, space: HospitalSpace, service: RefCounted) -> void:
	service.boundaries(world)
	service.dispatch(world)
	space.advance(world)
	service.advance(world)
	world.facts.sim_tick += 1
	world.touch()
	space.finish_boundary(world)

func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print(("PASS " if ok else "FAIL ")+label)
