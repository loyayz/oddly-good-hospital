extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var content: HospitalContent = HospitalContent.new()
	var fixture: Dictionary = _fixture(content)
	var world: WorldState = fixture.world
	var research: HospitalResearch = fixture.research
	_check("panel_waits_for_actual_first_consultation",not research.opened(world))
	var visit: Dictionary = world.facts.visits[world.ids("visits")[0]]
	visit.evidence_by_source.gp = 95.0
	research.record_diagnostic_work(world,visit,"gp")
	_check("clinical_work_is_published_at_settlement",not research.opened(world))
	research.settle(world)
	_check("actual_consultation_opens_research",research.opened(world))
	_check("non_case_topics_have_initial_material",world.facts.research_progress.materials.R14.kind=="initial")
	var balance: int = HospitalLedger.balance(world)
	research.execute(world,"research_todo_add",{"research_id":"R14"})
	research.execute(world,"research_todo_add",{"research_id":"R12"})
	research.execute(world,"research_todo_add",{"research_id":"R14"})
	research.execute(world,"research_todo_move",{"research_id":"R12","index":0})
	_check("ordered_plans_are_unique_and_free",world.facts.research_progress.todo==["R12","R14"] and HospitalLedger.balance(world)==balance)
	research.execute(world,"research_request_mail",{"research_id":"R01"})
	var due: int = world.facts.research_progress.mail.R01
	world.facts.sim_tick += 10
	research.execute(world,"research_request_mail",{"research_id":"R01"})
	_check("repeated_request_keeps_original_deadline",int(world.facts.research_progress.mail.R01)==due)
	world.facts.sim_tick = due
	research.boundaries(world)
	var diagnosis: Dictionary = visit.duplicate(true)
	diagnosis.disease_id = "D03"
	research.record_diagnostic_work(world,diagnosis,"spectrum")
	research.settle(world)
	_check("same_tick_diagnosis_wins_one_material_receipt",world.facts.research_progress.materials.R01.kind=="diagnosis" and not world.facts.research_progress.mail.has("R01"))
	var material_events: int = 0
	for event: SimEvent in research.take_events():
		if event.kind=="research_material_acquired" and "R01" in event.changed_ids:
			material_events += 1
	_check("same_tick_material_is_not_awarded_twice",material_events==1)
	var researcher: Dictionary = world.facts.staff.researcher
	researcher.on_shift = false
	_check("missing_worker_does_not_implicitly_charge",not research.execute(world,"research_start",{"research_id":"R14"}).accepted and HospitalLedger.balance(world)==balance)
	_check("explicit_paid_waiting_is_preserved",research.execute(world,"research_start",{"research_id":"R14","allow_waiting":true}).accepted)
	var job: Dictionary = research.active_job(world,"R14")
	var original_total: int = job.total_work_milli
	_check("one_active_job_per_topic",not research.execute(world,"research_start",{"research_id":"R14","allow_waiting":true}).accepted)
	researcher.on_shift = true
	researcher.skill = 2
	fixture.development.dispatch(world)
	research.advance(world)
	_check("actual_qualified_research_uses_staff_skill",int(job.remaining_work_milli)==original_total-1050 and int(researcher.research_practice_ticks)==1)
	world.facts.actors.researcher.location.cell = [54,87]
	research.advance(world)
	_check("old_desk_coordinates_do_not_prove_arrival",int(job.remaining_work_milli)==original_total-1050)
	research.execute(world,"research_pause",{"research_id":"R14"})
	_check("pause_releases_worker_and_desk",job.worker_id.is_empty() and job.desk_id.is_empty() and researcher.active_job_id.is_empty())
	var remaining: int = job.remaining_work_milli
	var expected_refund: int = int(job.cost)*remaining/int(job.total_work_milli)
	research.execute(world,"research_cancel",{"research_id":"R14"})
	var after_cancel: int = HospitalLedger.balance(world)
	research.execute(world,"research_cancel",{"research_id":"R14"})
	_check("frozen_refund_is_once_and_proportional",job.refund==expected_refund and HospitalLedger.balance(world)==after_cancel)
	_check("cancelled_task_does_not_unlock",not "R14" in world.facts.research)
	var restored: WorldState = WorldState.new(world.freeze())
	_check("saved_material_mail_plan_and_task_validate",research.validate(restored).is_empty())
	_fixture_release(fixture)
	_shared_desk_order(content)
	_community_and_completion(content)
	print(JSON.stringify({"stage":25,"failures":failures,"performance":"not_measured"}))
	quit(0 if failures.is_empty() else 1)

func _shared_desk_order(content: HospitalContent) -> void:
	var fixture: Dictionary = _fixture(content)
	var world: WorldState = fixture.world
	var research: HospitalResearch = fixture.research
	world.facts.research_progress.opened_tick = 0
	_check("research_queues_without_reserving_desk",research.execute(world,"research_start",{"research_id":"R14"}).accepted)
	var job: Dictionary = research.active_job(world,"R14")
	var doctor: Dictionary = world.facts.staff.gp_doctor
	doctor.scheduled_kind = "training"
	doctor.base_task = {}
	_check("training_can_queue_for_same_real_desk",fixture.development.execute(world,"train_staff",{"staff_id":"gp_doctor","track":"surgery","queue_without_desk":true}).accepted)
	fixture.development.dispatch(world)
	var course: Dictionary = world.facts.training_jobs[doctor.training_job_id]
	_check("shared_desk_follows_original_job_sequence",job.desk_id=="research_desk" and course.desk_id.is_empty())
	research.execute(world,"research_pause",{"research_id":"R14"})
	fixture.development.dispatch(world)
	_check("paused_research_releases_desk_to_training",course.desk_id=="research_desk")
	research.execute(world,"research_resume",{"research_id":"R14"})
	fixture.development.dispatch(world)
	_check("resume_does_not_preempt_existing_course",course.desk_id=="research_desk" and job.desk_id.is_empty())
	_fixture_release(fixture)

func _community_and_completion(content: HospitalContent) -> void:
	var fixture: Dictionary = _fixture(content)
	var world: WorldState = fixture.world
	var research: HospitalResearch = fixture.research
	world.facts.research_progress.opened_tick = 0
	world.facts.ledger.opening_balance = 0
	var quote: Dictionary = research.preview(world,"R14","",true)
	_check("community_preserves_zero_cost_and_double_work",quote.ok and quote.cost==0 and quote.total_work_milli==int(content.definition("research","R14").work_seconds)*20000)
	research.execute(world,"research_start",{"research_id":"R14","community":true,"allow_waiting":true,"confirmed_quote":quote.basis})
	var job: Dictionary = research.active_job(world,"R14")
	job.remaining_work_milli = 0
	research.settle(world)
	var event_count: int = research.take_events().size()
	research.settle(world)
	_check("completion_is_terminal_and_idempotent",job.state=="completed" and "R14" in world.facts.research and event_count==1 and research.take_events().is_empty())
	_check("completed_task_cannot_refund",research.execute(world,"research_cancel",{"research_id":"R14"}).accepted and HospitalLedger.balance(world)==0 and not world.facts.ledger.entries.has(job.id+":research_refund"))
	_check("terminal_facts_validate",research.validate(world).is_empty())
	for trail: Dictionary in content.catalog.research_trails:
		var expanded: Array = research.trail_research(trail.id)
		for research_id: String in expanded:
			for required: String in content.definition("research",research_id).requires:
				_check("trail_uses_original_dependency_"+trail.id+"_"+research_id+"_"+required,expanded.find(required)<expanded.find(research_id))
	_fixture_release(fixture)

func _fixture(content: HospitalContent) -> Dictionary:
	var world: WorldState = FeasibilityHospitals.create("research-rules",false,content)
	world.facts.research.erase("R12")
	var space: HospitalSpace = HospitalSpace.new(content)
	var development: HospitalClinicalDevelopment = HospitalClinicalDevelopment.new(content,space)
	var research: HospitalResearch = HospitalResearch.new(content,space)
	var recruitment: RecruitmentService = RecruitmentService.new(content,space)
	var scheduler: HospitalShiftScheduler = HospitalShiftScheduler.new(content,space)
	FeasibilityHospitals._add_staff(world,"researcher","实际研究员","researcher",[55,87],"",0,0,0,0)
	FeasibilityHospitals._add_facility(world,"research_desk","FUR05",[55,86],[2,1],[55,88],[[55,87]])
	development.ensure(world)
	scheduler.ensure(world)
	recruitment.ensure(world)
	research.ensure(world)
	development.research = research
	research.recruitment = recruitment
	research.scheduler = scheduler
	return {"world":world,"space":space,"development":development,"research":research}

func _fixture_release(fixture: Dictionary) -> void:
	fixture.development.research = null
	fixture.research.recruitment = null
	fixture.research.scheduler = null

func _check(name: String, ok: bool) -> void:
	if not ok:
		failures.append(name)
