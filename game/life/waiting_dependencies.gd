extends RefCounted

# The observation projection is a fixed tuple, not a second reservation owner.
# Keep every compared field and deep-copy nested values on actual changes.
enum ActorField { FLOOR, RECT }

enum ReservationField { FLOOR, KIND, SPAN, ACTOR, STAFF, REGIONS }


# Runtime reverse dependencies only. Tasks, queues and permission facts stay
# with their existing owners; a dirty waiter is consumed in their original order.
var resources: Dictionary = {}
var waiters: Dictionary = {}
var _regions: BodyIndex = BodyIndex.new()
var _region_waiters: Dictionary = {}
# Exact floor/rectangle identities share only spatial observation, never decisions.
var _region_tokens: Dictionary = {}
var _next_region: int = 0
var _actors: Dictionary = {}
var _reservations: Dictionary = {}

func clear() -> void:
	resources.clear()
	waiters.clear()
	_regions.clear()
	_region_waiters.clear()
	_region_tokens.clear()
	_actors.clear()
	_reservations.clear()
	_next_region = 0

func remove(id: String) -> void:
	var saved: Dictionary = waiters.get(id,{})
	if saved.is_empty(): return
	for key: String in saved.resources:
		resources[key].waiters.erase(id)
		if resources[key].waiters.is_empty(): resources.erase(key)
	for token: String in saved.regions:
		var shared: Dictionary = _region_waiters[token]
		shared.waiters.erase(id)
		if not shared.waiters.is_empty(): continue
		_regions.remove(token)
		_region_waiters.erase(token)
		_region_tokens[shared.floor_id].erase(shared.rect)
		if _region_tokens[shared.floor_id].is_empty(): _region_tokens.erase(shared.floor_id)
	waiters.erase(id)

func remember(id: String, observed: Dictionary, floor_id: int, bounds: Array[Rect2]) -> void:
	remove(id)
	var saved: Dictionary = {"dirty":false,"resources":[],"regions":[]}
	waiters[id] = saved
	for key: String in observed:
		var current: Dictionary = observed[key]
		if not resources.has(key):
			var source: Dictionary = current.duplicate()
			source.erase("value")
			resources[key] = {"source":source.duplicate(true),"value":current.value.duplicate(true),"waiters":{}}
		elif resources[key].value!=current.value:
			mark(key)
			resources[key].value = current.value.duplicate(true)
		resources[key].waiters[id] = true
		saved.resources.append(key)
	for rect: Rect2 in bounds:
		var floor_tokens: Dictionary = _region_tokens.get_or_add(floor_id,{})
		var token: String = str(floor_tokens.get(rect,""))
		if token.is_empty():
			_next_region += 1
			token = str(_next_region)
			floor_tokens[rect] = token
			_regions.update(token,floor_id,rect)
			_region_waiters[token] = {"floor_id":floor_id,"rect":rect,"waiters":{}}
		var shared: Dictionary = _region_waiters[token].waiters
		if shared.has(id): continue
		shared[id] = true
		saved.regions.append(token)

func dirty(id: String) -> bool:
	return not waiters.has(id) or bool(waiters[id].dirty)

func mark(key: String) -> void:
	if not resources.has(key): return
	for id: String in resources[key].waiters: waiters[id].dirty = true

func refresh(read: Callable) -> int:
	var changed: int = 0
	for key: String in resources:
		var saved: Dictionary = resources[key]
		var value: Array = read.call(saved.source)
		if value==saved.value: continue
		saved.value = value.duplicate(true)
		mark(key)
		changed += 1
	return changed

func _mark_bounds(floor_id: int, rect: Rect2) -> void:
	if floor_id<=0: return
	for token: String in _regions.candidates(floor_id,rect):
		for id: String in _region_waiters[token].waiters: waiters[id].dirty = true

func actor_changed(id: String, old_floor: int, old_rect: Rect2, floor_id: int, rect: Rect2) -> void:
	if old_floor==floor_id and old_rect==rect: return
	mark("actor:"+id)
	_mark_bounds(old_floor,old_rect)
	_mark_bounds(floor_id,rect)
	if floor_id>0: _actors[id] = [floor_id,rect]
	else: _actors.erase(id)

# Raw calculation worlds and imported facts also use the same reverse index.
# Compare each spatial record once per owner observation, never per waiter.
func observe_actors(index: BodyIndex) -> void:
	for id: String in _actors.keys():
		if index._records.has(id): continue
		var previous: Array = _actors[id]
		actor_changed(id,int(previous[ActorField.FLOOR]),previous[ActorField.RECT],0,Rect2())
	for id: String in index._records:
		var current: BodyIndex.Record = index._records[id]
		var previous: Array = _actors.get(id,[])
		actor_changed(id,int(previous[ActorField.FLOOR]) if not previous.is_empty() else 0,previous[ActorField.RECT] if not previous.is_empty() else Rect2(),current.floor_id,current.rect)

func reservation_changed(id: String, reservation: Dictionary) -> void:
	var previous: Array = _reservations.get(id,[])
	var current: Array = [] if reservation.is_empty() else [int(reservation.floor_id),reservation.get("kind",""),reservation.get("span",-1),reservation.get("actor_id",""),reservation.get("staff_ids",[]),reservation.get("regions",[])]
	if previous==current: return
	mark("reservation:"+id)
	for state: Array in [previous,current]:
		if state.is_empty(): continue
		if state[ReservationField.KIND]=="door": mark("floor:"+str(state[ReservationField.FLOOR]))
		for rect: Array in state[ReservationField.REGIONS]:
			_mark_bounds(int(state[ReservationField.FLOOR]),Rect2(float(rect[0]),float(rect[1]),float(rect[2]),float(rect[3])))
	if current.is_empty(): _reservations.erase(id)
	else: _reservations[id] = current.duplicate(true)

func observe_reservations(adaptations: Dictionary) -> void:
	for id: String in _reservations.keys():
		if not adaptations.has(id): reservation_changed(id,{})
	for id: String in adaptations: reservation_changed(id,adaptations[id])
