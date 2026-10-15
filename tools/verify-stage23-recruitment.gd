extends SceneTree

const Recruitment = preload("res://game/staff/recruitment_service.gd")
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var content: HospitalContent = HospitalContent.new()
	var world: WorldState = FeasibilityHospitals.create("recruitment-rules",false,content)
	var recruitment = Recruitment.new(content,HospitalSpace.new(content))
	recruitment.ensure(world)
	var before: Dictionary = world.freeze()
	var first: Dictionary = recruitment.standard_preview(world,{"role":"doctor","title_id":"DT02","primary_track":"treatment"})
	var again: Dictionary = recruitment.standard_preview(world,{"role":"doctor","title_id":"DT02","primary_track":"treatment","sort":"wage","floor_id":2})
	_check("standard_preview_stable_and_read_only",first.id==again.id and first.quote_hash==again.quote_hash and before==world.freeze())
	_check("mature_doctor_frozen_price",first.hire==1000 and first.wage_day==180 and first.abilities.treatment==2)
	var payload: Dictionary = {"standard_key":first.standard_key,"ordinal":first.ordinal,"filter":{"role":"doctor","title_id":"DT02","primary_track":"treatment"},"quote_hash":first.quote_hash}
	world.touch()
	var hired: CommandResult = recruitment.execute(world,"recruitment_hire",payload)
	_check("atomic_hire_ignores_unrelated_revision",hired.accepted and HospitalLedger.balance(world)==99000 and world.facts.staff[hired.changed_ids[0]].hired_tick==world.sim_tick)
	before = world.freeze()
	_check("same_standard_candidate_cannot_hire_twice",not recruitment.execute(world,"recruitment_hire",payload).accepted and before==world.freeze())
	recruitment.boundaries(world)
	_check("seven_daily_roles",world.facts.recruitment.candidates.size()==7)
	before = world.freeze()
	recruitment.boundaries(world)
	_check("daily_batch_idempotent",before==world.freeze())
	var candidate_id: String = str(world.facts.recruitment.candidates.keys()[0])
	_check("bookmark_moves_unique_identity",recruitment.execute(world,"recruitment_bookmark",{"candidate_id":candidate_id,"enabled":true}).accepted and world.facts.recruitment.candidates[candidate_id].pool=="bookmarked")
	world.facts.sim_tick = 36000
	recruitment.boundaries(world)
	_check("expires_without_losing_bookmark",world.facts.recruitment.candidates.has(candidate_id) and world.facts.recruitment.candidates.size()==8)
	_check("unbookmark_expired_archives",recruitment.execute(world,"recruitment_bookmark",{"candidate_id":candidate_id,"enabled":false}).accepted and not world.facts.recruitment.candidates.has(candidate_id))
	var cash: int = HospitalLedger.balance(world)
	_check("impossible_search_never_charges",not recruitment.execute(world,"recruitment_search",{"filter":{"role":"nurse","ability":"surgery","min_ability":1}}).accepted and HospitalLedger.balance(world)==cash)
	_check("targeted_search_freezes_three",recruitment.execute(world,"recruitment_search",{"filter":{"role":"cleaner","species_id":"S01","ability":"skill","min_ability":2}}).accepted and HospitalLedger.balance(world)==cash-100 and world.facts.recruitment.active_search.candidates.size()==3)
	var restored: WorldState = WorldState.new(world.freeze())
	for tick: int in range(36000,37200):
		world.facts.sim_tick = tick
		restored.facts.sim_tick = tick
		recruitment.advance(world)
		recruitment.advance(restored)
	_check("search_restore_preserves_outcomes",world.freeze()==restored.freeze() and world.facts.recruitment.active_search.is_empty())
	var targeted: int = 0
	for candidate: Dictionary in world.facts.recruitment.candidates.values():
		if candidate.pool=="targeted":
			targeted += 1
			_check("targeted_hard_filter",candidate.species_id=="S01" and candidate.skill>=2)
	_check("search_results_exactly_three",targeted==3)
	var receptionist: Dictionary = world.facts.staff.reception
	var receipt: Dictionary = {"id":"registration-original","staff_id":"reception","standard_work_milli":1000}
	_check("real_completion_only_once",recruitment.consume_completion(world,"registration_completed",receipt) and not recruitment.consume_completion(world,"registration_completed",receipt) and receptionist.job_practice==1)
	_check("preview_or_zero_work_no_practice",not recruitment.consume_completion(world,"registration_completed",{"id":"empty","staff_id":"reception","standard_work_milli":0}))
	for index: int in range(19):
		recruitment.consume_completion(world,"registration_completed",{"id":"reg_%d"%index,"staff_id":"reception","standard_work_milli":1000})
	_check("twenty_real_work_units_level_once",receptionist.skill==2 and receptionist.job_practice==0)
	var roles_world: WorldState = FeasibilityHospitals.create("seven-role-hire",false,content)
	roles_world.facts.staff.clear()
	roles_world.facts.actors.clear()
	var roles_recruitment = Recruitment.new(content,HospitalSpace.new(content))
	roles_recruitment.ensure(roles_world)
	for role: String in Recruitment.ROLES:
		var quote: Dictionary = roles_recruitment.standard_preview(roles_world,{"role":role})
		var result: CommandResult = roles_recruitment.execute(roles_world,"recruitment_hire",{"standard_key":quote.standard_key,"ordinal":quote.ordinal,"filter":{"role":role},"quote_hash":quote.quote_hash})
		_check("real_entry_hire_"+role,result.accepted and roles_world.facts.staff[result.changed_ids[0]].role==role and roles_world.facts.actors[result.changed_ids[0]].location.kind=="floor")
	var researcher: String = ""
	for id: String in roles_world.facts.staff:
		if roles_world.facts.staff[id].role=="researcher":
			researcher = id
	var research_receipt: Dictionary = {"id":"real-time-1","qualified_active_research":true}
	_check("research_actual_time_partial",roles_recruitment.research_work(roles_world,researcher,1199,research_receipt) and roles_world.facts.staff[researcher].job_practice==0 and roles_world.facts.staff[researcher].research_practice_ticks==1199)
	_check("research_time_receipt_once",not roles_recruitment.research_work(roles_world,researcher,1199,research_receipt))
	_check("research_time_carries_topics",roles_recruitment.research_work(roles_world,researcher,1,{"id":"next-topic","qualified_active_research":true}) and roles_world.facts.staff[researcher].job_practice==1 and roles_world.facts.staff[researcher].research_practice_ticks==0)
	for species: Dictionary in content.catalog.species:
		var adapter: Dictionary = recruitment.adapter(species.id)
		_check("all_species_defined_role_adapter_"+species.id,not adapter.is_empty() and adapter.roles.size()==7)
	print(JSON.stringify({"stage":23,"checks":checks,"failures":failures,"performance":"skipped","formal_species_assets":"stage35"}))
	quit(0 if failures.is_empty() else 1)

func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures.append(label)
