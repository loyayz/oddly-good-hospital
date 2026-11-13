extends RefCounted

static func _continuation(movement: Dictionary, connector_id: String) -> Array:
	var source: Array=movement.get("route_waypoint",{}).get("continuation",movement.get("path",[]).slice(int(movement.get("cursor",0))))
	for index: int in source.size():
		if source[index].kind=="connector" and source[index].connector_id==connector_id: return source.slice(index).duplicate(true)
	return []

