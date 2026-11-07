extends "res://tests/acceptance/staff_fixtures.gd"

# Passive observations only: all selection, motion, occupancy and cadence remain
# production decisions. Counts assert bounded retry timing, not performance.
class VisitorProbe extends HospitalVisitors:
	var quotes: Array = []
	var arrival_observations: Array = []
	func _public_waiting(world: WorldState, stay: Dictionary) -> bool:
		var intent: Dictionary = stay.public_use
		if not world.facts.moves.has(stay.actor_id):
			if int(intent.arrived_tick)<0 and space.public_areas.contains(world,intent.area,stay.actor_id):
				arrival_observations.append({"kind":"area","tick":world.sim_tick})
			elif intent.phase=="local_travel" and world.facts.facilities.has(intent.facility_id):
				var layout: Dictionary = space.facility_layout(world,intent.facility_id)
				if space.at(world,stay.actor_id,int(layout.floor_id),layout.patient_cell): arrival_observations.append({"kind":"target","tick":world.sim_tick})
		return super._public_waiting(world,stay)
	func _public_seat_quote(world: WorldState, stay: Dictionary, facility_id: String) -> Dictionary:
		var result: Dictionary = super._public_seat_quote(world,stay,facility_id)
		quotes.append({"tick":world.sim_tick,"facility":facility_id,"ok":not result.is_empty()})
		return result

func _tick(x: Dictionary, host_phase: bool = false) -> void:
	x.c.visitors.dispatch(x.world)
	if host_phase: x.l.dispatch(x.world)
	x.space.advance(x.world)
	x.world.facts.sim_tick += 1
	x.world.touch(false)

func run_case(database: HospitalContent, selected: String) -> Dictionary:
	_content = database
	if not selected in ["COMPANION-SEAT-RETRY","VISITOR-SEAT-RETRY"]: return {"ok":false,"error":"unknown case"}
	var x: Dictionary = _fixture()
	var room: String = _room(x,"waiting")
	_facility(x,"occupied_chair","FUR09",[52,72],room)
	x.world.facts.entry = {"floor_id":1,"cell":[38,88],"exit_cell":[38,88]}
	# Pre-operation fixture: host has a normal wait-GP ticket and genuinely
	# walks to its explicit chair. Companion admission is a legal boundary.
	# VISITOR-SEAT-RETRY is only a waiting-purpose semantic probe: direct _admit
	# bypasses normal ward eligibility/current-window checks in arrivals().
	# Its legal_setup assertion means valid facts, not legal ward admission.
	var host: Dictionary = _visit(x,"retry_host",[53,80])
	var request: CommandResult = x.l.execute(x.world,"waiting_select_seat",{"visit_id":host.id,"facility_id":"occupied_chair"})
	var host_seated: bool = false
	for i: int in 600:
		_tick(x,true)
		if HospitalWaitingLife.is_seated(x.world,host.id): host_seated=true;break
	var probe: VisitorProbe = VisitorProbe.new(_content,x.space)
	x.c.visitors = probe
	x.l.visitors = probe
	var purpose: String = "companion" if selected.begins_with("COMPANION") else "ward_visit"
	var admitted: bool = probe._admit(x.world,host,{"purpose":purpose,"window":""})
	var visitor: Dictionary = probe._present(x.world,host.id)
	var checks: Dictionary = {"legal_setup":request.accepted and host_seated and admitted and x.world.validate(_content).is_empty(),"valid_each_step":true,"no_dependency":true,"safe_standing":true}
	if not checks.legal_setup: return {"ok":false,"checks":checks,"validation":x.world.validate(_content)}
	var arrival: int = -1
	var build_tick: int = -1
	var seated_tick: int = -1
	var first_retry: int = -1
	var waiting_quotes: Array = []
	var build_ok: bool = false
	for i: int in 700:
		var tick: int = x.world.sim_tick
		if arrival>=0 and tick>=arrival+110 and build_tick<0 and tick%50==7:
			build_tick=tick
			build_ok=BuildService.new(_content,x.space).execute(x.world,"build_facility",{"id":"new_chair","definition_id":"FUR09","floor_id":1,"cell":[44,72],"room_id":room}).accepted
		var previous: int = probe.quotes.size()
		_tick(x)
		if arrival<0 and int(visitor.public_use.arrived_tick)>=0: arrival=int(visitor.public_use.arrived_tick)
		for row: Dictionary in probe.quotes.slice(previous):
			if build_tick<0: waiting_quotes.append(row)
			elif row.facility=="new_chair" and first_retry<0: first_retry=int(row.tick)
		checks.valid_each_step=checks.valid_each_step and x.world.validate(_content).is_empty()
		var id: String = visitor.public_use.id
		checks.no_dependency=checks.no_dependency and not x.space.public_areas._wait_results.has(id) and not x.space.public_areas._wait_dependencies.waiters.has(id)
		if visitor.public_use.phase=="local_wait" and not x.world.facts.moves.has(visitor.actor_id):
			var actor: Dictionary=x.world.facts.actors[visitor.actor_id]
			checks.safe_standing=checks.safe_standing and actor.posture=="standing" and x.space.public_areas.safe_wait(x.world,actor.id,int(actor.location.floor_id),actor.location.cell)
		if visitor.public_use.phase=="seated": seated_tick=tick;break
	var ticks: Array = []
	for row: Dictionary in waiting_quotes: ticks.append(row.tick)
	var expected: Array = []
	if arrival>=0 and build_tick>=0:
		expected.append(arrival)
		for tick: int in range(arrival+1,build_tick):
			if tick%50==0: expected.append(tick)
	checks.exact_wait_scan_boundaries=ticks==expected and ticks.size()>=3
	checks.immediate_first_area=arrival>=0 and arrival%50!=0 and not probe.arrival_observations.is_empty() and probe.arrival_observations[0].tick==arrival and ticks.has(arrival)
	checks.available_chair_recovers_on_scan=build_ok and first_retry==build_tick+(50-build_tick%50)
	var target_tick: int = -1
	for row: Dictionary in probe.arrival_observations:
		if row.kind=="target": target_tick=int(row.tick)
	checks.immediate_actual_target=target_tick>=0 and target_tick%50!=0 and seated_tick==target_tick
	checks.actual_owner=seated_tick>=0 and x.world.facts.adaptations.get("new_chair",{}).get("actor_id","")==visitor.actor_id and x.space.at(x.world,visitor.actor_id,1,x.space.facility_layout(x.world,"new_chair").patient_cell)
	checks.arrival_preserved=int(visitor.public_use.arrived_tick)==arrival
	var result: Dictionary={"ok":checks.values().all(func(v:Variant)->bool:return bool(v)),"case":selected,"checks":checks,"arrival":arrival,"build_tick":build_tick,"first_retry":first_retry,"target_tick":target_tick,"seated_tick":seated_tick,"wait_quote_ticks":ticks,"expected_ticks":expected,"quotes":probe.quotes,"arrivals":probe.arrival_observations,"validation":x.world.validate(_content),"tick_seconds":WorldState.TICK_SECONDS,"purpose":purpose}
	x.a.dispose();x.p.waiting_life=null;x.p.environment=null;x.l.environment=null;x.l.visitors=null;x.c.recruitment=null
	return result
