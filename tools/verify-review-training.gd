extends SceneTree

const Development = preload("res://game/staff/clinical_development.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var content: HospitalContent = HospitalContent.new()
	var world: WorldState = FeasibilityHospitals.create("review-training",false,content)
	var space: HospitalSpace = HospitalSpace.new(content)
	var development: RefCounted = Development.new(content,space)
	development.ensure(world)
	var student: Dictionary = world.facts.staff.gp_doctor
	student.abilities.treatment = 1
	var mentor: Dictionary = student.duplicate(true)
	mentor.id = "review_mentor"
	mentor.title_id = str(content.balance.doctor_training.mentor_min_title_id)
	mentor.abilities.treatment = 4
	world.facts.staff[mentor.id] = mentor
	world.facts.actors[mentor.id] = world.facts.actors.gp_doctor.duplicate(true)
	world.facts.actors[mentor.id].id = mentor.id
	for staff: Dictionary in [student,mentor,world.facts.staff.exam_nurse]:
		staff.scheduled_kind = "training"
		staff.on_shift = true
		staff.energy = 100.0
		staff.fatigue = 20.0
		staff.block_new_work = false
		staff.base_prepared = true
		staff.base_task = {}
		staff.life_task = {"phase":"idle"}
		staff.leave_plan = {}
		staff.rest_obligation = false
		staff.rest_debt_ticks = 0
		staff.sleep_remaining_ticks = 0
	world.facts.facilities.review_desk = {"id":"review_desk","definition_id":"FUR05","floor_id":1,"cell":[43,77],"footprint":[1,1],"patient_cell":[43,78],"operator_cells":[[44,77]],"repair_cell":[42,77],"failed":false}
	_place(world,space,"gp_doctor",[44,77])
	_place(world,space,mentor.id,[44+space.clearance(world.facts.actors.gp_doctor),77])
	var enrolled: CommandResult = development.execute(world,"train_staff",{"staff_id":"gp_doctor","track":"treatment","desk_id":"review_desk","mentor_id":mentor.id})
	_check("formal_enrollment",enrolled.accepted)
	if not enrolled.accepted:
		print(enrolled.reason)
	if student.training_job_id.is_empty():
		_finish()
		return
	var job: Dictionary = world.facts.training_jobs[student.training_job_id]
	var total: int = int(job.total_work_milli)
	mentor.scheduled_kind = "work"
	development.dispatch(world)
	var before: float = _remaining(job)
	development.advance(world)
	var solo: float = 1000.0/(1.0+float(content.balance.wellbeing.fatigue_work_multiplier_per_point)*20.0)
	_check("mentor_requires_training_shift",is_equal_approx(before-_remaining(job),solo))
	student.fatigue = 30.0
	before = _remaining(job)
	development.advance(world)
	_check("fatigue_frozen_within_segment",is_equal_approx(before-_remaining(job),solo))
	mentor.scheduled_kind = "training"
	mentor.block_new_work = true
	development.dispatch(world)
	before = _remaining(job)
	development.advance(world)
	_check("external_mentor_block_rejected",is_equal_approx(before-_remaining(job),solo))
	mentor.block_new_work = false
	mentor.energy = float(content.balance.wellbeing.recreation_max_energy_priority)
	development.dispatch(world)
	before = _remaining(job)
	development.advance(world)
	_check("low_energy_mentor_rejected",is_equal_approx(before-_remaining(job),solo))
	mentor.energy = 100.0
	mentor.fatigue = 40.0
	development.dispatch(world)
	before = _remaining(job)
	development.advance(world)
	var new_solo: float = 1000.0/(1.0+float(content.balance.wellbeing.fatigue_work_multiplier_per_point)*30.0)
	var mentor_rate: float = 1000.0/(1.0+float(content.balance.wellbeing.fatigue_work_multiplier_per_point)*40.0)
	_check("mentor_arrival_freezes_both_rates",is_equal_approx(before-_remaining(job),new_solo+0.25*minf(new_solo,mentor_rate)))
	_check("mentor_owns_dispatch_block",development.worked_staff().has(mentor.id))
	_json_round_trip(world,development,job.id,"working_segment")
	# A faster mentor must still be limited by the student's own throughput.
	mentor.scheduled_kind = "work"
	development.dispatch(world)
	development.advance(world)
	mentor.scheduled_kind = "training"
	mentor.block_new_work = false
	mentor.fatigue = 0.0
	development.dispatch(world)
	before = _remaining(job)
	development.advance(world)
	_check("fast_mentor_limited_by_student",is_equal_approx(before-_remaining(job),new_solo*1.25))
	student.energy = float(content.balance.wellbeing.recreation_max_energy_priority)
	development.dispatch(world)
	before = _remaining(job)
	development.advance(world)
	_check("low_energy_student_pauses",is_equal_approx(before,_remaining(job)) and job.state=="paused")
	student.energy = 100.0
	student.on_shift = false
	development.dispatch(world)
	before = _remaining(job)
	development.advance(world)
	_check("pause_preserves_work",is_equal_approx(before,_remaining(job)))
	var restored: WorldState = WorldState.new(world.freeze())
	_check("save_retains_fraction_and_total",restored.facts.training_jobs[job.id]==job and int(job.total_work_milli)==total)
	_json_round_trip(world,development,job.id,"paused_segment")
	student.on_shift = true
	student.fatigue = 10.0
	mentor.scheduled_kind = "work"
	development.dispatch(world)
	before = _remaining(job)
	development.advance(world)
	_check("resume_freezes_new_fatigue",is_equal_approx(before-_remaining(job),1000.0/(1.0+float(content.balance.wellbeing.fatigue_work_multiplier_per_point)*10.0)))
	job.remaining_work_milli = int(job.total_work_milli)/2
	job.work_fraction_milli = 0.5
	var balance_before_cancel: int = HospitalLedger.balance(world)
	development.execute(world,"cancel_training",{"staff_id":"gp_doctor"})
	_check("fraction_below_half_course_never_over_refunds",int(job.refund)==int(job.cost)/2-1 and HospitalLedger.balance(world)-balance_before_cancel==int(job.refund))
	development.execute(world,"cancel_training",{"staff_id":"gp_doctor"})
	_check("fraction_refund_is_unique",HospitalLedger.balance(world)-balance_before_cancel==int(job.refund))
	_json_round_trip(world,development,job.id,"cancelled_segment")
	_place(world,space,"gp_doctor",[40,77])
	_place(world,space,"exam_nurse",[44,77])
	_check("nurse_formal_enrollment",development.execute(world,"train_staff",{"staff_id":"exam_nurse","track":"care","desk_id":"review_desk"}).accepted)
	var nurse_job: Dictionary = world.facts.training_jobs[world.facts.staff.exam_nurse.training_job_id]
	development.dispatch(world)
	before = _remaining(nurse_job)
	development.advance(world)
	_check("nurse_multiplier_is_one",is_equal_approx(before-_remaining(nurse_job),1000.0))
	nurse_job.remaining_work_milli = 0
	development.settle(world)
	_json_round_trip(world,development,nurse_job.id,"completed_segment")
	_finish()

func _json_round_trip(world: WorldState, development: RefCounted, job_id: String, label: String) -> void:
	var chunks: Array[PackedByteArray] = []
	var codec: HospitalJsonStream = HospitalJsonStream.new()
	var budget: Callable = func(_bytes: int) -> bool: return true
	var encoded: bool = codec.encode_to(world.freeze(),budget,func(chunk: PackedByteArray) -> Dictionary:
		chunks.append(chunk)
		return {"ok":true})
	_check(label+"_json_encoded",encoded)
	if not encoded:
		return
	var decoded: Dictionary = HospitalJsonStream.new().decode_from(codec.bytes,codec.digest,budget,func() -> Dictionary:
		return {"ok":true,"data":chunks.pop_front() if not chunks.is_empty() else PackedByteArray()})
	_check(label+"_json_decoded",decoded.ok)
	if not decoded.ok:
		return
	var restored: WorldState = WorldState.new(decoded.value)
	var original: Dictionary = world.facts.training_jobs[job_id]
	var saved: Dictionary = restored.facts.training_jobs[job_id]
	_check(label+"_json_preserves_frozen_work",saved.get("work_segment",{})==original.get("work_segment",{}) and saved.get("work_fraction_milli",0.0)==original.get("work_fraction_milli",0.0) and saved.remaining_work_milli==original.remaining_work_milli)
	_check(label+"_json_training_valid",development.validate(restored).is_empty())
	if saved.has("work_segment"):
		saved.work_segment.mentor_id = "missing_review_mentor"
		_check(label+"_rejects_invalid_segment_mentor",not development.validate(restored).is_empty())

func _remaining(job: Dictionary) -> float:
	return float(job.remaining_work_milli)-float(job.get("work_fraction_milli",0.0))

func _place(world: WorldState, space: HospitalSpace, id: String, cell: Array) -> void:
	world.facts.actors[id].location = {"kind":"floor","floor_id":1,"cell":cell,"height_m":0.0}
	space.sync_actor(world,id)

func _check(name: String, ok: bool) -> void:
	if not ok:
		failures.append(name)

func _finish() -> void:
	print(JSON.stringify({"review":"training","failures":failures}))
	quit(0 if failures.is_empty() else 1)
