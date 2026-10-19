extends "res://tests/acceptance/staff_fixtures.gd"

class Routes extends HospitalSpace:
	var route_calls: int = 0
	var dynamic_batches: int = 0
	func begin_dynamic_route_query(world: WorldState, refresh_actors: bool = true) -> void:
		dynamic_batches += 1
		super.begin_dynamic_route_query(world,refresh_actors)
	func route(world: WorldState, actor_id: String, floor_id: int, target: Array, members: Array = [], offsets: Dictionary = {}, ignore_people: bool = false) -> Dictionary:
		route_calls += 1
		return super.route(world,actor_id,floor_id,target,members,offsets,ignore_people)

class Wellbeing extends HospitalStaffWellbeing:
	var tea_calls: int = 0
	var occupancy_calls: int = 0
	func _tea_position(world: WorldState, staff_id: String) -> Dictionary:
		tea_calls += 1
		return super._tea_position(world,staff_id)
	func _patient_occupies(world: WorldState, facility_id: String, view: Dictionary = {}) -> bool:
		occupancy_calls += 1
		return super._patient_occupies(world,facility_id,view)

class Recruitment extends RecruitmentService:
	var card_calls: int = 0
	var preview_calls: int = 0
	func card(world: WorldState, candidate: Dictionary) -> Dictionary:
		card_calls += 1
		return super.card(world,candidate)
	func standard_preview(world: WorldState, filter: Dictionary = {}) -> Dictionary:
		preview_calls += 1
		return super.standard_preview(world,filter)

class Bases extends HospitalClinicalDevelopment:
	var entry_calls: int = 0
	func _base_entry(world: WorldState, staff_id: String, base: Dictionary, busy: Dictionary) -> Dictionary:
		entry_calls += 1
		return super._base_entry(world,staff_id,base,busy)

func run(t, database: HospitalContent) -> void:
	_content = database
	var started: int = Time.get_ticks_usec()
	var tea: Dictionary = _tea()
	var status: Dictionary = _status()
	var receipts: Dictionary = _receipts()
	t.check("STAFF-43",tea.ok and status.ok and receipts.ok,{"CL-A02_CL-A10":tea,"CL-A08":status,"CL-A05":receipts,"elapsed_usec":Time.get_ticks_usec()-started})

func run_views(t, database: HospitalContent) -> void:
	_content = database
	var started: int = Time.get_ticks_usec()
	var occupancy: Dictionary = _occupancy()
	var bases: Dictionary = _bases()
	var desks: Dictionary = _desks_and_busy()
	t.check("STAFF-44",occupancy.ok and bases.ok and desks.ok,{"CL-A03":occupancy,"CL-A04":bases,"shared_desks_and_busy":desks,"elapsed_usec":Time.get_ticks_usec()-started})

func _tea() -> Dictionary:
	var x: Dictionary = _fixture({"searcher":"receptionist"})
	HospitalFactory._add_room(x.world,{"id":"small_rest","type":"rest","anchor":[34,66],"size":[8,8],"door":{"definition_id":"DR04","offset":3}},_content)
	_facility(x,"bed","SE04",[35,68],"small_rest")
	_facility(x,"public_chair","FUR09",[44,80])
	x.world.facts.staff.searcher.energy = 35.0
	x.world.touch()
	var geometry: Routes = Routes.new(_content)
	var current: Wellbeing = Wellbeing.new(_content,geometry)
	current.ensure(x.world)
	current._begin(x.world,"searcher","rest")
	var actual: Dictionary = x.world.facts.staff.searcher.life_task
	var no_remote: bool = actual.phase=="area_travel" and actual.facility_id=="" and x.world.facts.staff_life.reservations.is_empty() and current.tea_calls==0
	var before: Dictionary = x.world.freeze()
	var bed: Dictionary = current._select_facility(x.world,"searcher","sleep")
	return {"ok":no_remote and not bed.is_empty() and before==x.world.freeze() and current.occupancy_calls==1,"area_travel_without_global_tea_search":no_remote,"tea_calls_before_arrival":current.tea_calls,"sleep_only_own_bed":bed,"sleep_occupancy_queries":current.occupancy_calls,"sleep_query_readonly":before==x.world.freeze()}

func _status() -> Dictionary:
	var x: Dictionary = _fixture()
	var service: Recruitment = Recruitment.new(_content,x.space)
	var command: CommandResult = service.execute(x.world,"recruitment_search",{"filter":{"role":"cleaner"}})
	var before: Dictionary = x.world.freeze()
	var value: Dictionary = service.search_status(x.world)
	var equal: bool = value==x.world.facts.recruitment.active_search
	if not value.is_empty(): value.remaining_ticks = -1
	return {"ok":command.accepted and equal and before==x.world.freeze() and service.card_calls==0 and service.preview_calls==0,"search_command":command.to_record(),"status_deep_copy":equal and before==x.world.freeze(),"card_calls":service.card_calls,"standard_preview_calls":service.preview_calls}

# Declared completed-unit inputs exercise settlement and idempotency, rather
# than substituting completion for any measured cleaning or movement work.
func _receipts() -> Dictionary:
	var x: Dictionary = _fixture({"cleaner":"cleaner"})
	var records: Dictionary = x.world.facts.environment.receipts
	for index: int in 64:
		var id: String = "consumed_"+str(index)
		records[id] = {"id":id,"kind":"cleanup_completed","staff_id":"cleaner","standard_work_milli":1000,"practice_awarded":true}
	x.r.settle(x.world)
	var before: int = int(x.world.facts.staff.cleaner.job_practice)
	records.unit = {"id":"unit","kind":"cleanup_completed","staff_id":"cleaner","standard_work_milli":1000,"practice_awarded":false}
	x.world.completion_receipt_added("environment","unit")
	x.r.settle(x.world)
	var first: int = int(x.world.facts.staff.cleaner.job_practice)
	x.r.settle(x.world)
	var repeated: int = int(x.world.facts.staff.cleaner.job_practice)
	# The owner can republish the same dictionary identity after a legitimate
	# in-place correction. Its current flag is authoritative, not collection size.
	records.unit.practice_awarded = false
	x.world.completion_receipt_added("environment","unit")
	x.r.settle(x.world)
	var updated: int = int(x.world.facts.staff.cleaner.job_practice)
	var restored: Dictionary = _restore(x)
	restored.r.settle(restored.world)
	var restore_once: bool = int(restored.world.facts.staff.cleaner.job_practice)==updated
	var replacement: Dictionary = records.duplicate(true)
	replacement.unit.practice_awarded = false
	x.world.facts.environment.receipts = replacement
	x.r.settle(x.world)
	var replaced: int = int(x.world.facts.staff.cleaner.job_practice)
	return {"ok":first==before+1 and repeated==first and updated==first+1 and restore_once and replaced==updated+1,"historical_receipts":records.size(),"practice_sequence":[before,first,repeated,updated,replaced],"restored_consumed_history_once":restore_once}

func _occupancy_expected(world: WorldState, facility_id: String, actor_id: String) -> bool:
	for actor: Dictionary in world.facts.actors.values():
		if actor.id!=actor_id and actor.get("support_facility_id","")==facility_id: return true
	for seat: Dictionary in world.facts.waiting_life.seats.values():
		if seat.phase=="seated" and seat.facility_id==facility_id and seat.actor_id!=actor_id: return true
	for need: Dictionary in world.facts.waiting_life.needs.values():
		if need.phase in ["using","returning"] and need.get("facility_id","")==facility_id and world.facts.visits[need.visit_id].actor_id!=actor_id: return true
	for session: Dictionary in world.facts.sessions.values():
		if session.facility_id==facility_id: return true
	return world.facts.staff_life.reservations.has(facility_id)

func _occupancy() -> Dictionary:
	var x: Dictionary = _fixture({"owner":"doctor","other":"nurse"})
	_facility(x,"chair","FUR09",[43,80])
	x.world.facts.actors.owner.support_facility_id = "chair"
	var expected: Array = []
	var actual: Array = []
	x.space.begin_route_query(x.world)
	for id: String in ["owner","other"]:
		expected.append(_occupancy_expected(x.world,"chair",id))
		actual.append(x.l._occupied(x.world,"chair",id))
	x.space.end_route_query()
	var self_free: bool = not actual[0] and actual[1]
	x.world.facts.waiting_life.seats.other = {"facility_id":"chair","actor_id":"other","phase":"local_travel"}
	var unclaimed: bool = not x.l._occupied(x.world,"chair","owner")
	x.world.facts.waiting_life.seats.other.phase = "seated"
	var changed: bool = x.l._occupied(x.world,"chair","owner")
	return {"ok":expected==actual and self_free and unclaimed and changed,"comparisons":actual.size(),"own_reservation_exemption":self_free,"travelling_intent_has_no_occupancy":unclaimed,"next_query_observes_second_owner":changed}

func _base_expected(x: Dictionary, facility_id: String, candidate: String = "") -> Array:
	var result: Array = []
	var base: Dictionary = x.space.facility_layout(x.world,facility_id)
	for id: String in x.world.ids("staff"):
		var staff: Dictionary = x.world.facts.staff[id]
		var task: Dictionary = staff.get("base_task",{})
		if task.get("facility_id","")!=facility_id and id!=candidate: continue
		var commitment: int = 2
		if not HospitalClinicalDevelopment.safe_busy(x.world,id) and staff.get("on_shift",false) and staff.life_task.phase=="idle":
			var movement: Dictionary = x.world.facts.moves.get(id,{})
			if not movement.is_empty() and int(movement.target_floor)==int(base.floor_id) and movement.target_cell==HospitalClinicalDevelopment._operator(base): commitment = 1
			elif task.get("phase","")=="working" and movement.is_empty() and x.space.at(x.world,id,int(base.floor_id),HospitalClinicalDevelopment._operator(base)): commitment = 0
		result.append({"id":id,"queue_tick":x.d._base_order_tick(x.world,staff),"commitment":commitment})
	result.sort_custom(x.d._base_before)
	return result

func _bases() -> Dictionary:
	var x: Dictionary = _fixture({"doctor":"doctor","nurse":"nurse","candidate":"doctor"})
	var definition: String = str(_content.balance.staff_work_bases.doctor_equipment_id)
	HospitalFactory._add_room(x.world,{"id":"base_room","type":"gp","anchor":[34,66],"size":[8,8],"door":{"definition_id":"DR04","offset":3}},_content)
	_facility(x,"base",definition,[35,68],"base_room")
	for id: String in ["doctor","nurse"]:
		x.world.facts.staff[id].base_task = {"facility_id":"base","phase":"travel","queue_tick":0}
		x.world.facts.staff[id].on_shift = true
	x.world.touch()
	var service: Bases = Bases.new(_content,x.space)
	x.d = service
	var query: Dictionary = service._base_view(x.world)
	service._base_batch = query
	var incoming: bool = query.incoming==_incoming_expected(x.world)
	var same: bool = service._base_line(x.world,"base")==_base_expected(x,"base")
	service._base_line(x.world,"base")
	var existing_calls: int = service.entry_calls
	same = same and service._base_line(x.world,"base","candidate")==_base_expected(x,"base","candidate")
	var prior: Array = service._base_signature(x.world,"doctor")
	x.world.facts.staff.doctor.base_task = {}
	service._refresh_base_view(x.world,"doctor",prior)
	same = same and service._base_line(x.world,"base")==_base_expected(x,"base")
	incoming = incoming and query.incoming==_incoming_expected(x.world)
	for phase: String in ["working","travel"]:
		prior = service._base_signature(x.world,"nurse")
		x.world.facts.staff.nurse.base_task.phase = phase
		service._refresh_base_view(x.world,"nurse",prior)
		incoming = incoming and query.incoming==_incoming_expected(x.world)
	prior = service._base_signature(x.world,"nurse")
	x.world.facts.staff.nurse.base_task = {}
	service._refresh_base_view(x.world,"nurse",prior)
	incoming = incoming and query.incoming==_incoming_expected(x.world)
	prior = service._base_signature(x.world,"candidate")
	x.world.facts.staff.candidate.base_task = {"facility_id":"base","phase":"travel","queue_tick":0}
	service._refresh_base_view(x.world,"candidate",prior)
	incoming = incoming and query.incoming==_incoming_expected(x.world) and query.incoming==["candidate"]
	var restored: WorldState = WorldState.new(x.world.freeze())
	var replacement: Dictionary = service._base_context(restored)
	incoming = incoming and replacement.world_id==restored.get_instance_id() and replacement.incoming==_incoming_expected(restored)
	service._base_batch = {}
	return {"ok":same and incoming and existing_calls==2,"independent_queue_equal":same,"incoming_matches_full_scan_through_changes_and_restore":incoming,"entry_calls_two_identical_queries":existing_calls,"entry_calls_with_candidate_and_changed_owner":service.entry_calls}

func _incoming_expected(world: WorldState) -> Array:
	var result: Array = []
	for id: String in world.ids("staff"):
		if world.facts.staff[id].get("base_task",{}).get("phase","")=="travel": result.append(id)
	return result

func _desks_and_busy() -> Dictionary:
	var x: Dictionary = _training_fixture()
	var job: Dictionary = _enroll(x)
	if job.is_empty(): return {"ok":false,"reason":"training command failed"}
	var view: Dictionary = HospitalClinicalDevelopment.desk_view(x.world)
	var free: bool = not HospitalClinicalDevelopment.desk_taken(x.world,"desk",job.id,view)
	var prior: String = str(job.desk_id)
	job.desk_id = "desk"
	HospitalClinicalDevelopment.update_desk_view(view,job,prior)
	var later_sees: bool = HospitalClinicalDevelopment.desk_taken(x.world,"desk","later_job",view) and not HospitalClinicalDevelopment.desk_taken(x.world,"desk",job.id,view)
	var busy: Dictionary = HospitalClinicalDevelopment.busy_view(x.world)
	var current_field: bool = not HospitalClinicalDevelopment.safe_busy(x.world,"doctor",busy)
	x.world.facts.staff.doctor.active_job_id = "actual_operation"
	current_field = current_field and HospitalClinicalDevelopment.safe_busy(x.world,"doctor",busy)
	x.world.facts.staff.doctor.active_job_id = ""
	var restored: WorldState = WorldState.new(x.world.freeze())
	var world_replaced: bool = not HospitalClinicalDevelopment.safe_busy(restored,"doctor",busy)
	return {"ok":free and later_sees and current_field and world_replaced,"own_job_allowed":free,"later_dispatch_sees_new_owner":later_sees,"direct_staff_commitment_reread":current_field,"new_world_rebuild":world_replaced}
