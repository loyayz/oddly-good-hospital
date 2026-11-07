extends SceneTree

var checks: Dictionary = {}
func check(value: bool, name: String) -> void:
	checks[name] = value
func validate_input(w: WorldState, db: HospitalContent, scheduler: HospitalShiftScheduler, wellbeing: HospitalStaffWellbeing, label: String) -> void:
	var errors: Dictionary = {"world":w.validate(db),"scheduler":scheduler.validate(w),"wellbeing":wellbeing.validate(w)}
	print("INPUT_VALIDATION "+label+" "+JSON.stringify(errors))
	check(str(errors.world).is_empty() and str(errors.scheduler).is_empty() and str(errors.wellbeing).is_empty(),label+" valid")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var db: HospitalContent = HospitalContent.new()
	var w: WorldState = HospitalFactory.create("item020","Preview",true,db)
	var sim: HospitalSimulation = HospitalSimulation.new(w,db)
	var s: HospitalShiftScheduler = sim.services.scheduler
	var panel: HospitalSchedulePanel = HospitalSchedulePanel.new()
	panel.simulation = sim
	panel.build_controls()
	var before: String = JSON.stringify(w.facts)
	panel._preview_suggestion()
	var rows: Array = panel._proposal.coverage
	check(before==JSON.stringify(w.facts),"suggestion and UI read only")
	check(rows[2].nurse==0 and rows[2].receptionist==0 and "导诊无排班合资格护士" in rows[2].gaps and "接待无排班接待员" in rows[2].gaps,"starter third shift explicit gaps")
	check(rows[0].nurse==2 and rows[0].care==2 and rows[0].receptionist==1 and rows[0].cleaner==1 and rows[0].researcher==0 and rows[0].decorator==0,"six roles and nursing skills")
	check("当前实际状态" in panel._preview.text and "不代表已到岗" in panel._preview.text and "草案，未应用" in panel._preview.text,"UI scope text")
	var doctor_only: bool = true
	for change: Dictionary in panel._proposal.changes:
		doctor_only = doctor_only and w.facts.staff[change.staff_id].role=="doctor"
	check(doctor_only,"only doctor suggestions")
	var buttons: Array = []
	for child: Node in panel.get_children():
		if child is Button: buttons.append(child.text)
	check("预览医生建议排班" in buttons and not "预览建议排班" in buttons,"actual button scope")
	print("STARTER_UI\n"+panel._preview.text)
	panel._preview_suggestion()
	check(before==JSON.stringify(w.facts),"repeated preview read only")
	panel._staff.select(1)
	panel._load_staff()
	check(panel._proposal.is_empty() and "尚未预览" in panel._preview.text,"switch staff clears draft and old preview")
	panel._preview_manual()
	check(before==JSON.stringify(w.facts) and panel._proposal.changes.size()==1,"manual preview read only")
	# Reception reporting must depend on the reception desk, not a clinical station.
	var removed: Dictionary = {}
	for id: String in w.facility_ids("FUR02"):
		removed[id] = w.facts.facilities[id]
		w.facts.facilities.erase(id)
	validate_input(w,db,s,sim.services.wellbeing,"reception without clinic")
	check("接待无排班接待员" in s.coverage(w)[2].gaps,"reception desk without clinic still reports gap")
	w.facts.facilities.merge(removed)
	panel._show_coverage(s.coverage(w))
	check(not "休息/生活任务中" in panel._preview.text,"idle life task is not shown as resting")
	var nurse_id: String = "starter_guide_nurse"
	var nurse: Dictionary = w.facts.staff[nurse_id]
	var original: Dictionary = w.facts.duplicate(true)
	# Valid full-world raw qualification boundary, not a naturally generated career.
	var fixtures = preload("res://tests/acceptance/staff_fixtures.gd").new()
	fixtures._content = db
	var ward: Dictionary = fixtures._fixture({"nurse":"nurse"})
	var ward_room: String = fixtures._room(ward,"ward")
	fixtures._facility(ward,"preview_bed","EQ05",[43,75],ward_room)
	var qualification_proposal: Dictionary = ward.s.suggestion(ward.world)
	ward.world.facts.staff.nurse.certificates = []
	validate_input(ward.world,db,ward.s,ward.w,"raw care without ward certificate")
	var qualification_before: String = JSON.stringify(ward.world.facts)
	var qualification_rejected: CommandResult = ward.s.execute(ward.world,"apply_schedule",qualification_proposal)
	check(not qualification_rejected.accepted and qualification_rejected.code=="material_change" and qualification_before==JSON.stringify(ward.world.facts),"certificate change invalidates draft atomically")
	rows = ward.s.coverage(ward.world)
	check(rows[0].care==1 and rows[0].ward_nurse==0 and "病房缺护理或查房排班资格" in rows[0].gaps,"care skill without ward certificate")
	# Start from the existing legal sleep-boundary builder, then execute real travel
	# and bed entry. Only the current preview is asserted, not a full sleep cycle.
	var sleep_builder = preload("res://tests/acceptance/staff_scheduled_sleep.gd").new()
	sleep_builder._content = db
	var sleep_input: Dictionary = sleep_builder._input(["work","work","rest"],0,13500)
	validate_input(sleep_input.world,db,sleep_input.s,sleep_input.w,"pre sleep boundary")
	var sleep_sim: HospitalSimulation = HospitalSimulation.new(sleep_input.world,db)
	for tick: int in 1200:
		sleep_sim.step()
		if sleep_sim.world.facts.staff.sleeper.life_task.phase=="sleep": break
	validate_input(sleep_sim.world,db,sleep_sim.services.scheduler,sleep_sim.services.wellbeing,"actual sleep preview")
	var sleeping: Dictionary = sleep_sim.world.facts.staff.sleeper
	check(sleeping.life_task.phase=="sleep" and sleeping.block_new_work and sleep_sim.services.scheduler.coverage(sleep_sim.world)[0].care==1,"current unavailability separate from scheduled capacity")
	sleep_sim.dispose()
	# Future leave is not today's leave; half-open boundaries do not suppress adjacent slots.
	nurse.leave_plan = {"kind":"voluntary","state":"planned","requested_start_tick":18000,"days":1,"actual_start_tick":-1,"end_tick":-1}
	validate_input(w,db,s,sim.services.wellbeing,"future leave")
	check(s.coverage(w)[0].nurse==2,"next day leave counted today")
	nurse.leave_plan.requested_start_tick = 6000
	nurse.leave_plan.end_tick = 9000
	validate_input(w,db,s,sim.services.wellbeing,"partial leave")
	check(s.coverage(w)[0].nurse==2 and s.coverage(w)[1].nurse==1 and s.coverage(w)[1].leave_excluded==1,"partial leave and exact boundary")
	nurse.leave_plan = {}
	# Calculation boundary with the production payroll settlement, not a claim
	# that safe resignation/physical departure was simulated by this test.
	var departure: WorldState = WorldState.new(w.freeze())
	var finance: FinanceService = FinanceService.new(db,sim.space)
	var departure_proposal: Dictionary = s.suggestion(departure)
	check(finance.settle_departure(departure,nurse_id).accepted,"departure wage settlement")
	validate_input(departure,db,s,sim.services.wellbeing,"departed boundary")
	check(s.coverage(departure)[0].nurse==1,"departed not counted")
	var departure_before: String = JSON.stringify(departure.facts)
	var rejected: CommandResult = s.execute(departure,"apply_schedule",departure_proposal)
	check(not rejected.accepted and rejected.code=="material_change" and departure_before==JSON.stringify(departure.facts),"departure invalidates draft atomically")
	w.facts.sim_tick = 6000
	nurse.schedule_overrides = {"1":{"kind":"rest","pools":[],"locked":false}}
	var draft: Array = nurse.schedule.duplicate(true)
	draft[0].kind = "rest"
	draft[2].kind = "work"
	var changes: Array = [{"staff_id":nurse_id,"schedule":draft}]
	validate_input(w,db,s,sim.services.wellbeing,"schedule override boundary")
	var snapshot: String = JSON.stringify(w.facts)
	rows = s.coverage(w,changes)
	print("OVERRIDE_ROWS "+JSON.stringify({"rows":rows,"day":nurse.schedule_day,"slot":s.shift_index(w),"tick":w.sim_tick}))
	check(rows[0].nurse==2 and rows[1].nurse==1 and rows[2].nurse==1,"past preserved override wins future draft shown")
	check(snapshot==JSON.stringify(w.facts),"coverage overrides read only")
	# Stale prior-day overrides must not affect today.
	w.facts.sim_tick = 18000
	validate_input(w,db,s,sim.services.wellbeing,"prior day override boundary")
	check(s.coverage(w)[1].nurse==2,"stale day overrides ignored")
	w.facts = original
	w.facts.sim_tick = 0
	# Reach a real assigned guidance post through production dispatch, without fake arrival.
	for tick: int in 1200:
		sim.step()
		if str(w.facts.staff[nurse_id].get("active_job_id","")).begins_with("floor_desk:"): break
	var claimed: bool = false
	for staff: Dictionary in w.facts.staff.values():
		if str(staff.get("active_job_id","")).begins_with("floor_desk:"): claimed = true
	panel._preview_suggestion()
	check(claimed and "导诊岗位已占用，不能同时承担其他护理" in panel._preview.text,"real guidance owner not presented as free nursing")
	check("到岗护士" in panel._preview.text and "快照" in panel._preview.text,"actual guidance status separately displayed")
	# One capable nurse cannot be promised concurrently for a desk and clinical work.
	for staff: Dictionary in w.facts.staff.values():
		if staff.role=="nurse" and staff.id!=nurse_id:
			staff.schedule = [{"kind":"rest","pools":[],"locked":false},{"kind":"work","pools":[],"locked":false},{"kind":"work","pools":[],"locked":false}]
	validate_input(w,db,s,sim.services.wellbeing,"one nurse shared capacity boundary")
	rows = s.coverage(w)
	check(rows[0].care==1 and "导诊与临床护理共用护士，不能同时保证" in rows[0].gaps,"one nurse shared capacity warning")
	panel._show_coverage(rows)
	print("SHARED_UI\n"+panel._preview.text)
	panel.free()
	sim.dispose()
	print(JSON.stringify({"checks":checks,"passed":not checks.values().has(false)}))
	quit(1 if checks.values().has(false) else 0)
