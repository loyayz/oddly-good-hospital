extends HospitalSpace

var timings: Dictionary = {}

func _record(method: String, started: int) -> void:
	var row: Dictionary = timings.get(method,{"calls":0,"usec":0})
	row.calls += 1
	row.usec += Time.get_ticks_usec()-started
	timings[method] = row

func _dynamic_clear(world: WorldState, actor_id: String, floor_id: int, rect: Rect2, members: Array = []) -> bool:
	var started: int = Time.get_ticks_usec()
	var result: bool = super._dynamic_clear(world,actor_id,floor_id,rect,members)
	_record("dynamic_clear",started)
	return result

func _step_static_clear(world: WorldState, actor: Dictionary, movement: Dictionary, next: Vector2) -> bool:
	var started: int = Time.get_ticks_usec()
	var result: bool = super._step_static_clear(world,actor,movement,next)
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
