extends "res://tests/acceptance/growth_fixtures.gd"

class ObservedClinic extends HospitalClinic:
	var reused: int = 0
	var changed: int = 0
	func _reference_routing_unchanged(world: WorldState, layout: Dictionary, fit: Dictionary) -> bool:
		var result: bool = super._reference_routing_unchanged(world,layout,fit)
		if result: reused += 1
		else: changed += 1
		return result

class ReservedClinic extends HospitalClinic:
	func _reference_routing_unchanged(_world: WorldState, _layout: Dictionary, _fit: Dictionary) -> bool:
		return false

func run_case(t, database: HospitalContent) -> void:
	_content = database
	var ctx: Dictionary = _context()
	var nominal: WorldState = ctx.arrivals._capacity_reference_world(ctx.world)
	var actual: ObservedClinic = ObservedClinic.new(_content,HospitalSpace.new(_content))
	var reserved: ReservedClinic = ReservedClinic.new(_content,HospitalSpace.new(_content))
	var before: Dictionary = nominal.freeze()
	var equal: bool = true
	var observations: Array = []
	var nonempty: int = 0
	for binding: String in ["B_S13_D09_M09","B_S49_D37_M37","B_S22_D14_M14"]:
		var candidate: Dictionary = actual._arrival_candidate(nominal,binding,false)
		if not candidate.ok:
			equal = false
			continue
		var facts: Dictionary = candidate.world.freeze()
		for kind: String in ["reception","gp","consult","outpatient","spectrum","resonance"]:
			actual.space.begin_route_query(candidate.world,{"nominal":true})
			var first: Array = actual.service_candidates(candidate.world,candidate.visit,kind,true,true)
			var warm: Array = actual.service_candidates(candidate.world,candidate.visit,kind,true,true)
			actual.space.end_route_query()
			reserved.space.begin_route_query(candidate.world,{"nominal":true})
			var independent: Array = reserved.service_candidates(candidate.world,candidate.visit,kind,true,true)
			reserved.space.end_route_query()
			equal = equal and first==independent and warm==independent and candidate.world.freeze()==facts
			if not first.is_empty(): nonempty += 1
			observations.append({"binding":binding,"kind":kind,"count":first.size(),"equal":first==independent and warm==independent})
	# Guard the permission boundary independently from candidate enumeration:
	# an existing foreign reservation must never use this equivalence, and any
	# proposed navigation change must retain the full reserved-world path.
	var candidate: Dictionary = actual._arrival_candidate(nominal,"B_S13_D09_M09",false)
	var world: WorldState = candidate.world
	var layout: Dictionary = {"floor_id":1,"footprint":[2,2],"patient_cell":[4,5],"operator_cells":[[3,4]],"repair_cell":[2,3]}
	var guards: bool = not actual._reference_routing_unchanged(world,layout,layout)
	actual.space.begin_route_query(world,{"nominal":true})
	guards = guards and actual._reference_routing_unchanged(world,layout,layout)
	for field: String in layout:
		var changed: Dictionary = layout.duplicate(true)
		changed[field] = 2 if field=="floor_id" else []
		guards = guards and not actual._reference_routing_unchanged(world,layout,changed)
	world.facts.adaptations.foreign = {"owner_id":"other"}
	guards = guards and not actual._reference_routing_unchanged(world,layout,layout)
	world.facts.adaptations.erase("foreign")
	world.facts.connectors.in_flight_guard = {"phase":"riding"}
	guards = guards and not actual._reference_routing_unchanged(world,layout,layout)
	world.facts.connectors.erase("in_flight_guard")
	actual.space.end_route_query()
	for simulation: HospitalSimulation in _simulations: simulation.dispose()
	_simulations.clear()
	t.check("GROW-81",equal and nonempty>0 and actual.reused>1 and guards and nominal.freeze()==before and actual.space._route_queries.is_empty() and reserved.space._route_queries.is_empty(),{"observations":observations,"nonempty":nonempty,"reused":actual.reused,"changed":actual.changed,"guards":guards,"readonly":nominal.freeze()==before})
