extends RefCounted

# Read-only diagnostic observation at entry to the original visitor seat quote.
# Do not call read_view/build or scan actors: that would warm the very cache we
# are measuring. Retain only bounded scalar facts, never the live views/world.
static func capture(space: Object, world: Object, actor_id: String, facility_id: String) -> Dictionary:
	var result: Dictionary = {"same_world_scope":false,"supported_view_ready":false,"known_supported":false}
	var queries: Array = space._route_queries
	if queries.is_empty() or queries.back().world!=world: return result
	result.same_world_scope = true
	var views: Dictionary = queries.back().views
	var key: String = "visitor_supported:"+actor_id
	if not views.has(key): return result
	result.supported_view_ready = true
	result.known_supported = views[key].has(facility_id)
	return result
