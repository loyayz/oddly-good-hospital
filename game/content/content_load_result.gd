class_name ContentLoadResult
extends RefCounted

var registry: ContentRegistry
var errors: PackedStringArray = []

var accepted: bool:
	get:
		return registry != null and errors.is_empty()
