extends "res://tests/acceptance/staff_fixtures.gd"

class MutationWaiting extends HospitalWaitingLife:
	var force_refresh: bool=false
	var mutate: bool=false
	var selections: int=0
	func _dispatch_public_need(world: WorldState, visit: Dictionary, need: Dictionary, need_scan: Dictionary = {}) -> void:
		super._dispatch_public_need(world,visit,need,{} if force_refresh else need_scan)
		selections+=1
		if mutate and selections==1:
			var actor: Dictionary=world.facts.actors[world.facts.visits["due_01"].actor_id]
			actor.location.cell[0]+=0.25
			space.sync_actor(world,actor.id)

class OriginalPrewarm extends MutationWaiting:
	func _dispatch_waiting(world: WorldState) -> void:
		_prepare_need_costs(world)
		super._dispatch_waiting(world)
	func _prepare_need_costs(world: WorldState) -> void:
		var actors: Array = []
		for visit_id: String in world.active_visit_ids():
			var visit: Dictionary = world.facts.visits[visit_id]
			if not _waiting(world,visit) or world.facts.moves.has(visit.actor_id): continue
			if world.facts.waiting_life.needs.has(visit_id): continue
			var ticket: Dictionary = world.facts.tickets[visit.ticket_id]
			if ticket.get("service_assigned",false) and int(ticket.get("called_tick",-1))>=0: continue
			if world.sim_tick<int(world.facts.waiting_life.clocks[visit_id].next_need_tick): continue
			if floor_guidance!=null and floor_guidance.working(world,visit_id): continue
			actors.append(str(visit.actor_id))
		if actors.is_empty(): return
		space.begin_dynamic_route_query(world)
		space._navigation.prepare_structural_fields(space,world,actors)
		space.end_route_query()

func run(database: HospitalContent, mutate: bool = false) -> Dictionary:
	_content = database
	var x: Dictionary = _fixture()
	HospitalFactory._add_room(x.world,{"id":"waiting","type":"waiting","anchor":[34,66],"size":[10,12],"door":{"definition_id":"DR04","offset":3}},_content)
	_facility(x,"toilet","FUR07",[39,68],"waiting")
	for index: int in 12:
		var visit: Dictionary = _visit(x,"due_%02d" % index,[34+(index%4)*4,82+(index/4)*4])
		x.world.register_visit(str(visit.id))
	var later: Dictionary = _visit(x,"not_due",[50,92])
	later.arrival_tick=1; later.arrived_tick=1
	x.world.facts.waiting_life.clocks[later.id].next_need_tick=1801
	var moving: Dictionary = _visit(x,"moving",[54,92])
	# Legal input boundary immediately before the first 180-second need.
	x.world.facts.sim_tick = 1800
	for visit: Dictionary in x.world.facts.visits.values(): x.world.facts.tickets[visit.ticket_id].waited_ticks=1800-int(visit.arrival_tick)
	var move_reason: String = x.space.request_move(x.world,moving.actor_id,1,[55,92])
	x.world.touch()
	x.space.begin_dynamic_route_query(x.world);x.space.end_route_query()
	# Deliberate raw change before dispatch must be absorbed by its first refresh.
	if mutate: x.world.facts.actors[x.world.facts.visits["due_00"].actor_id].location.cell[0]+=0.25
	var validation: String = x.world.validate(_content)
	var before: Dictionary = x.world.freeze()
	var original: Dictionary = _bind(WorldState.new(before.duplicate(true)))
	var serial: OriginalPrewarm = OriginalPrewarm.new(_content,original.space)
	serial.force_refresh=true;serial.mutate=mutate
	var batched: MutationWaiting=MutationWaiting.new(_content,x.space)
	batched.mutate=mutate
	batched.environment=x.e;batched.visitors=x.c.visitors
	x.l=batched;x.p.waiting_life=batched
	serial.environment=original.e; serial.visitors=original.c.visitors
	original.l=serial; original.p.waiting_life=serial
	x.l.dispatch(x.world)
	serial.dispatch(original.world)
	var travelling: bool = x.world.facts.waiting_life.needs.size()==12 and x.world.facts.adaptations.is_empty()
	for visit: Dictionary in x.world.facts.visits.values():
		if not str(visit.id).begins_with("due_"): continue
		var need: Dictionary = x.world.facts.waiting_life.needs.get(visit.id,{})
		travelling = travelling and need.get("phase","")=="area_travel" and x.world.facts.moves.has(visit.actor_id) and (mutate and str(visit.id)=="due_01" or x.world.facts.actors[visit.actor_id].location==before.actors[visit.actor_id].location) and int(x.world.facts.tickets[visit.ticket_id].waited_ticks)==1800
	var same: bool = x.world.freeze()==original.world.freeze()
	var used: bool = int(x.space.query_counts.get("native_field_batches",0))==0 and int(original.space.query_counts.get("native_field_batches",0))==1 and int(original.space.query_counts.get("native_field_requests",0))==12
	var avoided: bool = int(x.space.query_counts.get("native_field_requests",0))==0
	var after_validation: String = x.world.validate(_content)
	var excluded: bool = move_reason.is_empty() and not x.world.facts.waiting_life.needs.has(later.id) and not x.world.facts.waiting_life.needs.has(moving.id)
	var details: Dictionary = {"batch_actor_index_builds":x.space.query_counts.actor_index_builds,"forced_actor_index_builds":original.space.query_counts.actor_index_builds,"input_validation":validation,"output_validation":after_validation,"due_visits":12,"old_preparation_reference_executed":used,"new_dispatch_avoids_whole_fields":avoided,"new_field_requests":x.space.query_counts.get("native_field_requests",0),"old_field_requests":original.space.query_counts.get("native_field_requests",0),"travel_without_early_reservation_or_position_commit":travelling,"not_due_and_existing_move_excluded":excluded,"facts_rng_ids_tickets_equal_to_serial_preparation":same,"threads_used":x.space.query_counts.get("native_field_threads",0)}
	var closed: bool=x.space._route_queries.is_empty() and original.space._route_queries.is_empty() and x.space._indexed_actor_scope.is_empty() and original.space._indexed_actor_scope.is_empty()
	details.scopes_closed=closed
	details.injected_raw_and_synchronized_body_changes=mutate
	for row: Dictionary in [x,original]:
		row.a.dispose(); row.p.waiting_life=null; row.p.environment=null; row.l.environment=null; row.l.visitors=null; row.e.waiting_life=null; row.c.recruitment=null
	return {"ok":validation.is_empty() and after_validation.is_empty() and travelling and same and used and avoided and excluded and closed,"details":details}
