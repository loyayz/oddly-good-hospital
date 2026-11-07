extends RefCounted
# One actor's synchronous read-only candidate batch. Never retained across commits.
var _space: HospitalSpace
var _world: WorldState
var actor: Dictionary
var _floor: int
var _query: RouteClearance
func _init(space: HospitalSpace, world: WorldState, original_actor: Dictionary, floor_id: int) -> void:
	_space = space
	_world = world
	actor = original_actor.duplicate(true)
	_floor = floor_id
func reason(cell: Array) -> String:
	actor.location = {"kind":"floor","floor_id":_floor,"cell":cell,"height_m":0.0}
	if _query==null:
		# Same no-scope branch as HospitalSpace.static_reason; do not create a graph.
		var geometry: RouteClearance = _space._navigation.cached_static_geometry(_space,_world,_floor,actor)
		_query = RouteClearance.new(_space,_world,actor,_floor,[],{},true,_space._navigation.floor_source(_space,_world,_floor),geometry)
	return _query.reason(Vector2i(int(cell[0]),int(cell[1])))
func dynamic_clear() -> bool:
	return _space._dynamic_clear(_world,actor.id,_floor,_space.body_rectangle(actor))
