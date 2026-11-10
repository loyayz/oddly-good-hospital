extends SceneTree

# Local-query contract tests use full production geometry/index/movement. The
# reference enumerates current facts, independently of the index under test.
class CountingSpace extends HospitalSpace:
	var body_reads: int = 0
	func body_rectangle(actor: Dictionary) -> Rect2:
		body_reads += 1
		return super.body_rectangle(actor)

var content: HospitalContent
var staff_suite: RefCounted
var space_suite: RefCounted
var checks: Dictionary = {}
var details: Dictionary = {}

func _initialize() -> void: call_deferred("_run")

func _full(space: HospitalSpace, world: WorldState, floor_id: int, rect: Rect2, ignored: String = "") -> bool:
	for actor: Dictionary in world.facts.actors.values():
		if actor.id!=ignored and actor.location.kind=="floor" and int(actor.location.floor_id)==floor_id and rect.intersects(space.body_rectangle(actor),false): return true
	return false

func _entry_full(space: HospitalSpace, world: WorldState, candidate: Dictionary) -> Dictionary:
	var entry: Dictionary = world.facts.get("entry",{"anchor":[47,93],"size":[3,3]})
	var anchor: Array = entry.get("cell",entry.get("anchor",[47,93]))
	var size: Array = entry.get("size",[3,3])
	var actor: Dictionary = space_suite._actor("candidate_preview",candidate.species_id,anchor)
	for y: int in range(int(anchor[1]),int(anchor[1])+int(size[1])):
		for x: int in range(int(anchor[0]),int(anchor[0])+int(size[0])):
			if not space.static_reason(world,actor,1,Vector2i(x,y)).is_empty(): continue
			actor.location.cell = [x,y]
			if not _full(space,world,1,space.body_rectangle(actor)): return {"ok":true,"floor_id":1,"cell":[x,y]}
	return {"ok":false,"reason":"1F入口缺少支持该真实身体的合法空位"}

func _same(space: HospitalSpace, world: WorldState, floor_id: int, rect: Rect2, ignored: String = "") -> bool:
	return space.intersects_actor_body(world,floor_id,rect,ignored)==_full(space,world,floor_id,rect,ignored)

func _boundaries() -> void:
	var sim: HospitalSimulation = space_suite._transit_fixture()
	var w: WorldState = sim.world
	space_suite._add_actor(sim,"subject","S49",[48,90])
	space_suite._add_actor(sim,"other_floor","S49",[48,90],2)
	space_suite._add_actor(sim,"outside","S49",[48,90])
	w.facts.actors.outside.location = {"kind":"outside"}
	sim.space.sync_actor(w,"outside")
	checks.boundary_input_valid = w.validate(content).is_empty()
	var actor: Dictionary = w.facts.actors.subject
	var rect: Rect2 = sim.space.body_rectangle(actor)
	var edge: Rect2 = Rect2(rect.end,Vector2.ONE)
	checks.touching_clear = not sim.space.intersects_actor_body(w,1,edge)
	edge.position -= Vector2.ONE*0.0001
	checks.subcell_overlap_blocks = sim.space.intersects_actor_body(w,1,edge)
	checks.own_body_ignored = not sim.space.intersects_actor_body(w,1,rect,"subject")
	checks.other_floor_distinct = sim.space.intersects_actor_body(w,2,rect) and not sim.space.intersects_actor_body(w,3,rect)
	space_suite._add_actor(sim,"candidate_preview","S49",[47,93])
	var recruitment: RecruitmentService = RecruitmentService.new(content,sim.space)
	checks.recruitment_does_not_ignore_preview_id = recruitment._entry(w,{"species_id":"S49"})=={"ok":true,"floor_id":1,"cell":[48,93]}
	w.facts.actors.candidate_preview.location = {"kind":"outside"}
	sim.space.sync_actor(w,"candidate_preview")
	var initial: Dictionary = w.freeze()
	var matrix: bool = true
	var count: int = 0
	# Raw-body calculation boundary: these posture/facing combinations test the
	# exact geometry contract, not an executed clinical support/bed transition.
	for species: Dictionary in content.catalog.species:
		actor.species_id = species.id
		for posture: String in ["standing","seated","lying"]:
			actor.posture = posture
			for heading: float in [0.0,PI*0.25,PI*0.5,PI]:
				actor.facing = heading
				sim.space.sync_actor(w,"subject")
				rect = sim.space.body_rectangle(actor)
				for probe: Rect2 in [rect,Rect2(rect.end,Vector2.ONE),Rect2(rect.position-Vector2(0.0001,0),rect.size),Rect2(47,93,1,1)]:
					matrix = _same(sim.space,w,1,probe) and _same(sim.space,w,1,probe,"subject") and matrix
					count += 2
	checks.body_size_posture_heading_matrix = matrix
	details.geometry_comparisons = count
	var binding_checks: int = 0
	var binding_equal: bool = true
	actor.posture = "standing"
	actor.facing = 0.0
	for binding: Dictionary in content.catalog.treatment_bindings:
		if binding.get("symptom_envelope",{}).is_empty(): continue
		actor.species_id = binding.species_id
		actor.body_binding_id = binding.id
		sim.space.sync_actor(w,"subject")
		rect = sim.space.body_rectangle(actor)
		binding_equal = _same(sim.space,w,1,rect) and binding_equal
		actor.erase("body_binding_id")
		sim.space.sync_actor(w,"subject")
		binding_equal = _same(sim.space,w,1,rect) and _same(sim.space,w,1,Rect2(rect.end-Vector2.ONE*0.0001,Vector2.ONE)) and binding_equal
		binding_checks += 3
	checks.body_binding_publish_and_clear = binding_equal and binding_checks>0
	details.binding_comparisons = binding_checks
	# Exact facts identity, not numeric revision, owns the cached index.
	w.facts = initial.duplicate(true)
	w.facts.actors.subject.location.cell = [50,90]
	checks.facts_replacement = _same(sim.space,w,1,Rect2(48,90,1,1)) and not sim.space.intersects_actor_body(w,1,Rect2(48,90,1,1)) and sim.space.intersects_actor_body(w,1,Rect2(50,90,1,1))
	var copied: WorldState = WorldState.new(initial.duplicate(true))
	checks.new_world_owner = sim.space.intersects_actor_body(copied,1,Rect2(48,90,1,1)) and not sim.space.intersects_actor_body(w,1,Rect2(48,90,1,1))
	checks.final_boundary_valid = w.validate(content).is_empty()
	sim.dispose()

func _recruitment() -> void:
	var x: Dictionary = staff_suite._fixture()
	var filter: Dictionary = {"role":"nurse"}
	var cash: int = HospitalLedger.balance(x.world)
	var hired_ids: Array[String] = []
	var accepted: bool = true
	var locations: Array = []
	# Fill the actual 3x3 entry through paid recruitment, not fixture teleports.
	for n: int in 9:
		var card: Dictionary = x.r.standard_preview(x.world,filter)
		var before: Dictionary = x.world.freeze()
		accepted = card.entry==_entry_full(x.space,x.world,card) and before==x.world.freeze() and accepted
		var hired: CommandResult = x.r.execute(x.world,"recruitment_hire",staff_suite._hire_payload(card,filter))
		accepted = hired.accepted and accepted
		if not hired.accepted: break
		var id: String = "staff_"+str(card.id)
		hired_ids.append(id)
		locations.append(x.world.facts.actors[id].location.cell.duplicate())
	checks.nine_actual_hires_distinct = accepted and hired_ids.size()==9 and locations==[[47,93],[48,93],[49,93],[47,94],[48,94],[49,94],[47,95],[48,95],[49,95]]
	var blocked: Dictionary = x.r.standard_preview(x.world,filter)
	var before: Dictionary = x.world.freeze()
	var rejected: CommandResult = x.r.execute(x.world,"recruitment_hire",staff_suite._hire_payload(blocked,filter))
	checks.full_entry_failure_atomic = not blocked.entry.ok and not rejected.accepted and rejected.code=="entry_blocked" and before==x.world.freeze() and HospitalLedger.balance(x.world)==cash-9*200
	for service: String in ["d","s","w","l","c","f","e","p","m","a"]: x[service].ensure(x.world)
	var valid: String = x.world.validate(content)
	checks.recruited_world_valid = valid.is_empty()
	details.recruited_validation = valid
	if not hired_ids.is_empty():
		var reason: String = x.space.request_move(x.world,hired_ids[0],1,[44,91])
		var vacated: bool = false
		for tick: int in 150:
			x.space.advance(x.world)
			x.world.facts.sim_tick += 1
			x.world.touch(false)
			x.space.finish_boundary(x.world)
			var next: Dictionary = x.r.standard_preview(x.world,filter)
			if next.entry.ok:
				vacated = next.entry.cell==[47,93] and next.entry==_entry_full(x.space,x.world,next)
				var hire: CommandResult = x.r.execute(x.world,"recruitment_hire",staff_suite._hire_payload(next,filter))
				vacated = vacated and hire.accepted
				break
		checks.real_movement_frees_first_entry = reason.is_empty() and vacated
		for service: String in ["d","s","w","l","c","f","e","p","m","a"]: x[service].ensure(x.world)
		checks.recruitment_final_valid = x.world.validate(content).is_empty()
	# Current species dimensions participate in complete row-major selection.
	var species_equal: bool = true
	for species: Dictionary in content.catalog.species:
		var candidate: Dictionary = {"species_id":species.id}
		species_equal = x.r._entry(x.world,candidate)==_entry_full(x.space,x.world,candidate) and species_equal
	checks.recruitment_all_species_reference = species_equal
	x.a.dispose()

func _convoys() -> void:
	var sim: HospitalSimulation = space_suite._transit_fixture()
	var w: WorldState = sim.world
	space_suite._add_actor(sim,"leader","S49",[36,84])
	space_suite._add_actor(sim,"follower","S49",[36,86])
	var reason: String = sim.space.request_group_move(w,"leader",["leader","follower"],{},2,[44,82])
	checks.convoy_requested = reason.is_empty()
	checks.convoy_input_valid = w.validate(content).is_empty()
	var gap: Rect2 = Rect2(36.4,85.4,0.2,0.2)
	checks.convoy_corridor_gap_clear = sim.space._actor_index.intersects(1,gap,"") and not sim.space.intersects_actor_body(w,1,gap)
	var follower: Rect2 = sim.space.body_rectangle(w.facts.actors.follower)
	checks.ignore_leader_keeps_follower = sim.space.intersects_actor_body(w,1,follower,"leader") and not sim.space.intersects_actor_body(w,1,follower,"follower")
	var equal: bool = true
	var valid: bool = true
	var phases: Dictionary = {}
	var checks_count: int = 0
	var steps: int = 0
	for tick: int in 1000:
		space_suite._movement_tick(sim)
		steps += 1
		valid = w.validate(content).is_empty() and valid
		for id: String in ["leader","follower"]:
			var actor: Dictionary = w.facts.actors[id]
			var preview: Dictionary = actor.duplicate(true)
			if actor.location.kind=="transit":
				var connection: Dictionary = w.facts.connectors[actor.location.connector_id]
				phases[connection.phase] = true
				preview.location = {"kind":"floor","floor_id":connection.to,"cell":actor.location.queue_cell}
			var body: Rect2 = sim.space.body_rectangle(preview)
			for floor_id: int in [1,2]:
				for ignored: String in ["","leader","follower"]:
					equal = _same(sim.space,w,floor_id,body,ignored) and equal
					checks_count += 1
		if not w.facts.moves.has("leader"): break
	checks.real_convoy_turns_and_transit_match = equal and valid and phases.has("boarding") and phases.has("riding") and phases.has("alighting") and not w.facts.moves.has("leader") and w.facts.actors.leader.location.floor_id==2
	checks.convoy_dissolved_to_raw_bodies = sim.space._convoy_members.is_empty() and sim.space.intersects_actor_body(w,2,sim.space.body_rectangle(w.facts.actors.follower),"leader")
	details.convoy = {"steps":steps,"comparisons":checks_count,"phases":phases,"validation":w.validate(content)}
	sim.dispose()

func _returners() -> void:
	var handoff: RefCounted = load("res://tests/acceptance/staff_return_handoff.gd").new()
	handoff._content = content
	var x: Dictionary = handoff._fixture({"first":"nurse","second":"nurse"})
	var requests: bool = true
	for id: String in ["first","second"]:
		requests = x.s.execute(x.world,"plan_leave",{"staff_id":id,"days":1,"start":"now"}).accepted and requests
	var departed: bool = false
	for tick: int in 1000:
		handoff._tick(x)
		if x.world.facts.staff.first.life_task.phase=="offsite" and x.world.facts.staff.second.life_task.phase=="offsite":
			departed = true
			break
	checks.two_real_departures = requests and departed and x.world.validate(content).is_empty()
	for id: String in ["first","second"]:
		requests = x.s.execute(x.world,"cancel_leave",{"staff_id":id}).accepted and requests
	var revision: int = x.world.revision
	x.w._return_from_outside(x.world,"first")
	x.w._return_from_outside(x.world,"second")
	checks.same_revision_second_return_waits = requests and x.world.revision==revision and x.world.facts.actors.first.location.kind=="floor" and x.world.facts.actors.second.location.kind=="outside" and x.world.facts.staff.second.life_reason=="返院入口正被使用，等待实际空位"
	var restored: Dictionary = handoff._restore(x)
	x.a.dispose()
	x = restored
	var all_valid: bool = x.world.validate(content).is_empty()
	var recovered: bool = false
	for tick: int in 1000:
		handoff._tick(x)
		all_valid = x.world.validate(content).is_empty() and not handoff._overlap(x) and all_valid
		if x.world.facts.staff.first.life_task.phase=="idle" and x.world.facts.staff.second.life_task.phase=="idle":
			recovered = true
			break
	checks.both_reenter_after_real_vacancy_restore = recovered and all_valid and x.world.facts.actors.first.location.kind=="floor" and x.world.facts.actors.second.location.kind=="floor"
	x.a.dispose()

func _non_body_occupancy() -> void:
	var x: Dictionary = staff_suite._fixture({"owner":"nurse"})
	var room: String = staff_suite._room(x)
	staff_suite._facility(x,"bed","SE04",[40,70],room)
	var reason: String = x.space.reserve_facility(x.world,"bed","owner","owner")
	var regions: Array = x.world.facts.adaptations.get("bed",{}).get("regions",[])
	var valid: bool = reason.is_empty() and not regions.is_empty() and x.world.validate(content).is_empty()
	var all_clear: bool = valid
	for raw: Array in regions:
		var rect: Rect2 = Rect2(float(raw[0]),float(raw[1]),float(raw[2]),float(raw[3]))
		x.space.movement._sweep_index.update("sweeper",1,rect)
		all_clear = not x.space.intersects_actor_body(x.world,1,rect) and _same(x.space,x.world,1,rect) and all_clear
	checks.reservations_and_sweeps_not_bodies = all_clear
	x.a.dispose()

func _guidance_publication() -> void:
	var suite: RefCounted = load("res://tests/acceptance/floor_guidance.gd").new()
	suite._content = content
	var x: Dictionary = suite._base()
	var visit: Dictionary = suite._visit(x,"oriented_queue",[40,88])
	var actor: Dictionary = x.world.facts.actors[visit.actor_id]
	var binding: Dictionary = content.definition("treatment_bindings","B_S03_D23_M23")
	actor.species_id = binding.species_id
	actor.body_binding_id = binding.id
	visit.binding_id = binding.id
	visit.disease_id = binding.disease_id
	visit.requested_plan_id = "P_"+str(binding.disease_id)+"_COMMON"
	x.space.sync_actor(x.world,actor.id)
	var valid: bool = x.world.validate(content).is_empty()
	var changed_at_arrival: bool = false
	var probes_match: bool = true
	var probes: int = 0
	var ticks: int = 0
	for tick: int in 800:
		x.space._ensure_actor_index(x.world)
		var old: Rect2 = x.space._actor_index.rectangle(actor.id)
		var heading: float = actor.facing
		x.g.dispatch(x.world)
		x.l.dispatch(x.world)
		x.c.dispatch(x.world)
		valid = x.world.validate(content).is_empty() and valid
		if heading!=float(actor.facing):
			var rect: Rect2 = x.space.body_rectangle(actor)
			var row: Dictionary = x.g.state(x.world,visit.id)
			changed_at_arrival = old!=rect and row.has("queue_seq") and int(row.queue_arrived_tick)==x.world.sim_tick and row.queue_cell==actor.location.cell
			probes_match = x.space._actor_index.rectangle(actor.id)==rect
			# Test the rotation's newly occupied strips before any later movement,
			# revision change or cold rebuild can hide a missed publication.
			for ix: int in 21:
				for iy: int in 21:
					var point: Vector2 = rect.position+rect.size*Vector2((ix+0.5)/21.0,(iy+0.5)/21.0)
					var probe: Rect2 = Rect2(point,Vector2.ONE*0.0001)
					probes_match = x.space.intersects_actor_body(x.world,1,probe) and _same(x.space,x.world,1,probe) and probes_match
					probes += 1
			break
		x.space.advance(x.world)
		x.g.advance(x.world)
		x.l.advance(x.world)
		x.world.facts.sim_tick += 1
		x.world.touch(false)
		x.space.finish_boundary(x.world)
		ticks += 1
	checks.real_guidance_turn_publishes_body = changed_at_arrival and probes_match and valid
	details.guidance = {"ticks":ticks,"probes":probes,"actual_arrival_turn":changed_at_arrival,"body_current":probes_match,"valid":valid}
	suite._dispose(x)

func _work_count() -> void:
	var w: WorldState = HospitalFactory.create("entry-body-fixed-load","入口固定工作量",false,content)
	for n: int in 320:
		var id: String = "remote_%03d"%n
		w.facts.actors[id] = space_suite._actor(id,"S49",[34+(n%20)*1.2,66+(n/20)*1.2])
	var space: CountingSpace = CountingSpace.new(content)
	var recruitment: RecruitmentService = RecruitmentService.new(content,space)
	var candidate: Dictionary = {"species_id":"S49"}
	var cold: Dictionary = recruitment._entry(w,candidate)
	var visits: int = space.query_counts.actor_index_actor_visits
	var before: Dictionary = w.freeze()
	space.body_reads = 0
	var started: int = Time.get_ticks_usec()
	for n: int in 100: recruitment._entry(w,candidate)
	var local_us: int = Time.get_ticks_usec()-started
	var local_reads: int = space.body_reads
	var no_scans: bool = space.query_counts.actor_index_actor_visits==visits
	space.body_reads = 0
	started = Time.get_ticks_usec()
	var reference: Dictionary
	for n: int in 100: reference = _entry_full(space,w,candidate)
	var full_us: int = Time.get_ticks_usec()-started
	checks.hot_entry_no_full_actor_work = cold==reference and local_reads==100 and space.body_reads==32100 and no_scans and before==w.freeze() and w.validate(content).is_empty()
	details.fixed_load = {"actors":320,"queries":100,"local_body_reads":local_reads,"full_body_reads":space.body_reads,"warm_index_rebuilds":space.query_counts.actor_index_actor_visits-visits,"local_us":local_us,"full_us":full_us,"result":cold}

func _run() -> void:
	content = HospitalContent.new()
	staff_suite = load("res://tests/acceptance/staff.gd").new()
	staff_suite._content = content
	space_suite = load("res://tests/acceptance/space.gd").new()
	space_suite.content = content
	_boundaries()
	_recruitment()
	_convoys()
	_returners()
	_non_body_occupancy()
	_guidance_publication()
	_work_count()
	var ok: bool = checks.values().all(func(value: Variant)->bool:return bool(value))
	var result: Dictionary = {"ok":ok,"checks":checks,"details":details,"engine":Engine.get_version_info().string,"scope":"Entry-body lookup, actual recruitment and real convoy movement; not full-game performance or GUI acceptance"}
	print(JSON.stringify(result,"  "))
	var output: String = OS.get_environment("ENTRY_BODY_TEST_OUTPUT")
	if not output.is_empty(): FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	quit(0 if ok else 1)
