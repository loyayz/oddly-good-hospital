class_name HospitalPersonalBeds
extends RefCounted

var _owner: WeakRef
var _world: WeakRef
var _basis: Array = []
var _by_staff: Dictionary = {}

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
		signature.append([bed_id,bed.get("failed",false),bed.get("stored",false)])
	# Only a genuine unassigned/free-bed gap depends on changing live routes.
	# Fully owned capacity never observes every passing body or rematches it.
	signature.append(_pending_route_basis(world,owners,space))
	if _world!=null and _world.get_ref()==world and signature==_basis: return
	_world = weakref(world)
	_by_staff.clear()
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
	staff_ids.sort_custom(func(a: String,b: String)->bool:
		var first: Dictionary = world.facts.staff[a]
		var second: Dictionary = world.facts.staff[b]
		var limit: int = ceili(float(space.content.balance.staff_sleep.awake_limit_seconds)/WorldState.TICK_SECONDS)
		var first_due: bool = int(first.awake_ticks)>=limit or int(first.sleep_remaining_ticks)>0
		var second_due: bool = int(second.awake_ticks)>=limit or int(second.sleep_remaining_ticks)>0
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
		return
	# No ownership, actor or layout changes occur while collecting this batch.
	# Share sealed before-layout exit witnesses across all staff/bed candidates;
	# each prospective round trip still has its own independent candidate world.
	space.begin_dynamic_route_query(world)
	for staff_id: String in staff_ids:
		candidates[staff_id] = []
		for bed_id: String in free_beds:
			var bed: Dictionary = world.facts.facilities[bed_id]
			if bed.get("stored",false) or bed.get("failed",false) or HospitalRemodel.blocked(world,bed_id) or not HospitalStaffWellbeing._is_staff_room(world.facts.rooms.get(bed.get("room_id",""),{})): continue
			var quote: Dictionary = space.facility_trip_quote(world,bed_id,staff_id)
			if quote.ok: candidates[staff_id].append({"bed_id":bed_id,"travel_ticks":int(quote.travel_ticks)})
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
	signature[signature.size()-1] = _pending_route_basis(world,owners,space)
	_basis = signature

func _pending_route_basis(world: WorldState, owners: Dictionary, space: HospitalSpace) -> Array:
	var free: bool = false
	for bed_id: String in world.facility_ids("SE04"):
		var bed: Dictionary = world.facts.facilities[bed_id]
		if not owners.has(bed_id) and not bed.get("failed",false) and not bed.get("stored",false) and not HospitalRemodel.blocked(world,bed_id) and HospitalStaffWellbeing._is_staff_room(world.facts.rooms.get(bed.get("room_id",""),{})): free = true; break
	if not free: return []
	var assigned: Dictionary = {}
	for owner: Dictionary in owners.values(): assigned[owner.staff_id] = true
	var unassigned: bool = false
	for staff_id: String in world.ids("staff"):
		if not assigned.has(staff_id) and not world.facts.staff[staff_id].get("departed",false) and world.facts.actors[staff_id].location.kind=="floor": unassigned = true; break
	if not unassigned: return []
	var actors: Array = []
	for actor_id: String in world.ids("actors"):
		var actor: Dictionary = world.facts.actors[actor_id]
		actors.append([actor_id,actor.species_id,actor.get("body_binding_id",""),actor.location.duplicate(true),actor.get("posture","standing")])
	return [actors,world.facts.moves.duplicate(true),world.facts.connectors.duplicate(true),world.facts.staff_life.reservations.duplicate(true)]

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
