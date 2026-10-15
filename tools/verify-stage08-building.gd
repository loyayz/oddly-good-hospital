extends SceneTree

var checks: Dictionary = {}
var failures: Array[String] = []
var content: HospitalContent
var build: BuildService

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	content = HospitalContent.new()
	build = BuildService.new(content)
	var world: WorldState = empty_world()
	var room_type_count: int = 0
	for definition: Dictionary in content.catalog.get("build_room_types",[]):
		var type_world: WorldState = empty_world()
		var type_draft: Dictionary = room_draft()
		type_draft.room_type_id = definition.id
		type_draft.size = definition.min_inner_size.duplicate()
		check("empty_shell_"+str(definition.id),build.execute(type_world,"build_room",type_draft).accepted and type_world.facts.facilities.is_empty())
		room_type_count += 1
	check("all_seventeen_original_room_types",room_type_count==17)
	var draft: Dictionary = room_draft()
	var frozen: String = canonical(world)
	var quote: Dictionary = build.preview(world,draft)
	check("readonly_complete_preview",quote.ok and int(quote.price)==690 and quote.ready and canonical(world)==frozen)
	if not quote.ok:
		print("PREVIEW_REASON="+str(quote.get("reason","")))
	var command: Dictionary = draft.duplicate(true)
	command.quote = quote.get("quote",{})
	command.record_key = "room-once"
	world.touch()
	check("unrelated_revision_accepted",build.execute(world,"build_room",command).accepted)
	check("empty_room_no_free_equipment",world.facts.rooms.has("room-a") and world.facts.facilities.is_empty() and HospitalLedger.balance(world)==99310)
	var after: String = canonical(world)
	check("duplicate_confirmation_no_second_cost",build.execute(world,"build_room",command).accepted and canonical(world)==after)
	var changed: Dictionary = command.duplicate(true)
	changed.origin = [40,70]
	check("duplicate_payload_conflict",not build.execute(world,"build_room",changed).accepted and canonical(world)==after)
	check("undo_empty_room_refunds_all",build.execute(world,"build_undo",{}).accepted and world.facts.rooms.is_empty() and HospitalLedger.balance(world)==100000)
	check("undo_receipt_validate",build.validate(world).is_empty())
	var invalid: Dictionary = room_draft()
	invalid.origin = [30,70]
	assert_atomic(world,"unowned_room_atomic","build_room",invalid)
	invalid = room_draft()
	invalid.origin = [46,92]
	assert_atomic(world,"entrance_buffer_preserved","build_room",invalid)
	invalid = room_draft()
	invalid.size = [3,4]
	assert_atomic(world,"minimum_rectangle_required","build_room",invalid)
	var disconnected: Array = rectangle_cells([33,66],[4,4])+[[40,70]]
	invalid = {"cells":disconnected,"room_type_id":"gp","door":{"edge":"south","offset":1}}
	assert_atomic(world,"disconnected_room_rejected","build_room",invalid)
	var holed: Array = rectangle_cells([33,66],[6,6])
	holed.erase([34,67])
	invalid.cells = holed
	assert_atomic(world,"internal_hole_rejected","build_room",invalid)
	var l_shape: Array = rectangle_cells([33,66],[4,4])+rectangle_cells([37,69],[2,1])
	var l_draft: Dictionary = {"id":"l-room","room_type_id":"gp","floor_id":1,"cells":l_shape,"door":{"edge":"south","offset":1,"definition_id":"DR01"}}
	check("legal_l_room",build.execute(world,"build_room",l_draft).accepted)
	check("l_room_wall_edges_do_not_use_bounding_box",world.facts.rooms.get("l-room",{}).get("cells",[]).size()==18)
	world = empty_world()
	check("purchase_facility",build.execute(world,"build_facility",{"id":"bench","definition_id":"FUR09","cell":[33,75]}).accepted)
	check("move_free",build.execute(world,"build_move",{"target_id":"bench","cell":[34,75]}).accepted and HospitalLedger.balance(world)==99950)
	check("rotate_free",build.execute(world,"build_rotate",{"target_id":"bench"}).accepted and HospitalLedger.balance(world)==99950)
	check("unused_facility_full_refund",build.execute(world,"build_demolish",{"target_id":"bench"}).accepted and HospitalLedger.balance(world)==100000)
	check("undo_demolition_restores_and_recharges",build.execute(world,"build_undo",{}).accepted and world.facts.facilities.has("bench") and HospitalLedger.balance(world)==99950)
	world.facts.facilities.bench.use_receipts["actual-seat"] = true
	assert_atomic(world,"used_object_cannot_undo","build_undo",{})
	check("used_facility_eighty_percent",build.execute(world,"build_demolish",{"target_id":"bench"}).accepted and HospitalLedger.balance(world)==99990)
	assert_atomic(world,"used_demolition_cannot_undo","build_undo",{})
	world = empty_world()
	build.ensure(world)
	world.facts.inventory.build_items.gift = {"id":"gift","definition_id":"M09","paid_cost":0,"ownership":"gift","rotation":0,"completed_upgrade_paid_cost":0}
	check("gift_inventory_actual_identity",build.execute(world,"build_facility",{"inventory_id":"gift","definition_id":"M09","cell":[33,75]}).accepted and world.facts.inventory.build_items.is_empty() and world.facts.facilities.has("gift") and HospitalLedger.balance(world)==100000)
	check("gift_undo_restores_single_item",build.execute(world,"build_undo",{}).accepted and not world.facts.facilities.has("gift") and world.facts.inventory.build_items.size()==1)
	check("gift_place_again",build.execute(world,"build_facility",{"inventory_id":"gift","definition_id":"M09","cell":[33,75]}).accepted)
	check("gift_no_refund",build.execute(world,"build_demolish",{"target_id":"gift"}).accepted and HospitalLedger.balance(world)==100000)
	world = empty_world()
	world.facts.ledger.opening_balance = 50
	assert_atomic(world,"insufficient_funds_atomic","build_room",room_draft())
	world = empty_world()
	check("land_only_acquires_grass",build.execute(world,"build_land",{"plot":[0,2]}).accepted and HospitalLedger.balance(world)==97000 and world.facts.rooms.is_empty() and world.facts.facilities.is_empty() and world.facts.floors.overrides["1"].plots.size()==2)
	assert_atomic(world,"land_purchase_cannot_be_undone","build_undo",{})
	assert_atomic(world,"land_purchase_requires_shared_edge","build_land",{"plot":[2,0]})
	world = empty_world()
	var original: Dictionary = build.preview(world,room_draft())
	var cheaper: Dictionary = room_draft()
	cheaper.quote = original.quote.duplicate(true)
	cheaper.quote.price -= 1
	assert_atomic(world,"changed_actual_price_atomic","build_room",cheaper)
	check("build_for_door_checks",build.execute(world,"build_room",room_draft()).accepted)
	var door_id: String = world.facts.floors.overrides["1"].doors[0].id
	assert_atomic(world,"cannot_remove_only_exit","build_demolish",{"target_id":door_id})
	check("replace_door_refunds_original",build.execute(world,"build_door",{"target_id":door_id,"definition_id":"DR04","edge":"south","offset":1}).accepted and HospitalLedger.balance(world)==99220)
	check("room_move_preserves_door_and_cash",build.execute(world,"build_move",{"target_id":"room-a","cell":[38,67]}).accepted and HospitalLedger.balance(world)==99220)
	check("room_rotate_preserves_real_structure",build.execute(world,"build_rotate",{"target_id":"room-a","turns":1}).accepted)
	check("real_new_building_state_validates",build.validate(world).is_empty())
	world.facts.ledger.entries["operating-day"] = {"owner_id":"day","component":"operations:0","amount":-10,"tick":0,"settled":true}
	assert_atomic(world,"operating_settlement_disables_undo","build_undo",{})
	world = empty_world()
	check("put_facility_for_occupancy",build.execute(world,"build_facility",{"id":"bench","definition_id":"FUR09","cell":[33,75]}).accepted)
	world.facts.sessions.busy = {"facility_id":"bench","remaining_ticks":10}
	assert_atomic(world,"active_service_cannot_move","build_move",{"target_id":"bench","cell":[34,75]})
	assert_atomic(world,"active_service_cannot_demolish","build_demolish",{"target_id":"bench"})
	world = empty_world()
	world.facts.environment = {"dirt":{"scrap":{"id":"scrap","floor_id":1,"cell":[33,75],"bin_id":""}}}
	assert_atomic(world,"real_dirt_cannot_be_built_over","build_facility",{"definition_id":"FUR09","cell":[33,75]})
	world = empty_world()
	check("gift_upgrade_setup",build.execute(world,"build_facility",{"id":"gift-upgrade","definition_id":"M09","cell":[33,75]}).accepted)
	world.facts.facilities["gift-upgrade"].ownership = "gift"
	world.facts.facilities["gift-upgrade"].paid_cost = 0
	world.facts.facilities["gift-upgrade"].completed_upgrade_paid_cost = 101
	world.facts.facilities["gift-upgrade"].used = true
	check("gift_base_zero_paid_upgrade_refund",build.preview(world,{"kind":"build_demolish","target_id":"gift-upgrade"}).get("refund",-1)==80)
	world = empty_world()
	world.facts.actors.person = {"id":"person","species_id":"S49","location":{"kind":"floor","floor_id":1,"cell":[33,75]},"facing":0.0,"posture":"standing"}
	assert_atomic(world,"actual_body_occupancy_preserved","build_facility",{"definition_id":"FUR09","cell":[33,75]})
	world = empty_world()
	for index: int in 22:
		var result: CommandResult = build.execute(world,"build_facility",{"id":"seat-"+str(index),"definition_id":"FUR09","cell":[33+index,75]})
		check("history_item_"+str(index),result.accepted)
	check("history_bounded_twenty",world.facts.build_history.size()==20)
	check("snapshot_restores_conditional_undo",build.execute(WorldState.new(world.freeze()),"build_undo",{}).accepted)
	var preview: BuildPreview = BuildPreview.new(build)
	var first: int = preview.request(room_draft(),{"hospital_id":world.hospital_id,"hospital_session":"first","view_floor_id":1})
	var same: int = preview.request(room_draft(),{"hospital_id":world.hospital_id,"hospital_session":"first","view_floor_id":2,"world_revision":99})
	check("preview_ignores_view_only_generation",first==same)
	frozen = canonical(world)
	var projected: Dictionary = preview.update(world)
	check("preview_view_binding_readonly",not projected.draw_on_current_floor and canonical(world)==frozen)
	var newest: Dictionary = room_draft()
	newest.origin = [38,66]
	preview.request(newest,{"hospital_id":world.hospital_id,"hospital_session":"first","view_floor_id":1})
	preview.request(room_draft(),{"hospital_id":world.hospital_id,"hospital_session":"first","view_floor_id":1})
	check("preview_keeps_one_latest_pending",preview.pending.semantic.draft.origin==room_draft().origin)
	preview.cancel()
	check("cancel_preview_has_no_world_effect",preview.current.is_empty() and preview.pending.is_empty() and canonical(world)==frozen)
	world = empty_world()
	var sliced: BuildPreview = BuildPreview.new(build)
	sliced.request(room_draft(),{"hospital_id":world.hospital_id,"hospital_session":"sliced","view_floor_id":1})
	var first_slice: Dictionary = sliced.update(world,1)
	check("first_slice_cannot_claim_ready",not first_slice.ready and sliced.job!=null and not sliced.job.complete)
	var original_job: BuildPreviewJob = sliced.job
	world.touch()
	sliced.update(world,1)
	check("unrelated_revision_keeps_incremental_job",sliced.job==original_job and sliced.restarted_jobs==0)
	for index: int in 1000:
		if sliced.job.complete:
			break
		sliced.update(world,16)
	check("complete_incremental_preview_matches_authority",sliced.job.complete and sliced.result.ready and sliced.result.quote==build.preview(world,room_draft()).quote and sliced.result.units_checked>16)
	world.facts.actors.blocker = {"id":"blocker","species_id":"S49","location":{"kind":"floor","floor_id":1,"cell":[33,66]},"facing":0.0,"posture":"standing"}
	var revoked: Dictionary = sliced.update(world,1)
	check("new_body_revokes_ready_before_recheck",not revoked.ready and sliced.restarted_jobs==1)
	for index: int in 1000:
		if sliced.job.complete:
			break
		sliced.update(world,16)
	check("incremental_complete_collision_rejected",sliced.job.complete and not sliced.result.ok and not sliced.result.ready)
	var revised: Dictionary = room_draft()
	revised.origin = [38,66]
	sliced.request(revised,{"hospital_id":world.hospital_id,"hospital_session":"sliced","view_floor_id":1})
	sliced.update(world,1)
	check("superseding_draft_releases_old_job",sliced.job.draft.origin==[38,66] and not sliced.result.ready)
	print("BUILDING_RULES="+str(checks.size())+" failures="+str(failures.size()))
	for failure: String in failures:
		print("FAIL="+failure)
	var output: FileAccess = FileAccess.open("res://stage08-building-rules.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures,"performance":"skipped"},"\t",true,true))
	quit(0 if failures.is_empty() else 1)

func empty_world() -> WorldState:
	var world: WorldState = FeasibilityHospitals.create("build-rules",false,content)
	for collection: String in ["actors","staff","visits","tickets","sessions","attempts","preparations","ward_stays","facilities","rooms","connectors","moves","adaptations"]:
		world.facts[collection] = {}
	world.facts.floors.overrides = {"1":{"plots":[[1,2]],"blocked":[],"doors":[]}}
	return world

func room_draft() -> Dictionary:
	return {"id":"room-a","kind":"build_room","room_type_id":"gp","floor_id":1,"origin":[33,66],"size":[4,4],"door":{"edge":"south","offset":1,"definition_id":"DR01"}}

func rectangle_cells(origin: Array, size: Array) -> Array:
	var result: Array = []
	for y: int in range(int(origin[1]),int(origin[1])+int(size[1])):
		for x: int in range(int(origin[0]),int(origin[0])+int(size[0])):
			result.append([x,y])
	return result

func canonical(world: WorldState) -> String:
	return JSON.stringify(world.facts,"",true,true)

func assert_atomic(world: WorldState, label: String, kind: String, payload: Dictionary) -> void:
	var before: String = canonical(world)
	var result: CommandResult = build.execute(world,kind,payload)
	check(label,not result.accepted and before==canonical(world))

func check(label: String, passed: bool) -> void:
	checks[label] = passed
	if not passed:
		failures.append(label)
