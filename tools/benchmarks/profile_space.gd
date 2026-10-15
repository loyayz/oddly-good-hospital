extends HospitalSpace

var timings: Dictionary = {}

func _record(method: String, started: int) -> void:
	var row: Dictionary = timings.get(method,{"calls":0,"usec":0})
	row.calls += 1
	row.usec += Time.get_ticks_usec()-started
	timings[method] = row

func _floor_route(world: WorldState, actor: Dictionary, floor_id: int, start: Vector2i, goal: Vector2i, members: Array = [], offsets: Dictionary = {}, ignore_people: bool = false) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var result: Dictionary = super._floor_route(world,actor,floor_id,start,goal,members,offsets,ignore_people)
	_record("floor_route_inclusive",started)
	return result

func _dispatch_routes(world: WorldState, present_at_start: int) -> void:
	var started: int = Time.get_ticks_usec()
	super._dispatch_routes(world,present_at_start)
	_record("dispatch_routes_inclusive",started)

func _unit_sweeps(world: WorldState, actor: Dictionary, next: Vector2, members: Array, offsets: Dictionary, direction: Vector2) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var result: Dictionary = super._unit_sweeps(world,actor,next,members,offsets,direction)
	_record("unit_sweeps_inclusive",started)
	return result

func _movement_clear(world: WorldState, actor_id: String, floor_id: int, broad: Rect2, sweeps: Dictionary, members: Array) -> bool:
	var started: int = Time.get_ticks_usec()
	var result: bool = super._movement_clear(world,actor_id,floor_id,broad,sweeps,members)
	_record("movement_clear_inclusive",started)
	return result

func _active_route_clear(world: WorldState, actor: Dictionary, movement: Dictionary, versions: Dictionary) -> bool:
	var started: int = Time.get_ticks_usec()
	var result: bool = super._active_route_clear(world,actor,movement,versions)
	_record("active_route_clear",started)
	return result

func _dynamic_clear(world: WorldState, actor_id: String, floor_id: int, rect: Rect2, members: Array = []) -> bool:
	var started: int = Time.get_ticks_usec()
	var result: bool = super._dynamic_clear(world,actor_id,floor_id,rect,members)
	_record("dynamic_clear",started)
	return result

func _step_static_clear(world: WorldState, actor: Dictionary, movement: Dictionary, next: Vector2, query: RouteClearance = null) -> bool:
	var started: int = Time.get_ticks_usec()
	var result: bool = super._step_static_clear(world,actor,movement,next,query)
	_record("step_static_clear",started)
	return result

func _reserve_doors(world: WorldState, actor: Dictionary, movement: Dictionary, swept: Rect2) -> bool:
	var started: int = Time.get_ticks_usec()
	var result: bool = super._reserve_doors(world,actor,movement,swept)
	_record("reserve_doors",started)
	return result

func _actor_rect(actor: Dictionary, origin: Vector2) -> Rect2:
	var started: int = Time.get_ticks_usec()
	var result: Rect2 = super._actor_rect(actor,origin)
	_record("actor_rect",started)
	return result

func _sync_actor(world: WorldState, id: String) -> void:
	var started: int = Time.get_ticks_usec()
	super._sync_actor(world,id)
	_record("sync_actor",started)

func profile() -> Dictionary:
	return timings.duplicate(true)
