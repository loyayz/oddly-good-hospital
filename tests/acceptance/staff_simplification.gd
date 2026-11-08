extends "res://tests/acceptance/floor_guidance.gd"

func run_simplification(database: HospitalContent) -> Dictionary:
	_content = database
	var x: Dictionary = _base(true)
	var visit: Dictionary = _visit(x,"direct_arrival",[40,88])
	# Begin at the admission boundary rather than injecting a completed service.
	x.world.facts.tickets.erase(visit.ticket_id)
	visit.ticket_id = ""
	visit.phase = "arrival"
	x.world.touch()
	x.world.facts.staff.guide_nurse.on_shift = false
	for tick: int in 180: _step(x,true)
	var waits_for_guide: bool = x.world.facts.sessions.is_empty() and x.g.state(x.world,visit.id).get("receipts",[]).is_empty()
	x.world.facts.staff.guide_nurse.on_shift = true
	var no_registration: bool = x.c.service_candidates(x.world,visit,"reception").is_empty()
	var reached_doctor: bool = false
	var guide_completed_first: bool = false
	for tick: int in 1200:
		_step(x,true)
		no_registration = no_registration and not visit.has("registration_receipt") and not visit.phase in ["reception","wait_reception"]
		for session: Dictionary in x.world.facts.sessions.values():
			no_registration = no_registration and session.kind!="reception"
			if session.kind=="gp":
				reached_doctor = session.staff_ids==["doctor"]
				guide_completed_first = x.g.state(x.world,visit.id).get("receipts",[]).size()==1
		if reached_doctor: break
	var roles: bool = RecruitmentService.ROLES==["doctor","nurse","cleaner","researcher"] and RecruitmentService.ORDINARY_ROLES==["cleaner","researcher"]
	var validation: String = x.world.validate(_content)
	var result: Dictionary = {"ok":waits_for_guide and roles and no_registration and reached_doctor and guide_completed_first and validation.is_empty(),"waits_for_guide":waits_for_guide,"roles":roles,"no_registration":no_registration,"actual_doctor_service":reached_doctor,"guidance_completed_before_doctor":guide_completed_first,"validation":validation,"tick":x.world.sim_tick,"phase":visit.phase,"waiting_reason":visit.waiting_reason}
	_dispose(x)
	result.economy = _economy()
	result.guidance_speed_talent = _guidance_talent("S04",55,false)
	result.guidance_mood_talent = _guidance_talent("S50",60,true)
	result.ok = result.ok and result.economy.ok and result.guidance_speed_talent.ok and result.guidance_mood_talent.ok
	return result

func _guidance_talent(species: String, expected_ticks: int, mood: bool) -> Dictionary:
	var x: Dictionary = _base()
	x.world.facts.actors.guide_nurse.species_id = species
	x.space.sync_actor(x.world,"guide_nurse")
	x.world.touch()
	var visit: Dictionary = _visit(x,"talent_"+species,[40,88])
	for tick: int in 800:
		_step(x)
		if not x.g.state(x.world,visit.id).get("receipts",[]).is_empty(): break
	var receipts: Array = x.g.state(x.world,visit.id).get("receipts",[])
	var actual_ticks: int = int(receipts[0].completed_tick)-int(receipts[0].started_tick)+1 if not receipts.is_empty() else -1
	var applied: int = int(visit.get("staff_talent_mood",0))
	var once: bool = true
	if mood and not receipts.is_empty():
		x.r.service_mood(x.world,"guide_nurse","guidance",visit.id,receipts[0])
		once = int(visit.get("staff_talent_mood",0))==applied and bool(receipts[0].get("talent_mood_applied",false))
	var validation: String = x.world.validate(_content)
	var result: Dictionary = {"ok":actual_ticks==expected_ticks and applied==(2 if mood else 0) and once and validation.is_empty(),"species":species,"ticks":actual_ticks,"expected_ticks":expected_ticks,"mood_applied":applied,"once":once,"validation":validation}
	_dispose(x);return result

func _economy() -> Dictionary:
	var x: Dictionary = _bind(HospitalFactory.create(HospitalSnapshots.uuid(),"初始职员",true,_content))
	var wages: int = 0
	var removed_absent: bool = true
	for staff: Dictionary in x.world.facts.staff.values():
		wages += x.f.wage(staff)
		removed_absent = removed_absent and not staff.role in ["receptionist","decorator"]
	for facility: Dictionary in x.world.facts.facilities.values(): removed_absent = removed_absent and facility.definition_id!="FUR01"
	var cash: int = HospitalLedger.balance(x.world)
	var rejected: bool = not x.r.standard_preview(x.world,{"role":"receptionist"}).ok and not x.r.standard_preview(x.world,{"role":"decorator"}).ok
	var starter_count: int = x.world.facts.staff.size()
	_dispose(x)
	x = _fixture()
	x.world.facts.ledger.opening_balance += 2500-HospitalLedger.balance(x.world)
	var rescue: CommandResult = x.f.execute(x.world,"finance_rescue",{})
	# Normal simulation command completion initializes each new employee.
	for key: String in ["d","s","w","r","f"]: x[key].ensure(x.world)
	var counts: Dictionary = {}
	for staff: Dictionary in x.world.facts.staff.values(): counts[staff.role] = int(counts.get(staff.role,0))+1
	var borrowed: Array = []
	for item: Dictionary in x.world.facts.inventory.build_items.values():
		if item.get("ownership","")=="borrowed": borrowed.append(item.definition_id)
	borrowed.sort()
	var validation: String = x.world.validate(_content)
	var result: Dictionary = {"ok":removed_absent and rejected and starter_count==6 and wages==690 and cash==11050 and rescue.accepted and counts=={"doctor":2,"nurse":1} and borrowed==["FUR02","M37","SE01"] and validation.is_empty(),"removed_roles_and_desk_absent":removed_absent,"invalid_recruitment_rejected":rejected,"starter_staff":starter_count,"wages":wages,"cash":cash,"rescue_accepted":rescue.accepted,"rescue_roles":counts,"borrowed":borrowed,"validation":validation}
	_dispose(x);return result
