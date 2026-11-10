class_name HospitalPersonalBeds
extends RefCounted

var _owner: WeakRef
var _world: WeakRef
var _basis: Array = []
var _by_staff: Dictionary = {}
var _route_basis: Array = []
var _pending_regions: Dictionary = {}

func _init(owner: HospitalStaffWellbeing) -> void:
	_owner = weakref(owner)

func sync(world: WorldState) -> void:
	var space: HospitalSpace = _owner.get_ref().space
	var state: Dictionary = world.facts.staff_life
	if not state.has("personal_beds"):
		state.personal_beds = {}
	var owners: Dictionary = state.personal_beds
	var signature: Array = [world.geometry_revision,world.ids("staff"),world.facility_ids("SE04"),owners.duplicate(true)]
	for staff_id: String in world.ids("staff"):
		var staff: Dictionary = world.facts.staff[staff_id]
		var actor: Dictionary = world.facts.actors[staff_id]
		signature.append([staff_id,staff.get("departed",false),actor.species_id,actor.get("body_binding_id",""),actor.location.kind])
	for adaptation_id: String in world.ids("adaptations"):
		var adaptation: Dictionary = world.facts.adaptations[adaptation_id]
		signature.append([adaptation_id,adaptation.kind,adaptation.get("actor_id","") if adaptation.kind=="facility" else "",adaptation.get("staff_ids",[]),adaptation.get("footprint",[]),adaptation.get("span",0)])
	for bed_id: String in world.facility_ids("SE04"):
		var bed: Dictionary = world.facts.facilities[bed_id]
		signature.append([bed_id,bed.get("failed",false),bed.get("stored",false),HospitalRemodel.blocked(world,bed_id),HospitalStaffWellbeing._is_staff_room(world.facts.rooms.get(bed.get("room_id",""),{}))])
	for bed_id: String in owners:
		var staff_id: String = str(owners[bed_id].staff_id)
		var staff: Dictionary = world.facts.staff.get(staff_id,{})
		if staff.is_empty() or staff.get("departed",false):
			# Only a departing owner's actual bed release affects this lifecycle.
			signature.append([bed_id,state.reservations.has(bed_id),world.facts.actors.get(staff_id,{}).get("location",{}).duplicate(true)])
	# Dynamic opportunity belongs to the remaining candidates, not every body
	# and journey in the hospital. Their exact fit regions were already proved
	# by the previous batch; the original static/lifecycle basis owns their age.
	if _world!=null and _world.get_ref()==world and signature==_basis and _pending_route_basis(world,owners,space)==_route_basis: return
	_world = weakref(world)
	_by_staff.clear()
	_pending_regions.clear()
	for bed_id: String in owners.keys():
		var staff_id: String = str(owners[bed_id].staff_id)
		var staff: Dictionary = world.facts.staff.get(staff_id,{})
		var adapter: Dictionary = world.facts.adaptations.get(bed_id,{})
		var released: bool = not state.reservations.has(bed_id) and adapter.get("actor_id","")!=staff_id and (not world.facts.actors.has(staff_id) or not world.facts.facilities.has(bed_id) or not space.overlaps_facility(world,staff_id,bed_id))
		var exists: bool = world.facts.facilities.has(bed_id) or world.facts.inventory.get("build_items",{}).has(bed_id)
		if not exists or (staff.is_empty() or staff.get("departed",false)) and released:
			owners.erase(bed_id)
		else: _by_staff[staff_id] = bed_id
	var staff_ids: Array = []
	for staff_id: String in world.ids("staff"):
		if not _by_staff.has(staff_id) and not world.facts.staff[staff_id].get("departed",false) and world.facts.actors[staff_id].location.kind=="floor": staff_ids.append(staff_id)
	var awake_limit: int = ceili(float(space.content.balance.staff_sleep.awake_limit_seconds)/WorldState.TICK_SECONDS)
	staff_ids.sort_custom(func(a: String,b: String)->bool:
		var first: Dictionary = world.facts.staff[a]
		var second: Dictionary = world.facts.staff[b]
		var first_due: bool = int(first.awake_ticks)>=awake_limit or int(first.sleep_remaining_ticks)>0
		var second_due: bool = int(second.awake_ticks)>=awake_limit or int(second.sleep_remaining_ticks)>0
		if first_due!=second_due: return first_due
		if first.awake_ticks!=second.awake_ticks: return first.awake_ticks>second.awake_ticks
		if first.energy!=second.energy: return first.energy<second.energy
		return a<b)
	var candidates: Dictionary = {}
	var free_beds: Array = []
	for bed_id: String in world.facility_ids("SE04"):
		if not owners.has(bed_id): free_beds.append(bed_id)
	if staff_ids.is_empty() or free_beds.is_empty():
		signature[3] = owners.duplicate(true)
		_basis = signature
		_route_basis = []
		return
	# No ownership, actor or layout changes occur while collecting this batch.
	# Share sealed before-layout exit witnesses across all staff/bed candidates;
	# each prospective round trip still has its own independent candidate world.
	space.begin_dynamic_route_query(world)
	var geometry_eligibility: Dictionary = {}
	for staff_id: String in staff_ids:
		candidates[staff_id] = []
		var actor: Dictionary = world.facts.actors[staff_id]
		var shape_key: String = JSON.stringify([space.body(actor),space.clearance(actor)],"",true,true)
		var geometry: Dictionary = geometry_eligibility.get_or_add(shape_key,{})
		for bed_id: String in free_beds:
			var bed: Dictionary = world.facts.facilities[bed_id]
			if bed.get("stored",false) or bed.get("failed",false) or HospitalRemodel.blocked(world,bed_id) or not HospitalStaffWellbeing._is_staff_room(world.facts.rooms.get(bed.get("room_id",""),{})): continue
			# Only a confirmed fixed-geometry failure rejects another equal body.
			# Successful pairs keep the original full live round trip, with no
			# extra preflight; dynamic failures are never shared as rejections.
			if geometry.get(bed_id,false): continue
			var quote: Dictionary = space.facility_trip_quote(world,bed_id,staff_id)
			if quote.ok:
				candidates[staff_id].append({"bed_id":bed_id,"travel_ticks":int(quote.travel_ticks)})
				_remember_regions(bed_id,quote.fit,staff_id)
			elif not geometry.has(bed_id):
				var fit: Dictionary = space.facility_geometry_quote(world,bed_id,staff_id)
				geometry[bed_id] = not fit.ok
				if fit.ok: _remember_regions(bed_id,fit,staff_id)
			if geometry.has(bed_id) and not geometry[bed_id]: _pending_regions[bed_id].staff_ids[staff_id] = true
	space.end_route_query()
	var result: Dictionary = HospitalPersonalBedMatching.compute(staff_ids,candidates)
	if not result.ok:
		_basis.clear()
		return
	var assigned: Dictionary = result.owners
	for bed_id: String in assigned:
		owners[bed_id] = {"staff_id":assigned[bed_id]}
		_by_staff[assigned[bed_id]] = bed_id
	# Store the new ownership identity so the next ordinary step does no batch
	# matching. Real lifecycle/layout events invalidate this derived basis.
	signature[3] = owners.duplicate(true)
	_basis = signature
	_route_basis = _pending_route_basis(world,owners,space)

# SE04 uses its fixed FF08 base plus actual access/repair regions. This saves
# only geometry already returned by fit, never a route or assignment decision.
func _remember_regions(bed_id: String, fit: Dictionary, staff_id: String) -> void:
	var saved: Dictionary = _pending_regions.get_or_add(bed_id,{"floor_id":int(fit.floor_id),"regions":[],"staff_ids":{}})
	saved.staff_ids[staff_id] = true
	for area: Array in fit.regions:
		var rect: Rect2 = Rect2(float(area[0]),float(area[1]),float(area[2]),float(area[3]))
		if not rect in saved.regions: saved.regions.append(rect)

func _pending_route_basis(world: WorldState, owners: Dictionary, space: HospitalSpace) -> Array:
	var assigned: Dictionary = {}
	for owner: Dictionary in owners.values(): assigned[owner.staff_id] = true
	var floors: Dictionary = {}
	var eligible: Dictionary = {}
	for bed_id: String in _pending_regions:
		if owners.has(bed_id): continue
		var bed: Dictionary = _pending_regions[bed_id]
		var pending: bool = false
		for staff_id: String in bed.staff_ids:
			if assigned.has(staff_id): continue
			eligible[staff_id] = true
			pending = true
		if not pending: continue
		var regions: Array[Rect2] = floors.get_or_add(int(bed.floor_id),[] as Array[Rect2])
		for rect: Rect2 in bed.regions:
			if not rect in regions: regions.append(rect)
	if floors.is_empty(): return []
	var subjects: Array = []
	var staff_ids: Array = eligible.keys()
	staff_ids.sort()
	# Geometry-incompatible bodies cannot gain this bed by moving. Their
	# bodies/layout still invalidate _basis, and their real local occupancy is
	# observed below exactly like every other actor's.
	for staff_id: String in staff_ids:
		if world.facts.staff[staff_id].get("departed",false): continue
		var actor: Dictionary = world.facts.actors[staff_id]
		if actor.location.kind!="floor": continue
		var movement: Dictionary = world.facts.moves.get(staff_id,{})
		# Single-body structural routes do not read unrelated journeys or lift
		# queues. A candidate's own convoy still owns its connector fit.
		subjects.append([staff_id,actor.location.duplicate(true),actor.get("posture","standing"),actor.get("facing",0.0),movement.duplicate(true) if movement.has("convoy") else {}])
	if subjects.is_empty(): return []
	space._ensure_actor_index(world)
	var local: Array = []
	var ordered_floors: Array = floors.keys()
	ordered_floors.sort()
	for floor_id: int in ordered_floors:
		var regions: Array[Rect2] = floors[floor_id]
		local.append([floor_id,_indexed_regions(space._actor_index,floor_id,regions),_indexed_regions(space.movement._sweep_index,floor_id,regions)])
		for region: Dictionary in space._reservation_regions_many(world,floor_id,regions):
			local.append([region.reservation_id,region.rect,region.reservation.duplicate(true)])
	return [subjects,local,space.navigation.connection_basis(world)]

func _indexed_regions(index: BodyIndex, floor_id: int, regions: Array[Rect2]) -> Array:
	var result: Array = []
	for id: String in index.candidates_in_regions(floor_id,regions):
		var record: BodyIndex.Record = index.record(id)
		result.append([id,record.rect,record.regions.duplicate()])
	return result

func bed_for(world: WorldState, staff_id: String) -> String:
	if _world==null or _world.get_ref()!=world: sync(world)
	return str(_by_staff.get(staff_id,""))

static func validate(world: WorldState) -> String:
	if not world.facts.staff_life.has("personal_beds"): return ""
	if not world.facts.staff_life.personal_beds is Dictionary: return "个人床归属集合无效"
	var seen: Dictionary = {}
	for bed_id: Variant in world.facts.staff_life.personal_beds:
		var owner: Variant = world.facts.staff_life.personal_beds[bed_id]
		var bed: Dictionary = world.facts.facilities.get(bed_id,world.facts.inventory.get("build_items",{}).get(bed_id,{}))
		if not bed_id is String or not owner is Dictionary or not owner.get("staff_id") is String or bed.get("definition_id","")!="SE04" or not world.facts.staff.has(owner.staff_id) or seen.has(owner.staff_id): return "个人床归属引用或互斥无效"
		seen[owner.staff_id] = true
	return ""
