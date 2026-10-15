extends SceneTree

var _failures: Array[String] = []
var _checks: int = 0
var _content: HospitalContent

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_content = HospitalContent.new()
	_check("published_content",_content.error.is_empty())
	var world: WorldState = HospitalFactory.create("stage28_rules","空间成长验收",false,_content)
	world.facts.mode = "creative"
	var simulation: HospitalSimulation = HospitalSimulation.new(world,_content)
	var room: CommandResult = simulation.apply(GameCommand.new("room",world.hospital_id,world.revision,"build_room",BusinessPayload.new({"floor_id":1,"room_type_id":"gp","origin":[34,66],"size":[4,4]})))
	_check("real_empty_room",room.accepted,room.reason)
	var built: CommandResult = _command(simulation,"lift","connector_build",{"definition_id":"VC02","floor_id":1,"cell":[54,84]})
	_check("ground_single_station",built.accepted,built.reason)
	if not built.accepted: _finish(); return
	var connection_id: String = str(built.changed_ids[0])
	_check("single_station_has_no_upper_landing",not HospitalTransit.has_stop(world.facts.connectors[connection_id],2))
	var quote: Dictionary = simulation.services.floors.preview(world,{"source":"lift","connection_id":connection_id,"floor_id":2,"plot":[1,2]})
	_check("module_uses_actual_room",quote.ok,str(quote.get("reason","")))
	var bought: CommandResult = _command(simulation,"floor2","floor_purchase",{"source":"lift","connection_id":connection_id,"floor_id":2,"plot":[1,2]})
	_check("module_completes_actual_structure",bought.accepted and int(world.facts.floors.completed_top_floor.get("1:2",1))==2,bought.reason)
	_check("empty_floor_not_materialized",not world.facts.floors.overrides.has("2"))
	_check("upper_plate_does_not_grant_lift_station",not HospitalTransit.has_stop(world.facts.connectors[connection_id],2))
	var upper: CommandResult = _command(simulation,"upper_room","build_room",{"floor_id":2,"room_type_id":"gp","origin":[34,66],"size":[4,4]})
	_check("unconnected_plate_accepts_empty_room",upper.accepted,upper.reason)
	var station: CommandResult = _command(simulation,"station2","connector_extend",{"connection_id":connection_id,"floor_id":2})
	_check("explicit_second_station",station.accepted and HospitalTransit.has_stop(world.facts.connectors[connection_id],2),station.reason)
	world.facts.actors.test_actor = {"id":"test_actor","name":"验收居民","species_id":"S49","location":{"kind":"floor","floor_id":1,"cell":[50.0,90.0]},"facing":0.0,"posture":"standing"}
	world.touch()
	_check("real_cross_floor_request",simulation.space.request_move(world,"test_actor",2,[54,88]).is_empty())
	for index: int in 600:
		if simulation.space.at(world,"test_actor",2,[54,88]): break
		simulation.step()
	_check("real_actor_alights_on_upper_floor",simulation.space.at(world,"test_actor",2,[54,88]))
	_check("sole_connection_cannot_strand_actor",not simulation.services.connectors.preview(world,"connector_remove",{"connection_id":connection_id}).ok)
	_check("transit_roundtrip_does_not_double_place_actor",world.facts.actors.test_actor.location.kind=="floor" and world.facts.connectors[connection_id].riders.is_empty())
	_check("new_state_snapshot_validation",world.validate(_content).is_empty(),world.validate(_content))
	var restored: WorldState = WorldState.new(world.freeze())
	_check("restored_structure_and_ticket_state",restored.validate(_content).is_empty(),restored.validate(_content))
	var sparse: WorldState = HospitalFactory.create("stage28_sparse","稀疏楼层验收",false,_content)
	var sparse_sim: HospitalSimulation = HospitalSimulation.new(sparse,_content)
	sparse.facts.floors.completed_top_floor["1:2"] = 10000
	_check("ten_thousand_floor_projection",sparse_sim.space.owned(sparse,10000,Vector2i(35,70)))
	_check("ten_thousand_floor_storage_stays_sparse",sparse.facts.floors.overrides.size()==1 and sparse.facts.floors.completed_top_floor.size()==1)
	_check("legal_empty_structure_history_restores",sparse.validate(_content).is_empty(),sparse.validate(_content))
	for definition: Dictionary in _content.catalog.blueprint_presets:
		var preset: Dictionary = simulation.services.blueprints.builtin(definition.id)
		_check("builtin_"+definition.id,preset.ok and simulation.services.blueprints.validate_definition(preset.get("blueprint",{})).is_empty(),str(preset.get("reason","")))
	var empty: WorldState = HospitalFactory.create("stage28_blueprint","蓝图验收",false,_content)
	empty.facts.ledger.opening_balance = 100000
	var blueprint_sim: HospitalSimulation = HospitalSimulation.new(empty,_content)
	var preset: Dictionary = blueprint_sim.services.blueprints.builtin("BP01")
	var draft: Dictionary = {"blueprint":preset.blueprint,"floor_id":1,"cell":[34,66],"use_inventory":true}
	var preview: Dictionary = blueprint_sim.services.blueprints.preview(empty,draft)
	_check("complete_blueprint_quote",preview.ok,str(preview.get("reason","")))
	if preview.ok:
		draft.quote = {"price":preview.price,"inventory_choices":preview.inventory_choices}
		var before: int = HospitalLedger.balance(empty)
		var placed: CommandResult = _command(blueprint_sim,"blueprint","blueprint_place",draft)
		_check("atomic_blueprint_payment",placed.accepted and before-HospitalLedger.balance(empty)==int(preview.price),placed.reason)
		var repeat: CommandResult = _command(blueprint_sim,"blueprint","blueprint_place",draft)
		_check("blueprint_command_idempotent",repeat.accepted and before-HospitalLedger.balance(empty)==int(preview.price))
		var room_id: String = str(empty.ids("rooms")[0])
		var group: Dictionary = blueprint_sim.services.remodel.group_commands(empty,[room_id],[],1,[44,66],1)
		var arranged: CommandResult = _command(blueprint_sim,"arrange","remodel_prepare",{"commands":group.commands})
		_check("arrangement_does_not_move_room",arranged.accepted and empty.facts.rooms[room_id].origin==[34,66])
		if arranged.accepted:
			var order_id: String = str(arranged.changed_ids[0])
			var remodel: Dictionary = blueprint_sim.services.remodel.preview(empty,order_id)
			_check("empty_room_group_ready",remodel.ok,str(remodel.get("reason","")))
			if remodel.ok:
				var result: CommandResult = _command(blueprint_sim,"apply","remodel_apply",{"order_id":order_id,"quote":{"price":remodel.price,"refund":remodel.refund,"layout":remodel.layout}})
				_check("group_move_preserves_room_identity",result.accepted and empty.facts.rooms.has(room_id) and empty.facts.rooms[room_id].origin==[44,66],result.reason)
		_check("blueprint_and_remodel_snapshot",empty.validate(_content).is_empty(),empty.validate(_content))
	blueprint_sim.dispose()
	sparse_sim.dispose()
	simulation.dispose()
	_finish()

func _command(simulation: HospitalSimulation, id: String, kind: String, payload: Dictionary) -> CommandResult:
	return simulation.apply(GameCommand.new(id,simulation.world.hospital_id,simulation.world.revision,kind,BusinessPayload.new(payload)))

func _check(label: String, passed: bool, reason: String = "") -> void:
	_checks += 1
	if not passed: _failures.append(label+": "+reason)

func _finish() -> void:
	for failure: String in _failures: push_error(failure)
	print(JSON.stringify({"checks":_checks,"failures":_failures,"status":"passed" if _failures.is_empty() else "failed"}))
	quit(0 if _failures.is_empty() else 1)
