class_name HospitalContent
extends RefCounted

var catalog: Dictionary
var balance: Dictionary
var layouts: Dictionary
var _indexes: Dictionary = {}
var _assets: Dictionary = {}
var error: String = ""

func _init() -> void:
	catalog = _read("res://docs/data/content-catalog.json")
	balance = _read("res://docs/data/balance.json")
	layouts = _read("res://docs/data/clinical-layouts.json")
	var production: Dictionary = _read("res://assets/models/stage01-production.json")
	for asset: Dictionary in production.get("assets",[]):
		_assets[asset.content_id] = asset
	for collection: String in catalog:
		if catalog[collection] is Array:
			var index: Dictionary = {}
			for entry: Variant in catalog[collection]:
				if entry is Dictionary:
					var key: String = str(entry.get("id",entry.get("definition_id","")))
					if not key.is_empty():
						index[key] = entry
			_indexes[collection] = index

func definition(collection: String, id: String) -> Dictionary:
	return _indexes.get(collection, {}).get(id, {})

func facility_definition(id: String) -> Dictionary:
	for collection: String in ["machines","clinical_equipment","furniture_equipment"]:
		var record: Dictionary = definition(collection,id)
		if not record.is_empty():
			return record
	return {}

func asset_anchor(id: String, slot: String) -> Vector3:
	var point: Array = _assets[id].anchors_engine_local_m[slot]
	return Vector3(float(point[0]),float(point[1]),float(point[2]))

func actor_body(actor: Dictionary) -> Dictionary:
	var dimensions: Dictionary = definition("species",actor.species_id).body.duplicate()
	var binding: Dictionary = definition("treatment_bindings",actor.get("body_binding_id",""))
	var symptom: Dictionary = binding.get("symptom_envelope",{})
	for axis: String in ["width_m","depth_m","height_m"]:
		dimensions[axis] = maxf(float(dimensions[axis]),float(symptom.get(axis,0)))
	return dimensions

func facility_fee(definition_id: String, kind: String) -> int:
	for fee: Dictionary in balance.billing.facility_fees:
		if fee.equipment_id == definition_id and fee.service_kind == kind:
			return int(fee.amount)
	return 0

func doctor_fee(title_id: String) -> int:
	for fee: Dictionary in balance.billing.doctor_consultation_fees:
		if fee.title_id == title_id:
			return int(fee.amount)
	return 0

func _read(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		error = "无法读取核心内容：" + path
		return {}
	var json: JSON = JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		error = "核心内容格式错误：" + path
		return {}
	return json.data
