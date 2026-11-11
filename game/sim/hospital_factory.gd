class_name HospitalFactory
extends RefCounted

static func create(hospital_id: String, display_name: String, preset: bool, content: HospitalContent) -> WorldState:
	var starter: Dictionary = content.starter_layout.duplicate(true)
	var data: Dictionary = {"schema_version":1,"gameplay_version":1,"hospital_id":hospital_id,"display_name":display_name,
		"mode":"normal","sim_tick":0,"world_revision":0,"clock_version":WorldState.CLOCK_VERSION,"entity_next":0,
		"actors":{},"staff":{},"visits":{},"tickets":{},"sessions":{},"attempts":{},"preparations":{},"ward_stays":{},
		"facilities":{},"adaptations":{},"moves":{},"command_receipts":{},"rooms":{},"connectors":{},"research":[],
		"ledger":{"opening_balance":int(content.balance.starting_cash),"entries":{}},"inventory":{"units":0,"issues":{},"build_items":{}},"rng":{},
		"floors":{"height_intervals":[{"first":1,"last":1,"height_m":float(content.balance.floors.clear_height_m)}],
			"overrides":{"1":{"plots":[starter.plot.duplicate()],"blocked":[],"wall_edges":[],"doors":[],"paths":[]}}},
		"entry":{"floor_id":1,"cell":starter.entry.anchor.duplicate(),"exit_cell":[48,95]},
		"arrival_receipts":{},"initial_offers":starter.initial_offers.duplicate()}
	var world: WorldState = WorldState.new(data)
	var streams: Array[String] = ["arrival","treatment","incident","personality","equipment","task_board","guidance","communication","gratitude","patience","recruitment","community_activity","registration"]
	for index: int in streams.size():
		var generator: RandomNumberGenerator = RandomNumberGenerator.new()
		generator.seed = 314159 + index * 104729
		data.rng[streams[index]] = {"algorithm":"godot-pcg32-4.7.2","seed_decimal":str(generator.seed),"state_decimal":str(generator.state)}
	for gift: Dictionary in starter.inventory:
		data.inventory.build_items["starter_gift_"+gift.definition_id] = {"id":"starter_gift_"+gift.definition_id,
			"definition_id":gift.definition_id,"quantity":int(gift.quantity),"paid_cost":int(gift.paid_cost),"borrowed":gift.borrowed,
			"ownership":"gift","rotation":0,"completed_upgrade_paid_cost":0}
	var units: int = int(content.balance.supplies.initial_purchase_units)
	var supply_price: int = int(content.definition("medical_supplies","SUP01").unit_price)
	HospitalLedger.post(world,LedgerEntry.new(hospital_id,"starter_supplies",-units*supply_price))
	data.inventory.units = units
	if not preset:
		return world
	for room: Dictionary in starter.rooms:
		_add_room(world,room,content)
	var placement: BuildService = BuildService.new(content)
	for item: Dictionary in starter.objects:
		_add_facility(world,item,content)
		# Rest fixtures share ordinary placement's real access/repair anchors.
		# Clinical starter stations retain their authored service anchors.
		if item.definition_id in ["SE04","FUR06"]:
			placement._set_anchors(data.facilities[item.id],content.facility_definition(item.definition_id))
	for path: Dictionary in starter.path_rectangles:
		for x: int in range(int(path.anchor[0]),int(path.anchor[0])+int(path.size[0])):
			for y: int in range(int(path.anchor[1]),int(path.anchor[1])+int(path.size[1])):
				data.floors.overrides["1"].paths.append([x,y])
	for index: int in content.balance.starter_purchase.size():
		var purchase: Dictionary = content.balance.starter_purchase[index]
		HospitalLedger.post(world,LedgerEntry.new(hospital_id,"starter_build_%02d"%index,-int(purchase.amount)))
	var doctor_index: int = 0
	for roster: Dictionary in starter.doctor_roster:
		_add_staff(world,roster.id,"医生"+str(doctor_index+1),"doctor",[42+doctor_index*2,94],content)
		var doctor: Dictionary = data.staff[roster.id]
		doctor.title_id = roster.title_id
		doctor.personality_id = roster.personality_id
		doctor.primary_track = roster.primary_track
		doctor.shifts = roster.shifts.duplicate(true)
		doctor.on_shift = roster.shifts[0].kind != "rest"
		for ability: String in ["diagnosis","treatment","surgery"]:
			doctor.abilities[ability] = int(roster[ability])
		for pay: Dictionary in content.balance.doctor_pay:
			if pay.title_id == roster.title_id:
				HospitalLedger.post(world,LedgerEntry.new(roster.id,"hire",-int(pay.hire)))
		doctor_index += 1
	var positions: Dictionary = {"nurse":[52,94],"cleaner":[54,94]}
	for role: String in positions:
		_add_staff(world,"starter_"+role,role,role,positions[role],content)
		for price: Dictionary in content.balance.staff:
			if price.role == role:
				HospitalLedger.post(world,LedgerEntry.new("starter_"+role,"hire",-int(price.hire)))
	_add_staff(world,"starter_guide_nurse","导诊护士","nurse",[50,94],content)
	for price: Dictionary in content.balance.staff:
		if price.role=="nurse": HospitalLedger.post(world,LedgerEntry.new("starter_guide_nurse","hire",-int(price.hire)))
	return world

static func _add_staff(world: WorldState, id: String, name: String, role: String, cell: Array, _content: HospitalContent) -> void:
	world.facts.actors[id] = {"id":id,"name":name,"species_id":"S49","location":{"kind":"floor","floor_id":1,"cell":cell.duplicate(),"height_m":0.0},"facing":0.0,"posture":"standing"}
	world.facts.staff[id] = {"id":id,"role":role,"title_id":"DT01" if role=="doctor" else "",
		"abilities":{"diagnosis":1 if role in ["doctor","nurse"] else 0,"treatment":1 if role=="doctor" else 0,"care":1 if role=="nurse" else 0,"surgery":0},
		"energy":100.0,"fatigue":0.0,"stress_milli":0,"on_shift":true,"certificates":["q_ward"] if role=="nurse" else [],
		"practice":{"diagnosis":0,"treatment":0,"care":0,"surgery":0},"completed_jobs":{},"hired_tick":world.sim_tick,"skill":1}

static func _add_room(world: WorldState, source: Dictionary, content: HospitalContent) -> void:
	var request: Dictionary = {"id":source.id,"room_type_id":source.type,"floor_id":int(source.get("floor_id",1)),"origin":source.anchor.duplicate(),"size":source.size.duplicate(),"door":source.door.duplicate(true)}
	request.door.id = str(source.id)+"_door"
	var result: Dictionary = BuildService.new(content)._add_room(world,request)
	assert(result.ok,str(result.get("reason","初始房间结构无效")))

static func _put_cell(cells: Array, cell: Array) -> void:
	if not cell in cells:
		cells.append(cell)

static func _add_facility(world: WorldState, item: Dictionary, content: HospitalContent) -> void:
	var x: int = int(item.anchor[0])
	var y: int = int(item.anchor[1])
	var width: int = int(item.size[0])
	var height: int = int(item.size[1])
	var patient: Array = [x,y+height]
	var operators: Array = [[x+width,y+height-1]]
	var repair: Array = [x-1,y]
	if item.definition_id == "FUR02":
		patient = [x+1,y+1]
		operators = [[x,y-1]]
		repair = [x+width,y]
	var definition: Dictionary = content.facility_definition(item.definition_id)
	world.facts.facilities[item.id] = {"id":item.id,"definition_id":item.definition_id,"room_id":str(item.room_id) if item.room_id!=null else "",
		"floor_id":1,"cell":[x,y],"footprint":[width,height],"patient_cell":patient,"operator_cells":operators,
		"repair_cell":repair,"grade":0,"condition":100.0,"failed":false,"pending_failure":false,"use_receipts":{},
		"paid_cost":int(definition.get("price",0)),"borrowed":false,"used":false,"ownership":"purchased","rotation":0}
	if item.room_id==null:
		world.facts.facilities[item.id].erase("room_id")
