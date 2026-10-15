class_name HospitalContent
extends RefCounted

var registry: ContentRegistry
var error: String = ""

var catalog: Dictionary:
	get:
		return registry.legacy_catalog() if registry != null else {}
var balance: Dictionary:
	get:
		return registry.rules() if registry != null else {}
var layouts: Dictionary:
	get:
		return registry.layouts() if registry != null else {}
var starter_layout: Dictionary:
	get:
		return registry.starter_layout() if registry != null else {}
var assets: Dictionary:
	get:
		return registry.assets() if registry != null else {}
var _assets: Dictionary:
	get:
		return assets
var content_fingerprint: String:
	get:
		return registry.fingerprint if registry != null else ""
var packs: Array:
	get:
		return registry.packs() if registry != null else []

func _init(paths: PackedStringArray = PackedStringArray(["res://content/core"])) -> void:
	load_packs(paths)

func load_packs(paths: PackedStringArray) -> bool:
	var candidate: ContentLoadResult = ContentLoader.new().load_packs(paths)
	if not candidate.accepted:
		error = "；".join(candidate.errors)
		return false
	registry = candidate.registry
	error = ""
	return true

func snapshot_identity() -> Array[Dictionary]:
	return registry.snapshot_identity() if registry != null else []

func definition(collection: String, id: String) -> Dictionary:
	return registry.legacy_definition(collection, id) if registry != null else {}

func facility_definition(id: String) -> Dictionary:
	return registry.facility_definition(id) if registry != null else {}

func resolve_bindings(species_id: String, disease_id: String) -> Array:
	return registry.resolve_bindings(species_id, disease_id) if registry != null else []

func asset_anchor(id: String, slot: String, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	var asset: Dictionary = assets.get(ContentRegistry.legacy_id(id), {})
	var point: Variant = asset.get("anchors_engine_local_m", {}).get(slot)
	if not point is Array or point.size() != 3:
		return fallback
	return Vector3(float(point[0]), float(point[1]), float(point[2]))

func actor_body(actor: Dictionary) -> Dictionary:
	var species: Dictionary = definition("species", actor.species_id)
	if species.is_empty():
		return {}
	var dimensions: Dictionary = species.body.duplicate()
	var binding: Dictionary = definition("treatment_bindings",actor.get("body_binding_id",""))
	var symptom: Dictionary = binding.get("symptom_envelope",{})
	for axis: String in ["width_m","depth_m","height_m"]:
		dimensions[axis] = maxf(float(dimensions[axis]),float(symptom.get(axis,0)))
	return dimensions

func facility_fee(definition_id: String, kind: String) -> int:
	for fee: Dictionary in balance.get("billing", {}).get("facility_fees", []):
		if fee.equipment_id == ContentRegistry.legacy_id(definition_id) and fee.service_kind == kind:
			return int(fee.amount)
	return 0

func doctor_fee(title_id: String) -> int:
	for fee: Dictionary in balance.get("billing", {}).get("doctor_consultation_fees", []):
		if fee.title_id == ContentRegistry.legacy_id(title_id):
			return int(fee.amount)
	return 0
