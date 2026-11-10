extends SceneTree

# A legal assignment-calculation boundary. Staff and fixtures are real factory
# records; route/fit/matching code is unchanged. Only trip entry calls are counted.
class CountingSpace extends HospitalSpace:
	var trip_calls: int = 0
	func facility_trip_quote(world: WorldState, facility_id: String, actor_id: String, staff_ids: Array = []) -> Dictionary:
		trip_calls += 1
		return super.facility_trip_quote(world,facility_id,actor_id,staff_ids)

var _content: HospitalContent
var _fixture: RefCounted
var _checks: Dictionary = {}
var _validation: Dictionary = {}

func _initialize() -> void: call_deferred("_run")

func _input(roles: Dictionary = {"candidate":"doctor"}) -> Dictionary:
	var x: Dictionary = _fixture._fixture(roles)
	var room: String = _fixture._room(x)
	_fixture._facility(x,"bed","SE04",[40,70],room)
	var blocker: Dictionary = x.world.facts.actors.candidate.duplicate(true)
	blocker.id = "blocker"
	blocker.location.cell = [40,72]
	x.world.facts.actors["blocker"] = blocker
	var remote: Dictionary = blocker.duplicate(true)
	remote.id = "remote"
	remote.location.cell = [50,80]
	x.world.facts.actors["remote"] = remote
	x.world.touch()
	x.space = CountingSpace.new(_content)
	x.w = HospitalStaffWellbeing.new(_content,x.space)
	return x

func _owner(x: Dictionary) -> String:
	return str(x.world.facts.staff_life.personal_beds.get("bed",{}).get("staff_id",""))

func _validate(x: Dictionary, label: String) -> void:
	var world_error: String = x.world.validate(_content)
	var life_error: String = x.w.validate(x.world)
	_validation[label] = {"world":world_error,"wellbeing":life_error}
	_checks[label+"_valid"] = world_error.is_empty() and life_error.is_empty()

func _run() -> void:
	_content = HospitalContent.new()
	_fixture = load("res://tests/acceptance/staff_fixtures.gd").new()
	_fixture._content = _content
	var x: Dictionary = _input()
	x.w.ensure(x.world)
	_validate(x,"input")
	_checks.initial_local_body_blocks = _owner(x).is_empty()
	var trips: int = x.space.trip_calls
	var scans: int = x.space.query_counts.actor_index_actor_visits
	x.w.ensure(x.world)
	_checks.unchanged_skips_match_and_actor_scan = x.space.trip_calls==trips and x.space.query_counts.actor_index_actor_visits==scans
	_fixture._position(x,"remote",[51,80])
	x.w.ensure(x.world)
	_checks.remote_motion_skips_match_and_actor_scan = x.space.trip_calls==trips and x.space.query_counts.actor_index_actor_visits==scans
	var remote_request: String = x.space.request_move(x.world,"remote",1,[51,81])
	_validate(x,"remote_journey_input")
	x.w.ensure(x.world)
	_checks.remote_journey_does_not_rematch = remote_request.is_empty() and x.space.trip_calls==trips
	x.space.cancel_ground_move(x.world,"remote")
	_fixture._position(x,"remote",[40,72])
	x.w.ensure(x.world)
	_checks.local_entry_rechecks = x.space.trip_calls==trips+1 and _owner(x).is_empty()
	_fixture._position(x,"remote",[51,80])
	_fixture._position(x,"blocker",[44,72])
	var before: Dictionary = x.world.freeze()
	x.w.ensure(x.world)
	var expected: Dictionary = before.duplicate(true)
	expected.staff_life.personal_beds["bed"] = {"staff_id":"candidate"}
	_checks.local_vacancy_assigns_without_execution = _owner(x)=="candidate" and x.world.freeze()==expected
	_validate(x,"local_vacancy_result")

	var y: Dictionary = _input()
	_fixture._position(y,"blocker",[44,72])
	# Sweeps normally expire before wellbeing runs. This calculation-boundary
	# check preserves the full helper contract if a caller observes one in flight.
	y.space.movement._sweep_index.update("blocker",1,Rect2(40,72,1,1))
	y.w.ensure(y.world)
	var sweep_denied: bool = _owner(y).is_empty()
	_validate(y,"sweep_input")
	y.space.movement._sweep_index.expire_boundary()
	y.w.ensure(y.world)
	_checks.sweep_expiry_rechecks = sweep_denied and _owner(y)=="candidate"

	var z: Dictionary = _input()
	_fixture._position(z,"blocker",[44,72])
	_fixture._position(z,"remote",[40,72])
	var reserved: String = z.space.reserve_facility(z.world,"bed","remote","remote")
	z.w.ensure(z.world)
	var reservation_denied: bool = _owner(z).is_empty()
	_validate(z,"reservation_input")
	var move_error: String = z.space.request_move(z.world,"remote",1,[44,74])
	var ticks: int = 0
	while z.world.facts.moves.has("remote") and ticks<120:
		z.space.advance(z.world)
		z.world.facts.sim_tick += 1
		ticks += 1
	z.space.release_adaptations(z.world)
	z.w.ensure(z.world)
	_validate(z,"reservation_exit_result")
	_checks.actual_reservation_exit_rechecks = reserved.is_empty() and move_error.is_empty() and reservation_denied and not z.world.facts.moves.has("remote") and not z.world.facts.adaptations.has("bed") and _owner(z)=="candidate"

	var priority: Dictionary = _input({"candidate":"doctor","second":"nurse"})
	_fixture._position(priority,"second",[54,82])
	priority.w.ensure(priority.world)
	_validate(priority,"priority_input")
	priority.world.facts.staff.second.awake_ticks = 13500
	priority.world.facts.staff.candidate.awake_ticks = 0
	_fixture._position(priority,"blocker",[44,72])
	priority.w.ensure(priority.world)
	_checks.new_opportunity_uses_current_priority = _owner(priority)=="second"
	_validate(priority,"priority_result")

	var structural: Dictionary = _input()
	structural.world.facts.facilities.bed.failed = true
	structural.world.touch()
	structural.w.ensure(structural.world)
	_validate(structural,"unavailable_bed_input")
	trips = structural.space.trip_calls
	_fixture._position(structural,"candidate",[37,92])
	structural.w.ensure(structural.world)
	_checks.no_eligible_bed_ignores_movement = structural.space.trip_calls==trips
	structural.world.facts.facilities.bed.failed = false
	structural.world.touch()
	_fixture._position(structural,"blocker",[44,72])
	structural.w.ensure(structural.world)
	_checks.geometry_change_rebuilds_regions = _owner(structural)=="candidate"

	var incompatible: Dictionary = _input({"candidate":"doctor","giant":"nurse"})
	_fixture._position(incompatible,"giant",[52,82])
	incompatible.world.facts.actors.giant.species_id = "S53"
	incompatible.d.ensure(incompatible.world)
	_fixture._facility(incompatible,"chair","FUR06",[42,73],"support_room")
	incompatible.world.touch()
	incompatible.w.ensure(incompatible.world)
	_validate(incompatible,"incompatible_input")
	var failed_fit: Dictionary = incompatible.space.facility_geometry_quote(incompatible.world,"bed","giant")
	trips = incompatible.space.trip_calls
	var giant_move: String = incompatible.space.request_move(incompatible.world,"giant",1,[53,82])
	incompatible.space.advance(incompatible.world)
	incompatible.w.ensure(incompatible.world)
	_checks.incompatible_remote_motion_does_not_rematch = not failed_fit.ok and giant_move.is_empty() and incompatible.space.trip_calls==trips and _owner(incompatible).is_empty()
	_validate(incompatible,"incompatible_move_result")
	incompatible.space.cancel_ground_move(incompatible.world,"giant")
	# Reopen the static geometry through the real build owner, then create a
	# real vacancy. The former rejection must not suppress this same-boundary
	# opportunity or the now-due giant's original priority.
	var builder: BuildService = BuildService.new(_content,incompatible.space)
	var moved_chair: CommandResult = builder.execute(incompatible.world,"build_move",{"target_id":"chair","floor_id":1,"cell":[54,70]})
	incompatible.world.facts.staff.giant.awake_ticks = 13500
	_fixture._position(incompatible,"blocker",[44,72])
	incompatible.w.ensure(incompatible.world)
	_checks.geometry_recovery_restores_incompatible_subject = moved_chair.accepted and _owner(incompatible)=="giant"
	_validate(incompatible,"incompatible_recovery_result")

	var remodel: Dictionary = _input()
	_fixture._position(remodel,"blocker",[44,72])
	var service: HospitalRemodel = HospitalRemodel.new(_content,remodel.space)
	var prepared: CommandResult = service.execute(remodel.world,"remodel_prepare",{"commands":[{"kind":"build_move","target_id":"bed","floor_id":1,"cell":[40,70]}]})
	remodel.w.ensure(remodel.world)
	var remodel_denied: bool = _owner(remodel).is_empty()
	_validate(remodel,"remodel_input")
	var cancelled: CommandResult = service.execute(remodel.world,"remodel_cancel",{"order_id":prepared.changed_ids[0]})
	remodel.w.ensure(remodel.world)
	_validate(remodel,"remodel_result")
	_checks.remodel_cancel_reopens_assignment = prepared.accepted and remodel_denied and cancelled.accepted and _owner(remodel)=="candidate"

	var connector: Dictionary = _input()
	var plots: Array = HospitalSpace.floor_plots(connector.world,1).duplicate(true)
	connector.world.facts.floors.completed_top_floor = {}
	for plot: Array in plots: connector.world.facts.floors.completed_top_floor[HospitalSpace.plot_key(plot)] = 2
	connector.world.facts.floors.height_intervals = [{"first":1,"last":2,"height_m":float(_content.balance.floors.clear_height_m)}]
	connector.world.facts.floors.overrides["2"] = {"plots":plots,"blocked":[],"doors":[],"paths":[]}
	connector.world.facts.connectors["lift"] = {"id":"lift","definition_id":"VC02","first_floor":1,"last_floor":2,"cell":[58,84],"footprint":[4,4],"rotation":0,"anchor":[59,88],"repair_cell":[57,85],"floor_id":1,"phase":"idle","riders":[],"remaining_ticks":0,"ticket_next":0,"condition":100.0,"failed":false,"pending_failure":false,"use_receipts":{},"paid_cost":3200,"used":false}
	connector.world.touch()
	connector.w.ensure(connector.world)
	_validate(connector,"connector_input")
	trips = connector.space.trip_calls
	connector.world.facts.connectors.lift.remaining_ticks = 10
	connector.world.facts.connectors.lift.ticket_next = 3
	connector.w.ensure(connector.world)
	_validate(connector,"connector_queue_result")
	_checks.connector_queue_counters_do_not_rematch = connector.space.trip_calls==trips
	connector.world.facts.connectors.lift.pending_failure = true
	connector.w.ensure(connector.world)
	_validate(connector,"connector_direction_result")
	_checks.connector_direction_change_rechecks = connector.space.trip_calls==trips+1

	var result: Dictionary = {"passed":not _checks.values().has(false),"checks":_checks,"validation":_validation}
	print(JSON.stringify(result,"\t"))
	var output: String = OS.get_environment("PERSONAL_BED_TEST_OUTPUT")
	if not output.is_empty(): FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	quit(0 if result.passed else 1)
