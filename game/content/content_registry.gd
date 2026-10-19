class_name ContentRegistry
extends RefCounted

const FACILITY_COLLECTIONS: Array[String] = ["machines", "clinical_equipment", "furniture_equipment", "service_equipment", "accessibility_equipment", "staff_recreation_equipment", "vertical_connectors", "doors"]

var _data: Dictionary = {}
var _indexes: Dictionary = {}
var _bindings: Dictionary = {}
var _facilities: Dictionary = {}
var _compatibility: Dictionary = {}
var _equipment_effects: Dictionary = {}

var fingerprint: String:
	get:
		return str(_data.get("fingerprint", ""))

func _init(data: Dictionary = {}) -> void:
	_data = data
	_indexes = _data.get("indexes", {})
	for binding: Dictionary in _indexes.get("treatment_bindings", {}).values():
		var pair: String = str(binding.species_id) + "|" + str(binding.disease_id)
		if not _bindings.has(pair):
			_bindings[pair] = []
		_bindings[pair].append(binding)
	for pair: String in _bindings:
		_bindings[pair].sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
	_compatibility = {"catalog":_legacy(_data.get("catalog", {})),"indexes":{},
		"rules":_legacy(_data.get("rules", {})),"layouts":_legacy(_data.get("layouts", {})),
		"starter_layout":_legacy(_data.get("starter_layout", {})),"asset_index":_legacy(_data.get("asset_index", {}))}
	for collection_name: String in _data.get("collections", {}):
		var records: Variant = _compatibility.catalog.get(collection_name)
		var index: Dictionary = {}
		if records is Dictionary:
			index = records
		elif records is Array:
			for record: Variant in records:
				if record is Dictionary:
					var identifier: String = str(record.get("id", record.get("definition_id", "")))
					if not identifier.is_empty():
						index[identifier] = record
		_compatibility.indexes[collection_name] = index
	for collection: String in FACILITY_COLLECTIONS:
		for identifier: String in _indexes.get(collection,{}):
			if not _facilities.has(identifier): _facilities[identifier] = legacy_definition(collection,identifier)
	for profile: Dictionary in _compatibility.catalog.get("medical_equipment_profiles",[]):
		_equipment_effects[str(profile.definition_id)] = str(profile.effect_kind)
	_freeze(_equipment_effects)
	_freeze(_data)
	_freeze(_bindings)
	_freeze(_facilities)
	_freeze(_compatibility)

func definition(collection: String, identifier: String) -> Dictionary:
	return _indexes.get(collection, {}).get(canonical_id(identifier), {})

func equipment_effect_kind(identifier: String) -> String:
	return str(_equipment_effects.get(legacy_id(identifier),""))

func legacy_definition(collection: String, identifier: String) -> Dictionary:
	return _compatibility.get("indexes", {}).get(collection, {}).get(legacy_id(identifier), {})

func collection(name: String) -> Variant:
	return _data.get("collections", {}).get(name, [])

func legacy_catalog() -> Dictionary:
	return _compatibility.get("catalog", {})

func rules() -> Dictionary:
	return _compatibility.get("rules", {})

func layouts() -> Dictionary:
	return _compatibility.get("layouts", {})

func starter_layout() -> Dictionary:
	return _compatibility.get("starter_layout", {})

func assets() -> Dictionary:
	return _compatibility.get("asset_index", {})

func packs() -> Array:
	return _data.get("packs", [])

func snapshot_identity() -> Array[Dictionary]:
	var identity: Array[Dictionary] = []
	for pack: Dictionary in packs():
		identity.append(pack.duplicate(true))
	return identity

func facility_definition(identifier: String) -> Dictionary:
	return _facilities.get(canonical_id(identifier),{})

func resolve_bindings(species_id: String, disease_id: String) -> Array:
	return _bindings.get(canonical_id(species_id) + "|" + canonical_id(disease_id), [])

func effective_case_body(species_id: String, disease_id: String) -> Dictionary:
	return _data.get("envelopes", {}).get(canonical_id(species_id) + "|" + canonical_id(disease_id), {})

static func canonical_id(identifier: String) -> String:
	return identifier if identifier.contains(":") else "core:" + identifier

static func legacy_id(identifier: String) -> String:
	return identifier.trim_prefix("core:")

static func _legacy(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value:
			result[legacy_id(str(key))] = _legacy(value[key])
		return result
	if value is Array:
		var result: Array = []
		for child: Variant in value:
			result.append(_legacy(child))
		return result
	if value is String:
		return legacy_id(value)
	return value

static func _freeze(value: Variant) -> void:
	if value is Dictionary:
		for child: Variant in value.values():
			_freeze(child)
		value.make_read_only()
	elif value is Array:
		for child: Variant in value:
			_freeze(child)
		value.make_read_only()
