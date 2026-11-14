extends RefCounted

const Fixture = preload("res://tests/fixtures/preview_tall_hospital.gd")

class CountPreview extends BuildPreview:
	var updates: int = 0
	func update(world: WorldState, maximum_units: int = 0, completed_boundary: Array = []) -> Dictionary:
		updates += 1
		return super.update(world,maximum_units,completed_boundary)

static func run(content: HospitalContent) -> Dictionary:
	# Original geometric fixture: all 640 bodies remain on its four active
	# floors; floor 2 is owned and empty except for the real shaft. Factory
	# visitor placeholders do not qualify this test as a formal active load.
	var fixture: RefCounted = Fixture.new(content)
	var world: WorldState = fixture.world
	var raw_input: Dictionary={"tick":world.sim_tick,"rng":world.facts.rng.duplicate(true),"ledger":world.facts.ledger.duplicate(true),"inventory":world.facts.inventory.duplicate(true)}
	# Bind the complete declared input through ordinary service initialization;
	# no simulation step, movement or work precedes the preview baseline.
	var initializer:=HospitalSimulation.new(world,content)
	initializer.dispose()
	var initialization: Dictionary={"tick_unchanged":world.sim_tick==raw_input.tick,"rng_unchanged":world.facts.rng==raw_input.rng,"ledger_unchanged":world.facts.ledger==raw_input.ledger,"inventory_fields_unchanged":true,"added_inventory_fields":[],"added_inventory_item_fields":{}}
	# Supplies initializes its empty orders, usage and policy fields. All
	# declared stock, issues and purchased items retain their original values.
	for field: String in raw_input.inventory:
		if field!="build_items":
			initialization.inventory_fields_unchanged=initialization.inventory_fields_unchanged and world.facts.inventory.get(field)==raw_input.inventory[field]
			continue
		# Maintenance adds condition and repair defaults to stored equipment.
		# Check every originally declared item field and the complete item set.
		var items: Dictionary=world.facts.inventory.build_items
		initialization.inventory_fields_unchanged=initialization.inventory_fields_unchanged and items.size()==raw_input.inventory.build_items.size()
		for id: String in raw_input.inventory.build_items:
			var original: Dictionary=raw_input.inventory.build_items[id]
			var actual: Dictionary=items.get(id,{})
			for key: String in original:
				initialization.inventory_fields_unchanged=initialization.inventory_fields_unchanged and actual.get(key)==original[key]
			for key: String in actual:
				if not original.has(key): initialization.added_inventory_item_fields.get_or_add(id,[]).append(key)
	for field: String in world.facts.inventory:
		if not raw_input.inventory.has(field): initialization.added_inventory_fields.append(field)
	var input_preserved: bool=initialization.tick_unchanged and initialization.rng_unchanged and initialization.ledger_unchanged and initialization.inventory_fields_unchanged
	var before: Dictionary = world.freeze()
	var observations: Array = []
	var input_validation: String=world.validate(content)
	var ok: bool = fixture.errors.is_empty() and input_validation.is_empty() and input_preserved
	var shapes: Array = [{"origin":[1,1],"size":[4,4]},{"origin":[95,95],"size":[2,2]},{"origin":[1,1],"size":[1,1]},{"origin":[1.5,1],"size":[4,4]},
		{"cells":[[1,1],[1,1]]},{"cells":[[1,1],[7,7]]}]
	var ring: Array = []
	for y: int in range(1,7):
		for x: int in range(1,7):
			if x!=3 or y!=3: ring.append([x,y])
	shapes.append({"cells":ring})
	shapes.append({"cells":BuildGeometry.cells({"origin":[1,1],"size":[4,4]})})
	for shape: Dictionary in shapes:
		var draft: Dictionary = {"kind":"build_room","room_type_id":"gp","floor_id":2,"door":{"definition_id":"DR01","edge":"south","offset":1}}
		draft.merge(shape)
		var original: Dictionary = BuildGeometry.shape(draft,content.definition("build_room_types","gp").min_inner_size)
		var job: BuildPreviewJob = BuildPreviewJob.new(BuildService.new(content),world,draft)
		for unit: int in 1000:
			if job.complete or job._phase=="prepare": break
			job.advance(world,2000,1)
		ok = ok and (job._shape==original if original.ok else job.complete and not job.result.get("ok",false))
	for width: int in [85,96]:
		var draft: Dictionary = _draft(width)
		var preview: BuildPreview = BuildPreview.new(BuildService.new(content))
		preview.request(draft,{"hospital_id":world.hospital_id,"view_floor_id":2})
		var updates: int = 0
		while (preview.job==null or not preview.job.complete) and updates<2000:
			preview.update(world,0,[world,world.revision])
			updates += 1
		var expected: bool = bool(preview.result.get("ok",false)) if width==85 else not bool(preview.result.get("ok",false)) and str(preview.result.get("reason","")).contains("竖向结构")
		# Empty 2F has no shared wall discount: 360 new wall edges at 20,
		# plus the selected DR01 at 50. Interior area has no construction fee.
		if width==85: expected = expected and int(preview.result.get("price",-1))==2*(85+95)*20+50
		ok = ok and expected and preview.job.complete and world.freeze()==before
		observations.append({"width":width,"height":95,"complete":preview.job.complete,"ok":preview.result.get("ok",false),"reason":preview.result.get("reason",""),"price":preview.result.get("price",-1),"updates":updates})
	var preview: BuildPreview = BuildPreview.new(BuildService.new(content))
	preview.request(_draft(85),{"hospital_id":world.hospital_id,"view_floor_id":2,"view_generation":1})
	preview.update(world,1)
	var generation: int = preview.generation
	preview.rebind({"hospital_id":world.hospital_id,"view_floor_id":10,"view_generation":2})
	world.touch()
	preview.update(world,1)
	var unchanged: bool = preview.generation==generation and preview.restarted_jobs==0 and not preview.result.draw_on_current_floor
	HospitalSpace.materialize_layout(world,2)
	world.facts.floors.overrides["2"].blocked.append([0,0])
	preview.update(world,1)
	var restarted: bool = preview.restarted_jobs==1 and not preview.result.get("ready",false)
	preview.cancel()
	var cancelled: bool = preview.job==null and preview.current.is_empty() and preview.pending.is_empty() and preview.result.is_empty()
	var turning: BuildPreview = BuildPreview.new(BuildService.new(content))
	# Original rooms end at y79. This independent public strip keeps clear of
	# their walls, the top-edge props, the lift and the hospital entrance. The
	# 160 first-floor bodies finish their ordered initial placement above y82.
	var first_floor_draft: Dictionary = {"kind":"build_room","room_type_id":"gp","floor_id":1,"origin":[16,82],"size":[8,8],"door":{"definition_id":"DR01","edge":"south","offset":1}}
	turning.request(first_floor_draft,{"hospital_id":world.hospital_id,"view_floor_id":1})
	# Preparation now visits changed-room rows, every room and all 640 actors
	# separately. Use the same full-preview limit as the maximum requests above;
	# a completed failure still cannot stand in for an actual occupancy view.
	for slice: int in 2000:
		turning.update(world,1,[world,world.revision])
		if not turning.job._occupancy_views.is_empty() or turning.job.complete: break
	var cached_occupancy: bool = not turning.job._occupancy_views.is_empty()
	var occupancy_boundary: Dictionary={"draft":first_floor_draft.duplicate(true),"phase":turning.job._phase,"units_checked":turning.job.units_checked,"complete":turning.job.complete,"reason":turning.job.result.get("reason",""),"plan_ok":turning.job._plan.get("ok",false),"changed_ids":turning.job._plan.get("changed_ids",[]).size(),"candidate_rooms":turning.job._candidate.facts.rooms.size() if turning.job._candidate!=null else 0,"candidate_actors":turning.job._candidate.facts.actors.size() if turning.job._candidate!=null else 0}
	if not cached_occupancy:
		turning.cancel()
		return {"ok":false,"details":{"maximum_requests":observations,"irrelevant_change_and_rebind":unchanged,"relevant_restart":restarted,"cancelled":cancelled,"cached_occupancy_before_facing_change":false,"occupancy_precondition_boundary":occupancy_boundary,"facing_checks_executed":false}}
	var rotating_actor: Dictionary = {}
	for actor: Dictionary in world.facts.actors.values():
		if actor.location.kind=="floor" and int(actor.location.floor_id)==1:
			rotating_actor = actor
			break
	var facing: float = float(rotating_actor.facing)
	var completed_shape: Dictionary = turning.job._shape
	var previous_safety: HospitalSpace = turning.job._safety_checker
	var previous_navigation: NavigationCache = previous_safety._navigation
	var basis: Dictionary = turning.job.dependency_basis(world)
	var cold_job: BuildPreviewJob = BuildPreviewJob.new(turning.service,world,first_floor_draft,basis)
	var separate_economics: bool = cold_job.dependency_key==cold_job.dependencies(world) and turning.job.dependencies(world,basis)!=cold_job.dependency_key and not basis.has("solvent") and not basis.has("retry_cash")
	rotating_actor.facing = facing+PI*0.5
	# Direct prospective queries do not assume every original write touched the
	# revision. Facing is a real rotated-body occupancy dependency.
	turning.update(world,1)
	var facing_restart: bool = turning.restarted_jobs==1 and not turning.result.get("ready",false)
	var shape_reused: bool = not completed_shape.is_empty() and is_same(turning.job._shape,completed_shape) and turning.job.units_checked==1
	var cache_retained: bool = turning.job._safety_checker!=previous_safety and turning.job._safety_checker._navigation==previous_navigation and turning.job._safety_checker._route_queries.is_empty()
	rotating_actor.facing = facing
	var original_source: Dictionary = turning.job._previous_checker._navigation.floor_source(turning.job._previous_checker,world,1)
	world.facts.floors.overrides["1"].blocked.append([0,0])
	turning.update(world,1)
	var refreshed_source: Dictionary = turning.job._previous_checker._navigation.floor_source(turning.job._previous_checker,world,1)
	var source_recaptured: bool = turning.restarted_jobs==2 and not [0,0] in original_source.layout.blocked and [0,0] in refreshed_source.layout.blocked
	world.facts.floors.overrides["1"].blocked.erase([0,0])
	turning.cancel()
	var cache_released: bool = turning._safety_navigation!=previous_navigation and turning._safety_navigation._entries.is_empty() and turning._previous_navigation._entries.is_empty()
	# The binding and preview share the same original budget, including across
	# repeated consumers in one frame. Exhaustion cannot publish permission.
	var budget: ViewWorkBudget = ViewWorkBudget.new(2000)
	budget.spend(2000)
	preview.work_budget = budget
	preview.request(_draft(85),{"hospital_id":world.hospital_id,"view_floor_id":2})
	preview.update(world)
	var shared: bool = budget.remaining_usec()==0 and preview.job.units_checked==0 and not preview.result.get("ready",false)
	var overlay: HospitalBuildOverlay = HospitalBuildOverlay.new()
	overlay.show_preview(_draft(96),{"ready":false},2)
	var bounds: AABB = overlay.mesh.get_aabb()
	var outline: bool = bounds.position.is_equal_approx(Vector3(-48,0.06,-96)) and bounds.size.is_equal_approx(Vector3(144,0,142.5))
	overlay.show_preview(_draft(96),{"ready":true,"ok":true},10)
	outline = outline and overlay.mesh==null
	overlay.free()
	world.facts.floors.overrides["2"].blocked.clear()
	preview.cancel()
	var window: Dictionary = _window_result(content)
	return {"ok":ok and unchanged and restarted and cached_occupancy and facing_restart and shape_reused and separate_economics and cache_retained and source_recaptured and cache_released and cancelled and shared and outline and window.passed,"details":{"input_validation":input_validation,"input_preserved":input_preserved,"initialization":initialization,"fixture_errors":fixture.errors,"maximum_requests":observations,"irrelevant_change_and_rebind":unchanged,"relevant_restart":restarted,"cached_occupancy_before_facing_change":cached_occupancy,"occupancy_precondition_boundary":occupancy_boundary,"facing_restart_without_revision":facing_restart,"completed_shape_reused":shape_reused,"shared_basis_separate_economics":separate_economics,"static_cache_retained_with_fresh_scope":cache_retained,"navigation_source_recaptured_without_touch":source_recaptured,"cache_released_on_cancel":cache_released,"cancelled":cancelled,"shared_budget":shared,"complete_outline_bounds_and_floor":outline,"window_owned_result":window}}

static func _window_result(content: HospitalContent) -> Dictionary:
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"窗口结果边界",false,content)
	var simulation: HospitalSimulation = HospitalSimulation.new(world,content)
	var session: GameSession = GameSession.new(simulation,"preview-window")
	var panel: HospitalBuildPanel = HospitalBuildPanel.new()
	panel.simulation = simulation
	panel.session = session
	var preview: CountPreview = CountPreview.new(simulation.services.building)
	panel._preview = preview
	panel._draft = {"kind":"build_room","room_type_id":"gp","floor_id":1,"origin":[35,68],"size":[4,4],"door":{"definition_id":"DR01","edge":"south","offset":1}}
	preview.request(panel._draft,panel._binding())
	for update_index: int in 1000:
		panel._refresh_preview()
		if preview.job!=null and preview.job.complete: break
	var completed: bool = preview.job!=null and preview.job.complete and panel._result.get("ok",false)
	if not completed:
		var failure: Dictionary = panel._result.duplicate(true)
		panel.free()
		simulation.dispose()
		return {"passed":false,"completion":failure}
	var owned: Dictionary = panel._result
	var calls: int = preview.updates
	for repeat: int in 3: panel._refresh_preview()
	var reused: bool = preview.updates==calls and is_same(owned,panel._result)
	var public_value: Dictionary = preview.update(world,0,[world,world.revision])
	public_value.draft.origin[0] = 0
	public_value.quote.price = -1
	var isolated: bool = panel._result.draft.origin==[35,68] and preview.result.draft.origin==[35,68] and panel._result.quote.price>=0 and preview.result.quote.price>=0
	calls = preview.updates
	panel.set_floor(2)
	panel._refresh_preview()
	var floor_rebind: bool = preview.updates==calls+1 and not panel._result.draw_on_current_floor
	panel.set_floor(1)
	panel._refresh_preview()
	var original_cash: int = HospitalLedger.balance(world)
	var before_tick: int = world.sim_tick
	calls = preview.updates
	var ordered: CommandResult = session.submit(GameCommand.new("window-cash-change",world.hospital_id,world.revision,"renovation_order",BusinessPayload.new({"material_id":"MAT01","floor_id":1,"units":[{"cell":[44,80]}],"allow_waiting":true}),session.loading_session_id))
	panel._refresh_preview()
	var command_boundary: bool = ordered.accepted and world.sim_tick==before_tick and HospitalLedger.balance(world)==original_cash-25 and preview.updates==calls+1 and int(panel._result.balance_after)==HospitalLedger.balance(world)-int(panel._result.price)+int(panel._result.refund)
	calls = preview.updates
	panel._preview_visibility_changed()
	panel._refresh_preview()
	var reshown: bool = preview.updates==calls+1
	panel._draft = panel._draft.duplicate(true)
	panel._draft.origin = [36,68]
	preview.request(panel._draft,panel._binding())
	calls = preview.updates
	panel._refresh_preview()
	var draft_changed: bool = preview.updates==calls+1 and preview.current.semantic.draft.origin==[36,68]
	var validation: String = world.validate(content)
	panel.free()
	simulation.dispose()
	return {"passed":reused and isolated and floor_rebind and command_boundary and reshown and draft_changed and validation.is_empty(),"unchanged_window_reuses_owned_result":reused,"public_result_deep_isolation":isolated,"view_floor_rebind":floor_rebind,"paused_command_and_cash_refresh":command_boundary,"reshown_refresh":reshown,"new_draft_refresh":draft_changed,"validation":validation}

static func _draft(width: int) -> Dictionary:
	return {"kind":"build_room","room_type_id":"gp","floor_id":2,"origin":[0,0],"size":[width,95],"door":{"definition_id":"DR01","edge":"south","offset":1}}
