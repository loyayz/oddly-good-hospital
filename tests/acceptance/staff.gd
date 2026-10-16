extends "res://tests/acceptance/staff_fixtures.gd"

const CASES: Dictionary = {
	"STAFF-01":"docs/design/07-clinical-team.md §1；医生与护士各三能力，五岗位单技能，资格不混用",
	"STAFF-02":"docs/design/07-clinical-team.md §3；实际完成按岗位能力归并一次，取消不成长，合格失败治疗仍成长",
	"STAFF-03":"docs/design/07-clinical-team.md §3；实践门槛20/50/100/180，保留未解锁经验且不绕过手术入门",
	"STAFF-04":"docs/design/07-clinical-team.md §3、§11；课程研究、实践和现金不足不产生部分效果",
	"STAFF-05":"docs/design/07-clinical-team.md §3、§11；课程费用、R17与人类工时及护士手术入门正确冻结",
	"STAFF-06":"docs/design/07-clinical-team.md §3、§11；真实桌位独占、实际带教工作率与课程完成唯一",
	"STAFF-07":"docs/design/07-clinical-team.md §3、§11；暂停恢复保留课程余量，取消按未完成比例只退款一次",
	"STAFF-08":"docs/design/07-clinical-team.md §3；实践掌握终结半程课程并退款，不冒充结课",
	"STAFF-09":"docs/design/07-clinical-team.md §3；同阶段真实结课优先实践，不重复升级退款",
	"STAFF-10":"docs/design/07-clinical-team.md §2；逐级评估500币120秒，新工资从完成tick累计",
	"STAFF-11":"docs/design/07-clinical-team.md §1、§11；培养目标只提示，不清实践或取消原课程",
	"STAFF-12":"docs/design/07-clinical-team.md §8.1、§13；docs/design/08-hospital-life.md §10；共享基地排序、真实排队/回岗，改建保留原整理且不返回等待腾空区域",
	"STAFF-13":"docs/design/07-clinical-team.md §9；1800秒一日与600秒三班边界一致",
	"STAFF-14":"docs/design/07-clinical-team.md §9、§10；至少一休且跨日最多连续两班，前日尾部统计保留，非法编辑原子拒绝",
	"STAFF-15":"docs/design/12-implementation-plan.md 第15阶段15.2；建议保留锁定，无关变化不拒绝，相关变化须重核",
	"STAFF-16":"docs/design/07-clinical-team.md §9；休息换班不强拆当前安全诊疗、手术或转床",
	"STAFF-17":"docs/design/07-clinical-team.md §9；欠休跨日保存，时间和能量双终点不能被改班绕过",
	"STAFF-18":"docs/design/09-consultation-wellbeing.md §5；带薪假从实际离院足额计时，取消召回不回滚恢复",
	"STAFF-19":"docs/design/09-consultation-wellbeing.md §4、§5；劳累90安全长休，55终点前不能召回接单",
	"STAFF-20":"docs/design/09-consultation-wellbeing.md §4；工作移动休息和待岗按实际速率积分，不复制护士劳累",
	"STAFF-21":"docs/design/09-consultation-wellbeing.md §4 日常短休自动错峰；真实替手、每池一位，不抢断或强召回",
	"STAFF-22":"docs/design/09-consultation-wellbeing.md §4 找到能真正使用的休息位置；真实兼容员工位与恢复总时长",
	"STAFF-23":"docs/design/09-consultation-wellbeing.md §4 七类职员都需要真正睡觉；900秒无床自愿睡眠不等床或离院",
	"STAFF-24":"docs/design/09-consultation-wellbeing.md §4 七类职员都需要真正睡觉；1350秒必须睡，缺床45秒后真实离院",
	"STAFF-25":"docs/design/09-consultation-wellbeing.md §4 七类职员都需要真正睡觉；睡25秒后移床20秒仍余425秒",
	"STAFF-26":"docs/design/09-consultation-wellbeing.md §4 七类职员都需要真正睡觉；七岗位实际450秒才清醒归零，恢复不叠加",
	"STAFF-27":"docs/design/09-consultation-wellbeing.md §6；娱乐开场才消耗次数冷却，30秒恢复有上限，双人不补搭档",
	"STAFF-28":"docs/design/09-consultation-wellbeing.md §6；合法非医生待岗可娱乐，工作覆盖与睡眠补休优先",
	"STAFF-29":"docs/design/08-hospital-life.md §17.2、§17.4；公共兼容空座优先，员工活动占用位不得被预占",
	"STAFF-30":"docs/design/08-hospital-life.md §17.4；30秒窗口、附近12秒、环境差10与性格定点选择，手选不受自动窗口限制",
	"STAFF-31":"docs/design/08-hospital-life.md §17.3；安抚椅真实连续20秒减怒3且每Visit一次，离位读档不重领",
	"STAFF-32":"docs/design/08-hospital-life.md §17.3；罩椅只减半当前噪声怒气分量，不改变环境和其他原因",
	"STAFF-33":"docs/design/08-hospital-life.md §17.3；阅览椅减压0.04与活力椅回能1.2替代普通同类速率",
	"STAFF-34":"docs/design/08-hospital-life.md §17；180秒生活需求仅真实候诊触发，临床预约优先，暂离保留票序等时",
	"STAFF-35":"docs/design/08-hospital-life.md §17.1、§17.2；8秒安全使用或兜底，45秒寻找上限，需求效果与暂离原因唯一",
	"STAFF-36":"docs/design/11-growth-arrivals-recruitment.md §6.1、§6.2、§6.4；标准候选稳定、原价录用一次、序号递增，不赠本院实践",
	"STAFF-37":"docs/design/11-growth-arrivals-recruitment.md §6.2、§6.5；资金入口失败不收费，成功从1F真实录用tick付薪",
	"STAFF-38":"docs/design/11-growth-arrivals-recruitment.md §6.1、§6.4；寻访100币120秒三身份，冻结名额与随机结果，取消不退款",
	"STAFF-39":"docs/design/11-growth-arrivals-recruitment.md §6.2、§6.4；七岗位每日简历、两日到期与关注互斥，未录用不收费",
	"STAFF-40":"docs/design/11-growth-arrivals-recruitment.md §6.5、§6.6；真实完成与研究120秒余数成长，贡献最大者唯一领取，护士不发通用等级"
}

func run(t) -> void:
	_content = HospitalContent.new()
	_recorder = t
	_cache = t.checkpoints(_content,"res://tests/acceptance/staff_fixtures.gd")
	for case_id: String in CASES:
		if not t.wants(case_id): continue
		t.begin_case(case_id)
		if not _content.error.is_empty():
			t.check(case_id,false,{"content_error":_content.error})
			continue
		await call("_case_"+case_id.right(2),t)


func _case_01(t) -> void:
	var x: Dictionary = _fixture({"doctor":"doctor","nurse":"nurse","reception":"receptionist","cleaner":"cleaner","mechanic":"mechanic","researcher":"researcher","decorator":"decorator"})
	var doctor: Dictionary = x.world.facts.staff.doctor
	var nurse: Dictionary = x.world.facts.staff.nurse
	var model_ok: bool = HospitalClinicalDevelopment.tracks(doctor)==["diagnosis","treatment","surgery"] and HospitalClinicalDevelopment.tracks(nurse)==["diagnosis","care","surgery"]
	model_ok = model_ok and doctor.abilities.diagnosis==1 and doctor.abilities.treatment==1 and doctor.abilities.surgery==0 and nurse.abilities.diagnosis==1 and nurse.abilities.care==1 and nurse.abilities.surgery==0
	for id: String in ["reception","cleaner","mechanic","researcher","decorator"]:
		model_ok = model_ok and x.world.facts.staff[id].skill==1 and x.world.facts.staff[id].has("job_practice")
	model_ok = model_ok and not nurse.certificates.has("q_gp") and not nurse.certificates.has("q_or") and not doctor.has("job_practice") and not nurse.has("job_practice")
	t.check("STAFF-01",model_ok,{"doctor":doctor,"nurse":nurse})

func _case_02(t) -> void:
	var x: Dictionary = _fixture({"doctor":"doctor","nurse":"nurse"})
	_facility(x,"diagnosis","FUR02",[42,76])
	var visit: Dictionary = _visit(x)
	var session: Dictionary = x.c._start(x.world,visit,"gp","diagnosis",["doctor"],200,{"evidence":90.0,"doctor_fee":12,"facility_fee":8})
	session.remaining_ticks = 1
	x.c.advance(x.world)
	x.c._complete_service(x.world,session)
	x.c.settle_practice(x.world)
	var examination: Dictionary = x.c._start(x.world,visit,"spectrum","diagnosis",["nurse"],200,{"evidence":15.0,"facility_fee":6})
	examination.remaining_ticks = 1
	x.c.advance(x.world)
	x.c._complete_service(x.world,examination)
	x.c.settle_practice(x.world)
	var cancelled: Dictionary = x.c._start(x.world,visit,"spectrum","diagnosis",["nurse"],200,{"evidence":15.0,"facility_fee":6})
	x.world.facts.sessions.erase(cancelled.id)
	x.c._complete_service(x.world,cancelled)
	var attempt_id: String = "completed_failed_treatment"
	x.world.facts.attempts[attempt_id] = {"id":attempt_id,"visit_id":visit.id,"plan_id":visit.requested_plan_id,"staff_ids":["doctor"],"facility_fee":12,"cure_fee":30,"recovery_ticks":0,"result":false}
	visit.attempt_ids.append(attempt_id)
	var failed: Dictionary = x.c._start(x.world,visit,"outpatient","diagnosis",["doctor"],200,{"attempt_id":attempt_id})
	failed.remaining_ticks = 1
	x.c.advance(x.world)
	x.c.settle_practice(x.world)
	x.c.settle_practice(x.world)
	var doctor: Dictionary = x.world.facts.staff.doctor
	var nurse: Dictionary = x.world.facts.staff.nurse
	t.check("STAFF-02",doctor.practice.diagnosis==1 and doctor.practice.treatment==1 and nurse.practice.diagnosis==1 and nurse.practice.care==0 and nurse.completed_jobs.size()==1 and doctor.completed_jobs.size()==2,{"doctor_practice":doctor.practice,"nurse_practice":nurse.practice})

func _case_03(t) -> void:
	var x: Dictionary = _fixture({"doctor":"doctor"})
	var doctor: Dictionary = x.world.facts.staff.doctor
	doctor.practice.treatment = 20
	doctor.practice.surgery = 180
	x.d.settle(x.world)
	var thresholds_ok: bool = doctor.abilities.treatment==1 and doctor.practice.treatment==20 and doctor.abilities.surgery==0
	x.world.facts.research.append("R11")
	for boundary: Array in [[20,2],[50,3],[100,4],[180,5]]:
		doctor.practice.treatment = boundary[0]
		x.d.settle(x.world)
		x.d.settle(x.world)
		thresholds_ok = thresholds_ok and doctor.abilities.treatment==boundary[1] and doctor.practice.treatment==boundary[0]
	x.c._practice(x.world,"doctor","treatment","cap_work")
	x.c.settle_practice(x.world)
	thresholds_ok = thresholds_ok and doctor.practice.treatment==180 and doctor.title_id=="DT01" and doctor.abilities.surgery==0 and doctor.completed_courses.is_empty()
	t.check("STAFF-03",thresholds_ok,{"abilities":doctor.abilities,"practice":doctor.practice})

func _case_04(t) -> void:
	var x: Dictionary = _training_fixture()
	x.world.facts.research.clear()
	var cash_before: int = HospitalLedger.balance(x.world)
	var gate_ok: bool = not x.d.execute(x.world,"train_staff",{"staff_id":"doctor","track":"treatment","desk_id":"desk"}).accepted
	gate_ok = gate_ok and not x.d.execute(x.world,"train_staff",{"staff_id":"nurse","track":"surgery","desk_id":"desk"}).accepted
	x.world.facts.research = ["R11","R34"]
	x.world.facts.staff.doctor.abilities.treatment = 2
	gate_ok = gate_ok and not x.d.execute(x.world,"train_staff",{"staff_id":"doctor","track":"treatment","desk_id":"desk"}).accepted
	gate_ok = gate_ok and HospitalLedger.balance(x.world)==cash_before and x.world.facts.training_jobs.is_empty()
	x.world.facts.staff.doctor.abilities.treatment = 1
	_cash(x,399)
	gate_ok = gate_ok and not x.d.execute(x.world,"train_staff",{"staff_id":"doctor","track":"treatment","desk_id":"desk"}).accepted and HospitalLedger.balance(x.world)==399 and x.world.facts.training_jobs.is_empty()
	t.check("STAFF-04",gate_ok,{"cash":HospitalLedger.balance(x.world),"jobs":x.world.facts.training_jobs})

func _case_05(t) -> void:
	var x: Dictionary = _training_fixture()
	var normal: Dictionary = x.d.preview(x.world,"doctor","treatment")
	var nurse_entry: Dictionary = x.d.preview(x.world,"nurse","surgery")
	var job: Dictionary = _enroll(x)
	x.world.facts.research.append("R17")
	var discounted: Dictionary = x.d.preview(x.world,"nurse","care")
	var quote_ok: bool = normal.ok and normal.cost==400 and normal.work_ticks==1080 and nurse_entry.ok and nurse_entry.cost==200 and nurse_entry.work_ticks==1080 and discounted.ok and discounted.cost==200 and discounted.work_ticks==540
	quote_ok = quote_ok and not job.is_empty() and job.cost==400 and job.total_work_milli==1080000 and HospitalLedger.balance(x.world)==24400
	t.check("STAFF-05",quote_ok,{"normal":normal,"nurse_entry":nurse_entry,"discounted":discounted,"frozen":job})

func _case_06(t) -> void:
	var x: Dictionary = _training_fixture()
	var job: Dictionary = _enroll(x)
	var busy: CommandResult = x.d.execute(x.world,"train_staff",{"staff_id":"doctor","track":"diagnosis","desk_id":"desk"})
	var second: Dictionary = _enroll(x,"nurse","care")
	x.d.dispatch(x.world)
	var desk_ok: bool = not busy.accepted and not job.is_empty() and not second.is_empty() and job.state=="working" and second.desk_id.is_empty()
	_training_ticks(x,1080)
	x.d.settle(x.world)
	var trained: Dictionary = x.world.facts.staff.doctor
	desk_ok = desk_ok and job.state=="completed" and trained.abilities.treatment==2 and trained.completed_courses.size()==1 and trained.growth_history.size()==1 and HospitalLedger.balance(x.world)==24000
	var mentor_fixture: Dictionary = _training_fixture()
	HospitalFactory._add_staff(mentor_fixture.world,"mentor","导师","doctor",[52,80],_content)
	for service: String in ["d","s","w","r","f"]:
		mentor_fixture[service].ensure(mentor_fixture.world)
	var mentor: Dictionary = mentor_fixture.world.facts.staff.mentor
	mentor.title_id = "DT03"
	mentor.abilities.treatment = 3
	mentor.scheduled_kind = "training"
	var taught: Dictionary = _enroll(mentor_fixture,"doctor","treatment","mentor")
	mentor_fixture.d.dispatch(mentor_fixture.world)
	var before_solo: int = int(taught.get("remaining_work_milli",0))
	mentor_fixture.d.advance(mentor_fixture.world)
	var solo_delta: int = before_solo-int(taught.get("remaining_work_milli",0))
	var desk_layout: Dictionary = mentor_fixture.space.facility_layout(mentor_fixture.world,"desk")
	var teacher_cell: Array = [int(desk_layout.operator_cells[0][0])+1,int(desk_layout.operator_cells[0][1])]
	for _tick: int in 200:
		if mentor_fixture.space.at(mentor_fixture.world,"mentor",1,teacher_cell):
			break
		mentor_fixture.world.facts.sim_tick += 1
		mentor_fixture.space.advance(mentor_fixture.world)
		mentor_fixture.d.advance(mentor_fixture.world)
	var teacher_at_desk: bool = mentor_fixture.space.at(mentor_fixture.world,"mentor",1,teacher_cell)
	mentor_fixture.d.dispatch(mentor_fixture.world)
	var before_joint: int = int(taught.get("remaining_work_milli",0))
	mentor_fixture.d.advance(mentor_fixture.world)
	var joint_delta: int = before_joint-int(taught.get("remaining_work_milli",0))
	mentor.on_shift = false
	var before_absent: int = int(taught.get("remaining_work_milli",0))
	mentor_fixture.d.advance(mentor_fixture.world)
	var absent_delta: int = before_absent-int(taught.get("remaining_work_milli",0))
	desk_ok = desk_ok and teacher_at_desk and solo_delta==1000 and joint_delta==1250 and absent_delta==1000 and taught.get("total_work_milli",0)==1080000
	t.check("STAFF-06",desk_ok,{"course":job,"second_course":second,"completed":trained.completed_courses,"teacher_at_desk":teacher_at_desk,"solo_work":solo_delta,"joint_work":joint_delta,"absent_work":absent_delta})

func _case_07(t) -> void:
	var x: Dictionary = _training_checkpoint(540)
	var job: Dictionary = x.world.facts.training_jobs[x.world.facts.staff.doctor.training_job_id]
	var saved_id: String = str(job.get("id",""))
	var remaining: int = int(job.get("remaining_work_milli",-1))
	x.d.suspend_facility(x.world,"desk","移动研究桌")
	_training_ticks(x,1)
	x = _restore(x)
	job = x.world.facts.training_jobs.get(saved_id,{})
	var frozen_remaining: int = int(job.get("remaining_work_milli",-1))
	var cancel: CommandResult = x.d.execute(x.world,"cancel_training",{"staff_id":"doctor"})
	var balance_after: int = HospitalLedger.balance(x.world)
	var again: CommandResult = x.d.execute(x.world,"cancel_training",{"staff_id":"doctor"})
	t.check("STAFF-07",remaining==540000 and frozen_remaining==remaining and cancel.accepted and not again.accepted and job.get("refund",-1)==200 and job.state=="cancelled" and HospitalLedger.balance(x.world)==balance_after and balance_after==24600 and x.world.facts.staff.doctor.abilities.treatment==1 and x.d.validate(x.world).is_empty(),{"remaining":frozen_remaining,"job":job,"cash":balance_after})

func _case_08(t) -> void:
	var x: Dictionary = _training_checkpoint(540)
	var job: Dictionary = x.world.facts.training_jobs[x.world.facts.staff.doctor.training_job_id]
	x.world.facts.staff.doctor.practice.treatment = 20
	x.d.settle(x.world)
	var saved_id: String = job.id
	x = _restore(x)
	x.d.settle(x.world)
	job = x.world.facts.training_jobs[saved_id]
	var doctor: Dictionary = x.world.facts.staff.doctor
	t.check("STAFF-08",doctor.abilities.treatment==2 and job.state=="superseded" and job.refund==200 and doctor.completed_courses.is_empty() and doctor.training_job_id.is_empty() and HospitalLedger.balance(x.world)==24600 and doctor.growth_history.size()==1 and doctor.growth_history[0].source=="practice",{"job":job,"history":doctor.growth_history})

func _case_09(t) -> void:
	var x: Dictionary = _training_checkpoint(1079)
	var job: Dictionary = x.world.facts.training_jobs[x.world.facts.staff.doctor.training_job_id]
	x.world.facts.staff.doctor.practice.treatment = 20
	_training_ticks(x,1)
	x.d.settle(x.world)
	var doctor: Dictionary = x.world.facts.staff.doctor
	t.check("STAFF-09",job.state=="completed" and job.refund==0 and doctor.abilities.treatment==2 and doctor.completed_courses.size()==1 and doctor.growth_history.size()==1 and HospitalLedger.balance(x.world)==24400,{"job":job,"history":doctor.growth_history})

func _case_10(t) -> void:
	var x: Dictionary = _training_fixture()
	var doctor: Dictionary = x.world.facts.staff.doctor
	var premature: CommandResult = x.d.execute(x.world,"promote_staff",{"staff_id":"doctor","desk_id":"desk"})
	doctor.cured_cases = 20
	doctor.abilities.treatment = 2
	x.world.facts.research.append("R17")
	var promotion_quote: Dictionary = x.d.preview(x.world,"doctor","treatment","promotion")
	var promotion: CommandResult = x.d.execute(x.world,"promote_staff",{"staff_id":"doctor","desk_id":"desk"})
	x.d.dispatch(x.world)
	_training_ticks(x,1199)
	x.f.settle(x.world)
	var old_wages: int = int(doctor.wage_numerator)
	var old_title: String = doctor.title_id
	_training_ticks(x,1)
	x.f.settle(x.world)
	var promotion_ok: bool = not premature.accepted and promotion.accepted and promotion_quote.cost==500 and promotion_quote.work_ticks==1200 and old_title=="DT01" and doctor.title_id=="DT02" and doctor.title_rate_changed_tick==x.world.sim_tick and int(doctor.wage_numerator)-old_wages==180 and x.f.wage(doctor)==180
	t.check("STAFF-10",promotion_ok,{"quote":promotion_quote,"title":doctor.title_id,"rate_tick":doctor.title_rate_changed_tick,"wage_delta":int(doctor.wage_numerator)-old_wages})

func _case_11(t) -> void:
	var x: Dictionary = _training_fixture()
	var job: Dictionary = _enroll(x)
	var doctor: Dictionary = x.world.facts.staff.doctor
	doctor.practice.diagnosis = 7
	var cash_before: int = HospitalLedger.balance(x.world)
	var changed: CommandResult = x.d.execute(x.world,"set_growth_direction",{"staff_id":"doctor","track":"diagnosis"})
	var invalid_goal: CommandResult = x.d.execute(x.world,"set_growth_direction",{"staff_id":"nurse","track":"treatment"})
	var nurse_promotion: Dictionary = x.d.preview(x.world,"nurse","care","promotion")
	t.check("STAFF-11",changed.accepted and not invalid_goal.accepted and not nurse_promotion.ok and doctor.growth_direction=="diagnosis" and doctor.practice.diagnosis==7 and doctor.training_job_id==job.id and job.track=="treatment" and job.state=="waiting" and HospitalLedger.balance(x.world)==cash_before and job.desk_id.is_empty(),{"goal":doctor.growth_goal,"course":job})

func _case_12(t) -> void:
	var x: Dictionary = _fixture({"doctor":"doctor"})
	var office: String = _room(x,"doctor_office")
	_facility(x,"base","SE05",[43,74],office)
	_position(x,"doctor",x.space.facility_layout(x.world,"base").operator_cells[0])
	x.d.dispatch(x.world)
	_training_ticks(x,30)
	x = _restore(x)
	var doctor: Dictionary = x.world.facts.staff.doctor
	var half_base: bool = not doctor.base_prepared and doctor.base_task.remaining_ticks==30
	_training_ticks(x,30)
	x.d.dispatch(x.world)
	var once: bool = doctor.base_prepared and doctor.base_task.is_empty()
	doctor.on_shift = false
	x.d.dispatch(x.world)
	doctor.on_shift = true
	x.d.dispatch(x.world)
	var new_block: bool = not doctor.base_prepared and doctor.base_task.get("remaining_ticks",-1)==60
	var shared: Dictionary = _fixture({"anesthetist":"doctor","doctor":"doctor"})
	HospitalFactory._add_room(shared.world,{"id":"shared_office","type":"doctor_office","anchor":[36,79],"size":[4,4],"door":{"definition_id":"DR01","offset":1}},_content)
	_facility(shared,"shared_base","SE05",[36,80],"shared_office")
	var shared_base: Dictionary = shared.space.facility_layout(shared.world,"shared_base")
	_position(shared,"anesthetist",shared_base.operator_cells[0])
	_position(shared,"doctor",[37,84])
	shared.world.facts.staff.anesthetist.scheduled_kind = "surgery"
	shared.d.dispatch(shared.world)
	_training_ticks(shared,60)
	var first_prepared: bool = shared.world.facts.staff.anesthetist.base_prepared and shared.world.facts.staff.anesthetist.base_task.is_empty()
	shared.d.dispatch(shared.world)
	var second_waits: bool = shared.world.facts.staff.doctor.base_task.get("phase","")=="travel" and shared.world.facts.staff.doctor.base_task.get("remaining_ticks",-1)==60
	var before_yield: Dictionary = shared.world.facts.actors.anesthetist.location.duplicate(true)
	shared.d.dispatch(shared.world)
	var requested_without_teleport: bool = shared.world.facts.moves.has("anesthetist") and shared.world.facts.actors.anesthetist.location==before_yield
	var travel_preserves_work: bool = true
	var first_keeps_preparation: bool = true
	var second_arrived: bool = false
	for _tick: int in 60:
		shared.d.dispatch(shared.world)
		first_keeps_preparation = first_keeps_preparation and shared.world.facts.staff.anesthetist.base_prepared and shared.world.facts.staff.anesthetist.base_task.is_empty()
		if shared.world.facts.staff.doctor.base_task.get("phase","")=="working":
			second_arrived = shared.space.at(shared.world,"doctor",int(shared_base.floor_id),shared_base.operator_cells[0])
			break
		shared.world.facts.sim_tick += 1
		shared.space.advance(shared.world)
		shared.d.advance(shared.world)
		shared.d.settle(shared.world)
		travel_preserves_work = travel_preserves_work and shared.world.facts.staff.doctor.base_task.get("remaining_ticks",-1)==60
	var actually_yielded: bool = shared.world.facts.actors.anesthetist.location!=before_yield and not shared.space.at(shared.world,"anesthetist",int(shared_base.floor_id),shared_base.operator_cells[0])
	_training_ticks(shared,30)
	shared = _restore(shared)
	var shared_half: bool = not shared.world.facts.staff.doctor.base_prepared and shared.world.facts.staff.doctor.base_task.get("remaining_ticks",-1)==30 and shared.world.facts.staff.anesthetist.base_prepared
	shared.d.dispatch(shared.world)
	_training_ticks(shared,30)
	shared.d.dispatch(shared.world)
	var shared_complete: bool = shared.world.facts.staff.doctor.base_prepared and shared.world.facts.staff.doctor.base_task.is_empty() and shared.world.facts.staff.anesthetist.base_prepared and shared.world.facts.staff.anesthetist.base_task.is_empty()
	var ward_case: Dictionary = _fixture({"nurse":"nurse"})
	ward_case.world.facts.research = ["R33"]
	HospitalFactory._add_room(ward_case.world,{"id":"assigned_ward","type":"ward","anchor":[36,68],"size":[8,8],"door":{"definition_id":"DR01","offset":1}},_content)
	_facility(ward_case,"ward_bed","EQ05",[39,69],"assigned_ward")
	_facility(ward_case,"external_workbench","SE06",[36,78])
	_position(ward_case,"nurse",[36,75])
	var ward_assignment: CommandResult = ward_case.c.execute(ward_case.world,"clinical_assign_ward",{"staff_id":"nurse","ward_id":"assigned_ward"})
	ward_case.world.facts.sim_tick += 1
	ward_case.space.advance(ward_case.world)
	var reached_workbench: bool = false
	for _tick: int in 60:
		ward_case.d.dispatch(ward_case.world)
		ward_case.c.dispatch(ward_case.world)
		if ward_case.world.facts.staff.nurse.base_task.get("phase","")=="working":
			reached_workbench = ward_case.space.at(ward_case.world,"nurse",1,ward_case.space.facility_layout(ward_case.world,"external_workbench").operator_cells[0])
			break
		ward_case.world.facts.sim_tick += 1
		ward_case.space.advance(ward_case.world)
		ward_case.d.advance(ward_case.world)
		ward_case.d.settle(ward_case.world)
	_training_ticks(ward_case,60)
	var coverage_probe: Dictionary = {"nurse_id":"nurse","bed_id":"ward_bed"}
	var before_return: Dictionary = ward_case.world.facts.actors.nurse.location.duplicate(true)
	var prepared_outside: bool = ward_case.world.facts.staff.nurse.base_prepared and not ward_case.c._ward_covering(ward_case.world,coverage_probe)
	ward_case.c.dispatch(ward_case.world)
	var return_requested: bool = ward_case.world.facts.moves.has("nurse") and ward_case.world.facts.actors.nurse.location==before_return
	var existing_return: Dictionary = ward_case.world.facts.moves.get("nurse",{}).duplicate(true)
	ward_case.c.dispatch(ward_case.world)
	var preserves_move: bool = ward_case.world.facts.moves.get("nurse",{})==existing_return
	var ward_rect: Rect2 = Rect2(36,68,8,8)
	var outside_has_no_coverage: bool = true
	var keeps_preparation: bool = true
	var outside_steps: int = 0
	for _tick: int in 60:
		ward_case.world.facts.sim_tick += 1
		ward_case.d.dispatch(ward_case.world)
		ward_case.c.dispatch(ward_case.world)
		ward_case.space.advance(ward_case.world)
		ward_case.d.advance(ward_case.world)
		ward_case.d.settle(ward_case.world)
		var location: Dictionary = ward_case.world.facts.actors.nurse.location
		if not ward_rect.has_point(Vector2(float(location.cell[0]),float(location.cell[1]))):
			outside_steps += 1
			outside_has_no_coverage = outside_has_no_coverage and not ward_case.c._ward_covering(ward_case.world,coverage_probe)
		keeps_preparation = keeps_preparation and ward_case.world.facts.staff.nurse.base_prepared and ward_case.world.facts.staff.nurse.base_task.is_empty()
		if not ward_case.world.facts.moves.has("nurse"):
			break
	var returned_to_cover: bool = ward_case.world.facts.actors.nurse.location!=before_return and ward_case.world.facts.staff.nurse.ward_id=="assigned_ward" and ward_case.c._ward_covering(ward_case.world,coverage_probe)
	var ward_return_ok: bool = ward_assignment.accepted and reached_workbench and prepared_outside and return_requested and preserves_move and outside_steps>0 and outside_has_no_coverage and keeps_preparation and returned_to_cover
	var base_selection: Dictionary = _base_selection_examples()
	var base_arrangement: Dictionary = _base_arrangement_examples()
	t.check("STAFF-12",half_base and once and new_block and first_prepared and second_waits and requested_without_teleport and travel_preserves_work and first_keeps_preparation and second_arrived and actually_yielded and shared_half and shared_complete and ward_return_ok and base_selection.ok and base_arrangement.ok,{"base_task":doctor.base_task,"prepared":doctor.base_prepared,"shared":{"first_prepared":first_prepared,"second_waits":second_waits,"move_without_teleport":requested_without_teleport,"travel_preserves_work":travel_preserves_work,"first_keeps_preparation":first_keeps_preparation,"second_arrived":second_arrived,"actually_yielded":actually_yielded,"restored_half":shared_half,"both_prepared":shared_complete},"ward_return":{"assignment":ward_assignment.code,"external_workbench":reached_workbench,"prepared_outside":prepared_outside,"requested_without_teleport":return_requested,"preserves_move":preserves_move,"outside_steps":outside_steps,"outside_has_no_coverage":outside_has_no_coverage,"keeps_preparation":keeps_preparation,"returned_to_cover":returned_to_cover,"location":ward_case.world.facts.actors.nurse.location},"base_selection":base_selection,"base_arrangement":base_arrangement})

func _case_13(t) -> void:
	var x: Dictionary = _fixture({"doctor":"doctor"})
	var clock_ok: bool = true
	for item: Array in [[0,0],[5999,0],[6000,1],[11999,1],[12000,2],[17999,2],[18000,0]]:
		x.world.facts.sim_tick = item[0]
		x.s.boundaries(x.world)
		clock_ok = clock_ok and x.s.shift_index(x.world)==item[1] and int(x.world.facts.staff_schedule.day)==int(item[0])/18000
	t.check("STAFF-13",clock_ok,{"tick":x.world.sim_tick,"shift":x.s.shift_index(x.world)})

func _case_14(t) -> void:
	var x: Dictionary = _fixture({"doctor":"doctor"})
	var original: Array = x.world.facts.staff.doctor.schedule.duplicate(true)
	var no_rest: CommandResult = x.s.execute(x.world,"apply_schedule",{"changes":[{"staff_id":"doctor","schedule":_schedule(["outpatient","outpatient","outpatient"])}]})
	var atomic: bool = not no_rest.accepted and x.world.facts.staff.doctor.schedule==original
	# Today's late override plus tomorrow's proposed early and middle is a real
	# three-shift chain even though the new cyclic template has a late rest.
	x.world.facts.sim_tick = 12000
	x.world.facts.staff.doctor.schedule_overrides["1"] = {"kind":"rest","pools":[],"locked":false}
	x.world.facts.staff.doctor.schedule_overrides["2"] = {"kind":"outpatient","pools":[],"locked":false}
	var across_day: CommandResult = x.s.execute(x.world,"apply_schedule",{"changes":[{"staff_id":"doctor","schedule":_schedule(["outpatient","outpatient","rest"])}]})
	atomic = atomic and not across_day.accepted and x.world.facts.staff.doctor.schedule==original
	x.world.facts.staff.doctor.schedule_overrides.erase("2")
	var legal: Array = _schedule(["outpatient","rest","outpatient"])
	var applied: CommandResult = x.s.execute(x.world,"apply_schedule",{"changes":[{"staff_id":"doctor","schedule":legal}]})
	x = _restore(x)
	var previous_day_ok: bool = true
	var previous_day_results: Array = []
	for boundaries_first: bool in [false,true]:
		var rollover: Dictionary = _fixture({"doctor":"doctor","colleague":"doctor"})
		for member: Dictionary in rollover.world.facts.staff.values():
			member.schedule = _schedule(["rest","outpatient","outpatient"])
		rollover.world.facts.sim_tick = 17999
		rollover.s.boundaries(rollover.world)
		rollover.world.facts.sim_tick = 18000
		if boundaries_first:
			rollover.s.boundaries(rollover.world)
		var before_preview: Dictionary = rollover.world.freeze()
		var rollover_preview: Dictionary = rollover.s.suggestion(rollover.world)
		var preview_readonly: bool = rollover.world.freeze()==before_preview
		var quoted_tail: int = int(rollover_preview.basis.doctor.get("previous_day_work_tail",-1))
		var before_rejection: Dictionary = rollover.world.freeze()
		# The first employee's edit is legal. A later invalid edit must not
		# roll either employee's day or partially apply the valid first change.
		var rollover_rejected: CommandResult = rollover.s.execute(rollover.world,"apply_schedule",{"basis":rollover_preview.basis,"changes":[
			{"staff_id":"colleague","schedule":_schedule(["rest","rest","outpatient"])},
			{"staff_id":"doctor","schedule":_schedule(["outpatient","outpatient","rest"])}]})
		var unchanged: bool = rollover.world.freeze()==before_rejection
		var legal_rollover: Array = _schedule(["rest","outpatient","rest"])
		var rollover_accepted: CommandResult = rollover.s.execute(rollover.world,"apply_schedule",{"basis":rollover_preview.basis,"changes":[{"staff_id":"doctor","schedule":legal_rollover}]})
		var continued: Dictionary = _restore(rollover)
		var preserved_tail: bool = continued.world.facts.staff.doctor.previous_day_work_tail==2 and continued.world.facts.staff.doctor.schedule_day==1 and continued.world.facts.staff.doctor.schedule==legal_rollover and continued.s.validate(continued.world).is_empty()
		previous_day_ok = previous_day_ok and preview_readonly and quoted_tail==2 and not rollover_rejected.accepted and rollover_rejected.code=="invalid_schedule" and unchanged and rollover_accepted.accepted and preserved_tail
		previous_day_results.append({"boundaries_first":boundaries_first,"preview_readonly":preview_readonly,"quoted_tail":quoted_tail,"rejected":rollover_rejected.code,"unchanged":unchanged,"legal_edit":rollover_accepted.code,"saved_tail":preserved_tail})
	var legacy_fixture: Dictionary = _training_fixture()
	legacy_fixture.world.facts.staff.doctor.schedule[0].kind = "training"
	var legacy_course: Dictionary = _enroll(legacy_fixture)
	legacy_fixture.d.dispatch(legacy_fixture.world)
	var legacy_dto: Dictionary = legacy_fixture.world.freeze()
	for member: Dictionary in legacy_dto.staff.values():
		member.erase("previous_day_work_tail")
	var legacy_world: WorldState = WorldState.new(legacy_dto)
	var before_legacy_validation: Dictionary = legacy_world.freeze()
	var legacy_error: String = legacy_world.validate(_content)
	var legacy_readonly: bool = legacy_world.freeze()==before_legacy_validation
	var legacy_space: HospitalSpace = HospitalSpace.new(_content)
	var legacy_scheduler: HospitalShiftScheduler = HospitalShiftScheduler.new(_content,legacy_space)
	legacy_scheduler.ensure(legacy_world)
	var expected_defaults: Dictionary = before_legacy_validation.duplicate(true)
	for member: Dictionary in expected_defaults.staff.values():
		member.previous_day_work_tail = 0
	var default_only: bool = legacy_world.freeze()==expected_defaults
	legacy_scheduler.boundaries(legacy_world)
	var legacy_development: HospitalClinicalDevelopment = HospitalClinicalDevelopment.new(_content,legacy_space)
	var legacy_remaining: int = int(legacy_world.facts.training_jobs[legacy_course.id].remaining_work_milli)
	legacy_world.facts.sim_tick += 1
	legacy_development.advance(legacy_world)
	var legacy_continues: bool = legacy_world.facts.staff.doctor.on_shift and legacy_world.facts.training_jobs[legacy_course.id].remaining_work_milli==legacy_remaining-1000
	var legacy_ok: bool = legacy_error.is_empty() and legacy_readonly and default_only and legacy_continues
	t.check("STAFF-14",atomic and applied.accepted and x.world.facts.staff.doctor.schedule==legal and x.s.validate(x.world).is_empty() and previous_day_ok and legacy_ok,{"no_rest":no_rest.code,"across_day":across_day.code,"schedule":x.world.facts.staff.doctor.schedule,"previous_day":previous_day_results,"legacy":{"validation_error":legacy_error,"validation_readonly":legacy_readonly,"default_only":default_only,"continues":legacy_continues}})

func _case_15(t) -> void:
	var x: Dictionary = _fixture({"doctor":"doctor"})
	var locked: CommandResult = x.s.execute(x.world,"set_schedule_lock",{"staff_id":"doctor","shift":0,"locked":true})
	var locked_value: Dictionary = x.world.facts.staff.doctor.schedule[0].duplicate(true)
	var proposal: Dictionary = x.s.suggestion(x.world)
	var lock_ok: bool = locked.accepted
	for change: Dictionary in proposal.changes:
		lock_ok = lock_ok and change.schedule[0]==locked_value
	x.world.facts.display_name = "无关医院名称变更"
	var accepted: CommandResult = x.s.execute(x.world,"apply_schedule",proposal)
	var after: Array = x.world.facts.staff.doctor.schedule.duplicate(true)
	var cash: int = HospitalLedger.balance(x.world)
	x.s.execute(x.world,"apply_schedule",proposal)
	var duplicate_safe: bool = x.world.facts.staff.doctor.schedule==after and HospitalLedger.balance(x.world)==cash
	var stale: Dictionary = x.s.suggestion(x.world)
	x.world.facts.staff.doctor.abilities.diagnosis = 2
	var stale_result: CommandResult = x.s.execute(x.world,"apply_schedule",stale)
	t.check("STAFF-15",lock_ok and accepted.accepted and duplicate_safe and not stale_result.accepted and stale_result.code=="material_change" and x.world.facts.staff.doctor.schedule==after,{"proposal":proposal,"applied":accepted.code,"stale":stale_result.code})

func _case_16(t) -> void:
	var x: Dictionary = _fixture({"doctor":"doctor","anesthetist":"doctor","nurse":"nurse"})
	_facility(x,"diagnosis","FUR02",[43,75])
	var visit: Dictionary = _visit(x)
	var current: Dictionary = x.c._start(x.world,visit,"gp","diagnosis",["doctor"],200,{"evidence":90.0,"doctor_fee":12,"facility_fee":8})
	current.remaining_ticks = 2
	var remaining: int = current.remaining_ticks
	var rest: CommandResult = x.s.execute(x.world,"apply_schedule",{"changes":[{"staff_id":"doctor","schedule":_schedule(["rest","outpatient","outpatient"])}]})
	x.s.boundaries(x.world)
	var safety_ok: bool = rest.accepted and x.world.facts.sessions.has(current.id) and current.remaining_ticks==remaining and x.world.facts.staff.doctor.on_shift and x.world.facts.staff.doctor.block_new_work
	x.world.facts.sim_tick += 1
	x.c.advance(x.world)
	x.world.facts.sim_tick += 1
	x.c.advance(x.world)
	x.s.boundaries(x.world)
	safety_ok = safety_ok and not x.world.facts.sessions.has(current.id) and not x.world.facts.staff.doctor.on_shift
	# A prepared full surgery team remains indivisible while its safe session exists.
	var operation: Dictionary = x.c._start(x.world,visit,"surgery","diagnosis",["doctor","anesthetist","nurse"],100,{"attempt_id":"committed_operation"})
	var team: Array = operation.staff_ids.duplicate()
	for id: String in team:
		x.world.facts.staff[id].schedule = _schedule(["rest","work","work"])
	x.s.boundaries(x.world)
	safety_ok = safety_ok and operation.staff_ids==team and operation.remaining_ticks==100 and x.world.facts.sessions.has(operation.id)
	x.world.facts.sessions.erase(operation.id)
	x.world.facts.ward_stays["transfer"] = {"phase":"transfer","escort_id":"nurse"}
	x.s.boundaries(x.world)
	safety_ok = safety_ok and HospitalClinicalDevelopment.safe_busy(x.world,"nurse") and x.world.facts.staff.nurse.block_new_work
	t.check("STAFF-16",safety_ok,{"team":operation.staff_ids,"current_service_completed":not x.world.facts.sessions.has(current.id),"nurse_blocked":x.world.facts.staff.nurse.block_new_work})

func _case_17(t) -> void:
	var x: Dictionary = _fixture({"doctor":"doctor"})
	var room: String = _room(x)
	_facility(x,"rest_chair","FUR06",[43,75],room)
	_position(x,"doctor",x.space.facility_layout(x.world,"rest_chair").patient_cell)
	x.world.facts.staff.doctor.schedule = _schedule(["rest","outpatient","outpatient"])
	x.world.facts.staff.doctor.active_job_id = "already_committed_safe_work"
	x.s.boundaries(x.world)
	x.world.facts.sim_tick += 1
	x.s.boundaries(x.world)
	var debt: int = x.world.facts.staff.doctor.rest_debt_ticks
	x.world.facts.staff.doctor.erase("active_job_id")
	x.s.execute(x.world,"apply_schedule",{"changes":[{"staff_id":"doctor","schedule":_schedule(["outpatient","rest","outpatient"])}]})
	x.world.facts.staff.doctor.energy = 89.0
	x.w._begin(x.world,"doctor","rest")
	x.w.dispatch(x.world)
	x.world.facts.staff.doctor.energy = 90.0
	_life_ticks(x,1)
	var time_not_energy: bool = x.world.facts.staff.doctor.rest_debt_ticks==debt-1 and x.world.facts.staff.doctor.life_task.phase=="rest"
	x = _restore(x)
	_life_ticks(x,1)
	t.check("STAFF-17",debt==2 and time_not_energy and x.world.facts.staff.doctor.rest_debt_ticks==0 and x.world.facts.staff.doctor.energy>=90.0 and x.world.facts.staff.doctor.life_task.phase=="returning",{"original_debt":debt,"staff":x.world.facts.staff.doctor})

func _case_18(t) -> void:
	var x: Dictionary = _fixture({"doctor":"doctor"})
	_facility(x,"diagnosis","FUR02",[43,75])
	var visit: Dictionary = _visit(x)
	var current: Dictionary = x.c._start(x.world,visit,"gp","diagnosis",["doctor"],200,{"evidence":90.0,"doctor_fee":12,"facility_fee":8})
	current.remaining_ticks = 2
	var requested_tick: int = x.world.sim_tick
	var leave: CommandResult = x.s.execute(x.world,"plan_leave",{"staff_id":"doctor","days":1,"start":"now"})
	x.w.dispatch(x.world)
	var waits_safe: bool = x.world.facts.staff.doctor.life_task.phase=="wait_safe" and x.world.facts.staff.doctor.leave_plan.actual_start_tick==-1
	for _tick: int in 2:
		x.world.facts.sim_tick += 1
		x.c.advance(x.world)
	var left: bool = _reach_life_phase(x,"doctor","offsite")
	var plan: Dictionary = x.world.facts.staff.doctor.leave_plan
	var full_leave_ticks: int = int(plan.get("end_tick",-1))-int(plan.get("actual_start_tick",-1))
	var paid_before: int = x.world.facts.staff.doctor.wage_numerator
	x.world.facts.sim_tick += 1
	x.f.settle(x.world)
	_life_ticks(x,1)
	var energy_after: float = x.world.facts.staff.doctor.energy
	var recalled: CommandResult = x.s.execute(x.world,"cancel_leave",{"staff_id":"doctor"})
	var paid_delta: int = int(x.world.facts.staff.doctor.wage_numerator)-paid_before
	var leave_ok: bool = leave.accepted and waits_safe and left and full_leave_ticks==18000 and plan.actual_start_tick>requested_tick and plan.end_tick==x.world.sim_tick and recalled.accepted and x.world.facts.staff.has("doctor") and energy_after==x.world.facts.staff.doctor.energy and paid_delta==140
	var y: Dictionary = _fixture({"doctor":"doctor"})
	var original_cash: int = HospitalLedger.balance(y.world)
	y.s.execute(y.world,"plan_leave",{"staff_id":"doctor","days":1,"start":"next_day"})
	var cancelled: CommandResult = y.s.execute(y.world,"cancel_leave",{"staff_id":"doctor"})
	leave_ok = leave_ok and cancelled.accepted and y.world.facts.staff.doctor.leave_plan.is_empty() and HospitalLedger.balance(y.world)==original_cash
	t.check("STAFF-18",leave_ok,{"plan_after_recall":plan,"requested_tick":requested_tick,"left":left,"paid_delta":paid_delta})

func _case_19(t) -> void:
	var x: Dictionary = _fixture({"doctor":"doctor"})
	x.world.facts.staff.doctor.fatigue = 90.0
	x.world.facts.staff.doctor.active_job_id = "safe_current_task"
	x.s.boundaries(x.world)
	var automatic: Dictionary = x.world.facts.staff.doctor.leave_plan
	var long_rest_ok: bool = automatic.get("kind","")=="automatic" and x.world.facts.staff.doctor.block_new_work and x.world.facts.staff.doctor.on_shift
	var cannot_recall: CommandResult = x.s.execute(x.world,"cancel_leave",{"staff_id":"doctor"})
	x.s.execute(x.world,"apply_schedule",{"changes":[{"staff_id":"doctor","schedule":_schedule(["outpatient","outpatient","rest"])}]})
	x.world.facts.staff.doctor.erase("active_job_id")
	x.s.boundaries(x.world)
	long_rest_ok = long_rest_ok and not x.world.facts.staff.doctor.on_shift and not cannot_recall.accepted
	var outside: bool = _reach_life_phase(x,"doctor","offsite")
	if outside:
		# A valid checkpoint immediately before the compulsory fatigue endpoint.
		x.world.facts.staff.doctor.fatigue = 55.008
		x.world.facts.staff.doctor.life_task.offsite_ticks = 4374
		x.world.facts.sim_tick = int(x.world.facts.staff.doctor.leave_plan.actual_start_tick)+4374
		_life_ticks(x,1)
	long_rest_ok = long_rest_ok and outside and x.world.facts.staff.doctor.fatigue<=55.00001 and x.world.facts.staff.doctor.life_task.phase=="returning" and x.world.facts.staff.doctor.abilities.treatment==1 and x.world.facts.staff.doctor.cured_cases==0
	t.check("STAFF-19",long_rest_ok,{"plan":automatic,"staff":x.world.facts.staff.doctor})

func _case_20(t) -> void:
	var x: Dictionary = _fixture({"doctor":"doctor","nurse":"nurse"})
	for staff: Dictionary in x.world.facts.staff.values():
		staff.energy = 50.0
		staff.stress_milli = 50000
		staff.fatigue = 50.0 if staff.role=="doctor" else 0.0
	for _tick: int in 10:
		x.world.facts.sim_tick += 1
		x.w.advance(x.world,{"doctor":true,"nurse":true})
	var doctor: Dictionary = x.world.facts.staff.doctor
	var nurse: Dictionary = x.world.facts.staff.nurse
	var rates_ok: bool = _near(doctor.energy,49.92) and _near(doctor.fatigue,50.015) and doctor.stress_milli==50010 and _near(nurse.fatigue,0.0)
	var idle_energy: float = doctor.energy
	_life_ticks(x,10)
	rates_ok = rates_ok and _near(doctor.energy,idle_energy) and _near(doctor.fatigue,50.015) and doctor.stress_milli==50010
	var previous: Dictionary = {"doctor":x.world.facts.actors.doctor.location.duplicate(true)}
	_position(x,"doctor",[37,92])
	x.w.advance(x.world,{},previous)
	rates_ok = rates_ok and _near(doctor.energy,idle_energy-0.003) and _near(doctor.fatigue,50.015)
	var room: String = _room(x)
	_facility(x,"chair","FUR06",[43,75],room)
	_position(x,"doctor",x.space.facility_layout(x.world,"chair").patient_cell)
	doctor.energy = 35.0
	x.w.dispatch(x.world)
	x.w.dispatch(x.world)
	var rest_energy: float = doctor.energy
	var rest_stress: int = doctor.stress_milli
	var rest_fatigue: float = doctor.fatigue
	_life_ticks(x,10)
	rates_ok = rates_ok and _near(doctor.energy,rest_energy+1.0) and _near(doctor.fatigue,rest_fatigue-0.004) and doctor.stress_milli==rest_stress-15
	t.check("STAFF-20",rates_ok,{"doctor":doctor,"nurse_fatigue":nurse.fatigue})

func _case_21(t) -> void:
	var x: Dictionary = _fixture({"first":"doctor","second":"doctor","relief":"doctor"})
	_room(x)
	for staff: Dictionary in x.world.facts.staff.values():
		staff.base_prepared = true
		staff.scheduled_kind = "outpatient"
	x.world.facts.staff.first.energy = 40.0
	x.world.facts.staff.second.energy = 42.0
	_position(x,"first",[37,74])
	_position(x,"second",[42,74])
	_position(x,"relief",[48,74])
	x.w.dispatch(x.world)
	var one_early: int = 0
	for staff: Dictionary in x.world.facts.staff.values():
		if staff.life_task.get("early",false):
			one_early += 1
	var stagger_ok: bool = one_early==1 and x.world.facts.staff.first.life_task.get("early",false) and x.world.facts.staff.second.life_task.phase=="idle"
	var y: Dictionary = _fixture({"low":"doctor","travelling":"doctor"})
	_room(y)
	for staff: Dictionary in y.world.facts.staff.values():
		staff.base_prepared = true
		staff.scheduled_kind = "outpatient"
	y.world.facts.staff.low.energy = 40.0
	_position(y,"low",[38,75])
	_position(y,"travelling",[45,75])
	y.space.request_move(y.world,"travelling",1,[50,80])
	y.w.dispatch(y.world)
	stagger_ok = stagger_ok and y.world.facts.staff.low.life_task.phase=="idle"
	t.check("STAFF-21",stagger_ok,{"one_pool_count":one_early,"selected":x.world.facts.staff.first.life_task,"unavailable_relief":y.world.facts.staff.low.life_task})

func _case_22(t) -> void:
	var x: Dictionary = _fixture({"doctor":"doctor"})
	var room: String = _room(x)
	_facility(x,"ordinary","FUR06",[40,70],room)
	_facility(x,"vitality","FUR52",[50,70],room)
	_position(x,"doctor",[36,70])
	var doctor: Dictionary = x.world.facts.staff.doctor
	doctor.energy = 35.0
	x.w.dispatch(x.world)
	var selected: String = str(doctor.life_task.get("facility_id",""))
	var travel_before: float = doctor.energy
	_life_ticks(x,1)
	var no_early_recovery: bool = _near(doctor.energy,travel_before)
	_life_ticks(x,10,true)
	var travelling_energy: float = doctor.energy
	x = _restore(x)
	doctor = x.world.facts.staff.doctor
	var reservation_ok: bool = selected=="vitality" and no_early_recovery and travelling_energy<travel_before and doctor.life_task.facility_id==selected and x.world.facts.staff_life.reservations.size()==1
	var original_recovery: float = doctor.energy
	x.world.facts.facilities.erase("vitality")
	x.w.dispatch(x.world)
	reservation_ok = reservation_ok and doctor.life_task.phase=="returning" and _near(doctor.energy,original_recovery) and doctor.rest_obligation
	t.check("STAFF-22",reservation_ok,{"chosen":selected,"energy_before":travel_before,"energy_after_walk":travelling_energy,"task":doctor.life_task})

func _case_23(t) -> void:
	var roles: Dictionary = {"reception":"receptionist","doctor":"doctor","nurse":"nurse","cleaner":"cleaner","mechanic":"mechanic","researcher":"researcher","decorator":"decorator"}
	var x: Dictionary = _fixture(roles)
	var room: String = _room(x)
	for staff: Dictionary in x.world.facts.staff.values():
		staff.awake_ticks = 9000
		staff.on_shift = false
	x.w.dispatch(x.world)
	var no_bed_early: bool = true
	for staff: Dictionary in x.world.facts.staff.values():
		no_bed_early = no_bed_early and staff.life_task.phase=="idle" and staff.sleep_remaining_ticks==0 and x.world.facts.actors[staff.id].location.kind=="floor"
	t.check("STAFF-23",no_bed_early,{"roles":roles.keys(),"reservations":x.world.facts.staff_life.reservations})

func _case_24(t) -> void:
	var x: Dictionary = _fixture({"doctor":"doctor"})
	_room(x)
	_position(x,"doctor",[38,75])
	x.world.facts.staff.doctor.awake_ticks = 13500
	x.w.dispatch(x.world)
	var waiting: bool = x.world.facts.staff.doctor.life_task.phase=="wait_bed" and x.world.facts.staff.doctor.block_new_work
	_life_ticks(x,449)
	x.w.dispatch(x.world)
	waiting = waiting and x.world.facts.staff.doctor.life_task.phase=="wait_bed" and x.world.facts.staff.doctor.life_task.waited_ticks==449
	_life_ticks(x,1)
	x.w.dispatch(x.world)
	var leaving: bool = x.world.facts.staff.doctor.life_task.phase=="exiting" and x.world.facts.actors.doctor.location.kind=="floor" and x.world.facts.staff.doctor.sleep_remaining_ticks==4500
	var reached_exit: bool = _reach_life_phase(x,"doctor","offsite")
	var starts_outside: bool = reached_exit and x.world.facts.staff.doctor.life_task.offsite_ticks==0 and x.world.facts.actors.doctor.location.kind=="outside"
	var y: Dictionary = _fixture({"doctor":"doctor"})
	y.world.facts.staff.doctor.awake_ticks = 13500
	y.world.facts.floors.overrides["1"].blocked.append([48,95])
	y.w.dispatch(y.world)
	for _tick: int in 10:
		y.w.dispatch(y.world)
		_life_ticks(y,1,true)
	var no_teleport: bool = y.world.facts.actors.doctor.location.kind=="floor" and y.world.facts.staff.doctor.life_task.phase=="exiting" and y.world.facts.staff.doctor.sleep_remaining_ticks==4500
	t.check("STAFF-24",waiting and leaving and starts_outside and no_teleport,{"waited":449,"exit_reached":reached_exit,"blocked_task":y.world.facts.staff.doctor.life_task})

func _case_25(t) -> void:
	var x: Dictionary = _sleep_fixture("doctor")
	var doctor: Dictionary = x.world.facts.staff.sleeper
	var was_sleeping: bool = doctor.life_task.phase=="sleep"
	_life_ticks(x,250)
	var energy_slept: float = doctor.energy
	var interrupted: CommandResult = x.w.execute(x.world,"interrupt_staff_rest",{"staff_id":"sleeper","reason":"remodel"})
	_life_ticks(x,200,true)
	var remaining_sleep: int = doctor.sleep_remaining_ticks
	x = _restore(x)
	var restored_sleep: int = x.world.facts.staff.sleeper.sleep_remaining_ticks
	var resumed: bool = _reach_life_phase(x,"sleeper","sleep")
	doctor = x.world.facts.staff.sleeper
	t.check("STAFF-25",was_sleeping and interrupted.accepted and remaining_sleep==4250 and restored_sleep==4250 and resumed and doctor.sleep_remaining_ticks==4250 and doctor.energy<=energy_slept+0.00001 and x.world.facts.staff_life.reservations.size()==1 and x.w.validate(x.world).is_empty(),{"remaining_after_move":remaining_sleep,"remaining_after_resume":doctor.sleep_remaining_ticks,"resumed":resumed})

func _case_26(t) -> void:
	var x: Dictionary
	var sleep_ok: bool = true
	var sleep_details: Dictionary = {}
	for role: String in ["receptionist","doctor","nurse","cleaner","mechanic","researcher","decorator"]:
		x = _sleep_fixture(role)
		var sleeper: Dictionary = x.world.facts.staff.sleeper
		var entered: bool = sleeper.life_task.phase=="sleep"
		_life_ticks(x,10)
		var one_second: bool = _near(sleeper.energy,51.25) and sleeper.stress_milli==49950 and (role!="doctor" or _near(sleeper.fatigue,9.92))
		_life_ticks(x,4489)
		var not_early: bool = sleeper.sleep_remaining_ticks==1 and sleeper.life_task.phase=="sleep" and sleeper.energy==100.0
		_life_ticks(x,1)
		var completed: bool = sleeper.sleep_remaining_ticks==0 and sleeper.awake_ticks==0 and sleeper.life_task.phase=="returning"
		sleep_ok = sleep_ok and entered and one_second and not_early and completed
		sleep_details[role] = {"entered":entered,"rates":one_second,"last_tick":not_early,"completed":completed}
	var y: Dictionary = _fixture({"doctor":"doctor"})
	y.s.execute(y.world,"plan_leave",{"staff_id":"doctor","days":1,"start":"now"})
	var real_offsite: bool = _reach_life_phase(y,"doctor","offsite")
	var offsite: Dictionary = y.world.facts.staff.doctor
	if real_offsite:
		offsite.life_task.offsite_ticks = 4499
		y.world.facts.sim_tick = int(offsite.leave_plan.actual_start_tick)+4499
		offsite.awake_ticks = 7000
		offsite.energy = 20.0
		offsite.fatigue = 20.0
		offsite.stress_milli = 20000
		_life_ticks(y,1)
		sleep_ok = sleep_ok and offsite.awake_ticks==0 and offsite.sleep_remaining_ticks==0 and _near(offsite.energy,20.1) and _near(offsite.fatigue,19.992) and offsite.stress_milli==19990
		_life_ticks(y,1)
		sleep_ok = sleep_ok and offsite.awake_ticks==0
	t.check("STAFF-26",sleep_ok and real_offsite,{"roles":sleep_details,"offsite_credit":real_offsite})

func _case_27(t) -> void:
	var x: Dictionary = _fixture({"doctor":"doctor","partner":"nurse"})
	var room: String = _room(x)
	_facility(x,"game","RC03",[43,75],room)
	var game_layout: Dictionary = x.space.facility_layout(x.world,"game")
	_position(x,"doctor",game_layout.patient_cell)
	_position(x,"partner",game_layout.operator_cells[0])
	for staff: Dictionary in x.world.facts.staff.values():
		staff.energy = 60.0
		staff.fatigue = 10.0 if staff.role=="doctor" else 0.0
		staff.stress_milli = 50000
		staff.on_shift = false
	var cash_before: int = HospitalLedger.balance(x.world)
	var recreation: CommandResult = x.w.execute(x.world,"staff_recreation",{"staff_ids":["doctor","partner"],"facility_id":"game"})
	var count_before_start: bool = x.world.facts.staff.doctor.recreation_count==0 and x.world.facts.staff.partner.recreation_count==0
	x.w.dispatch(x.world)
	var started: bool = x.world.facts.staff.doctor.life_task.phase=="recreation" and x.world.facts.staff.doctor.recreation_count==1 and x.world.facts.staff.partner.recreation_count==1
	_life_ticks(x,300)
	var doctor: Dictionary = x.world.facts.staff.doctor
	var recreation_ok: bool = recreation.accepted and count_before_start and started and _near(doctor.energy,72.0) and doctor.stress_milli==45500 and _near(doctor.fatigue,9.7) and doctor.recreation_cooldown_tick==1200 and x.world.facts.staff_life.reservations.get("game",{}).get("remaining_ticks",-1)==0 and HospitalLedger.balance(x.world)==cash_before
	var y: Dictionary = _fixture({"idle":"cleaner"})
	var idle: Dictionary = y.world.facts.staff.idle
	idle.energy = 60.0
	idle.stress_milli = 50000
	idle.dispatch_idle = true
	idle.dispatch_idle_tick = y.world.sim_tick
	idle.recreation_cooldown_tick = 1200
	y.world.facts.sim_tick = 1199
	idle.dispatch_idle_tick = 1199
	var cooling: bool = not y.w._can_recreate(y.world,"idle")
	y.world.facts.sim_tick = 1200
	idle.dispatch_idle_tick = 1200
	var cooled: bool = y.w._can_recreate(y.world,"idle")
	idle.recreation_count = 3
	var capped: bool = not y.w._can_recreate(y.world,"idle")
	t.check("STAFF-27",recreation_ok and cooling and cooled and capped,{"start":started,"count_before_start":count_before_start,"doctor":doctor,"cooldown_gate":cooling,"daily_cap":capped})

func _case_28(t) -> void:
	var x: Dictionary = _fixture({"idle":"cleaner","doctor":"doctor","nurse":"nurse"})
	for staff: Dictionary in x.world.facts.staff.values():
		staff.energy = 60.0
		staff.stress_milli = 50000
		staff.dispatch_idle = true
		staff.dispatch_idle_tick = x.world.sim_tick
	var gates: bool = x.w._can_recreate(x.world,"idle") and not x.w._can_recreate(x.world,"doctor")
	x.world.facts.ward_stays["actual_coverage"] = {"nurse_id":"nurse","phase":"recovery"}
	gates = gates and not x.w._can_recreate(x.world,"nurse")
	var idle: Dictionary = x.world.facts.staff.idle
	idle.rest_debt_ticks = 1
	gates = gates and not x.w._can_recreate(x.world,"idle")
	idle.rest_debt_ticks = 0
	idle.energy = 35.0
	gates = gates and not x.w._can_recreate(x.world,"idle")
	idle.energy = 60.0
	idle.awake_ticks = 13500
	gates = gates and not x.w._can_recreate(x.world,"idle")
	idle.awake_ticks = 0
	var no_slot: CommandResult = x.w.execute(x.world,"staff_recreation",{"staff_id":"idle"})
	gates = gates and not no_slot.accepted and no_slot.code=="no_recreation_slot" and idle.life_task.phase=="idle" and not idle.rest_obligation and idle.energy==60.0
	t.check("STAFF-28",gates,{"no_slot":no_slot.code,"idle_task":idle.life_task,"rest_obligation":idle.rest_obligation})

func _case_29(t) -> void:
	var x: Dictionary = _fixture()
	HospitalFactory._add_room(x.world,{"id":"staff_corner","type":"rest","anchor":[54,82],"size":[5,5],"door":{"definition_id":"DR01","offset":2}},_content)
	HospitalFactory._add_room(x.world,{"id":"activity_corner","type":"rest","anchor":[54,70],"size":[5,5],"door":{"definition_id":"DR01","offset":2}},_content)
	x.world.facts.rooms.activity_corner.kind = "activity"
	_facility(x,"public_free","FUR06",[42,75])
	_facility(x,"public_occupied","FUR06",[46,75])
	_facility(x,"staff_seat","FUR06",[55,83],"staff_corner")
	_facility(x,"activity_seat","FUR06",[55,71],"activity_corner")
	var visit: Dictionary = _visit(x)
	var visitor_cell: Array = x.space.facility_layout(x.world,"public_occupied").patient_cell
	x.world.facts.actors.visitor = {"id":"visitor","name":"陪诊者","species_id":"S49","location":{"kind":"floor","floor_id":1,"cell":visitor_cell,"height_m":0.0},"facing":0.0,"posture":"seated","support_facility_id":"public_occupied"}
	var choices: Array = x.l.seat_candidates(x.world,visit.id)
	var legal_only: bool = choices.size()==1 and choices[0].facility_id=="public_free"
	var chosen: CommandResult = x.l.execute(x.world,"waiting_select_seat",{"visit_id":visit.id,"facility_id":"public_free"})
	var forbidden: CommandResult = x.l.execute(x.world,"waiting_select_seat",{"visit_id":visit.id,"facility_id":"staff_seat"})
	t.check("STAFF-29",legal_only and chosen.accepted and not forbidden.accepted and x.world.facts.waiting_life.seats.size()==1 and x.world.facts.waiting_life.seats[visit.id].facility_id=="public_free" and x.world.facts.actors.visitor.support_facility_id=="public_occupied",{"candidates":choices,"chosen":chosen.code,"forbidden":forbidden.code})

func _case_30(t) -> void:
	var x: Dictionary = _fixture()
	x.world.facts.floors.overrides["1"].plots.append([2,2])
	var visit: Dictionary = _visit(x,"choice",[32,70],"PP02")
	for item: Array in [["A",36],["B",48],["C",80],["D",94]]:
		_facility(x,item[0],"FUR06",[item[1],69])
		x.world.facts.facilities[item[0]].patient_cell = [item[1],70]
	# Four real nearby bodies make A crowded. None overlaps a seat's body,
	# operation area or the direct horizontal route to the candidate seats.
	for index: int in 4:
		var cell: Array = [[35,71],[36,72],[37,71],[36,73]][index]
		var id: String = "nearby_%d" % index
		x.world.facts.actors[id] = {"id":id,"name":"候诊者","species_id":"S49","location":{"kind":"floor","floor_id":1,"cell":cell,"height_m":0.0},"facing":0.0,"posture":"standing"}
	var observations: SeatObservations = SeatObservations.new()
	observations.cells = {"36:70":{"value":80.0,"noise":1.0,"clean":false,"water":false},
		"48:70":{"value":78.0,"noise":0.0,"clean":false,"water":false},
		"80:70":{"value":99.0,"noise":0.0,"clean":false,"water":false},
		"94:70":{"value":99.0,"noise":0.0,"clean":false,"water":false}}
	x.l.environment = observations
	var random_before: Dictionary = x.world.facts.rng.duplicate(true)
	var impatient: Array = x.l.seat_candidates(x.world,visit.id)
	visit.personality_id = "PP04"
	var shy: Array = x.l.seat_candidates(x.world,visit.id)
	var chosen_shy_again: Array = x.l.seat_candidates(x.world,visit.id)
	var bounded: bool = not impatient.is_empty() and not shy.is_empty() and impatient[0].facility_id=="A" and shy[0].facility_id=="B" and shy==chosen_shy_again
	for candidate: Dictionary in shy:
		bounded = bounded and candidate.facility_id in ["A","B"] and int(candidate.travel_ticks)<=300
	var manual: CommandResult = x.l.execute(x.world,"waiting_select_seat",{"visit_id":visit.id,"facility_id":"D"})
	t.check("STAFF-30",bounded and manual.accepted and x.world.facts.rng==random_before and x.world.facts.waiting_life.seats[visit.id].facility_id=="D",{"impatient":impatient,"shy":shy,"manual":manual.code})

func _case_31(t) -> void:
	var x: Dictionary = _fixture()
	_facility(x,"calm","FUR49",[42,75])
	_facility(x,"calm_again","FUR49",[47,75])
	var visit: Dictionary = _visit(x)
	var original_ticket: String = visit.ticket_id
	var waited: int = x.world.facts.tickets[original_ticket].waited_ticks
	var original_service_tick: int = visit.last_service_tick
	var seated: bool = _seat_checkpoint(x,visit,"calm")
	for _tick: int in 199:
		x.world.facts.sim_tick += 1
		x.l.advance(x.world)
	var no_early_calm: bool = visit.anger==50.0 and not visit.get("chair_calm_claimed",false)
	x.l.execute(x.world,"waiting_release_seat",{"visit_id":visit.id})
	x.space.release_adaptations(x.world)
	seated = _seat_checkpoint(x,visit,"calm") and seated
	for _tick: int in 200:
		x.world.facts.sim_tick += 1
		x.l.advance(x.world)
	var once: bool = visit.anger==47.0 and visit.get("chair_calm_claimed",false)
	x.l.execute(x.world,"waiting_release_seat",{"visit_id":visit.id})
	x.space.release_adaptations(x.world)
	seated = _seat_checkpoint(x,visit,"calm_again") and seated
	x = _restore(x)
	for _tick: int in 200:
		x.world.facts.sim_tick += 1
		x.l.advance(x.world)
	visit = x.world.facts.visits.visit
	var calm_ok: bool = seated and no_early_calm and once and visit.anger==47.0 and visit.ticket_id==original_ticket and x.world.facts.tickets[original_ticket].waited_ticks==waited and x.world.facts.staff.is_empty()
	# A chair's small mood relief is not a completed clinical service.
	calm_ok = calm_ok and visit.last_service_tick==original_service_tick
	t.check("STAFF-31",calm_ok,{"anger":visit.anger,"claimed":visit.get("chair_calm_claimed",false),"last_service_tick":visit.last_service_tick,"original_service_tick":original_service_tick})

func _case_32(t) -> void:
	var x: Dictionary
	var visit: Dictionary
	var observations: SeatObservations
	var seated: bool
	var noise_results: Dictionary = {}
	var raw_observations: Dictionary = {}
	for chair_type: String in ["FUR06","FUR50"]:
		x = _fixture()
		_facility(x,"seat",chair_type,[42,75])
		visit = _visit(x)
		seated = _seat_checkpoint(x,visit,"seat")
		observations = SeatObservations.new()
		observations.fallback = {"value":50.0,"noise":10.0,"clean":false,"water":false}
		x.l.environment = observations
		x.p.environment = observations
		x.world.facts.sim_tick = 10000
		var experience: Dictionary = x.world.facts.departments.experience[visit.id]
		experience.cause_clocks = {"construction_noise":0,"dirty":0}
		x.p._sample_anger(x.world,visit,experience)
		noise_results[chair_type] = {"seated":seated,"sources":experience.anger_sources.duplicate(true),"multiplier":x.l.noise_multiplier(x.world,visit.id)}
		raw_observations[chair_type] = observations.environment_at(x.world,1,[42,76])
	var ordinary_sources: Dictionary = noise_results.FUR06.sources
	var shield_sources: Dictionary = noise_results.FUR50.sources
	var noise_ok: bool = noise_results.FUR06.seated and noise_results.FUR50.seated and ordinary_sources.has("construction_noise") and shield_sources.has("construction_noise") and ordinary_sources.has("dirty") and shield_sources.has("dirty")
	noise_ok = noise_ok and _near(float(shield_sources.get("construction_noise",-1)),float(ordinary_sources.get("construction_noise",0))*0.5) and _near(float(shield_sources.get("dirty",-1)),float(ordinary_sources.get("dirty",0))) and raw_observations.FUR06==raw_observations.FUR50
	x.l.execute(x.world,"waiting_release_seat",{"visit_id":visit.id})
	noise_ok = noise_ok and _near(x.l.noise_multiplier(x.world,visit.id),1.0)
	t.check("STAFF-32",noise_ok,{"ordinary":noise_results.FUR06,"shield":noise_results.FUR50,"environment":raw_observations})

func _case_33(t) -> void:
	var x: Dictionary
	var chair_results: Dictionary = {}
	for chair_type: String in ["FUR06","FUR51","FUR52"]:
		x = _fixture({"doctor":"doctor"})
		var room: String = _room(x)
		_facility(x,"seat",chair_type,[43,75],room)
		_position(x,"doctor",x.space.facility_layout(x.world,"seat").patient_cell)
		var doctor: Dictionary = x.world.facts.staff.doctor
		doctor.energy = 35.0
		doctor.stress_milli = 50000
		x.w.dispatch(x.world)
		x.w.dispatch(x.world)
		_life_ticks(x,10)
		chair_results[chair_type] = {"energy":doctor.energy,"stress":doctor.stress_milli,"awake":doctor.awake_ticks,"phase":doctor.life_task.phase}
	var chair_ok: bool = _near(chair_results.FUR06.energy,36.0) and chair_results.FUR06.stress==49985 and _near(chair_results.FUR51.energy,36.0) and chair_results.FUR51.stress==49960 and _near(chair_results.FUR52.energy,36.2) and chair_results.FUR52.stress==49985
	for result: Dictionary in chair_results.values():
		chair_ok = chair_ok and result.awake==10 and result.phase=="rest"
	t.check("STAFF-33",chair_ok,chair_results)

func _case_34(t) -> void:
	var x: Dictionary = _fixture()
	var visit: Dictionary = _visit(x)
	var original_ticket: String = visit.ticket_id
	x.world.facts.sim_tick = 1799
	x.l.dispatch(x.world)
	var before_due: bool = x.world.facts.waiting_life.needs.is_empty()
	x.world.facts.sim_tick = 1800
	var ticket: Dictionary = x.world.facts.tickets[original_ticket]
	ticket.service_assigned = true
	ticket.called_tick = 1800
	x.l.dispatch(x.world)
	var clinical_first: bool = x.world.facts.waiting_life.needs.is_empty()
	ticket.service_assigned = false
	ticket.called_tick = -1
	x.l.dispatch(x.world)
	var need: Dictionary = x.world.facts.waiting_life.needs.get(visit.id,{})
	var random_patience: Dictionary = x.world.facts.rng.patience.duplicate(true)
	var original_wait: int = int(ticket.waited_ticks)
	for _tick: int in 10:
		x.world.facts.sim_tick += 1
		x.a.advance_wait(x.world)
		x.a.needs(x.world)
	var temporary: bool = not need.is_empty() and need.purpose=="toilet" and ticket.pause_reasons.has("need_service") and visit.ticket_id==original_ticket and ticket.waited_ticks==original_wait and x.world.facts.rng.patience==random_patience and not x.l.call_patient(x.world,visit.id)
	t.check("STAFF-34",before_due and clinical_first and temporary,{"before_due":before_due,"clinical_first":clinical_first,"need":need,"ticket":ticket})

func _case_35(t) -> void:
	var x: Dictionary = _fixture()
	var visit: Dictionary = _visit(x)
	x.world.facts.sim_tick = 1800
	x.l.dispatch(x.world)
	var need: Dictionary = x.world.facts.waiting_life.needs.get(visit.id,{})
	var no_facility_fallback: bool = need.get("phase","")=="fallback" and need.get("remaining_ticks",-1)==80
	var ticket: Dictionary = x.world.facts.tickets[visit.ticket_id]
	ticket.pause_reasons.event = "independent_event"
	for _tick: int in 79:
		x.world.facts.sim_tick += 1
		x.l.advance(x.world)
	var safe_until_eight: bool = need.phase=="fallback" and need.remaining_ticks==1 and visit.anger==50.0
	x.world.facts.sim_tick += 1
	x.l.advance(x.world)
	x.l.advance(x.world)
	var clock: Dictionary = x.world.facts.waiting_life.clocks[visit.id]
	var once_fallback: bool = visit.anger==55.0 and clock.next_purpose=="water" and clock.next_need_tick==x.world.sim_tick+1800 and not ticket.pause_reasons.has("need_service") and ticket.pause_reasons.get("event","")=="independent_event"
	var y: Dictionary = _fixture()
	_facility(y,"toilet","FUR07",[42,75])
	var actual: Dictionary = _visit(y,"actual",y.space.facility_layout(y.world,"toilet").patient_cell)
	y.world.facts.sim_tick = 1800
	y.l.dispatch(y.world)
	for _tick: int in 10:
		if y.world.facts.waiting_life.needs.get(actual.id,{}).get("phase","")=="using":
			break
		y.world.facts.sim_tick += 1
		y.space.advance(y.world)
		y.l.dispatch(y.world)
	var use: Dictionary = y.world.facts.waiting_life.needs.get(actual.id,{})
	var facility_started: bool = use.get("phase","")=="using" and use.get("remaining_ticks",-1)==80 and not y.l.call_patient(y.world,actual.id)
	var quote_kept: bool = y.world.facts.adaptations.has("toilet")
	for _tick: int in 79:
		y.world.facts.sim_tick += 1
		y.l.advance(y.world)
	var use_safe: bool = use.get("phase","")=="using" and use.get("remaining_ticks",-1)==1 and y.world.facts.adaptations.has("toilet")
	y.world.facts.sim_tick += 1
	y.l.advance(y.world)
	var facility_done: bool = actual.anger==50.0 and y.world.facts.waiting_life.clocks[actual.id].next_purpose=="water"
	# A checkpoint still seeking at the original 45-second deadline must stop
	# acquiring facilities and use supplies at the next real floor position.
	var z: Dictionary = _fixture()
	var timeout_visit: Dictionary = _visit(z,"timeout")
	z.world.facts.sim_tick = 1800
	z.l._begin_need(z.world,timeout_visit)
	var timeout_need: Dictionary = z.world.facts.waiting_life.needs[timeout_visit.id]
	timeout_need.phase = "seek"
	timeout_need.remaining_ticks = 0
	z.world.facts.sim_tick = 2250
	z.l.dispatch(z.world)
	var timeout: bool = timeout_need.phase=="fallback" and timeout_need.remaining_ticks==80 and timeout_need.facility_id.is_empty()
	t.check("STAFF-35",no_facility_fallback and safe_until_eight and once_fallback and facility_started and quote_kept and use_safe and facility_done and timeout,{"fallback_once":once_fallback,"actual_started":facility_started,"actual_safe":use_safe,"deadline_fallback":timeout})

func _case_36(t) -> void:
	var x: Dictionary = _fixture()
	x.world.facts.sim_tick = 123
	var doctor_filter: Dictionary = {"role":"doctor","title_id":"DT01","primary_track":"treatment"}
	var card: Dictionary = x.r.standard_preview(x.world,doctor_filter)
	var again: Dictionary = x.r.standard_preview(x.world,doctor_filter)
	var rng: Dictionary = x.world.facts.rng.recruitment.duplicate(true)
	var cash: int = HospitalLedger.balance(x.world)
	x = _restore(x)
	var restored: Dictionary = x.r.standard_preview(x.world,doctor_filter)
	var payload: Dictionary = _hire_payload(card,doctor_filter)
	var hired: CommandResult = x.r.execute(x.world,"recruitment_hire",payload)
	var duplicate: CommandResult = x.r.execute(x.world,"recruitment_hire",payload)
	var next_card: Dictionary = x.r.standard_preview(x.world,doctor_filter)
	var doctor_id: String = "staff_"+str(card.get("id",""))
	var staff: Dictionary = x.world.facts.staff.get(doctor_id,{})
	x.d.ensure(x.world)
	var standard_ok: bool = card.ok and card==again and card==restored and x.world.facts.rng.recruitment==rng and card.hire==280 and card.wage_day==140 and hired.accepted and not duplicate.accepted and x.world.facts.staff.size()==1 and HospitalLedger.balance(x.world)==cash-280 and next_card.ordinal==card.ordinal+1 and next_card.id!=card.id
	standard_ok = standard_ok and not staff.is_empty() and staff.abilities==card.abilities and staff.practice=={"diagnosis":0,"treatment":0,"care":0,"surgery":0} and staff.cured_cases==0 and staff.completed_courses.is_empty()
	var nurse_card: Dictionary = x.r.standard_preview(x.world,{"role":"nurse"})
	standard_ok = standard_ok and nurse_card.ok and nurse_card.hire==200 and nurse_card.wage_day==100 and nurse_card.abilities.diagnosis==1 and nurse_card.abilities.care==1 and nurse_card.abilities.surgery==0
	t.check("STAFF-36",standard_ok,{"card":card,"hired":hired.code,"duplicate":duplicate.code,"next_id":next_card.get("id",""),"cash":HospitalLedger.balance(x.world)})

func _case_37(t) -> void:
	var doctor_filter: Dictionary = {"role":"doctor","title_id":"DT01","primary_track":"treatment"}
	var x: Dictionary = _fixture()
	x.world.facts.sim_tick = 321
	var card: Dictionary = x.r.standard_preview(x.world,doctor_filter)
	var payload: Dictionary = _hire_payload(card,doctor_filter)
	_cash(x,279)
	var no_cash: CommandResult = x.r.execute(x.world,"recruitment_hire",payload)
	var fail_atomic: bool = not no_cash.accepted and x.world.facts.staff.is_empty() and x.world.facts.actors.is_empty() and HospitalLedger.balance(x.world)==279 and x.world.facts.recruitment.standard_ordinals.is_empty()
	_cash(x,1000)
	for cx: int in range(47,50):
		for cy: int in range(93,96):
			x.world.facts.floors.overrides["1"].blocked.append([cx,cy])
	x.world.touch()
	var no_entry: CommandResult = x.r.execute(x.world,"recruitment_hire",payload)
	fail_atomic = fail_atomic and not no_entry.accepted and no_entry.code=="entry_blocked" and x.world.facts.staff.is_empty() and HospitalLedger.balance(x.world)==1000 and x.world.facts.recruitment.standard_ordinals.is_empty()
	x.world.facts.floors.overrides["1"].blocked.clear()
	x.world.touch()
	# The workplace can be absent; a legal entrance permits paid employment.
	var hired: CommandResult = x.r.execute(x.world,"recruitment_hire",payload)
	var doctor_id: String = "staff_"+str(card.get("id",""))
	var staff: Dictionary = x.world.facts.staff.get(doctor_id,{})
	x.f.ensure(x.world)
	x.f.settle(x.world)
	var first_wage: int = int(staff.get("wage_numerator",0))
	x.f.settle(x.world)
	var location: Dictionary = x.world.facts.actors.get(doctor_id,{}).get("location",{})
	var hired_at_entrance: bool = hired.accepted and staff.get("hired_tick",-1)==321 and staff.get("wage_accrued_tick",-1)==321 and first_wage==140 and staff.wage_numerator==first_wage and location.get("kind","")=="floor" and location.get("floor_id",-1)==1 and x.world.facts.facilities.is_empty() and HospitalLedger.balance(x.world)==720
	t.check("STAFF-37",fail_atomic and hired_at_entrance,{"funds_rejection":no_cash.code,"entry_rejection":no_entry.code,"hired":hired.code,"staff":staff,"location":location})

func _case_38(t) -> void:
	var x: Dictionary = _fixture()
	var filter: Dictionary = {"role":"nurse","species_id":"S49","ability":"care","min_ability":1}
	var cash: int = HospitalLedger.balance(x.world)
	var search: CommandResult = x.r.execute(x.world,"recruitment_search",{"filter":filter})
	var frozen: Dictionary = x.world.facts.recruitment.active_search.duplicate(true)
	var second_search: CommandResult = x.r.execute(x.world,"recruitment_search",{"filter":filter})
	var search_ok: bool = search.accepted and not second_search.accepted and frozen.get("candidates",[]).size()==3 and frozen.get("remaining_ticks",-1)==1200 and HospitalLedger.balance(x.world)==cash-100
	var rng: Dictionary = x.world.facts.rng.recruitment.duplicate(true)
	x = _restore(x)
	search_ok = search_ok and x.world.facts.recruitment.active_search==frozen and x.world.facts.rng.recruitment==rng
	for _tick: int in 1199:
		x.world.facts.sim_tick += 1
		x.r.advance(x.world)
	search_ok = search_ok and x.world.facts.recruitment.candidates.is_empty() and x.world.facts.recruitment.active_search.remaining_ticks==1
	x.world.facts.sim_tick += 1
	x.r.advance(x.world)
	var published_ids: Dictionary = {}
	for candidate: Dictionary in x.world.facts.recruitment.candidates.values():
		published_ids[candidate.id] = true
		search_ok = search_ok and candidate.role=="nurse" and candidate.species_id=="S49" and candidate.abilities.care>=1 and candidate.abilities.surgery==0
	search_ok = search_ok and published_ids.size()==3 and x.world.facts.recruitment.active_search.is_empty()
	var new_search: CommandResult = x.r.execute(x.world,"recruitment_search",{"filter":filter})
	var cancel: CommandResult = x.r.execute(x.world,"recruitment_cancel_search",{})
	search_ok = search_ok and new_search.accepted and cancel.accepted and x.world.facts.recruitment.active_search.is_empty() and x.world.facts.recruitment.candidates.size()==3 and HospitalLedger.balance(x.world)==cash-200
	x.r.execute(x.world,"recruitment_search",{"filter":filter})
	for _tick: int in 1200:
		x.world.facts.sim_tick += 1
		x.r.advance(x.world)
	var before_rejected: int = HospitalLedger.balance(x.world)
	var full: CommandResult = x.r.execute(x.world,"recruitment_search",{"filter":filter})
	var impossible: CommandResult = x.r.execute(x.world,"recruitment_search",{"filter":{"role":"nurse","ability":"surgery","min_ability":1}})
	search_ok = search_ok and x.world.facts.recruitment.candidates.size()==6 and not full.accepted and full.code=="candidate_capacity" and not impossible.accepted and HospitalLedger.balance(x.world)==before_rejected
	t.check("STAFF-38",search_ok,{"started":search.code,"published":published_ids.keys(),"cancel":cancel.code,"capacity":full.code,"impossible":impossible.code,"cash":HospitalLedger.balance(x.world)})

func _case_39(t) -> void:
	var x: Dictionary = _fixture()
	var cash: int = HospitalLedger.balance(x.world)
	x.r.boundaries(x.world)
	var candidates: Dictionary = x.world.facts.recruitment.candidates
	var roles: Dictionary = {}
	for candidate: Dictionary in candidates.values():
		roles[candidate.role] = true
	var first_day_ids: Array = candidates.keys()
	first_day_ids.sort()
	var bookmark_id: String = str(first_day_ids[0])
	var bookmark: CommandResult = x.r.execute(x.world,"recruitment_bookmark",{"candidate_id":bookmark_id,"enabled":true})
	var passive_ok: bool = candidates.size()==7 and roles.size()==7 and bookmark.accepted and candidates[bookmark_id].pool=="bookmarked"
	x.world.facts.sim_tick = 18000
	x.r.boundaries(x.world)
	var day_two_count: int = candidates.size()
	x = _restore(x)
	candidates = x.world.facts.recruitment.candidates
	x.world.facts.sim_tick = 36000
	x.r.boundaries(x.world)
	var passive_count: int = 0
	for candidate: Dictionary in candidates.values():
		if candidate.pool=="passive":
			passive_count += 1
	passive_ok = passive_ok and day_two_count==14 and passive_count==14 and candidates.has(bookmark_id) and candidates[bookmark_id].pool=="bookmarked"
	var unbookmark: CommandResult = x.r.execute(x.world,"recruitment_bookmark",{"candidate_id":bookmark_id,"enabled":false})
	passive_ok = passive_ok and unbookmark.accepted and not candidates.has(bookmark_id)
	var current_ids: Array = candidates.keys()
	current_ids.sort()
	for index: int in 4:
		passive_ok = passive_ok and x.r.execute(x.world,"recruitment_bookmark",{"candidate_id":current_ids[index],"enabled":true}).accepted
	var fifth: CommandResult = x.r.execute(x.world,"recruitment_bookmark",{"candidate_id":current_ids[4],"enabled":true})
	var before_repeat: Dictionary = candidates.duplicate(true)
	x.r.boundaries(x.world)
	passive_ok = passive_ok and not fifth.accepted and fifth.code=="bookmark_capacity" and candidates==before_repeat and candidates.size()<=24 and HospitalLedger.balance(x.world)==cash
	t.check("STAFF-39",passive_ok,{"day_two_count":day_two_count,"day_three_passive":passive_count,"fifth_bookmark":fifth.code,"candidate_count":candidates.size()})

func _case_40(t) -> void:
	var x: Dictionary = _fixture({"reception":"receptionist","cleaner":"cleaner","mechanic":"mechanic","mechanic_b":"mechanic","researcher":"researcher","decorator":"decorator","nurse":"nurse"})
	var practice_ok: bool = true
	var sources: Dictionary = {"reception":"registration_completed","cleaner":"cleanup_completed","mechanic":"maintenance_order_completed","decorator":"surface_unit_completed"}
	for id: String in sources:
		var last_receipt: Dictionary = {}
		for unit: int in 20:
			last_receipt = {"id":"completed_"+id+"_"+str(unit),"staff_id":id,"standard_work_milli":1000,"completed_tick":x.world.sim_tick,"practice_awarded":false}
			practice_ok = x.r.consume_completion(x.world,sources[id],last_receipt) and practice_ok
		practice_ok = practice_ok and x.world.facts.staff[id].skill==1 and x.world.facts.staff[id].job_practice==20 and not x.r.consume_completion(x.world,sources[id],last_receipt)
		var unfinished: Dictionary = {"id":"unfinished_"+id,"staff_id":id,"standard_work_milli":0}
		practice_ok = practice_ok and not x.r.consume_completion(x.world,sources[id],unfinished)
	x.world.facts.research.append("R11")
	x.r.settle(x.world)
	for id: String in sources:
		practice_ok = practice_ok and x.world.facts.staff[id].skill==2 and x.world.facts.staff[id].job_practice==0 and x.world.facts.staff[id].first_job_tick==0
	var active_a: Dictionary = {"id":"research_topic_a","qualified_active_research":true}
	x.r.research_work(x.world,"researcher",1199,active_a)
	practice_ok = practice_ok and x.world.facts.staff.researcher.job_practice==0 and x.world.facts.staff.researcher.research_practice_ticks==1199
	x = _restore(x)
	var active_b: Dictionary = {"id":"research_topic_b","qualified_active_research":true}
	x.r.research_work(x.world,"researcher",1,active_b)
	x.r.research_work(x.world,"researcher",1,active_b)
	practice_ok = practice_ok and x.world.facts.staff.researcher.job_practice==1 and x.world.facts.staff.researcher.research_practice_ticks==0
	var inactive: Dictionary = {"id":"waiting_for_desk","qualified_active_research":false}
	practice_ok = practice_ok and not x.r.research_work(x.world,"researcher",1200,inactive)
	for unit: int in 19:
		x.r.research_work(x.world,"researcher",1200,{"id":"active_research_"+str(unit),"qualified_active_research":true})
	practice_ok = practice_ok and x.world.facts.staff.researcher.skill==2 and x.world.facts.staff.researcher.job_practice==0
	_facility(x,"machine","FUR02",[43,75])
	x.m._receipt(x.world,"repair_completed","major",{"mechanic":900,"mechanic_b":100},1000,"machine")
	x.m._receipt(x.world,"repair_completed","tie",{"mechanic":500,"mechanic_b":500},1000,"machine")
	x.m._receipt(x.world,"repair_completed","departed",{"no_longer_employed":900,"mechanic_b":100},1000,"machine")
	x.r.settle(x.world)
	x.r.settle(x.world)
	var receipts: Dictionary = x.world.facts.maintenance.receipts
	practice_ok = practice_ok and receipts["major:repair_completed"].staff_id=="mechanic" and receipts["tie:repair_completed"].staff_id=="mechanic" and receipts["departed:repair_completed"].staff_id.is_empty() and x.world.facts.staff.mechanic.job_practice==2 and x.world.facts.staff.mechanic_b.job_practice==0
	var nurse_receipt: Dictionary = {"id":"nurse_actual_test","staff_id":"nurse","standard_work_milli":1000}
	x.r.consume_completion(x.world,"test_completed",nurse_receipt)
	practice_ok = practice_ok and not x.world.facts.staff.nurse.has("job_practice") and x.world.facts.staff.nurse.abilities.diagnosis==1 and x.world.facts.staff.nurse.completed_courses.is_empty()
	x.world.facts.staff.cleaner.skill = 4
	x.world.facts.staff.cleaner.job_practice = 19
	x.r.consume_completion(x.world,"cleanup_completed",{"id":"to_maximum","staff_id":"cleaner","standard_work_milli":1000})
	x.r.consume_completion(x.world,"cleanup_completed",{"id":"after_maximum","staff_id":"cleaner","standard_work_milli":1000})
	practice_ok = practice_ok and x.world.facts.staff.cleaner.skill==5 and x.world.facts.staff.cleaner.job_practice==0
	t.check("STAFF-40",practice_ok,{"maintenance_receipts":receipts,"researcher":x.world.facts.staff.researcher,"nurse":x.world.facts.staff.nurse})
