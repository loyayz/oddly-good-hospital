extends SceneTree

func _initialize() -> void:
	var content: HospitalContent = HospitalContent.new()
	if not content.error.is_empty():
		push_error(content.error)
		quit(1)
		return
	var registry: ContentRegistry = content.registry
	var failures: Array[String] = []
	if content.catalog.species.size() != 80 or content.catalog.stories.size() != 12:
		failures.append("基础包内容或独立故事不完整")
	if content.definition("species", "core:S49") != content.definition("species", "S49"):
		failures.append("核心定义规范ID与兼容ID不一致")
	if registry.resolve_bindings("S49", "D37").is_empty():
		failures.append("显式病例适配索引未建立")
	if not content.catalog.is_read_only() or not content.catalog.species.is_read_only() or not content.definition("species", "S49").body.is_read_only():
		failures.append("注册表嵌套定义可修改")
	if content.catalog.build_room_types.size() != 17 or content.facility_definition("FUR01").price != 500 or content.facility_definition("SE04").is_empty():
		failures.append("房型与统一设施定义缺失")
	var original: String = content.content_fingerprint
	if content.load_packs(PackedStringArray(["res://content/absent"])) or content.registry != registry or content.content_fingerprint != original:
		failures.append("失败加载改变原注册表")
	if not failures.is_empty():
		for failure: String in failures:
			push_error(failure)
		quit(1)
		return
	print(JSON.stringify({"stage":4,"accepted":true,"definitions":80,"stories":12,"room_types":17,"fingerprint":original,"performance":"skipped"}))
	quit(0)
