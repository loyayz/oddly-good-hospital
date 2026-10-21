extends RefCounted

# Observe only real spatial unions; the original query still reads current facts.
class ProbeAreas extends HospitalPublicAreas:
	var queries: int = 0
	var rectangles: Array = []
	func _add_dynamic_dependencies(world: WorldState, floor_id: int, bounds: Rect2, members: Array, actors: Dictionary, reservations: Dictionary) -> void:
		queries += 1
		rectangles.append(bounds)
		super._add_dynamic_dependencies(world,floor_id,bounds,members,actors,reservations)

# Frozen fa9898b complete signature: original full facility enumeration and
# repeated point queries remain independent of membership/point optimization.
class ReferenceAreas extends HospitalPublicAreas:
	var queries: int = 0
	var rectangles: Array = []
	func _add_dynamic_dependencies(world: WorldState, floor_id: int, bounds: Rect2, members: Array, actors: Dictionary, reservations: Dictionary) -> void:
		queries += 1
		rectangles.append(bounds)
		super._add_dynamic_dependencies(world,floor_id,bounds,members,actors,reservations)
	func _decision_signature(world: WorldState, intent: Dictionary, definitions: Array, members: Array, extra: Dictionary, route_floors: Array = []) -> Array:
		var view: Dictionary = _decision_view(world)
		var ids: Array = [str(intent.actor_id)] if members.is_empty() else members
		var bodies: Array = []
		for id: String in ids:
			var actor: Dictionary = world.facts.actors[id]
			bodies.append([id,space.body(actor),actor.location,actor.get("posture","standing"),actor.get("facing",0.0)])
		var reference: Dictionary = intent.get("area",{})
		var room: Dictionary = world.facts.rooms.get(reference.get("room_id",""),{})
		var records: Array = [reference,room.get("kind",room.get("type","")),room.get("origin",[]),room.get("size",[]),room.get("wall_edges",[]),definitions,bodies,extra,intent.get("mode","auto"),intent.get("manual_facility_id",""),intent.get("arrived_tick",-1),intent.get("started_tick",-1),intent.has("ticket_id"),"R15" in world.facts.research]
		records.append(space.navigation.connection_basis(world))
		var points: Array = []
		var other_ids: Dictionary = {}
		var reservations: Dictionary = {}
		space._ensure_actor_index(world)
		var area: Dictionary = region(world,reference)
		records.append(area.get("geometry",""))
		var route_dependent: bool = intent.public_purpose=="rest" or definitions.is_empty()
		for facility_id: String in area.get("facilities",[]):
			var facility: Dictionary = world.facts.facilities[facility_id]
			if not facility.definition_id in definitions: continue
			var users: Array = view.users.get(facility_id,[])
			var reservation: Dictionary = world.facts.get("staff_life",{}).get("reservations",{}).get(facility_id,{})
			var adaptation: Dictionary = world.facts.adaptations.get(facility_id,{})
			records.append([facility_id,facility.definition_id,facility.cell,facility.footprint,facility.get("rotation",0),facility.get("patient_cell",[]),facility.get("operator_cells",[]),facility.get("repair_cell",[]),facility.get("failed",false),HospitalRemodel.blocked(world,facility_id),users,reservation.get("id",""),reservation.get("staff_ids",[]),adaptation.get("actor_id",""),adaptation.get("staff_ids",[]),adaptation.get("regions",[])])
			var occupied: bool = false
			for owner: String in users:
				if not owner in ids: occupied = true
			if occupied or not reservation.is_empty() or not adaptation.is_empty() and not str(adaptation.get("actor_id","")) in ids: continue
			route_dependent = true
			var layout: Dictionary = space.facility_layout(world,facility_id)
			for point: Array in [layout.patient_cell]+layout.get("operator_cells",[])+[layout.get("repair_cell",layout.patient_cell)]:
				points.append(point)
				var reach: float = maxf(6.0,float(space.clearance(world.facts.actors[ids[0]]))+1.0)
				var bounds: Rect2 = Rect2(Vector2(float(point[0]),float(point[1])),Vector2.ONE).grow(reach)
				_add_dynamic_dependencies(world,int(reference.floor_id),bounds,ids,other_ids,reservations)
		if (intent.public_purpose=="rest" or definitions.is_empty()) and not area.is_empty():
			# Tea is a real free standing place, including a region with no chairs.
			# Its availability can change when any body/reservation leaves that area.
			var bounds: Rect2 = Rect2(area.bounds).grow(float(space.clearance(world.facts.actors[ids[0]]))+1.0)
			_add_dynamic_dependencies(world,int(reference.floor_id),bounds,ids,other_ids,reservations)
		if route_dependent:
			# A failed route may recover through a remote floor. Retain the exact
			# static sources actually searched, plus newly declared routing stops.
			var versions: Array = []
			for floor_id: int in route_floors: versions.append([floor_id,space._navigation.floor_static_version(space,world,floor_id)])
			records.append([versions,space.navigation.routing_floor_basis(world)])
		var queue_key: String = JSON.stringify([intent.public_purpose,reference],"",true,true)
		for other: Dictionary in view.queues.get(queue_key,[]):
			if str(other.get("id",""))==str(intent.id) or int(other.get("arrived_tick",-1))<0: continue
			if not other.get("phase","") in ["local_wait","local_travel","manual_wait"]: continue
			var queue_bodies: Array = []
			for id: String in other.get("staff_ids",[str(other.actor_id)]):
				if world.facts.actors.has(id):
					var actor: Dictionary = world.facts.actors[id]
					queue_bodies.append([id,space.body(actor),actor.get("posture","standing"),actor.get("facing",0.0)])
			records.append([other.id,other.arrived_tick,other.phase,other.get("facility_id",""),other.get("mode","auto"),other.get("manual_facility_id",""),queue_bodies])
		var sorted_ids: Array = other_ids.keys()
		sorted_ids.sort()
		for id: String in sorted_ids:
			var other: Dictionary = world.facts.actors[id]
			var pair: Array = [str(intent.actor_id),id]
			pair.sort()
			records.append([id,other.location,space.body(other),other.get("posture","standing"),other.get("facing",0.0),world.facts.moves.has(id),world.facts.get("relationships",{}).get(":".join(pair),{})])
		var reservation_ids: Array = reservations.keys()
		reservation_ids.sort()
		for id: String in reservation_ids: records.append(reservations[id])
		records.append_array(_environment_samples(view,int(reference.get("floor_id",-1)),points))
		return records

func run_case(suite: RefCounted) -> Dictionary:
	var x: Dictionary = suite._areas()
	# Built footprints are disjoint. The second chair's repair place equals the
	# first patient's place; the third shares two other real work-place points.
	suite._facility(x,"dependency_second","FUR09",[37,69],"west")
	suite._facility(x,"dependency_third","FUR09",[38,68],"west")
	x.world.touch()
	x.subject = suite._visit(x,"dependency_subject",[40,75])
	x.peer = suite._visit(x,"dependency_peer",[42,75])
	x.obstacle = suite._visit(x,"dependency_obstacle",[40,76])
	x.probe = ProbeAreas.new(x.space)
	x.reference = ReferenceAreas.new(x.space)
	x.space.public_areas = x.probe
	var area: Dictionary = x.probe.for_facility(x.world,"west_chair")
	# This is a proposed regional task's calculation input. No arrived/use fact,
	# movement completion or negative selection result is fabricated.
	var intent: Dictionary = {"id":"dependency_task","actor_id":x.subject.actor_id,"public_purpose":"seat","mode":"auto","area":area,"phase":"area_travel","facility_id":"","arrived_tick":-1,"started_tick":x.world.sim_tick}
	var definitions: Array = ["FUR09"]
	var rows: Array = []
	var checks: Dictionary = {"valid_input":x.world.validate(suite._content).is_empty()}
	var baseline: Dictionary = _observe(x,intent,definitions,[])
	rows.append(_row("shared_real_work_places",baseline))
	checks.repeated_actual_points_reduce_queries = baseline.reference_queries==9 and baseline.actual_queries==6
	var repeat: Dictionary = _observe(x,intent,definitions,[])
	rows.append(_row("unchanged_input",repeat))
	checks.unchanged_signature_is_identical = baseline.signature==repeat.signature
	suite._position(x,x.obstacle.actor_id,[36.25,69.25])
	_changed(x)
	var moved: Dictionary = _observe(x,intent,definitions,[])
	rows.append(_row("fractional_real_body_position",moved))
	checks.current_fractional_body_change_is_observed = moved.signature!=baseline.signature
	suite._position(x,x.obstacle.actor_id,x.space.facility_layout(x.world,"west_chair").patient_cell)
	var reservation: String = x.space.reserve_facility(x.world,"west_chair",x.obstacle.actor_id,x.obstacle.actor_id)
	_changed(x)
	var reserved: Dictionary = _observe(x,intent,definitions,[])
	rows.append(_row("real_facility_reservation",reserved))
	checks.current_reservation_is_observed = reservation.is_empty() and reserved.signature!=moved.signature
	x.space.grant_facility_access(x.world,"west_chair",x.peer.actor_id)
	_changed(x)
	var permission: Dictionary = _observe(x,intent,definitions,[])
	rows.append(_row("real_reservation_permission",permission))
	checks.current_permission_change_is_observed = permission.signature!=reserved.signature
	x.world.facts.facilities.dependency_second.failed = true
	_changed(x)
	var failed: Dictionary = _observe(x,intent,definitions,[])
	rows.append(_row("failed_facility_still_in_signature",failed))
	checks.current_failure_remains_a_dependency = failed.signature!=permission.signature
	x.world.facts.facilities.dependency_second.failed = false
	_changed(x)
	var restored: Dictionary = _observe(x,intent,definitions,[])
	rows.append(_row("same_layout_failure_recovery",restored))
	checks.failure_recovery_is_immediate = restored.signature==permission.signature
	x.world.facts.floors.overrides["1"].blocked.append([40,74])
	x.world.touch()
	x.probe.changed(x.world)
	x.reference.changed(x.world)
	var static_change: Dictionary = _observe(x,intent,definitions,[])
	rows.append(_row("actual_static_source_change",static_change))
	checks.static_source_change_is_observed = static_change.signature!=restored.signature
	intent.public_purpose = "rest"
	rows.append(_row("tea_area_also_keeps_its_full_bounds",_observe(x,intent,definitions,[])))
	rows.append(_row("empty_definitions_keep_area_bounds",_observe(x,intent,[],[])))
	rows.append(_row("different_current_members",_observe(x,intent,definitions,[x.subject.actor_id,x.peer.actor_id])))
	rows.append(_row("duplicate_and_unknown_definitions",_observe(x,intent,["FUR09","FUR09","unknown"],[])))
	var result: Dictionary = {"ok":not checks.values().has(false) and rows.all(func(row: Dictionary)->bool:return row.ok),"checks":checks,"observations":rows,"reservation":reservation,"scope":"Current dependency calculations only; complete real waiting, release, movement and use remain the existing STAFF-69 through STAFF-72 cases."}
	x.a.dispose()
	x.p.waiting_life = null
	x.p.environment = null
	x.l.environment = null
	x.l.visitors = null
	x.c.recruitment = null
	x.clear()
	return result

func _changed(x: Dictionary) -> void:
	x.world.touch(false)
	x.probe.changed(x.world)
	x.reference.changed(x.world)

func _observe(x: Dictionary, intent: Dictionary, definitions: Array, members: Array) -> Dictionary:
	var before: Dictionary = x.world.freeze()
	x.probe.queries = 0
	x.probe.rectangles.clear()
	x.reference.queries = 0
	x.reference.rectangles.clear()
	var actual: Array = x.probe._decision_signature(x.world,intent,definitions,members,{},[1])
	var expected: Array = x.reference._decision_signature(x.world,intent,definitions,members,{},[1])
	var area_query: bool = intent.public_purpose=="rest" or definitions.is_empty()
	var unique_points: Array = []
	var point_queries: int = x.reference.queries-(1 if area_query else 0)
	for index: int in point_queries:
		var rectangle: Rect2 = x.reference.rectangles[index]
		if not rectangle in unique_points: unique_points.append(rectangle)
	var expected_queries: int = unique_points.size()+(1 if area_query else 0)
	return {"ok":actual==expected and x.probe.queries==expected_queries and before==x.world.freeze(),"signature":actual.duplicate(true),"full_original_signature_equal":actual==expected,"actual_queries":x.probe.queries,"reference_queries":x.reference.queries,"unique_point_queries":unique_points.size(),"separate_area_query":area_query,"expected_queries":expected_queries,"facts_and_rng_unchanged":before==x.world.freeze()}

func _row(label: String, observed: Dictionary) -> Dictionary:
	var result: Dictionary = observed.duplicate()
	result.erase("signature")
	result.boundary = label
	return result

