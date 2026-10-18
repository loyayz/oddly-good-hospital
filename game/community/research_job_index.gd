class_name ResearchJobIndex
extends RefCounted

# Jobs retain their original dictionary order. Groups contain identities, so an
# in-place state/reward update or replacement is read from the current owner.
var _world: WorldState
var _records: Dictionary = {}
var _count: int = -1
var _groups: Dictionary = {}
var _observer: String = "research_lookup_"+str(get_instance_id())

func view(world: WorldState) -> Dictionary:
	var records: Dictionary = world.facts.get("research_jobs",{})
	var changed: Array = world.pending_fact_ids(_observer,"research_jobs",records,self)
	if _world!=world or not is_same(_records,records) or _count!=records.size() or not changed.is_empty():
		_world = world
		_records = records
		_count = records.size()
		_groups.clear()
		for id: String in records:
			var research_id: String = str(records[id].research_id)
			if not _groups.has(research_id): _groups[research_id] = []
			_groups[research_id].append(id)
	return {"records":records,"groups":_groups}

static func build(world: WorldState) -> Dictionary:
	var records: Dictionary = world.facts.get("research_jobs",{})
	var groups: Dictionary = {}
	for id: String in records:
		var research_id: String = str(records[id].research_id)
		if not groups.has(research_id): groups[research_id] = []
		groups[research_id].append(id)
	return {"records":records,"groups":groups}
