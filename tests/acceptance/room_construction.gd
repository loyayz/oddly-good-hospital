extends RefCounted

var content: HospitalContent
var _sequence: int = 0
const GraphReference = preload("res://tests/acceptance/navigation_cold_graph.gd")
const CASES: Dictionary={
	"ROOM-BUILD-01":"房间规格§2.1；分次墙、先门、闭合空房和实际长度收费",
	"ROOM-BUILD-02":"房间规格§2.2；不规则、共墙、孔洞、极小与重叠",
	"ROOM-BUILD-03":"房间规格§2.3；拆改、合房、最后门失效与家具保留",
	"ROOM-BUILD-04":"房间规格§3；九用途、设施、关闭和重新开放",
	"ROOM-BUILD-05":"房间规格§3～4；个人床、娱乐与单手术台摆放限制",
	"ROOM-BUILD-06":"房间规格§9；独立墙、读档与失败原子性",
	"ROOM-BUILD-07":"房间规格§2.3；实际移动与身体保护",
	"ROOM-BUILD-08":"房间规格§2、§9；原生路径掩码与独立墙参考逐边一致",
	"ROOM-BUILD-09":"房间规格§2.3、§9；用途失效清排班、失败不泄漏与撤销恢复",
	"ROOM-BUILD-10":"房间规格§1～2；墙不得穿过跨层交通设施的任何实际停靠层"
}

func run(t) -> void:
	for id: String in CASES:
		if not t.wants(id): continue
		t.begin_case(id)
		var result: Dictionary=run_cases(HospitalContent.new(),[id])
		t.check(id,result.ok,result.cases[0])

func run_cases(database: HospitalContent, selected: Array = []) -> Dictionary:
	content = database
	var cases: Dictionary = {"ROOM-BUILD-01":_formation,"ROOM-BUILD-02":_geometry,"ROOM-BUILD-03":_removal,"ROOM-BUILD-04":_purposes,"ROOM-BUILD-05":_placement,"ROOM-BUILD-06":_walls_and_recovery,"ROOM-BUILD-07":_movement_safety,"ROOM-BUILD-08":_static_masks,"ROOM-BUILD-09":_schedule_cleanup,"ROOM-BUILD-10":_connector_walls}
	var rows: Array = []
	var ok: bool = true
	for id: String in (cases.keys() if selected.is_empty() else selected):
		if not cases.has(id): return {"ok":false,"error":"unknown case "+id}
		var started: int = Time.get_ticks_usec()
		var row: Dictionary = cases[id].call()
		row.id = id
		row.elapsed_ms = (Time.get_ticks_usec()-started)/1000.0
		row.ok = row.checks.values().all(func(value: Variant)->bool:return value==true)
		ok = ok and row.ok
		rows.append(row)
	return {"ok":ok,"cases":rows}

func _base() -> Dictionary:
	_sequence += 1
	var world: WorldState = HospitalFactory.create("room_construction_%d"%_sequence,"房间建造专项",false,content)
	return {"world":world,"builder":BuildService.new(content),"checks":{},"results":[]}

func _do(x: Dictionary, kind: String, payload: Dictionary) -> CommandResult:
	_sequence += 1
	var request: Dictionary = payload.duplicate(true)
	if not request.has("command_id"): request.command_id = "room_command_%d"%_sequence
	var result: CommandResult = x.builder.execute(x.world,kind,request)
	x.results.append({"kind":kind,"accepted":result.accepted,"reason":result.reason})
	return result

func _rect(x: Dictionary, id: String, origin: Array, size: Array, purpose: String = "gp", door: Dictionary = {}) -> CommandResult:
	return _do(x,"build_room",{"id":id,"origin":origin,"size":size,"room_type_id":purpose,"door":door if not door.is_empty() else {"definition_id":"DR01","edge":"south","offset":0}})

func _rooms(world: WorldState) -> Array:
	return world.facts.rooms.values().filter(func(room: Dictionary)->bool:return room.get("structure_valid",true))

func _finish(x: Dictionary) -> Dictionary:
	var validation: String = x.builder.validate(x.world)
	x.checks.build_state_valid = validation.is_empty()
	var snapshot_validation: String = x.world.validate(content)
	x.checks.snapshot_valid = snapshot_validation.is_empty()
	return {"checks":x.checks,"validation":validation,"snapshot_validation":snapshot_validation,"results":x.results,"balance":HospitalLedger.balance(x.world),"rooms":_rooms(x.world).size()}

func _formation() -> Dictionary:
	var x: Dictionary = _base()
	var before: int = HospitalLedger.balance(x.world)
	var first: Dictionary = {"edges":[{"axis":"x","line":66,"low":34,"high":36},{"axis":"y","line":34,"low":66,"high":68},{"axis":"y","line":36,"low":66,"high":68}]}
	x.checks.partial_wall = _do(x,"build_wall",first).accepted and _rooms(x.world).is_empty() and HospitalLedger.balance(x.world)==before-120
	x.checks.door_before_closure = _do(x,"build_door",{"id":"early","definition_id":"DR01","cell":[34,66],"edge":"north"}).accepted and _rooms(x.world).is_empty() and x.world.facts.floors.overrides["1"].doors[0].room_id==""
	x.checks.unclosed_door_restore_valid = WorldState.new(x.world.freeze()).validate(content).is_empty()
	var final_wall: Dictionary = {"edges":[{"axis":"x","line":68,"low":34,"high":36}],"command_id":"close_once"}
	var quote: Dictionary = x.builder.preview(x.world,final_wall.merged({"kind":"build_wall"}))
	final_wall.quote = quote.quote
	x.checks.closed_with_door = quote.ok and _do(x,"build_wall",final_wall).accepted and _rooms(x.world).size()==1 and _rooms(x.world)[0].kind==""
	var paid: int = HospitalLedger.balance(x.world)
	x.checks.duplicate_free = _do(x,"build_wall",final_wall).code=="duplicate" and HospitalLedger.balance(x.world)==paid
	var room_id: String = str(_rooms(x.world)[0].id)
	x.checks.multi_door_same_room = _do(x,"build_door",{"id":"second","definition_id":"DR01","cell":[35,66],"edge":"north"}).accepted and _rooms(x.world).size()==1 and _rooms(x.world)[0].id==room_id and x.world.facts.floors.overrides["1"].doors.all(func(door:Dictionary)->bool:return door.room_id==room_id)
	x.checks.only_wall_and_chosen_door_prices = HospitalLedger.balance(x.world)==before-160-100 and x.world.facts.get("environment",{}).get("surfaces",{}).is_empty()
	var before_rotation: int = HospitalLedger.balance(x.world)
	x.checks.door_reverse_invalidates_structure = _do(x,"build_rotate",{"target_id":"early","rotation":0}).accepted and _rooms(x.world).is_empty()
	x.checks.direction_restored_without_purchase = _do(x,"build_rotate",{"target_id":"early","rotation":2}).accepted and _rooms(x.world).size()==1 and HospitalLedger.balance(x.world)==before_rotation
	var other: Dictionary = _base()
	_do(other,"build_wall",{"edges":BuildGeometry.room_walls({"origin":[40,66],"size":[2,2]})})
	x.checks.no_door_no_room = _rooms(other.world).is_empty()
	x.checks.outward_door_no_room = _do(other,"build_door",{"id":"wrong_way","definition_id":"DR01","cell":[40,66],"edge":"south"}).accepted and _rooms(other.world).is_empty()
	x.checks.correct_direction_forms_room = _do(other,"build_door",{"target_id":"wrong_way","definition_id":"DR01","cell":[40,66],"edge":"north"}).accepted and _rooms(other.world).size()==1
	return _finish(x)

func _geometry() -> Dictionary:
	var x: Dictionary = _base()
	var before: int = HospitalLedger.balance(x.world)
	x.checks.first_room = _rect(x,"first",[34,66],[2,2],"gp",{"definition_id":"DR01","edge":"west","offset":0}).accepted
	x.checks.shared_wall = _rect(x,"second",[36,66],[2,2],"treatment",{"definition_id":"DR01","edge":"east","offset":0}).accepted and HospitalLedger.balance(x.world)==before-380
	var old: Dictionary = x.world.freeze()
	x.checks.overlap_atomic = not _rect(x,"overlap",[35,66],[2,2]).accepted and x.world.freeze()==old
	old = x.world.freeze()
	var ring: Array = [[40,66],[41,66],[42,66],[40,67],[42,67],[40,68],[41,68],[42,68]]
	x.checks.hole_atomic = not _do(x,"build_room",{"id":"hole","room_type_id":"gp","cells":ring}).accepted and x.world.freeze()==old
	x.checks.l_shape = _do(x,"build_room",{"id":"l_room","room_type_id":"gp","cells":[[34,72],[35,72],[34,73]],"door":{"definition_id":"DR01","edge":"south","cell":[34,74]}}).accepted and x.world.facts.rooms.l_room.cells.size()==3
	x.checks.tiny = _rect(x,"tiny",[40,72],[1,1]).accepted
	x.checks.tiny_purpose = _do(x,"build_room_use",{"target_id":"tiny","room_type_id":"operating_room"}).accepted
	_do(x,"build_room_use",{"target_id":"tiny","room_type_id":"gp"})
	old = x.world.freeze()
	x.checks.tiny_no_fake_equipment_fit = not _do(x,"build_facility",{"definition_id":"FUR02","room_id":"tiny","cell":[40,72]}).accepted and x.world.freeze()==old
	x.checks.no_minimum_rectangle = BuildGeometry.shape({"cells":[[1,1],[2,1],[1,2]]},[20,20]).ok
	return _finish(x)

func _removal() -> Dictionary:
	var x: Dictionary = _base()
	_rect(x,"first",[34,66],[2,2],"gp",{"definition_id":"DR01","edge":"west","offset":0})
	_rect(x,"second",[36,66],[2,2],"treatment",{"definition_id":"DR01","edge":"east","offset":0})
	x.checks.furnishing_placed = _do(x,"build_facility",{"id":"chair","definition_id":"FUR09","room_id":"first","cell":[35,67]}).accepted
	var old_position: Array = x.world.facts.facilities.chair.cell.duplicate()
	var before: int = HospitalLedger.balance(x.world)
	x.checks.shared_wall_merge = _do(x,"build_remove_wall",{"edges":[{"axis":"y","line":36,"low":66,"high":68}]}).accepted and _rooms(x.world).size()==1 and not x.world.facts.rooms.has("first") and not x.world.facts.rooms.has("second")
	var room: Dictionary = _rooms(x.world)[0]
	x.checks.new_empty_room = room.kind=="" and room.cells.size()==8
	x.checks.furnishing_retained = x.world.facts.facilities.chair.cell==old_position and x.world.facts.facilities.chair.room_id==room.id
	x.checks.use_preserves_furnishing = _do(x,"build_room_use",{"target_id":room.id,"room_type_id":"rest"}).accepted and x.world.facts.facilities.chair.cell==old_position
	var doors: Array = x.world.facts.floors.overrides["1"].doors.duplicate(true)
	x.checks.first_door_removal = _do(x,"build_demolish",{"target_id":doors[0].id}).accepted and _rooms(x.world).size()==1
	x.checks.last_door_invalidates = _do(x,"build_demolish",{"target_id":doors[1].id}).accepted and _rooms(x.world).is_empty()
	x.checks.no_wall_door_refund = HospitalLedger.balance(x.world)==before
	x.checks.remaining_furniture_and_walls = x.world.facts.facilities.has("chair") and x.world.facts.facilities.chair.cell==old_position and not x.world.facts.floors.overrides["1"].wall_edges.is_empty()
	return _finish(x)

func _purposes() -> Dictionary:
	var x: Dictionary = _base()
	var ids: Array = []
	for row: Dictionary in content.catalog.build_room_types: ids.append(row.id)
	ids.sort()
	var expected: Array = ["gp","treatment","operating_room","ward","doctor_office","research","rest","dormitory","toilet"]
	expected.sort()
	x.checks.exactly_nine = ids==expected
	_rect(x,"change",[34,66],[6,6])
	x.checks.device_placed = _do(x,"build_facility",{"id":"diagnostic","definition_id":"FUR02","room_id":"change","cell":[36,68]}).accepted
	var previous: Dictionary = x.world.facts.facilities.diagnostic.duplicate(true)
	x.checks.purpose_change_keeps_device = _do(x,"build_room_use",{"target_id":"change","room_type_id":"research"}).accepted and x.world.facts.facilities.diagnostic==previous
	x.checks.close_preserves_structure = _do(x,"build_room_open",{"target_id":"change","open_intent":false}).accepted and not x.world.facts.rooms.change.open_intent and x.world.facts.rooms.change.structure_valid
	x.checks.reopen = _do(x,"build_room_open",{"target_id":"change","open_intent":true}).accepted and x.world.facts.rooms.change.open_intent
	var before: Dictionary = x.world.freeze()
	x.checks.unknown_purpose_atomic = not _do(x,"build_room_use",{"target_id":"change","room_type_id":"T01"}).accepted and x.world.freeze()==before
	var preset: WorldState = HospitalFactory.create("preset_construction","预设建造",true,content)
	x.checks.preset_structure_valid = x.builder.validate(preset).is_empty()
	x.checks.preset_snapshot_valid = preset.validate(content).is_empty()
	x.checks.preset_beds_in_dormitory = preset.facts.facilities.values().filter(func(f:Dictionary)->bool:return f.definition_id=="SE04").all(func(f:Dictionary)->bool:return preset.facts.rooms[f.room_id].kind=="dormitory")
	return _finish(x)

func _placement() -> Dictionary:
	var x: Dictionary = _base()
	for row: Dictionary in content.catalog.research: x.world.facts.research.append(row.id)
	_rect(x,"lounge",[34,66],[8,8],"rest")
	var before: Dictionary = x.world.freeze()
	x.checks.lounge_no_bed = not _do(x,"build_facility",{"definition_id":"SE04","room_id":"lounge","cell":[36,68]}).accepted and x.world.freeze()==before
	x.checks.lounge_no_nursing_bed = not _do(x,"build_facility",{"definition_id":"EQ05","room_id":"lounge","cell":[36,68]}).accepted and x.world.freeze()==before
	x.checks.entertainment_lounge = _do(x,"build_facility",{"id":"game","definition_id":"RC01","room_id":"lounge","cell":[36,68]}).accepted
	_rect(x,"dorm",[45,66],[5,5],"dormitory")
	x.checks.dorm_bed = _do(x,"build_facility",{"definition_id":"SE04","room_id":"dorm","cell":[46,67]}).accepted
	before = x.world.freeze()
	x.checks.entertainment_not_dorm = not _do(x,"build_facility",{"definition_id":"RC01","room_id":"dorm","cell":[48,67]}).accepted and x.world.freeze()==before
	_rect(x,"surgery",[34,78],[12,12],"operating_room")
	x.checks.first_operating_table = _do(x,"build_facility",{"id":"table","definition_id":"EQ01","room_id":"surgery","cell":[36,80]}).accepted
	before = x.world.freeze()
	x.checks.no_second_operating_table = not _do(x,"build_facility",{"definition_id":"EQ01","room_id":"surgery","cell":[41,80]}).accepted and x.world.freeze()==before
	return _finish(x)

func _walls_and_recovery() -> Dictionary:
	var x: Dictionary = _base()
	_rect(x,"room",[34,66],[4,4])
	var count: int = _wall_count(x.world)
	var before: int = HospitalLedger.balance(x.world)
	x.checks.shared_edge_not_recharged = _do(x,"build_wall",{"edges":[{"axis":"x","line":66,"low":34,"high":38}]}).accepted and HospitalLedger.balance(x.world)==before and _wall_count(x.world)==count
	var saved: Dictionary = x.world.freeze()
	var restored: WorldState = WorldState.new(saved.duplicate(true))
	x.checks.recovery_same_facts = restored.freeze()==saved and x.builder.validate(restored).is_empty()
	var adjacent: Dictionary = _base()
	_rect(adjacent,"left",[34,66],[2,2],"gp",{"definition_id":"DR01","edge":"west","offset":0})
	_rect(adjacent,"right",[36,66],[2,2],"gp",{"definition_id":"DR01","edge":"east","offset":0})
	var before_invalid: Dictionary = adjacent.world.freeze()
	x.checks.shared_room_door_atomic = not _do(adjacent,"build_door",{"definition_id":"DR01","cell":[36,66],"edge":"west"}).accepted and adjacent.world.freeze()==before_invalid
	x.checks.broken_closure = _do(x,"build_remove_wall",{"edges":[{"axis":"y","line":38,"low":67,"high":68}]}).accepted and _rooms(x.world).is_empty()
	x.checks.break_no_refund = HospitalLedger.balance(x.world)==before
	var pieces_before: Array = x.world.facts.floors.overrides["1"].wall_edges.duplicate(true)
	x.checks.undo_restores_structure = _do(x,"build_undo",{}).accepted and _rooms(x.world).size()==1 and x.world.facts.floors.overrides["1"].wall_edges!=pieces_before
	return _finish(x)

func _wall_count(world: WorldState) -> int:
	var count: int = 0
	for edge: Dictionary in world.facts.floors.overrides["1"].wall_edges: count += int(edge.high)-int(edge.low)
	return count

func _movement_safety() -> Dictionary:
	var x: Dictionary = _base()
	HospitalFactory._add_staff(x.world,"walking_nurse","护士","nurse",[50,90],content)
	x.builder.space.request_move(x.world,"walking_nurse",1,[53,90])
	for tick: int in 2:
		x.builder.space.advance(x.world)
		x.world.facts.sim_tick += 1
		x.world.touch(false)
	x.checks.real_journey_started = x.world.facts.moves.has("walking_nurse") and x.world.facts.actors.walking_nurse.location.cell!=[50,90]
	var before: Dictionary = x.world.freeze()
	x.checks.cannot_cut_committed_route = not _do(x,"build_wall",{"edges":[{"axis":"y","line":52,"low":64,"high":96}]}).accepted and x.world.freeze()==before
	for tick: int in 300:
		if x.builder.space.at(x.world,"walking_nurse",1,[53,90]): break
		x.builder.space.advance(x.world)
		x.world.facts.sim_tick += 1
		x.world.touch(false)
	x.checks.original_journey_finishes = x.builder.space.at(x.world,"walking_nurse",1,[53,90])
	return _finish(x)

func _static_masks() -> Dictionary:
	var x: Dictionary = _base()
	_rect(x,"mask_room",[34,66],[12,10],"gp",{"definition_id":"DR01","edge":"south","offset":4})
	HospitalFactory._add_staff(x.world,"small","护士","nurse",[50,84],content)
	HospitalFactory._add_staff(x.world,"wide","护士","nurse",[55,84],content)
	x.world.facts.actors.wide.species_id = "S59"
	x.checks.unformed_wall_created = _do(x,"build_wall",{"edges":[{"axis":"y","line":52,"low":66,"high":82}]}).accepted
	var helper: RefCounted = GraphReference.new()
	for id: String in ["small","wide"]:
		var actor: Dictionary = x.world.facts.actors[id]
		var geometry: RouteClearance = RouteClearance.new(x.builder.space,x.world,actor,1,[],{},false)
		var masks: Dictionary = geometry.unit_static_masks()
		x.checks[id+"_correct_mask_path"] = masks.get("ready",false) if id=="small" else not masks.get("ready",false)
		x.checks[id+"_wall_blocks_real_sweep"] = not geometry.edge_reason(Vector2i(51,70),Vector2i(52,70)).is_empty()
		var graph: FloorNavigation = FloorNavigation.new(geometry)
		var expected: Dictionary = helper._complete_directed_reference(x.world,geometry)
		x.checks[id+"_all_nodes_edges_and_paths"] = helper._compare(graph,expected).ok
	var before: Dictionary = x.world.freeze()
	x.checks.entry_stays_open = not _do(x,"build_wall",{"edges":[{"axis":"x","line":94,"low":47,"high":50}]}).accepted and x.world.freeze()==before
	return _finish(x)

func _schedule_cleanup() -> Dictionary:
	var x: Dictionary = _base()
	_rect(x,"duty",[34,66],[4,4],"gp")
	HospitalFactory._add_staff(x.world,"doctor","医生","doctor",[50,90],content)
	var staff: Dictionary = x.world.facts.staff.doctor
	staff.schedule = [{"kind":"outpatient","pools":["duty"],"locked":false},{"kind":"rest","pools":[],"locked":false},{"kind":"rest","pools":[],"locked":false}]
	staff.schedule_overrides = {"0":{"kind":"outpatient","pools":["duty"],"locked":false}}
	x.checks.legal_before_boundary = x.world.validate(content).is_empty()
	var quote: Dictionary = x.builder.preview(x.world,{"kind":"build_room_use","target_id":"duty","room_type_id":"ward"})
	x.checks.preview_readonly = staff.schedule[0].pools==["duty"] and staff.schedule_overrides["0"].pools==["duty"]
	_do(x,"build_room_open",{"target_id":"duty","open_intent":false})
	var before: Dictionary = x.world.freeze()
	x.checks.failed_confirmation_no_schedule_leak = not _do(x,"build_room_use",{"target_id":"duty","room_type_id":"ward","quote":quote.quote}).accepted and x.world.freeze()==before
	x.checks.changed_purpose_clears_both = _do(x,"build_room_use",{"target_id":"duty","room_type_id":"ward"}).accepted and x.world.facts.staff.doctor.schedule[0].pools.is_empty() and x.world.facts.staff.doctor.schedule_overrides["0"].pools.is_empty()
	x.checks.undo_restores_schedule = _do(x,"build_undo",{}).accepted and x.world.facts.rooms.duty.kind=="gp" and x.world.facts.staff.doctor.schedule[0].pools==["duty"] and x.world.facts.staff.doctor.schedule_overrides["0"].pools==["duty"]
	x.checks.invalidated_room_clears_both = _do(x,"build_remove_wall",{"edges":[{"axis":"y","line":38,"low":67,"high":68}]}).accepted and x.world.facts.staff.doctor.schedule[0].pools.is_empty() and x.world.facts.staff.doctor.schedule_overrides["0"].pools.is_empty()
	return _finish(x)

func _connector_walls() -> Dictionary:
	var x: Dictionary = _base()
	# A declared, completed three-floor hospital before the tested wall edit.
	# The connector itself is bought and extended through its normal owner.
	x.world.facts.floors.height_intervals = [{"first":1,"last":3,"height_m":float(content.balance.floors.clear_height_m)}]
	x.world.facts.floors.completed_top_floor = {HospitalSpace.plot_key([1,2]):3}
	for floor_id: int in [2,3]:
		x.world.facts.floors.overrides[str(floor_id)] = {"plots":[[1,2]],"blocked":[],"wall_edges":[],"doors":[],"paths":[]}
	x.world.touch()
	var connector := HospitalConnectors.new(content,x.builder.space)
	var bought: CommandResult = connector.execute(x.world,"connector_build",{"definition_id":"VC02","floor_id":1,"cell":[50,70]})
	x.checks.connector_bought = bought.accepted
	if not bought.accepted: return _finish(x)
	var id: String = str(bought.changed_ids[0])
	for floor_id: int in [2,3]:
		x.checks["extended_"+str(floor_id)] = connector.execute(x.world,"connector_extend",{"connection_id":id,"floor_id":floor_id}).accepted
	x.checks.legal_input = x.world.validate(content).is_empty()
	for floor_id: int in [1,2,3]:
		var request: Dictionary = {"floor_id":floor_id,"edges":[{"axis":"x","line":72,"low":50,"high":54}]}
		var before: Dictionary = x.world.freeze()
		var quote: Dictionary = x.builder.preview(x.world,request.merged({"kind":"build_wall"}))
		x.checks["stop_"+str(floor_id)+"_preview_rejected_readonly"] = not quote.ok and x.world.freeze()==before
		x.checks["stop_"+str(floor_id)+"_confirmation_atomic"] = not _do(x,"build_wall",request).accepted and x.world.freeze()==before
	var cash: int = HospitalLedger.balance(x.world)
	x.checks.nearby_wall_still_legal = _do(x,"build_wall",{"floor_id":2,"edges":[{"axis":"x","line":80,"low":50,"high":54}]}).accepted and HospitalLedger.balance(x.world)==cash-80
	return _finish(x)
