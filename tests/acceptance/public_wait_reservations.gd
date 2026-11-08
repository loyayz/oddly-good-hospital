extends "res://tests/acceptance/public_waiting_cost_field.gd"

# Old complete public tail: construct the ordinary full query, not a partial object.
class FrozenPublicAreas extends HospitalPublicAreas:
	func safe_wait(world: WorldState, actor_id: String, floor_id: int, cell: Array, geometry: Dictionary = {}) -> bool:
		_ensure(world,floor_id)
		var actor: Dictionary = world.facts.actors[actor_id]
		var point: Vector2i = Vector2i(roundi(cell[0]),roundi(cell[1]))
		var origin: Vector2 = Vector2(float(cell[0]),float(cell[1]))
		if geometry.is_empty():
			var area: Dictionary = _cell_region(floor_id,point)
			if area.is_empty(): return false
			geometry = _entry_geometry_view(world,actor,area)
		if not geometry.points.has(origin): geometry.points[origin] = _safe_wait_geometry(world,actor,floor_id,origin,geometry.geometry,geometry.get("doors",{}))
		if not geometry.points[origin]: return false
		var current: Dictionary = space.read_view(world,"public_wait_clearance:"+actor_id+":"+str(floor_id),func()->Dictionary:
			return {"query":RouteClearance.new(space,world,actor,floor_id,[],{},true,space._navigation.floor_source(space,world,floor_id),geometry.geometry)})
		if not (current.query as RouteClearance).reservation_reason(point).is_empty(): return false
		return space._dynamic_clear(world,actor_id,floor_id,space._actor_rect(actor,origin))

# Frozen pre-change capture/predicate, independent of both new shared helpers.
func _oracle(world: WorldState, actor_id: String, floor_id: int, size: int, point: Vector2, members: Array = []) -> String:
	var footprint: Rect2=Rect2(point,Vector2.ONE*size)
	for reservation: Dictionary in world.facts.adaptations.values():
		if reservation.kind!="facility" or int(reservation.floor_id)!=floor_id: continue
		if actor_id==reservation.actor_id or actor_id in reservation.staff_ids or reservation.actor_id in members: continue
		for area: Array in reservation.regions:
			var rect: Rect2=Rect2(float(area[0]),float(area[1]),float(area[2]),float(area[3]))
			if footprint.intersects(rect,false): return "真实展开与岗位预约阻挡："+str(reservation.facility_id)
	return ""

func _record(rows: Array, name: String, passed: bool) -> void:
	rows.append({"name":name,"passed":passed})

func run_focused(content: HospitalContent) -> Dictionary:
	_content=content
	var x: Dictionary=_field_fixture(false)
	x.original.public_areas=FrozenPublicAreas.new(x.original)
	var actor: Dictionary=x.world.facts.actors[ACTOR]
	var rows: Array=[]
	var checks: int=0
	var saved: Dictionary=x.world.facts.adaptations.duplicate(true)
	# Explicit reservation boundary inputs; this is predicate testing, not a
	# fabricated claim that a facility service or physical journey occurred.
	for floor_id: int in [1,2]:
		for owner: String in [ACTOR,"foreign"]:
			for staff: bool in [false,true]:
				for kind: String in ["facility","door"]:
					for rect: Array in [[40.0,76.0,1.0,1.0],[41.0,76.0,1.0,1.0],[40.7,76.3,0.2,0.9]]:
						x.world.facts.adaptations={"probe":{"kind":kind,"actor_id":owner,"staff_ids":[ACTOR] if staff else [],"floor_id":floor_id,"facility_id":"probe_facility","regions":[rect]}}
						for size: int in [1,2,4]:
							for position: Vector2 in [Vector2(40,76),Vector2(39.65,75.65)]:
								var regions: Array[Dictionary]=RouteClearance.capture_reservation_regions(x.world,ACTOR,1)
								var expected: String=_oracle(x.world,ACTOR,1,size,position)
								_record(rows,"matrix_%d"%checks,expected==RouteClearance.reservation_regions_reason(position,size,regions))
								checks+=1
	# Capture owns rectangle values: mutating the raw region afterwards cannot
	# rewrite an already frozen permission snapshot.
	x.world.facts.adaptations={"probe":{"kind":"facility","actor_id":"foreign","staff_ids":[],"floor_id":1,"facility_id":"probe","regions":[[40,76,1,1]]}}
	var frozen: Array[Dictionary]=RouteClearance.capture_reservation_regions(x.world,ACTOR,1)
	x.world.facts.adaptations.probe.regions[0][0]=80
	_record(rows,"snapshot_owns_rectangles",not RouteClearance.reservation_regions_reason(Vector2(40,76),1,frozen).is_empty() and _oracle(x.world,ACTOR,1,1,Vector2(40,76)).is_empty())
	# Ordered first reason plus owner-in-members exception.
	x.world.facts.adaptations={"first":{"kind":"facility","actor_id":"foreign","staff_ids":[],"floor_id":1,"facility_id":"first","regions":[[40,76,2,2]]},"second":{"kind":"facility","actor_id":"other","staff_ids":[],"floor_id":1,"facility_id":"second","regions":[[40,76,2,2]]}}
	for members: Array in [[],["foreign"]]:
		var regions: Array[Dictionary]=RouteClearance.capture_reservation_regions(x.world,ACTOR,1,members)
		_record(rows,"order_and_member_"+str(members),_oracle(x.world,ACTOR,1,1,Vector2(40,76),members)==RouteClearance.reservation_regions_reason(Vector2(40,76),1,regions))
	x.world.facts.adaptations=saved.duplicate(true)
	# Actual public geometry/dynamic tails, including fractional points. Choose
	# a genuinely safe static point rather than stubbing static clearance.
	var area: Dictionary=x.actual.public_areas.region(x.world,x.area)
	var point: Vector2i=Vector2i(-1,-1)
	for candidate: Vector2i in area.cells:
		if x.actual.public_areas.safe_wait(x.world,ACTOR,1,[candidate.x,candidate.y]):
			point=candidate
			break
	_record(rows,"real_safe_point_exists",point.x>=0)
	if point.x>=0:
		for fraction: float in [0.0,0.35]:
			var cell: Array=[point.x+fraction,point.y+fraction]
			for kind: String in ["facility","door"]:
				for owner: String in [ACTOR,"foreign"]:
					x.world.facts.adaptations=saved.duplicate(true)
					x.world.facts.adaptations.probe={"kind":kind,"actor_id":owner,"staff_ids":[],"floor_id":1,"facility_id":"probe_facility","regions":[[point.x,point.y,0.5,0.8]]}
					x.actual._reservation_views.clear();x.original._reservation_views.clear()
					var before: Dictionary=x.world.freeze()
					var result: bool=x.actual.public_areas.safe_wait(x.world,ACTOR,1,cell)
					var expected: bool=x.original.public_areas.safe_wait(x.world,ACTOR,1,cell)
					_record(rows,"public_%s_%s_%s"%[fraction,kind,owner],result==expected and before==x.world.freeze())
		# Same query-key snapshot: permission mutation stays frozen until scope
		# closes. The actual dynamic tail remains live and is not cached away.
		x.world.facts.adaptations=saved.duplicate(true)
		x.world.facts.adaptations.probe={"kind":"facility","actor_id":"foreign","staff_ids":[],"floor_id":1,"facility_id":"probe_facility","regions":[[point.x,point.y,0.5,0.8]]}
		x.actual._reservation_views.clear();x.original._reservation_views.clear()
		_field_begin(x)
		var cell: Array=[point.x,point.y]
		var a: bool=x.actual.public_areas.safe_wait(x.world,ACTOR,1,cell)
		var b: bool=x.original.public_areas.safe_wait(x.world,ACTOR,1,cell)
		x.world.facts.adaptations.probe.actor_id=ACTOR
		var frozen_a: bool=x.actual.public_areas.safe_wait(x.world,ACTOR,1,cell)
		var frozen_b: bool=x.original.public_areas.safe_wait(x.world,ACTOR,1,cell)
		_field_end(x)
		var live_a: bool=x.actual.public_areas.safe_wait(x.world,ACTOR,1,cell)
		var live_b: bool=x.original.public_areas.safe_wait(x.world,ACTOR,1,cell)
		_record(rows,"scope_permission_snapshot_and_live_next_call",not a and a==b and not frozen_a and frozen_a==frozen_b and live_a and live_a==live_b)
		# Raw same-place region edit: no change notification or geometry bump.
		x.world.facts.adaptations.probe.actor_id="foreign"
		x.world.facts.adaptations.probe.regions=[[point.x,point.y,0.5,0.8]]
		_record(rows,"raw_live_reservation_edit",not x.actual.public_areas.safe_wait(x.world,ACTOR,1,cell) and not x.original.public_areas.safe_wait(x.world,ACTOR,1,cell))
	# Non-square actual bodies still use the same clearance square for the
	# reservation layer and the distinct full real rectangle for dynamic checks.
	x.world.facts.adaptations=saved.duplicate(true)
	var species: String=str(actor.species_id)
	var posture: String=str(actor.posture)
	actor.species_id="S01"
	for pose: String in ["standing","lying"]:
		actor.posture=pose
		var rect: Rect2=x.actual._actor_rect(actor,Vector2(40.35,76.35))
		var size: int=x.actual.clearance(actor)
		x.world.facts.adaptations.probe={"kind":"facility","actor_id":"foreign","staff_ids":[],"floor_id":1,"facility_id":"probe","regions":[[40+size-0.1,76,0.05,0.5]]}
		var regions: Array[Dictionary]=RouteClearance.capture_reservation_regions(x.world,ACTOR,1)
		_record(rows,"non_square_"+pose,rect.size.x!=rect.size.y and _oracle(x.world,ACTOR,1,size,Vector2(40,76))==RouteClearance.reservation_regions_reason(Vector2(40,76),size,regions))
	actor.species_id=species;actor.posture=posture
	_record(rows,"scope_closed",x.actual._route_queries.is_empty() and x.original._route_queries.is_empty())
	x.world.facts.adaptations=saved
	_field_dispose(x)
	return {"passed":rows.all(func(row: Dictionary)->bool:return row.passed),"checks":rows,"matrix_checks":checks,"scope":"Predicate and real public safety differential; not clinical arrival or performance acceptance."}
