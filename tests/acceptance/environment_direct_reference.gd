extends "res://tests/acceptance/environment_wall_reference.gd"

# Public direct reads before automatic batching: enumerate raw current facts.
func environment_at(world: WorldState, floor_id: int, cell: Array, actor_id: String = "", explain: bool = true) -> Dictionary:
	return _observe_at(world,floor_id,cell,actor_id,explain,true)

func sample_at(world: WorldState, floor_id: int, cell: Array, actor_id: String = "") -> Dictionary:
	return _observe_at(world,floor_id,cell,actor_id,false,false)
