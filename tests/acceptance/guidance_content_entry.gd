extends RefCounted

# Calculation/validation boundaries only. These fixtures supply legal initial
# bodies and never claim that routing, service arrival, or nursing work occurred.
func run_case(content: HospitalContent) -> Dictionary:
	var entry: Dictionary = _entry_checks(content)
	var fit: Dictionary = _fit_checks(content)
	return {"ok":entry.ok and fit.ok,"entry":entry,"guide_desk_fit":fit}

func _entry_checks(content: HospitalContent) -> Dictionary:
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"入口校验",false,content)
	var original: Dictionary = world.freeze()
	var checks: Dictionary = {"default_first_floor":world.facts.entry.floor_id==1 and world.validate(content).is_empty()}
	var legacy: WorldState = WorldState.new(original.duplicate(true))
	legacy.facts.erase("entry")
	legacy.facts.erase("gameplay_version")
	var legacy_before: Dictionary = legacy.freeze()
	checks.legacy_missing_default_preserved = legacy.entry_validation_error().is_empty() and legacy.validate(content).is_empty() and legacy.freeze()==legacy_before
	legacy.facts.gameplay_version = 0
	checks.explicit_legacy_version_preserved = legacy.validate(content).is_empty() and not legacy.facts.has("entry")
	legacy.facts.gameplay_version = 1
	checks.production_missing_entry_rejected = not legacy.entry_validation_error().is_empty() and not legacy.validate(content).is_empty()
	var errors: Dictionary = {}
	for floor_id: Variant in [0,2,-1,1.5,"1",null]:
		var invalid: WorldState = WorldState.new(original.duplicate(true))
		invalid.facts.entry.floor_id = floor_id
		var before: Dictionary = invalid.freeze()
		var reason: String = invalid.validate(content)
		var key: String = "floor_"+JSON.stringify(floor_id)
		checks[key] = not reason.is_empty() and invalid.freeze()==before
		errors[key] = reason
	for record: Variant in [null,[],{}, {"floor_id":1}, {"floor_id":1,"cell":[47]}, {"floor_id":1,"cell":[47.5,93]}, {"floor_id":1,"cell":[47,93],"exit_cell":[48,"95"]}]:
		var invalid: WorldState = WorldState.new(original.duplicate(true))
		invalid.facts.entry = record
		var before: Dictionary = invalid.freeze()
		var reason: String = invalid.validate(content)
		var key: String = "malformed_"+JSON.stringify(record)
		checks[key] = not reason.is_empty() and invalid.freeze()==before
		errors[key] = reason
	var decoded: WorldState = WorldState.new(original.duplicate(true))
	decoded.facts.entry = {"floor_id":1.0,"cell":[47.0,93.0]}
	checks.integral_json_numbers_and_optional_exit_supported = decoded.validate(content).is_empty()
	checks.original_unchanged = world.freeze()==original
	return {"ok":not checks.values().has(false),"checks":checks,"rejections":errors}

func _fit_checks(content: HospitalContent) -> Dictionary:
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"导诊台适配校验",false,content)
	var definition: Dictionary = content.facility_definition("SE01")
	HospitalFactory._add_facility(world,{"id":"guide","definition_id":"SE01","anchor":[44,74],"size":definition.footprint.duplicate(),"room_id":null},content)
	world.facts.actors["patient"] = _actor("patient","S49",[36,84])
	HospitalFactory._add_staff(world,"nurse","导诊护士","nurse",[52,84],content)
	world.facts.actors.nurse.species_id = "S53"
	world.touch()
	var space: HospitalSpace = HospitalSpace.new(content)
	var initial: Dictionary = world.freeze()
	var input_error: String = world.validate(content)
	var fit: Dictionary = space.facility_quote(world,"guide","patient",["nurse"])
	var checks: Dictionary = {
		"legal_input":input_error.is_empty(),
		"fixed_price_and_footprint":definition.price==600 and definition.footprint==[2,1],
		"reuse_workstation_profile":definition.fit_profile_id=="FF06" and definition.max_clearance_cells==3 and float(definition.max_height_m)==6.5,
		"real_patient_and_nurse_quote":fit.get("ok",false) and not fit.get("unchanged",false) and fit.get("staff_ids",[])==["nurse"] and fit.get("regions",[]).has([44,75,1,1]) and fit.get("regions",[]).has([44,71,3,3]),
		"quote_readonly":world.freeze()==initial}
	var missing: Dictionary = space.facility_quote(world,"guide","patient",["missing_nurse"])
	checks.missing_real_nurse_rejected = not missing.get("ok",true)
	# This cell is outside both the 2x1 desk and one-cell staff anchor. The
	# existing S53 body's three-cell clearance behind the desk is what makes it unavailable.
	world.facts.floors.overrides["1"].blocked.append([46,71])
	world.touch()
	var obstructed: Dictionary = space.facility_quote(world,"guide","patient",["nurse"])
	checks.large_nurse_geometry_rejected = not obstructed.get("ok",true)
	world.facts.floors.overrides["1"].blocked.erase([46,71])
	world.facts.actors["blocker"] = _actor("blocker","S49",[46,71])
	world.touch()
	var occupied: Dictionary = space.facility_quote(world,"guide","patient",["nurse"])
	checks.large_nurse_occupancy_rejected = not occupied.get("ok",true)
	world.facts.actors.erase("blocker")
	world.touch()
	checks.unblocked_nurse_recovers = space.facility_quote(world,"guide","patient",["nurse"]).get("ok",false)
	world.facts.actors.patient.species_id = "S53"
	world.facts.actors.nurse.species_id = "S49"
	world.touch()
	var large_patient: Dictionary = space.facility_quote(world,"guide","patient",["nurse"])
	checks.real_patient_size = large_patient.get("ok",false) and large_patient.get("regions",[]).has([44,75,3,3]) and large_patient.get("footprint",[])==[2,1]
	world.facts.floors.overrides["1"].blocked.append([46,77])
	world.touch()
	var blocked_patient: Dictionary = space.facility_quote(world,"guide","patient",["nurse"])
	checks.large_patient_geometry_rejected = not blocked_patient.get("ok",true)
	world.facts.floors.overrides["1"].blocked.erase([46,77])
	world.touch()
	var restored: WorldState = WorldState.new(world.freeze())
	checks.restored_quote_matches = space.facility_quote(world,"guide","patient",["nurse"])==HospitalSpace.new(content).facility_quote(restored,"guide","patient",["nurse"])
	return {"ok":not checks.values().has(false),"checks":checks,"input_error":input_error,"nurse_quote":fit,"patient_quote":large_patient,"missing_nurse":missing,"blocked_nurse":obstructed,"occupied_nurse":occupied,"blocked_patient":blocked_patient}

func _actor(id: String, species: String, cell: Array) -> Dictionary:
	return {"id":id,"name":id,"species_id":species,"location":{"kind":"floor","floor_id":1,"cell":cell.duplicate(),"height_m":0.0},"facing":0.0,"posture":"standing"}
