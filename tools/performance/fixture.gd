extends RefCounted

# Legal, already-built hospital input. All work after this boundary is performed
# by the production simulation; no service is disabled or replaced by a fake.
var world: WorldState
var content: HospitalContent
var floors: Array[int] = []
var visitor_ids: Array[String] = []
var errors: Array[String] = []
var _positions: Dictionary = {}
var _position_next: Dictionary = {}
var _space: HospitalSpace

func _init(database: HospitalContent, count: int, layout: String = "four_floors", input: String = "") -> void:
	content = database
	if not input.is_empty():
		var file: FileAccess = FileAccess.open(input,FileAccess.READ)
		var saved: Dictionary = file.get_var()
		if saved.content_fingerprint!=content.content_fingerprint: errors.append("前置内容身份不匹配")
		world = WorldState.new(saved.facts)
		floors.assign(saved.floors)
		visitor_ids.assign(saved.visitor_ids)
		return
	floors.assign([1] if layout=="wide" else ([1,10,1000,10000] if layout=="tall" else [1,2,3,4]))
	world = HospitalFactory.create("00000000-0000-4000-8000-%012d"%count,"固定负载%d"%count,false,content)
	world.facts.ledger.opening_balance = 10000000
	world.facts.inventory.units = 10000
	var plots: Array = []
	for x: int in 3:
		for y: int in 3: plots.append([x,y])
	world.facts.floors.height_intervals = [{"first":1,"last":floors.back(),"height_m":float(content.balance.floors.clear_height_m)}]
	world.facts.floors.completed_top_floor = {}
	for plot: Array in plots: world.facts.floors.completed_top_floor[HospitalSpace.plot_key(plot)] = floors.back()
	for floor_id: int in floors:
		world.facts.floors.overrides[str(floor_id)] = {"plots":plots.duplicate(true),"blocked":[],"doors":[],"paths":[]}
	for definition: Dictionary in content.catalog.research: world.facts.research.append(definition.id)
	for floor_id: int in floors:
		_build_floor(floor_id,64 if floors.size()==1 else 16,1200/floors.size())
	world.facts.entry = {"floor_id":1,"cell":[48,91],"exit_cell":[48,91]}
	if floors.size()>1:
		world.facts.connectors["benchmark_lift"] = {"id":"benchmark_lift","definition_id":"VC02","first_floor":1,"last_floor":floors.back(),"cell":[85,40],"footprint":[4,4],"rotation":0,"anchor":[86,44],"repair_cell":[84,41],"floor_id":1,"phase":"idle","riders":[],"remaining_ticks":0,"ticket_next":0,"condition":100.0,"failed":false,"pending_failure":false,"use_receipts":{},"paid_cost":3200,"used":false}
	_space = HospitalSpace.new(content)
	for floor_id: int in floors:
		_positions[floor_id] = _floor_positions(floor_id)
		_position_next[floor_id] = 0
	var staff_count: int = count/5
	for index: int in staff_count:
		var floor_id: int = floors[index%floors.size()]
		var role: String = ["doctor","doctor","doctor","doctor","nurse","nurse","receptionist","cleaner"][index/floors.size()%8]
		var id: String = "bench_staff_%04d"%index
		HospitalFactory._add_staff(world,id,id,role,[0,0],content)
		var actor: Dictionary = world.facts.actors[id]
		actor.location = _location(floor_id,_next_position(floor_id,actor))
		_space.sync_actor(world,id)
		var staff: Dictionary = world.facts.staff[id]
		staff.base_prepared = true
		staff.personality_id = "DP05"
		staff.abilities = {"diagnosis":2,"treatment":2,"care":2,"surgery":2}
		staff.title_id = "DT02" if role=="doctor" else ""
		staff.certificates = ["q_or","q_ward"] if role=="nurse" else []
		var slot: int = index/floors.size()%8
		var duty: String = "surgery" if slot in [2,3] else ("outpatient" if role=="doctor" else "work")
		staff.schedule = [{"kind":duty,"pools":[],"locked":false},{"kind":duty,"pools":[],"locked":false},{"kind":"rest","pools":[],"locked":false}]
	var visitors: int = count/20
	for index: int in count-staff_count-visitors:
		var floor_id: int = floors[index%floors.size()]
		var id: String = "bench_patient_%04d"%index
		var visit_id: String = "bench_visit_%04d"%index
		var binding: Dictionary = content.definition("treatment_bindings","B_S13_D09_M09")
		var actor: Dictionary = {"id":id,"name":"患者%04d"%index,"species_id":binding.species_id,"body_binding_id":binding.id,"facing":0.0,"posture":"standing"}
		actor.location = _location(floor_id,_next_position(floor_id,actor))
		world.facts.actors[id] = actor
		world.facts.visits[visit_id] = {"id":visit_id,"actor_id":id,"disease_id":binding.disease_id,"binding_id":binding.id,"requested_plan_id":"P_D09_SURGERY" if index%5==0 else "P_D09_COMMON","expression":"clear","personality_id":"PP01","anger":15.0,"phase":"arrival","evidence_by_source":{},"attempt_ids":[],"plan_decision":{},"complex":false,"final_result":"","waiting_reason":"","ticket_id":"","doctor_fee_quote":-1,"arrived_tick":0,"arrival_key":visit_id,"last_progress_tick":0,"last_service_tick":0}
		world.facts.arrival_receipts[visit_id] = visit_id
		_space.sync_actor(world,id)
	for index: int in visitors:
		var floor_id: int = floors[index%floors.size()]
		var id: String = "bench_visitor_%04d"%index
		var actor: Dictionary = {"id":id,"name":"访客%04d"%index,"species_id":"S49","facing":0.0,"posture":"standing"}
		actor.location = _location(floor_id,_next_position(floor_id,actor))
		world.facts.actors[id] = actor
		visitor_ids.append(id)
		_space.sync_actor(world,id)
	world.touch()

func _build_floor(floor_id: int, room_count: int, props: int) -> void:
	var kinds: Array = ["gp","T01","operating_room","ward","ward","ward","doctor_office","doctor_office","rest","toilet","doctor_office","doctor_office","T10","rest","gp","T01"]
	for index: int in room_count:
		var side: int = 8 if room_count==64 else 4
		var pitch: int = 11 if room_count==64 else 22
		var origin: Array = [5+index%side*pitch,5+index/side*pitch]
		var kind: String = kinds[index%16]
		var id: String = "bench_room_%d_%02d"%[floor_id,index]
		var original: Dictionary = world.facts.floors.overrides["1"]
		world.facts.floors.overrides["1"] = world.facts.floors.overrides[str(floor_id)]
		HospitalFactory._add_room(world,{"id":id,"type":kind,"anchor":origin,"size":[8,8],"door":{"definition_id":"DR04","offset":3}},content)
		world.facts.floors.overrides["1"] = original
		world.facts.rooms[id].floor_id = floor_id
		if kind in ["operating_room","ward"]:
			_add_layout(floor_id,id,origin,"or_standard" if kind=="operating_room" else "ward_two_beds")
		elif index%16!=14:
			var definition_id: String = {"gp":"FUR02","T01":"M09","T10":"M37","doctor_office":"SE05","rest":"SE04","toilet":"FUR07"}[kind]
			var n: int = 1 if index%16 in [10,11] else 2
			for slot: int in n: _facility(id+"_"+str(slot),definition_id,floor_id,[int(origin[0])+1+slot*3,int(origin[1])+1+slot*3],id)
		else:
			_facility(id+"_reception","FUR01",floor_id,[int(origin[0])+1,int(origin[1])+2],id)
			_facility(id+"_water","FUR17",floor_id,[int(origin[0])+5,int(origin[1])+2],id)
	var placed: int = 0
	for y: int in 96:
		for x: int in 96:
			if placed>=props: return
			if x>=4 and x<92 and y>=4 and y<92: continue
			_facility("bench_prop_%d_%04d"%[floor_id,placed],"FUR18",floor_id,[x,y],"")
			placed += 1

func _facility(id: String, definition_id: String, floor_id: int, cell: Array, room_id: String) -> Dictionary:
	var definition: Dictionary = content.facility_definition(definition_id)
	HospitalFactory._add_facility(world,{"id":id,"definition_id":definition_id,"anchor":cell,"size":definition.footprint,"room_id":room_id if not room_id.is_empty() else null},content)
	var facility: Dictionary = world.facts.facilities[id]
	facility.floor_id = floor_id
	return facility

func _add_layout(floor_id: int, room_id: String, origin: Array, layout_id: String) -> void:
	var layout: Dictionary = {}
	for record: Dictionary in content.layouts.layouts:
		if record.id==layout_id: layout = record
	var beds: int = 0
	for index: int in layout.objects.size():
		var item: Dictionary = layout.objects[index]
		var f: Dictionary = _facility(room_id+"_"+str(index),item.definition_id,floor_id,[int(origin[0])+int(item.anchor[0]),int(origin[1])+int(item.anchor[1])],room_id)
		if item.definition_id=="EQ01":
			f.patient_cell = _point(layout,"patient_staging",origin)
			f.operator_cells = [_point(layout,"surgeon",origin),_point(layout,"anesthetist",origin),_point(layout,"nurse",origin)]
			f.repair_cell = [int(origin[0])+int(layout.repair_points[0][0]),int(origin[1])+int(layout.repair_points[0][1])]
		elif item.definition_id=="EQ05":
			beds += 1
			f.patient_cell = _point(layout,"patient_staging_"+str(beds),origin)
			f.operator_cells = [_point(layout,"care_"+str(beds),origin),[int(origin[0])+4,int(origin[1])+(1 if beds==1 else 3)]]
			f.repair_cell = [int(origin[0])+int(layout.repair_points[beds-1][0]),int(origin[1])+int(layout.repair_points[beds-1][1])]
		elif item.definition_id=="SE06": f.operator_cells = [_point(layout,"nurse_base",origin)]

func _point(layout: Dictionary, kind: String, origin: Array) -> Array:
	for point: Dictionary in layout.service_points:
		if point.kind==kind: return [int(origin[0])+int(point.anchor[0]),int(origin[1])+int(point.anchor[1])]
	return []

func _floor_positions(floor_id: int) -> Array:
	var result: Array = []
	for y: int in range(6,91,2):
		for x: int in range(6,91,2): result.append([x,y])
	return result

func _next_position(floor_id: int, actor: Dictionary) -> Array:
	var choices: Array = _positions[floor_id]
	while int(_position_next[floor_id])<choices.size():
		var cell: Array = choices[int(_position_next[floor_id])]
		_position_next[floor_id] += 1
		actor.location = _location(floor_id,cell)
		if _space.static_reason(world,actor,floor_id,Vector2i(int(cell[0]),int(cell[1]))).is_empty() and _space._dynamic_clear(world,actor.id,floor_id,_space.body_rectangle(actor)):
			return cell.duplicate()
	errors.append("没有足够合法身体位置："+str(floor_id))
	return [48,91]

func _location(floor_id: int, cell: Array) -> Dictionary:
	return {"kind":"floor","floor_id":floor_id,"cell":cell,"height_m":0.0}

func describe() -> Dictionary:
	var beds: int = 0
	for facility: Dictionary in world.facts.facilities.values():
		if facility.definition_id=="EQ05": beds += 1
	return {"actors":world.present_actor_count(),"patients":world.facts.visits.size(),"staff":world.facts.staff.size(),"visitors":visitor_ids.size(),"rooms":world.facts.rooms.size(),"facilities":world.facts.facilities.size(),"beds":beds,"floors":floors,"errors":errors,"boundary":"built hospital; admitted patients before reception; actual production services thereafter"}

func store_input(path: String) -> void:
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	file.store_var({"content_fingerprint":content.content_fingerprint,"facts":world.freeze(),"floors":floors,"visitor_ids":visitor_ids})
