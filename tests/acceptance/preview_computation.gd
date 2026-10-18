extends RefCounted

const Fixture = preload("res://tools/performance/fixture.gd")

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
	rotating_actor.facing = facing+PI*0.5
	# Direct prospective queries do not assume every original write touched the
	# revision. Facing is a real rotated-body occupancy dependency.
	turning.update(world,1)
	var facing_restart: bool = turning.restarted_jobs==1 and not turning.result.get("ready",false)
	rotating_actor.facing = facing
	turning.cancel()
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
	return {"ok":ok and unchanged and restarted and cached_occupancy and facing_restart and cancelled and shared and outline,"details":{"maximum_requests":observations,"irrelevant_change_and_rebind":unchanged,"relevant_restart":restarted,"cached_occupancy_before_facing_change":cached_occupancy,"facing_restart_without_revision":facing_restart,"cancelled":cancelled,"shared_budget":shared,"complete_outline_bounds_and_floor":outline,"metric_scope":"headless complete preview computation; update calls are not displayed frames or OS input latency"}}

static func _draft(width: int) -> Dictionary:
	return {"kind":"build_room","room_type_id":"gp","floor_id":2,"origin":[0,0],"size":[width,95],"door":{"definition_id":"DR01","edge":"south","offset":1}}
