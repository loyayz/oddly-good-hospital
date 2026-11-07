extends RefCounted

# Independent test-only oracle. Never reads candidate payload-size metadata.
# Not executed until parent grants the frozen-source single-engine window.
static func expected_charge(record: Dictionary) -> int:
	return 2048 + 8 * (var_to_bytes(record.source).size() + var_to_bytes(record.static_source).size()) + 1024 * record.graphs.size()

static func readonly_tree(value: Variant) -> bool:
	if value is Dictionary:
		if not value.is_read_only(): return false
		for key: Variant in value:
			if not readonly_tree(key) or not readonly_tree(value[key]): return false
	elif value is Array:
		if not value.is_read_only(): return false
		for child: Variant in value:
			if not readonly_tree(child): return false
	return true

static func writable_tree(value: Variant) -> bool:
	if value is Dictionary:
		if value.is_read_only(): return false
		for key: Variant in value:
			if not writable_tree(key) or not writable_tree(value[key]): return false
	elif value is Array:
		if value.is_read_only(): return false
		for child: Variant in value:
			if not writable_tree(child): return false
	return true

static func resident_accounting(cache: NavigationCache) -> Dictionary:
	var sum: int = 0
	var undercharged: Array = []
	for key: String in cache._sources:
		var record: Dictionary = cache._sources[key]
		sum += int(record.charge)
		# An erased graph proof may remain conservatively charged until store.
		if int(record.charge) < expected_charge(record): undercharged.append(key)
	return {"sum":sum,"counter":cache._source_charged,"counter_exact":sum==cache._source_charged,"undercharged":undercharged}
