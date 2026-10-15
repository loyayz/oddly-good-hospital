extends SceneTree

const Development = preload("res://game/staff/clinical_development.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var content: HospitalContent = HospitalContent.new()
	var world: WorldState = FeasibilityHospitals.create("training-rules",false,content)
	var space: HospitalSpace = HospitalSpace.new(content)
	var development: RefCounted = Development.new(content,space)
	development.ensure(world)
	var doctor: Dictionary = world.facts.staff.gp_doctor
	doctor.abilities.treatment = 1
	doctor.scheduled_kind = "training"
	doctor.on_shift = true
	var quote: Dictionary = development.preview(world,"gp_doctor","treatment")
	_check("course_reads_fee_and_human_talent",quote.ok and int(quote.cost)==400 and int(quote.work_ticks)==1080)
	var balance: int = HospitalLedger.balance(world)
	_check("missing_desk_requires_explicit_paid_queue",not development.execute(world,"train_staff",{"staff_id":"gp_doctor","track":"treatment"}).accepted and HospitalLedger.balance(world)==balance)
	_check("paid_queue_can_start",development.execute(world,"train_staff",{"staff_id":"gp_doctor","track":"treatment","queue_without_desk":true,"confirmed_quote":quote.basis}).accepted)
	var job_id: String = doctor.training_job_id
	var job: Dictionary = world.facts.training_jobs[job_id]
	job.remaining_work_milli = int(job.total_work_milli)/2
	doctor.practice.treatment = 20
	development.settle(world)
	_check("practice_supersedes_without_course_fact",doctor.abilities.treatment==2 and job.state=="superseded" and doctor.completed_courses.is_empty())
	_check("refund_frozen_unfinished_fraction",job.refund==200 and HospitalLedger.balance(world)==balance-200)
	development.settle(world)
	_check("duplicate_settlement_does_not_refund_twice",HospitalLedger.balance(world)==balance-200)
	_check("enroll_next_course_after_real_practice",development.execute(world,"train_staff",{"staff_id":"gp_doctor","track":"treatment","queue_without_desk":true}).accepted)
	job = world.facts.training_jobs[doctor.training_job_id]
	job.remaining_work_milli = 0
	development.settle(world)
	_check("real_completion_records_one_course",doctor.abilities.treatment==3 and doctor.completed_courses.size()==1)
	doctor.abilities.surgery = 0
	doctor.practice.surgery = int(content.balance.clinical_ability_growth.practice_total_cap)
	development.settle(world)
	_check("practice_never_bypasses_surgery_entry",doctor.abilities.surgery==0)
	doctor.title_id = "DT01"
	doctor.cured_cases = 20
	doctor.growth_direction = "treatment"
	_check("promotion_uses_existing_abilities",development.execute(world,"promote_staff",{"staff_id":"gp_doctor","queue_without_desk":true}).accepted)
	job = world.facts.training_jobs[doctor.training_job_id]
	var restored: WorldState = WorldState.new(world.freeze())
	development.ensure(restored)
	_check("save_retains_paid_promotion_work",restored.facts.training_jobs[job.id].remaining_work_milli==job.remaining_work_milli and HospitalLedger.balance(restored)==HospitalLedger.balance(world))
	job.remaining_work_milli = 0
	development.settle(world)
	_check("promotion_changes_title_at_finish",doctor.title_id=="DT02" and doctor.title_rate_changed_tick==world.sim_tick)
	_check("nurse_has_only_applicable_tracks",Development.tracks(world.facts.staff.exam_nurse)==["diagnosis","care","surgery"])
	_check("new_facts_validate",development.validate(world).is_empty())
	print(JSON.stringify({"stage":14,"failures":failures,"performance":"skipped"}))
	quit(0 if failures.is_empty() else 1)

func _check(name: String, ok: bool) -> void:
	if not ok:
		failures.append(name)
