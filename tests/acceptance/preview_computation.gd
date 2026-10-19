extends RefCounted

const Fixture = preload("res://tools/performance/fixture.gd")

class CountPreview extends BuildPreview:
	var updates: int = 0
	func update(world: WorldState, maximum_units: int = 0, completed_boundary: Array = []) -> Dictionary:
		updates += 1
		return super.update(world,maximum_units,completed_boundary)

static func run(content: HospitalContent) -> Dictionary:
	# Original geometric fixture: all 640 bodies remain on its four active
	# floors; floor 2 is owned and empty except for the real shaft. Factory
	# visitor placeholders do not qualify this test as a formal active load.
	var fixture: RefCounted = Fixture.new(content,640,"tall")
	var world: WorldState = fixture.world
	var before: Dictionary = world.freeze()
	var observations: Array = []
	var ok: bool = fixture.errors.is_empty() and world.validate(content).is_empty()
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
		var started: int = Time.get_ticks_usec()
		var updates: int = 0
		var maximum_update_us: int = 0
		while (preview.job==null or not preview.job.complete) and updates<2000:
			var begin: int = Time.get_ticks_usec()
			preview.update(world,0,[world,world.revision])
			maximum_update_us = maxi(maximum_update_us,Time.get_ticks_usec()-begin)
			updates += 1
		var expected: bool = bool(preview.result.get("ok",false)) if width==85 else not bool(preview.result.get("ok",false)) and str(preview.result.get("reason","")).contains("竖向结构")
		if width==85: expected = expected and int(preview.result.get("price",-1))==323050
		ok = ok and expected and preview.job.complete and world.freeze()==before
		observations.append({"width":width,"height":95,"complete":preview.job.complete,"ok":preview.result.get("ok",false),"reason":preview.result.get("reason",""),"price":preview.result.get("price",-1),"updates":updates,"elapsed_us":Time.get_ticks_usec()-started,"maximum_update_us":maximum_update_us,"atomic_overruns":preview.job.atomic_overruns})
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
	var first_floor_draft: Dictionary = _draft(85)
	first_floor_draft.floor_id = 1
	turning.request(first_floor_draft,{"hospital_id":world.hospital_id,"view_floor_id":1})
	for slice: int in 1000:
		turning.update(world,1,[world,world.revision])
		if not turning.job._occupancy_views.is_empty() or turning.job.complete: break
	var cached_occupancy: bool = not turning.job._occupancy_views.is_empty()
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
	return {"ok":ok and unchanged and restarted and cached_occupancy and facing_restart and shape_reused and separate_economics and cache_retained and source_recaptured and cache_released and cancelled and shared and outline and window.passed,"details":{"maximum_requests":observations,"irrelevant_change_and_rebind":unchanged,"relevant_restart":restarted,"cached_occupancy_before_facing_change":cached_occupancy,"facing_restart_without_revision":facing_restart,"completed_shape_reused":shape_reused,"shared_basis_separate_economics":separate_economics,"static_cache_retained_with_fresh_scope":cache_retained,"navigation_source_recaptured_without_touch":source_recaptured,"cache_released_on_cancel":cache_released,"cancelled":cancelled,"shared_budget":shared,"complete_outline_bounds_and_floor":outline,"window_owned_result":window,"metric_scope":"headless complete preview computation; update calls are not displayed frames or OS input latency"}}

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
