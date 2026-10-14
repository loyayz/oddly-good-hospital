class_name FeasibilityHospitals
extends RefCounted

static func create(hospital_id: String, surgical: bool, content: HospitalContent) -> HospitalWorld:
	var data: Dictionary = {"hospital_id": hospital_id, "display_name": "云袋手术医院" if surgical else "小帆门诊医院",
		"mode": "normal", "sim_tick": 0, "world_revision": 0, "clock_version": HospitalWorld.CLOCK_VERSION,
		"entity_next": 0, "actors": {}, "staff": {}, "visits": {}, "tickets": {}, "sessions": {}, "attempts": {},
		"preparations": {}, "ward_stays": {}, "facilities": {}, "adaptations": {}, "moves": {}, "command_receipts": {},
		"ledger": {"opening_balance": 100000, "entries": {}}, "inventory": {"units": 60, "issues": {}},
		"rng": {}, "schema_version":1,
		"research": ["R11", "R12", "R33", "R34"],
		"rooms": {},
		"floors": {"height_intervals": [{"first": 1, "last": 10000, "height_m": 7.5}],
			"overrides": {"1": {"plots": [[1,2]], "blocked": [], "doors": []},
				"2": {"plots": [[1,2]], "blocked": [], "doors": []}}},
		"connectors": {"lift": {"id": "lift", "definition_id": "VC03", "stops": [1,2],
			"anchor": [54,83], "floor_id": 1, "phase": "idle", "riders": [], "remaining_ticks": 0}}}
	var world: HospitalWorld = HospitalWorld.new(data)
	var streams: Array[String] = ["arrival","treatment","incident","personality","equipment","task_board","registration","communication","gratitude","patience","recruitment","community_activity"]
	for index: int in streams.size():
		var generator: RandomNumberGenerator = RandomNumberGenerator.new()
		generator.seed = (271828 if surgical else 314159)+index*104729
		data.rng[streams[index]] = {"algorithm":"godot-pcg32-4.7.2","seed_decimal":str(generator.seed),"state_decimal":str(generator.state)}
	_add_staff(world, "reception", "接待员", "receptionist", [37,90], "DT01", 0, 0, 0, 0)
	_add_staff(world, "gp_doctor", "林医生", "doctor", [41,87], "DT02", 2, 2, 0, 0)
	_add_staff(world, "treat_doctor", "周医生", "doctor", [47,77], "DT02", 2, 2, 0, 0)
	_add_staff(world, "exam_nurse", "范护士", "nurse", [46,87], "", 2, 0, 1, 0)
	if surgical:
		_add_staff(world, "surgeon", "星医生", "doctor", [35,77], "DT03", 2, 3, 0, 3)
		_add_staff(world, "anesthetist", "月医生", "doctor", [39,76], "DT02", 2, 2, 0, 2)
		_add_staff(world, "or_nurse", "云护士", "nurse", [39,78], "", 1, 0, 2, 2)
		_add_staff(world, "ward_nurse", "叶护士", "nurse", [47,69], "", 1, 0, 2, 0)
		_add_staff(world, "round_doctor", "何医生", "doctor", [49,71], "DT02", 2, 2, 0, 0)
	_add_facility(world, "reception_desk", "FUR01", [37,89], [1,1], [37,91], [[37,90]])
	_add_facility(world, "gp", "FUR02", [41,86], [2,1], [41,88], [[41,87]])
	_add_facility(world, "exam", "FUR02", [46,86], [2,1], [46,88], [[46,87]])
	_add_facility(world, "treatment", "M37", [47,78], [2,2], [47,80], [[49,79]])
	if surgical:
		_add_facility(world, "or", "EQ01", [36,76], [3,3], [36,80], [[35,77],[39,76],[39,78]])
		_add_facility(world, "bed", "EQ05", [48,68], [3,3], [48,71], [[47,69],[47,69]])
		data.rooms["operating_room"] = {"id":"operating_room","kind":"operating_room","floor_id":1,"origin":[34,74],"size":[8,8]}
		data.rooms["ward"] = {"id":"ward","kind":"ward","floor_id":1,"origin":[47,65],"size":[8,8]}
		data.facilities["or"].room_id = "operating_room"
		data.facilities.bed.room_id = "ward"
		data.staff.ward_nurse.ward_id = "ward"
		for room: Dictionary in data.rooms.values():
			var x0: int = int(room.origin[0])-1
			var y0: int = int(room.origin[1])-1
			var x1: int = int(room.origin[0])+int(room.size[0])
			var y1: int = int(room.origin[1])+int(room.size[1])
			for x: int in range(x0,x1+1):
				data.floors.overrides["1"].blocked.append([x,y0])
				if x not in [int(room.origin[0])+3,int(room.origin[0])+4]:
					data.floors.overrides["1"].blocked.append([x,y1])
			for y: int in range(y0+1,y1):
				data.floors.overrides["1"].blocked.append([x0,y])
				data.floors.overrides["1"].blocked.append([x1,y])
			data.floors.overrides["1"].doors.append({"id":room.id+"_door","definition_id":"DR04","cell":[int(room.origin[0])+3,y1],"span":2,"axis":"x","room_id":room.id,"active_actor_id":"","clear_height_m":5.8})
	data.connectors["stairs"] = {"id":"stairs","definition_id":"VC01","stops":[1,2],"anchor":[58,90],"floor_id":1,"phase":"idle","riders":[],"remaining_ticks":0}
	for connector: Dictionary in data.connectors.values():
		var definition: Dictionary = content.definition("vertical_connectors",connector.definition_id)
		connector.cell = [int(connector.anchor[0])-int(definition.front_operation_anchor[0]),int(connector.anchor[1])-int(definition.front_operation_anchor[1])]
		connector.footprint = definition.footprint.duplicate()
	# Built second-floor widths share one sparse layout, not separate body maps.
	for x: int in range(35,60):
		for y: int in [69,71,75,78,82,86]:
			data.floors.overrides["2"].blocked.append([x,y])
	var patient_id: String = _add_actor(world, "patient", "梦泡先生" if surgical else "纸巾小姐", "S49", [48,93])
	var visit_id: String = world.new_id("visit")
	var binding_id: String = "B_S49_D23_M23" if surgical else "B_S49_D37_M37"
	data.visits[visit_id] = {"id": visit_id, "actor_id": patient_id, "disease_id": "D23" if surgical else "D37",
		"requested_plan_id":"P_D23_SURGERY" if surgical else "P_D37_COMMON",
		"expression":"clear","personality_id":"PP01","anger":float(content.definition("patient_personalities","PP01").initial_anger),
		"binding_id": binding_id, "phase": "arrival", "evidence_by_source": {}, "attempt_ids": [],
		"plan_decision": {}, "complex": false, "final_result": "", "waiting_reason": "", "ticket_id": "",
		"doctor_fee_quote": -1}
	data.actors[patient_id].body_binding_id = binding_id
	for species_id: String in ["S21", "S59", "S55", "S14"]:
		var species: Dictionary = content.definition("species", species_id)
		var index: int = ["S21", "S59", "S55", "S14"].find(species_id)
		_add_actor(world, "sample_" + species_id, species.name, species_id, [35 + index * 6, 65])
	return world

static func _add_actor(world: HospitalWorld, id: String, name: String, species: String, cell: Array) -> String:
	world.facts.actors[id] = {"id": id, "name": name, "species_id": species,
		"location": {"kind": "floor", "floor_id": 1, "cell": cell.duplicate(),"height_m":0.0}, "facing": 0.0,"posture":"standing"}
	return id

static func _add_staff(world: HospitalWorld, id: String, name: String, role: String, cell: Array,
		title: String, diagnosis: int, treatment: int, care: int, surgery: int) -> void:
	_add_actor(world, id, name, "S49", cell)
	world.facts.staff[id] = {"id": id, "role": role, "title_id": title,
		"abilities": {"diagnosis": diagnosis, "treatment": treatment, "care": care, "surgery": surgery},
		"energy": 100.0, "fatigue": 0.0, "stress_milli": 0, "on_shift": true,
		"certificates": (["q_ward"]+(["q_or"] if surgery>0 else [])) if role == "nurse" else [],
		"practice": {"diagnosis": 0, "treatment": 0, "care": 0, "surgery": 0}, "completed_jobs": {}}

static func _add_facility(world: HospitalWorld, id: String, definition_id: String, cell: Array,
		footprint: Array, patient_cell: Array, operator_cells: Array) -> void:
	world.facts.facilities[id] = {"id": id, "definition_id": definition_id, "floor_id": 1, "cell": cell,
		"footprint": footprint, "patient_cell": patient_cell, "operator_cells": operator_cells,
		"repair_cell": [int(cell[0]) + int(footprint[0]), int(cell[1]) + int(footprint[1])],
		"grade": 0, "condition": 100.0, "failed": false, "pending_failure": false, "use_receipts": {}}
