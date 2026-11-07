extends "res://tests/acceptance/visitor_seat_retry.gd"
class AreaProbe extends HospitalPublicAreas:
	var selected_ticks: Array = []
	func select(world: WorldState, actor_id: String, definitions: Array, room_kinds: Array, purpose: String, members: Array = [], maximum_travel_ticks: int = 9223372036854775807, selected_entries: Dictionary = {}, current_floor_only: bool = false) -> Dictionary:
		selected_ticks.append(world.sim_tick)
		return super.select(world,actor_id,definitions,room_kinds,purpose,members,maximum_travel_ticks,selected_entries,current_floor_only)

func run_no_area(database: HospitalContent) -> Dictionary:
	_content=database
	var x: Dictionary=_fixture()
	var room: String=_room(x,"waiting")
	_facility(x,"initial_chair","FUR09",[52,72],room)
	x.world.facts.entry={"floor_id":1,"cell":[38,88],"exit_cell":[38,88]}
	# Legal pre-operation input: ordinary queued host and admitted companion.
	# Remove the unused chair via its real build operation before dispatch.
	var host: Dictionary=_visit(x,"no_area_host",[53,80])
	var visitor_probe: VisitorProbe=VisitorProbe.new(_content,x.space)
	x.c.visitors=visitor_probe
	x.l.visitors=visitor_probe
	var admitted: bool=x.c.visitors._admit(x.world,host,{"purpose":"companion","window":""})
	var visitor: Dictionary=x.c.visitors._present(x.world,host.id)
	var admitted_area: Dictionary=visitor.public_use.area.duplicate(true)
	var removed: bool=BuildService.new(_content,x.space).execute(x.world,"build_demolish",{"target_id":"initial_chair"}).accepted
	var probe: AreaProbe=AreaProbe.new(x.space)
	x.space.public_areas=probe
	var checks: Dictionary={"legal_setup":admitted and removed and x.world.validate(_content).is_empty(),"valid_each_step":true,"no_subscription":true,"standing_area_retained":true,"no_walking_reservation":true}
	var built: bool=false
	var claim: int=-1
	for i: int in 400:
		if x.world.sim_tick==107:
			built=BuildService.new(_content,x.space).execute(x.world,"build_facility",{"id":"recovery_chair","definition_id":"FUR09","floor_id":1,"cell":[44,72],"room_id":room}).accepted
		_tick(x)
		checks.standing_area_retained=checks.standing_area_retained and visitor.public_use.area==admitted_area
		if visitor.public_use.phase!="seated": checks.no_walking_reservation=checks.no_walking_reservation and x.world.facts.adaptations.is_empty()
		checks.valid_each_step=checks.valid_each_step and x.world.validate(_content).is_empty()
		checks.no_subscription=checks.no_subscription and not probe._wait_results.has(visitor.public_use.id) and not probe._wait_dependencies.waiters.has(visitor.public_use.id)
		if visitor.public_use.phase=="seated": claim=x.world.sim_tick;break
	# At tick150 the new chair belongs to the retained standing area, so the
	# real retry is local: no redundant global region selection is required.
	checks.exact_region_retry=probe.selected_ticks==[0,50,100]
	checks.local_retry_after_build=not visitor_probe.quotes.is_empty() and visitor_probe.quotes[0].tick==150 and visitor_probe.quotes[0].facility=="recovery_chair" and visitor_probe.quotes[0].ok
	checks.actual_owner=claim>150 and x.world.facts.adaptations.get("recovery_chair",{}).get("actor_id","")==visitor.actor_id and x.space.at(x.world,visitor.actor_id,1,x.space.facility_layout(x.world,"recovery_chair").patient_cell)
	checks.recovered=built and claim>150 and visitor.public_use.facility_id=="recovery_chair"
	var result: Dictionary={"ok":checks.values().all(func(v:Variant)->bool:return bool(v)),"case":"VISITOR-NO-AREA-RETRY","checks":checks,"selected_ticks":probe.selected_ticks,"claim_tick":claim,"local_quotes":visitor_probe.quotes,"admitted_area":admitted_area,"tick_seconds":WorldState.TICK_SECONDS,"validation":x.world.validate(_content)}
	x.a.dispose();x.p.waiting_life=null;x.p.environment=null;x.l.environment=null;x.l.visitors=null;x.c.recruitment=null
	return result
