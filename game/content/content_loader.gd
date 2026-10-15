class_name ContentLoader
extends RefCounted

const GAME_VERSION: String = "1.97.0"
const SCHEMA_PATH: String = "res://game/content/schema100.json"
const MANIFEST_FIELDS: Array[String] = ["pack_id", "version", "schema_version", "min_game_version", "requires", "files"]
const AXES: Array[String] = ["width_m", "depth_m", "height_m"]

var _error: String = ""
var _schema: Dictionary = {}

func load_packs(paths: PackedStringArray) -> ContentLoadResult:
	_error = ""
	_schema = _read_json(SCHEMA_PATH)
	var result: ContentLoadResult = ContentLoadResult.new()
	var manifests: Dictionary = {}
	var payloads: Dictionary = {}
	var packs: Array = []
	for directory: String in paths:
		if not _error.is_empty():
			break
		var manifest_path: String = directory.path_join("manifest.json")
		var manifest: Dictionary = _read_json(manifest_path)
		if not _fields(manifest, MANIFEST_FIELDS, manifest_path):
			break
		var pack_id: String = str(manifest.pack_id)
		if not _pack_id_valid(pack_id) or manifests.has(pack_id):
			_fail(manifest_path, "包身份无效或重复")
			break
		if not _integer(manifest.schema_version) or int(manifest.schema_version) != int(_schema.get("schema_version", -1)):
			_fail(pack_id, "不支持的内容 schema")
			break
		if not _version_valid(manifest.version) or not _version_valid(manifest.min_game_version) or _version_compare(GAME_VERSION, manifest.min_game_version) < 0:
			_fail(pack_id, "包版本无效或需要更新游戏")
			break
		if not manifest.requires is Array or not manifest.files is Array:
			_fail(pack_id, "requires/files 必须是数组")
			break
		var dependency_ids: Array = []
		for dependency: Variant in manifest.requires:
			if not dependency is Dictionary or not _fields(dependency, ["pack_id", "version_range"], pack_id):
				_fail(pack_id, "依赖结构错误")
				break
			if not dependency.pack_id is String or not _pack_id_valid(dependency.pack_id) or not dependency.version_range is String or dependency_ids.has(dependency.pack_id):
				_fail(pack_id, "依赖身份或范围无效/重复")
				break
			dependency_ids.append(dependency.pack_id)
		if pack_id != "core" and not dependency_ids.has("core"):
			_fail(pack_id, "扩展必须声明核心包依赖")
			break
		var files: Dictionary = {}
		for item: Variant in manifest.files:
			if not item is Dictionary or not _fields(item, ["path", "sha256"], pack_id):
				_fail(pack_id, "文件清单结构错误")
				break
			if not item.path is String or not item.sha256 is String or not _safe_relative(item.path) or files.has(item.path):
				_fail(pack_id, "文件路径无效或重复")
				break
			var path: String = item.path
			if not _schema.files.has(path) and not (path.begins_with("assets/") and not path.ends_with(".json")):
				_fail(path, "未注册的内容集合或文件")
				break
			var full_path: String = directory.path_join(path)
			if not FileAccess.file_exists(full_path) or FileAccess.get_sha256(full_path) != item.sha256:
				_fail(path, "文件缺失或 SHA-256 不匹配")
				break
			files[path] = full_path
		if pack_id == "core":
			for required: String in _schema.get("core_required_files", []):
				if not files.has(required):
					_fail(pack_id, "缺少核心规则/内容文件：" + required)
		elif files.has("rules.json") or files.has("layouts.json") or files.has("starter_layout.json"):
			_fail(pack_id, "扩展不能覆盖核心规则或起始布局")
		manifests[pack_id] = manifest
		payloads[pack_id] = files
		packs.append({"id":pack_id, "version":str(manifest.version), "fingerprint":FileAccess.get_sha256(manifest_path)})
	if not manifests.has("core"):
		_fail("packs", "缺少必装核心包")
	var graph: Dictionary = {}
	for pack_id: String in manifests:
		graph[pack_id] = []
		for dependency: Dictionary in manifests[pack_id].requires:
			graph[pack_id].append(dependency.pack_id)
			if not manifests.has(dependency.pack_id):
				_fail(pack_id, "缺少依赖：" + str(dependency.pack_id))
			elif not _version_matches(str(manifests[dependency.pack_id].version), dependency.version_range):
				_fail(pack_id, "依赖版本不匹配：" + str(dependency.pack_id))
	_validate_graph(graph, "packs")
	if not _error.is_empty():
		result.errors.append(_error)
		return result
	var collections: Dictionary = {}
	var indexes: Dictionary = {}
	var special: Dictionary = {}
	var assets: Dictionary = {}
	for collection: String in _schema.collections:
		collections[collection] = [] if _schema.collections[collection].type == "array" else {}
		indexes[collection] = {}
	var pack_ids: Array = manifests.keys()
	pack_ids.sort()
	for pack_id: String in pack_ids:
		var files: Dictionary = payloads[pack_id]
		var locale: Dictionary = _read_locale(str(files.get("locale/zh_CN.csv", "")))
		for path: String in files:
			if not _schema.files.has(path) or path.ends_with(".csv"):
				continue
			var source: Variant = _read_value(files[path])
			var value: Variant = _normalize(source, _schema.files[path], pack_id, pack_id + "/" + path, locale)
			if not _error.is_empty():
				break
			var collection: String = path.trim_suffix(".json")
			if collections.has(collection):
				if value is Array:
					var identity_field: String = str(_schema.identity_fields.get(collection, ""))
					for record: Variant in value:
						if not identity_field.is_empty():
							var identifier: String = str(record[identity_field])
							if not identifier.begins_with(pack_id + ":") or indexes[collection].has(identifier):
								_fail(identifier, "定义命名空间不属于该包或 ID 重复")
								break
							indexes[collection][identifier] = record
						collections[collection].append(record)
				else:
					for identifier: String in value:
						if not identifier.begins_with(pack_id + ":") or collections[collection].has(identifier):
							_fail(identifier, "映射定义命名空间不属于该包或 ID 重复")
							break
						collections[collection][identifier] = value[identifier]
						indexes[collection][identifier] = value[identifier]
			elif path == "assets/index.json":
				for asset: Dictionary in value.assets:
					if assets.has(asset.content_id):
						_fail(str(asset.content_id), "资源绑定重复")
					assets[asset.content_id] = asset
			else:
				special[collection] = value
	for collection: String in collections:
		_validate_references(collections[collection], _schema.collections[collection], indexes, collection)
	for collection: String in special:
		_validate_references(special[collection], _schema.files[collection + ".json"], indexes, collection)
	_validate_references({"assets":assets.values()}, _schema.files["assets/index.json"], indexes, "assets")
	var envelopes: Dictionary = _validate_semantics(collections, indexes)
	if not _error.is_empty():
		result.errors.append(_error)
		return result
	packs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
	var identity: String = ""
	for pack: Dictionary in packs:
		identity += str(pack.id) + "|" + str(pack.version) + "|" + str(pack.fingerprint) + "\n"
	var catalog: Dictionary = collections.duplicate()
	catalog.schema_version = int(_schema.schema_version)
	catalog.content_version = str(manifests.core.version)
	result.registry = ContentRegistry.new({"collections":collections,"catalog":catalog,"indexes":indexes,"rules":special.rules,
		"layouts":special.layouts,"starter_layout":special.starter_layout,"asset_index":assets,"packs":packs,
		"fingerprint":identity.sha256_text(),"envelopes":envelopes})
	return result

func _normalize(value: Variant, schema: Dictionary, pack_id: String, path: String, locale: Dictionary) -> Variant:
	if not _error.is_empty():
		return null
	if value == null and bool(schema.get("nullable", false)):
		return null
	var kind: String = str(schema.type)
	if kind == "object":
		if not value is Dictionary:
			_fail(path, "必须是对象")
			return null
		for key: String in value:
			if not schema.properties.has(key):
				_fail(path, "未知字段：" + key)
		for key: String in schema.required:
			if not value.has(key):
				_fail(path, "缺少字段：" + key)
		if not _error.is_empty():
			return null
		var output: Dictionary = {}
		for key: String in value:
			output[key] = _normalize(value[key], schema.properties[key], pack_id, path + "." + key, locale)
		return output
	if kind == "map":
		if not value is Dictionary:
			_fail(path, "映射集合必须是对象，不能使用数组")
			return null
		var output: Dictionary = {}
		for key: String in value:
			var normalized_key: String = _canonical(key, pack_id, path) if schema.has("key_ref") else key
			output[normalized_key] = _normalize(value[key], schema.values, pack_id, path + "." + key, locale)
		return output
	if kind == "array":
		if not value is Array:
			_fail(path, "必须是数组")
			return null
		var output: Array = []
		for index: int in value.size():
			output.append(_normalize(value[index], schema.items, pack_id, path + "[" + str(index) + "]", locale))
		return output
	if kind == "string":
		if not value is String:
			_fail(path, "必须是字符串")
			return null
		var text_value: String = value
		if text_value.begins_with("@zh:"):
			var key: String = text_value.trim_prefix("@zh:")
			if not locale.has(key) or str(locale[key]).strip_edges().is_empty():
				_fail(path, "缺少中文文本：" + key)
				return null
			text_value = str(locale[key])
		if bool(schema.get("identity", false)) or schema.has("ref"):
			return _canonical(text_value, pack_id, path)
		if schema.has("enum") and not text_value in schema["enum"]:
			_fail(path, "未注册的处理器/规则：" + text_value)
		return text_value
	if kind == "integer":
		if not _integer(value):
			_fail(path, "必须是整数，不能使用布尔或小数")
			return null
		value = int(value)
	elif kind == "number":
		if not (value is int or value is float) or not is_finite(float(value)):
			_fail(path, "必须是有限数值")
			return null
	elif kind == "boolean":
		if not value is bool:
			_fail(path, "必须是布尔值")
	elif kind == "null":
		if value != null:
			_fail(path, "必须是空值")
	else:
		_fail(path, "未注册字段类型：" + kind)
	if schema.has("minimum") and (value is int or value is float) and float(value) < float(schema.minimum):
		_fail(path, "数值低于允许下界")
	return value

func _validate_references(value: Variant, schema: Dictionary, indexes: Dictionary, path: String) -> void:
	if not _error.is_empty() or value == null:
		return
	if schema.has("ref") and not _reference_exists(str(value), schema.ref, indexes):
		_fail(path, "失效引用：" + str(value))
	if schema.type == "object":
		for key: String in value:
			_validate_references(value[key], schema.properties[key], indexes, path + "." + key)
	elif schema.type == "map":
		for key: String in value:
			if schema.has("key_ref") and not _reference_exists(key, schema.key_ref, indexes):
				_fail(path, "失效映射引用：" + key)
			_validate_references(value[key], schema.values, indexes, path + "." + key)
	elif schema.type == "array":
		for index: int in value.size():
			_validate_references(value[index], schema.items, indexes, path + "[" + str(index) + "]")

func _reference_exists(identifier: String, targets: Array, indexes: Dictionary) -> bool:
	for target: String in targets:
		if indexes.get(target, {}).has(identifier):
			return true
	return false

func _validate_semantics(collections: Dictionary, indexes: Dictionary) -> Dictionary:
	var envelopes: Dictionary = {}
	if not _error.is_empty():
		return envelopes
	_validate_dimensions(collections, "content")
	var research_graph: Dictionary = {}
	for research: Dictionary in indexes.research.values():
		research_graph[research.id] = research.requires
	_validate_graph(research_graph, "research")
	var talents: Dictionary = {}
	for talent: Dictionary in indexes.staff_talents.values():
		if talents.has(talent.species_id):
			_fail(str(talent.id), "种族职员天赋重复")
		talents[talent.species_id] = talent
		var handler: Dictionary = indexes.staff_talent_handlers[talent.handler_id]
		if float(talent.value) < float(handler.min_value) or float(talent.value) > float(handler.max_value):
			_fail(str(talent.id), "天赋值超出处理器范围")
	for handler: Dictionary in indexes.staff_talent_handlers.values():
		if int(_schema.handler_versions.get(handler.id, -1)) != int(handler.version):
			_fail(str(handler.id), "缺少版本化规则处理器")
	var rigs: Dictionary = {}
	var roles: Array = []
	for adapter: Dictionary in indexes.staff_rig_adapters.values():
		rigs[adapter.rig] = adapter.roles
	for role: Dictionary in indexes.staff_role_profiles.values():
		roles.append(role.role)
	for species: Dictionary in indexes.species.values():
		_validate_body(species.body, str(species.id))
		if not talents.has(species.id) or not rigs.has(species.rig):
			_fail(str(species.id), "缺少职员天赋或骨架适配")
			continue
		for role: String in roles:
			if not role in rigs[species.rig]:
				_fail(str(species.id), "职员骨架缺少岗位：" + role)
	var bound_species: Dictionary = {}
	for binding: Dictionary in indexes.treatment_bindings.values():
		var species: Dictionary = indexes.species[binding.species_id]
		if binding.animation_profile != species.rig:
			_fail(str(binding.id), "病例骨架与种族不符")
		var symptom: Dictionary = binding.get("symptom_envelope", species.body)
		_validate_body(symptom, str(binding.id))
		var effective: Dictionary = {}
		for axis: String in AXES:
			effective[axis] = maxf(float(species.body[axis]), float(symptom[axis]))
		var pair: String = str(binding.species_id) + "|" + str(binding.disease_id)
		if envelopes.has(pair) and envelopes[pair] != effective:
			_fail(str(binding.id), "同种族病症组合的逐轴有效包络冲突：" + pair)
		envelopes[pair] = effective
		bound_species[binding.species_id] = true
		for presentation: String in ["symptom_variant", "treatment_variant", "recovery_variant"]:
			if str(binding[presentation]).strip_edges().is_empty():
				_fail(str(binding.id), "缺少身体表现适配")
	for species_id: String in indexes.species:
		if not bound_species.has(species_id):
			_fail(species_id, "新种族必须至少有一条完整病例适配")
	var facility_ids: Dictionary = {}
	for collection: String in ContentRegistry.FACILITY_COLLECTIONS:
		for identifier: String in indexes[collection]:
			if facility_ids.has(identifier):
				_fail(identifier, "同一实体拥有多个设施定义")
			facility_ids[identifier] = true
	for door: Dictionary in indexes.doors.values():
		if float(door.clear_width_m) <= 0.0 or float(door.clear_width_m) >= float(door.span_cells)*1.5 or float(door.clear_height_m) <= 0.0 or door.fit_policy != "automatic":
			_fail(str(door.id), "门的净宽/高或自动适配规则无效")
	for routine: Dictionary in indexes.treatment_routines.values():
		if routine.beats.size() != 4 or float(routine.service_seconds) <= 0.0 or float(routine.service_seconds) > 300.0:
			_fail(str(routine.id), "治疗演出必须有合法工时和四段")
	for protocol: Dictionary in indexes.treatment_protocols.values():
		if protocol.kind == "surgery":
			if not protocol.requires_distinct_staff:
				_fail(str(protocol.id), "手术必须使用互异医护岗位")
			for ability: String in ["min_surgeon_surgery", "min_anesthetist_surgery", "min_nurse_surgery"]:
				if int(protocol[ability]) < 1 or int(protocol[ability]) > 5:
					_fail(str(protocol.id), "手术岗位资格不可达到")
		elif not protocol.uses_disease_profile:
			if protocol.clinical_profiles.size() != indexes.profiles.size():
				_fail(str(protocol.id), "舒缓临床档位不完整")
	var disease_protocols: Dictionary = {}
	var unlocked: Array = collections.initial_disease_ids.duplicate()
	for research: Dictionary in indexes.research.values():
		unlocked.append_array(research.disease_ids)
	for plan: Dictionary in indexes.treatment_plans.values():
		if not disease_protocols.has(plan.disease_id):
			disease_protocols[plan.disease_id] = []
		disease_protocols[plan.disease_id].append(indexes.treatment_protocols[plan.protocol_id])
	for disease_id: String in indexes.diseases:
		var has_routine: bool = false
		var has_gentle: bool = false
		for protocol: Dictionary in disease_protocols.get(disease_id, []):
			if protocol.kind == "outpatient":
				has_routine = has_routine or bool(protocol.uses_disease_profile)
				has_gentle = has_gentle or not bool(protocol.uses_disease_profile)
		if not has_routine or not has_gentle or not disease_id in unlocked:
			_fail(disease_id, "病症缺少常规/舒缓方案或解锁节点")
	var pairs: Dictionary = {}
	for adapter: Dictionary in indexes.surgical_adapters.values():
		var binding: Dictionary = indexes.treatment_bindings[adapter.binding_id]
		var plan: Dictionary = indexes.treatment_plans[adapter.plan_id]
		var protocol: Dictionary = indexes.treatment_protocols[plan.protocol_id]
		if binding.disease_id != plan.disease_id or protocol.kind != "surgery":
			_fail(str(adapter.id), "手术适配与病例/方案不符")
		var anchors: Array = adapter.required_anchors.duplicate()
		anchors.sort()
		if anchors != ["exit", "patient_support", "symptom_target"]:
			_fail(str(adapter.id), "手术承托/器械/出口锚点不完整")
		var pair: String = str(adapter.binding_id) + "|" + str(adapter.plan_id)
		if pairs.has(pair):
			_fail(str(adapter.id), "手术适配重复")
		pairs[pair] = true
	for task: Dictionary in indexes.tasks.values():
		if task.eligibility_rule.has("maintainable_equipment_min") and (not _integer(task.eligibility_rule.maintainable_equipment_min) or int(task.eligibility_rule.maintainable_equipment_min) <= 0):
			_fail(str(task.id), "维护对象最低数必须是严格正整数")
	for incident: Dictionary in indexes.incidents.values():
		if not incident.release_reservations_on_finish or not incident.restores_state or 4.0 + float(incident.natural_resolution_seconds) + float(incident.actor_recovery_seconds) > float(incident.max_duration_seconds):
			_fail(str(incident.id), "事件缺少有界终止及资源释放")
	return envelopes

func _validate_body(body: Dictionary, path: String) -> void:
	if body.size() != AXES.size():
		_fail(path, "身体必须提供完整米制宽深高")
		return
	for axis: String in AXES:
		if not body.has(axis) or not (body[axis] is int or body[axis] is float) or not is_finite(float(body[axis])) or float(body[axis]) <= 0.0 or float(body[axis]) > 7.0:
			_fail(path, "身体包络数值无效")

func _validate_dimensions(value: Variant, path: String) -> void:
	if value is Dictionary:
		for key: String in value:
			var child: Variant = value[key]
			if key in ["footprint", "min_inner_size", "cabin_size"] and child != null:
				if not child is Array or child.size() != 2:
					_fail(path, "占地必须是二维格数组")
				else:
					for dimension: Variant in child:
						if not _integer(dimension) or int(dimension) <= 0 or int(dimension) > 96:
							_fail(path, "占地超出合法地图范围")
			_validate_dimensions(child, path + "." + key)
	elif value is Array:
		for child: Variant in value:
			_validate_dimensions(child, path + "[]")

func _validate_graph(graph: Dictionary, path: String) -> void:
	if not _error.is_empty():
		return
	var complete: Dictionary = {}
	for key: String in graph:
		_visit_dependency(key, graph, {}, complete, path)

func _visit_dependency(key: String, graph: Dictionary, active: Dictionary, complete: Dictionary, path: String) -> void:
	if not _error.is_empty() or complete.has(key):
		return
	if active.has(key):
		_fail(path, "依赖循环：" + key)
		return
	if not graph.has(key):
		_fail(path, "缺少依赖：" + key)
		return
	active[key] = true
	for dependency: String in graph[key]:
		_visit_dependency(dependency, graph, active, complete, path)
	active.erase(key)
	complete[key] = true

func _canonical(identifier: String, pack_id: String, path: String) -> String:
	var parts: PackedStringArray = identifier.split(":")
	var pack_namespace: String = pack_id if parts.size() == 1 else parts[0]
	var local_id: String = parts[0] if parts.size() == 1 else parts[1]
	var pattern: RegEx = RegEx.new()
	pattern.compile("^[A-Za-z0-9_][A-Za-z0-9_.-]*$")
	if parts.size() > 2 or not _pack_id_valid(pack_namespace) or pattern.search(local_id) == null:
		_fail(path, "定义 ID 无效：" + identifier)
	return pack_namespace + ":" + local_id

func _pack_id_valid(identifier: String) -> bool:
	var pattern: RegEx = RegEx.new()
	pattern.compile("^(core|[a-z][a-z0-9_-]*(\\.[a-z][a-z0-9_-]*)+)$")
	return pattern.search(identifier) != null

func _safe_relative(path: String) -> bool:
	if path.is_absolute_path() or path.contains("\\") or path.contains(":"):
		return false
	for component: String in path.split("/"):
		if component in ["", ".", ".."]:
			return false
	return true

func _read_locale(path: String) -> Dictionary:
	var locale: Dictionary = {}
	if path.is_empty():
		return locale
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_csv_line() != PackedStringArray(["key", "zh_CN"]):
		_fail(path, "中文 CSV 表头错误")
		return locale
	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()
		if row.size() == 1 and row[0].is_empty():
			continue
		if row.size() != 2 or row[0].is_empty() or locale.has(row[0]):
			_fail(path, "中文 CSV 键重复或字段错误")
			break
		locale[row[0]] = row[1]
	return locale

func _read_value(path: String) -> Variant:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail(path, "无法读取文件")
		return null
	var json: JSON = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		_fail(path, "JSON 格式错误：" + json.get_error_message())
		return null
	return json.data

func _read_json(path: String) -> Dictionary:
	var value: Variant = _read_value(path)
	if not value is Dictionary:
		_fail(path, "必须是 JSON 对象")
		return {}
	return value

func _fields(value: Dictionary, names: Array, path: String) -> bool:
	if value.size() != names.size():
		_fail(path, "清单字段错误")
		return false
	for name: String in names:
		if not value.has(name):
			_fail(path, "缺少清单字段：" + name)
			return false
	return true

func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value))

func _version_valid(value: Variant) -> bool:
	if not value is String:
		return false
	var expression: RegEx = RegEx.new()
	expression.compile("^[0-9]+\\.[0-9]+\\.[0-9]+$")
	return expression.search(value) != null

func _version_compare(left: String, right: String) -> int:
	var a: PackedStringArray = left.split(".")
	var b: PackedStringArray = right.split(".")
	for index: int in 3:
		if int(a[index]) != int(b[index]):
			return 1 if int(a[index]) > int(b[index]) else -1
	return 0

func _version_matches(actual: String, requested: String) -> bool:
	for alternative: String in requested.split("||"):
		var matched: bool = not alternative.strip_edges().is_empty()
		for token: String in alternative.strip_edges().split(" ", false):
			if token == "*":
				continue
			var expression: RegEx = RegEx.new()
			expression.compile("^(>=|<=|>|<|=|\\^|~)?([0-9]+\\.[0-9]+\\.[0-9]+)$")
			var found: RegExMatch = expression.search(token)
			if found == null:
				_fail(requested, "不支持的语义版本范围")
				return false
			var operator: String = found.get_string(1)
			var target: String = found.get_string(2)
			var comparison: int = _version_compare(actual, target)
			match operator:
				">=": matched = matched and comparison >= 0
				"<=": matched = matched and comparison <= 0
				">": matched = matched and comparison > 0
				"<": matched = matched and comparison < 0
				"^", "~":
					var parts: PackedStringArray = target.split(".")
					var upper: String
					if operator == "~" or int(parts[0]) == 0 and int(parts[1]) > 0:
						upper = "%d.%d.0" % [int(parts[0]), int(parts[1]) + 1]
					elif int(parts[0]) > 0:
						upper = "%d.0.0" % (int(parts[0]) + 1)
					else:
						upper = "0.0.%d" % (int(parts[2]) + 1)
					matched = matched and comparison >= 0 and _version_compare(actual, upper) < 0
				_: matched = matched and comparison == 0
		if matched:
			return true
	return false

func _fail(path: String, reason: String) -> void:
	if _error.is_empty():
		_error = path + "：" + reason
