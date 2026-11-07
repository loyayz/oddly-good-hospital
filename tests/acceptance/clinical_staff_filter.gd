extends RefCounted

# Calculation-only tests: no simulated arrival, work, movement or elapsed time
# is manufactured. The legal queue/layout is the CLIN-33 fixture reused by
# clinical_selected_doctor.gd; expectations below come from clinical-team §6,
# §8, §9 and §10, not from a frozen implementation's answers.
class ObservedClinic extends HospitalClinic:
	var qualification_calls: Array = []
	func _service_qualified(world: WorldState, staff: Dictionary, kind: String) -> bool:
		qualification_calls.append([staff.id,kind])
		return super._service_qualified(world,staff,kind)

const FACILITIES: Array = ["gather_facility_0","gather_facility_1"]
const STAFF: Array = ["gather_worker","test_staff_0","test_staff_1","test_staff_2"]
var _content: HospitalContent
var _base: Dictionary = {}
var _checks: Array = []

func run(database: HospitalContent, group: String = "all") -> Dictionary:
	_content = database
	var builder: RefCounted = load("res://tests/acceptance/clinical_gathering.gd").new()
	var source: WorldState = builder._context(database,"gp").world
	for index: int in 3:
		HospitalFactory._add_staff(source,"test_staff_"+str(index),"候选医生","doctor",[40+index*4,24],database)
	source.touch()
	var validation: String = source.validate(database)
	_record("legal_source_fixture",validation.is_empty(),{"validation":validation})
	if not validation.is_empty(): return _report()
	_base = source.freeze()
	if group=="preparations":
		_preparation_regression()
		return _report()
	_order_and_selection()
	_declined_and_live_callbacks()
	_actual_and_structural()
	_between_call_freshness()
	_facility_specific_schedules()
	_nested_and_restored()
	_full_enumeration()
	_outpatient_selected_fixture()
	return _report()

func _report() -> Dictionary:
	var passed: bool = true
	for check: Dictionary in _checks: passed = passed and bool(check.passed)
	return {"passed":passed,"checks":_checks,"scope":"Direct expected candidate results; real fit/route/exit queries; calculation only, no timing or movement-progression claims","requirements":["docs/design/07-clinical-team.md §6","docs/design/07-clinical-team.md §8","docs/design/07-clinical-team.md §9","docs/design/07-clinical-team.md §10"],"fixture_source":"tests/acceptance/clinical_gathering.gd::_context, reused by clinical_selected_doctor.gd"}

func _record(name: String, passed: bool, details: Dictionary = {}) -> void:
	_checks.append({"name":name,"passed":passed,"details":details})

func _context(facts: Dictionary = {}) -> Dictionary:
	var world: WorldState = WorldState.new((_base if facts.is_empty() else facts).duplicate(true))
	var space: HospitalSpace = HospitalSpace.new(_content)
	return {"world":world,"space":space,"clinic":ObservedClinic.new(_content,space)}

func _pairs(facilities: Array = FACILITIES, staff: Array = STAFF) -> Array:
	var result: Array = []
	for facility_id: String in facilities:
		for staff_id: String in staff: result.append({"facility_id":facility_id,"staff_id":staff_id})
	return result

func _without(staff_id: String) -> Array:
	var result: Array = STAFF.duplicate()
	result.erase(staff_id)
	return result

func _query(name: String, c: Dictionary, expected: Array, structural: bool = false, reference: bool = false, selection: Dictionary = {}, kind: String = "gp", visit_id: String = "gather_visit_0") -> Array:
	var validation: String = c.world.validate(_content)
	var before: Dictionary = c.world.freeze()
	var revision: int = c.world.revision
	var depth: int = c.space._route_queries.size()
	var actual: Array = c.clinic.service_candidates(c.world,c.world.facts.visits[visit_id],kind,structural,reference,selection)
	var readonly: bool = c.world.freeze()==before and c.world.revision==revision
	var balanced: bool = c.space._route_queries.size()==depth
	_record(name,validation.is_empty() and actual==expected and readonly and balanced,{"validation":validation,"expected":expected,"actual":actual,"facts_and_rng_readonly":readonly,"query_scope_balanced":balanced})
	return actual

func _order_and_selection() -> void:
	var c: Dictionary = _context()
	for kind: String in ["gp","consult"]:
		for structural: bool in [false,true]:
			var suffix: String = kind+"_"+str(structural)
			_query("facility_outer_staff_inner_"+suffix,c,_pairs(),structural,false,{},kind)
			_query("selected_staff_"+suffix,c,_pairs(FACILITIES,["test_staff_1"]),structural,false,{"staff_id":"test_staff_1"},kind)
			_query("missing_selected_staff_"+suffix,c,[],structural,false,{"staff_id":"missing_staff"},kind)
			_query("empty_selected_staff_"+suffix,c,[],structural,false,{"staff_id":""},kind)
			_query("selected_facility_"+suffix,c,_pairs([FACILITIES[1]]),structural,false,{"facility_id":FACILITIES[1]},kind)
	var seen: Array = []
	var eligible: Array = []
	c.clinic.qualification_calls.clear()
	_query("first_only_stops_after_first_complete_pair",c,[_pairs()[0]],false,false,{"first_only":true,"eligible":func(pair: Dictionary)->bool: eligible.append(pair.duplicate()); return true,"accept":func(pair: Dictionary)->bool: seen.append(pair.duplicate()); return true})
	_record("first_only_no_extra_predicates_or_callbacks",seen==[_pairs()[0]] and eligible==seen and c.clinic.qualification_calls==[[STAFF[0],"gp"]],{"eligible":eligible,"accept":seen,"qualification":c.clinic.qualification_calls.duplicate()})

func _declined_and_live_callbacks() -> void:
	var c: Dictionary = _context()
	var all_pairs: Array = _pairs()
	var seen: Array = []
	_query("declined_first_falls_through_to_next_staff",c,[all_pairs[1]],false,false,{"first_only":true,"accept":func(pair: Dictionary)->bool: seen.append(pair.duplicate()); return seen.size()>1})
	_record("declined_first_callback_order",seen==all_pairs.slice(0,2),{"actual":seen})
	seen = []
	_query("declined_first_facility_reaches_next_facility",c,[all_pairs[4]],false,false,{"first_only":true,"accept":func(pair: Dictionary)->bool: seen.append(pair.duplicate()); return pair.facility_id==FACILITIES[1]})
	_record("full_first_facility_fallback_order",seen==all_pairs.slice(0,5),{"actual":seen})
	seen = []
	_query("declined_all_but_last_preserves_full_fallback",c,[all_pairs.back()],false,false,{"first_only":true,"accept":func(pair: Dictionary)->bool: seen.append(pair.duplicate()); return pair==all_pairs.back()})
	_record("all_eight_complete_pairs_attempted",seen==all_pairs,{"actual":seen})
	var eligibility: Array = []
	_query("facility_specific_eligible_callback_stays_live",c,[all_pairs.back()],false,false,{"eligible":func(pair: Dictionary)->bool: eligibility.append(pair.duplicate()); return pair==all_pairs.back()})
	_record("eligible_sees_each_pair_in_order",eligibility==all_pairs,{"actual":eligibility})
	var considered: Dictionary = {}
	_query("accept_callback_adds_live_considered",c,_pairs(FACILITIES,_without("test_staff_0")),false,false,{"considered":considered,"accept":func(_pair: Dictionary)->bool: considered.test_staff_0 = true; return true})
	var selection: Dictionary = {"considered":{"test_staff_0":true}}
	selection.eligible = func(_pair: Dictionary)->bool: selection.considered = {}; return true
	_query("eligible_callback_can_replace_considered_dictionary",c,all_pairs,false,false,selection)
	selection.erase("eligible")
	# A structural scan can be nested by a quotation callback, but neither
	# callback is permitted to mutate world facts during a sealed query.
	var nested_results: Array = []
	_query("readonly_nested_callback_keeps_outer_selection",c,[all_pairs[0]],false,false,{"first_only":true,"accept":func(_pair: Dictionary)->bool: nested_results.append(c.clinic.service_candidates(c.world,c.world.facts.visits.gather_visit_0,"gp",true,false,{"staff_id":"test_staff_2"})); return true})
	_record("nested_callback_has_own_staff_selection",nested_results==[_pairs(FACILITIES,["test_staff_2"])],{"actual":nested_results})

func _actual_and_structural() -> void:
	var edits: Array = [
		{"label":"off_shift","field":"on_shift","value":false},
		{"label":"base_unprepared","field":"base_prepared","value":false},
		{"label":"blocked_new_work","field":"block_new_work","value":true},
		{"label":"energy_boundary","field":"energy","value":15.0},
		{"label":"fatigue_boundary","field":"fatigue","value":float(_content.balance.wellbeing.fatigue_stop_new_work)},
		{"label":"supply_strike","field":"supply_strike","value":true}
	]
	for edit: Dictionary in edits:
		var c: Dictionary = _context()
		c.world.facts.staff.test_staff_0[edit.field] = edit.value
		_query("actual_excludes_"+str(edit.label),c,_pairs(FACILITIES,_without("test_staff_0")))
		_query("structural_keeps_"+str(edit.label),c,_pairs(),true)
	var unqualified: Dictionary = _context()
	unqualified.world.facts.staff.test_staff_0.abilities.diagnosis = 0
	for structural: bool in [false,true]:
		_query("qualification_required_"+str(structural),unqualified,_pairs(FACILITIES,_without("test_staff_0")),structural)
	var occupied: Dictionary = _context()
	occupied.world.facts.preparations["gather_visit_1"] = _preparation("gather_visit_1",FACILITIES[1],["test_staff_0"])
	_query("other_preparation_owns_staff_and_facility",occupied,_pairs([FACILITIES[0]],_without("test_staff_0")))
	_query("structural_ignores_temporary_other_preparation",occupied,_pairs(),true)

func _preparation(visit_id: String, facility_id: String, staff_ids: Array) -> Dictionary:
	return {"id":visit_id,"visit_id":visit_id,"kind":"gp","bed_id":"","facility_id":facility_id,"staff_ids":staff_ids.duplicate(),"deadline_tick":300,"setup_remaining_ticks":0}

func _between_call_freshness() -> void:
	var c: Dictionary = _context()
	var revision: int = c.world.revision
	_query("freshness_baseline",c,_pairs())
	c.world.facts.staff.test_staff_0.abilities.diagnosis = 0
	_query("no_touch_qualification_removed",c,_pairs(FACILITIES,_without("test_staff_0")))
	c.world.facts.staff.test_staff_0.abilities.diagnosis = 1
	_query("no_touch_qualification_restored",c,_pairs())
	c.world.facts.staff.test_staff_0.on_shift = false
	_query("no_touch_shift_removed",c,_pairs(FACILITIES,_without("test_staff_0")))
	c.world.facts.staff.test_staff_0.on_shift = true
	_query("no_touch_shift_restored",c,_pairs())
	c.world.facts.staff.test_staff_0.base_prepared = false
	_query("no_touch_readiness_removed",c,_pairs(FACILITIES,_without("test_staff_0")))
	c.world.facts.staff.test_staff_0.base_prepared = true
	_query("no_touch_readiness_restored_after_false",c,_pairs())
	HospitalFactory._add_staff(c.world,"zz_added_staff","新候选医生","doctor",[64,24],_content)
	_query("no_touch_new_staff_visible",c,_pairs(FACILITIES,STAFF+["zz_added_staff"]))
	c.world.facts.staff.erase("zz_added_staff")
	c.world.facts.actors.erase("zz_added_staff")
	_query("no_touch_removed_staff_gone",c,_pairs())
	c.world.facts.preparations["gather_visit_0"] = _preparation("gather_visit_0",FACILITIES[0],["test_staff_0"])
	_query("own_preparation_filters_membership_and_exempts_owner",c,_pairs([FACILITIES[0]],["test_staff_0"]))
	_query("own_preparation_also_limits_structural_membership",c,_pairs([FACILITIES[0]],["test_staff_0"]),true)
	_query("next_ticket_cannot_reuse_prior_ticket_eligibility",c,_pairs([FACILITIES[1]],_without("test_staff_0")),false,false,{},"gp","gather_visit_1")
	c.world.facts.preparations.gather_visit_0.staff_ids = ["test_staff_1"]
	_query("no_touch_preparation_membership_changed",c,_pairs([FACILITIES[0]],["test_staff_1"]))
	c.world.facts.preparations.gather_visit_0.facility_id = FACILITIES[1]
	_query("no_touch_preparation_facility_changed",c,_pairs([FACILITIES[1]],["test_staff_1"]))
	c.world.facts.preparations.clear()
	_query("no_touch_preparation_released",c,_pairs())
	_query("next_ticket_observes_release",c,_pairs(),false,false,{},"gp","gather_visit_1")
	_record("all_direct_edits_kept_revision_unchanged",c.world.revision==revision,{"before":revision,"after":c.world.revision})

func _facility_specific_schedules() -> void:
	var c: Dictionary = _context()
	var scheduler: HospitalShiftScheduler = HospitalShiftScheduler.new(_content,c.space)
	scheduler.ensure(c.world)
	c.clinic.scheduler = scheduler
	c.world.facts.staff.gather_worker.schedule[0].pools = [FACILITIES[1]]
	c.world.facts.staff.test_staff_0.schedule[0].pools = [FACILITIES[0]]
	c.world.facts.staff.test_staff_1.schedule[0].pools = ["gather_room_1"]
	c.world.facts.staff.test_staff_2.schedule[0].kind = "rest"
	c.world.facts.staff.test_staff_2.on_shift = false
	var expected: Array = _pairs([FACILITIES[0]],["test_staff_0"])+_pairs([FACILITIES[1]],["gather_worker","test_staff_1"])
	_query("actual_facility_and_room_pools",c,expected)
	_query("structural_without_reference_ignores_schedule",c,_pairs(),true)
	_query("structural_reference_keeps_facility_specific_schedule",c,expected,true,true)
	_query("actual_reference_keeps_facility_specific_schedule",c,expected,false,true)
	var revision: int = c.world.revision
	c.world.facts.staff.gather_worker.schedule[0].pools = [FACILITIES[0]]
	_query("no_touch_schedule_pool_changed",c,_pairs([FACILITIES[0]],["gather_worker","test_staff_0"])+_pairs([FACILITIES[1]],["test_staff_1"]))
	_record("schedule_edit_no_touch",c.world.revision==revision)

func _nested_and_restored() -> void:
	var c: Dictionary = _context()
	for nominal: bool in [false,true]:
		c.space.begin_route_query(c.world,{"nominal":true} if nominal else {})
		_query("nested_full_"+str(nominal),c,_pairs())
		_query("nested_selected_first_"+str(nominal),c,_pairs([FACILITIES[0]],["test_staff_1"]),false,false,{"staff_id":"test_staff_1","first_only":true})
		_query("nested_distinct_kind_"+str(nominal),c,_pairs(),true,false,{},"consult")
		c.space.end_route_query()
		_record("outer_scope_closes_"+str(nominal),c.space._route_queries.is_empty())
	var restored_facts: Dictionary = bytes_to_var(var_to_bytes(_base))
	var restored: Dictionary = {"world":WorldState.new(restored_facts),"space":c.space,"clinic":c.clinic}
	_query("binary_restored_world_same_candidates",restored,_pairs())
	_record("restoration_roundtrip_all_facts_equal",restored.world.freeze()==_base)
	restored.world.facts.staff.test_staff_1.abilities.diagnosis = 0
	_query("different_world_same_revision_uses_own_staff",restored,_pairs(FACILITIES,_without("test_staff_1")))
	_query("original_world_not_contaminated",c,_pairs())

func _full_enumeration() -> void:
	var c: Dictionary = _context()
	var ids: Array = STAFF.duplicate()
	for index: int in 28:
		var id: String = "zz_bulk_%02d" % index
		HospitalFactory._add_staff(c.world,id,"候选医生","doctor",[4+4*(index%20),30+4*int(index/20)],_content)
		ids.append(id)
	var expected: Array = _pairs(FACILITIES,ids)
	c.clinic.qualification_calls.clear()
	_query("all_32_staff_all_64_pairs_are_returned",c,expected)
	var expected_checks: Array = []
	for staff_id: String in ids: expected_checks.append([staff_id,"gp"])
	_record("64_pairs_check_each_of_32_staff_once",c.clinic.qualification_calls==expected_checks,{"qualification_calls":c.clinic.qualification_calls.size(),"pairs":expected.size(),"ordered_once":c.clinic.qualification_calls==expected_checks})
	c.clinic.qualification_calls.clear()
	var seen: Array = []
	_query("first_only_accepts_final_of_64_pairs",c,[expected.back()],false,false,{"first_only":true,"accept":func(pair: Dictionary)->bool: seen.append(pair.duplicate()); return pair==expected.back()})
	_record("fallback_has_no_candidate_cap",seen==expected,{"expected_count":64,"actual_count":seen.size(),"exact_order":seen==expected})
	_record("late_accept_rechecks_no_staff_eligibility",c.clinic.qualification_calls==expected_checks,{"qualification_calls":c.clinic.qualification_calls.size(),"complete_pairs_tried":seen.size(),"ordered_once":c.clinic.qualification_calls==expected_checks})

func _outpatient_selected_fixture() -> void:
	# Match the legal two-treatment-room extension in clinical_selected_doctor.
	var c: Dictionary = _context()
	for index: int in 2:
		var room_id: String = "quote_room_"+str(index)
		var origin: Array = [46+index*18,30]
		HospitalFactory._add_room(c.world,{"id":room_id,"type":"T01","anchor":origin,"size":[8,8],"door":{"definition_id":"DR04","offset":3}},_content)
		HospitalFactory._add_facility(c.world,{"id":"quote_facility_"+str(index),"definition_id":"M09","anchor":[int(origin[0])+1,int(origin[1])+1],"size":_content.facility_definition("M09").footprint,"room_id":room_id},_content)
	c.world.touch()
	var facilities: Array = ["quote_facility_0","quote_facility_1"]
	for structural: bool in [false,true]:
		_query("outpatient_order_"+str(structural),c,_pairs(facilities),structural,false,{},"outpatient")
		_query("outpatient_selected_"+str(structural),c,_pairs(facilities,["test_staff_2"]),structural,false,{"staff_id":"test_staff_2"},"outpatient")
	c.world.facts.staff.test_staff_0.abilities.treatment = 0
	_query("outpatient_no_touch_treatment_qualification",c,_pairs(facilities,_without("test_staff_0")),false,false,{},"outpatient")

func _preparation_regression() -> void:
	# Targeted rerun of the seven invalid-fixture checks from the initial run.
	# String bracket keys match the world's serialized entity-ID contract.
	var occupied: Dictionary = _context()
	occupied.world.facts.preparations["gather_visit_1"] = _preparation("gather_visit_1",FACILITIES[1],["test_staff_0"])
	_query("other_preparation_owns_staff_and_facility",occupied,_pairs([FACILITIES[0]],_without("test_staff_0")))
	_query("structural_ignores_temporary_other_preparation",occupied,_pairs(),true)
	var c: Dictionary = _context()
	_query("freshness_baseline",c,_pairs())
	c.world.facts.preparations["gather_visit_0"] = _preparation("gather_visit_0",FACILITIES[0],["test_staff_0"])
	_query("own_preparation_filters_membership_and_exempts_owner",c,_pairs([FACILITIES[0]],["test_staff_0"]))
	_query("own_preparation_also_limits_structural_membership",c,_pairs([FACILITIES[0]],["test_staff_0"]),true)
	_query("next_ticket_cannot_reuse_prior_ticket_eligibility",c,_pairs([FACILITIES[1]],_without("test_staff_0")),false,false,{},"gp","gather_visit_1")
	c.world.facts.preparations.gather_visit_0.staff_ids = ["test_staff_1"]
	_query("no_touch_preparation_membership_changed",c,_pairs([FACILITIES[0]],["test_staff_1"]))
	c.world.facts.preparations.gather_visit_0.facility_id = FACILITIES[1]
	_query("no_touch_preparation_facility_changed",c,_pairs([FACILITIES[1]],["test_staff_1"]))
