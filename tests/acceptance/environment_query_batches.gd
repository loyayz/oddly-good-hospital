extends RefCounted

# These are legal inputs immediately before selection. Actual movement, work,
# handoff and completion remain covered by OPS-13/14/16/17.
func run(content: HospitalContent) -> Dictionary:
	var builder: RefCounted = load("res://tests/acceptance/operations.gd").new()
	builder._content = content
	var safety: Dictionary = _safety(builder)
	var cleanup: Dictionary = _cleanup(builder)
	for simulation: HospitalSimulation in builder._live: simulation.dispose()
	return {"ok":safety.ok and cleanup.ok,"details":{"safety":safety,"cleanup":cleanup}}

func _safety(builder: RefCounted) -> Dictionary:
	var f: Dictionary = builder._new("装修单元当前身体边界")
	builder._staff(f,"safety_actor","cleaner",[41,80])
	var actor: Dictionary = f.w.facts.actors.safety_actor
	var environment: HospitalEnvironment = f.s.services.environment
	var order: Dictionary = {"floor_id":1}
	var unit: Dictionary = {"cell":[42,80],"worker_id":""}
	var rect: Rect2 = f.s.space.body_rectangle(actor)
	actor.location.cell[0] = float(actor.location.cell[0])+42.0-rect.end.x
	var before: Dictionary = f.w.freeze()
	var touching: bool = environment._unit_safe(f.w,order,unit)
	var readonly: bool = f.w.freeze()==before
	# Direct writes deliberately do not increment revision. Each later phase
	# must still use the current complete body rather than a retained answer.
	actor.location.cell[0] += 0.125
	var entered: bool = not environment._unit_safe(f.w,order,unit)
	var batch: Dictionary = {}
	var batch_blocked: bool = not environment._unit_safe(f.w,order,unit,batch)
	var clear_unit: Dictionary = {"cell":[46,80],"worker_id":""}
	var batch_clear: bool = environment._unit_safe(f.w,order,clear_unit,batch)
	unit.worker_id = "safety_actor"
	var own_worker: bool = environment._unit_safe(f.w,order,unit) and environment._unit_safe(f.w,order,unit,batch)
	unit.worker_id = ""
	batch_blocked = batch_blocked and not environment._unit_safe(f.w,order,unit,batch)
	actor.location.cell = [45,80]
	var departed: bool = environment._unit_safe(f.w,order,unit)
	var valid: String = f.w.validate(builder._content)
	return {"ok":touching and entered and own_worker and batch_blocked and batch_clear and departed and readonly and valid.is_empty(),"touching_edge_clear":touching,"fractional_body_entry_blocks":entered,"own_worker_excluded":own_worker,"batch_uses_same_live_body_and_per_unit_worker":batch_blocked and batch_clear,"next_boundary_reads_direct_change":departed,"query_readonly":readonly,"validation":valid}

func _cleanup(builder: RefCounted) -> Dictionary:
	var f: Dictionary = builder._new("清洁先老化后置顶及唯一派单")
	f.w.facts.sim_tick = 1000
	builder._staff(f,"cleaner_a","cleaner",[40,80])
	builder._staff(f,"cleaner_b","cleaner",[40,82])
	var environment: HospitalEnvironment = f.s.services.environment
	var aged: String = environment.spawn_dirt(f.w,"CL01","aged_source","aged_fact",1,[47,80])
	var pinned: String = environment.spawn_dirt(f.w,"CL01","pinned_source","pinned_fact",1,[44,82])
	var other: String = environment.spawn_dirt(f.w,"CL01","other_source","other_fact",1,[42,80])
	if "" in [aged,pinned,other]: return {"ok":false,"reason":"合法前置未生成全部污物"}
	f.w.facts.environment.dirt[aged].generated_tick = 0
	f.w.facts.environment.pinned_dirt_id = pinned
	environment.dispatch(f.w)
	var ordering: bool = f.w.facts.staff.cleaner_a.active_job_id==aged and f.w.facts.staff.cleaner_b.active_job_id==pinned and f.w.facts.environment.dirt[other].worker_id==""
	var routes: bool = true
	for id: String in [aged,pinned]:
		var patch: Dictionary = f.w.facts.environment.dirt[id]
		routes = routes and f.s.space.route(f.w,patch.worker_id,1,patch.work_cell).ok
	var unique: bool = f.w.facts.environment.dirt[aged].worker_id!=f.w.facts.environment.dirt[pinned].worker_id
	var g: Dictionary = builder._new("严格工作区域与无操作位保留原任务")
	builder._staff(g,"region_cleaner","cleaner",[40,80])
	var restricted: HospitalEnvironment = g.s.services.environment
	var outside: String = restricted.spawn_dirt(g.w,"CL01","outside_source","outside_fact",1,[47,80])
	var blocked: String = restricted.spawn_dirt(g.w,"CL01","blocked_source","blocked_fact",1,[44,80])
	var reachable: String = restricted.spawn_dirt(g.w,"CL01","reachable_source","reachable_fact",1,[42,82])
	if "" in [outside,blocked,reachable]: return {"ok":false,"reason":"严格区域前置未生成全部污物"}
	g.w.facts.staff.region_cleaner.work_region = {"strict":true,"floor_id":1,"origin":[38,78],"size":[8,8]}
	for cell: Array in [[44,80],[43,80],[44,79],[44,81],[45,80]]: g.w.facts.floors.overrides["1"].blocked.append(cell)
	g.w.touch()
	restricted.dispatch(g.w)
	var region: bool = g.w.facts.staff.region_cleaner.active_job_id==reachable and g.w.facts.environment.dirt[outside].worker_id=="" and g.w.facts.environment.dirt[blocked].worker_id=="" and g.w.facts.environment.dirt[blocked].remaining_milli==4000 and not g.w.facts.environment.dirt[blocked].reason.is_empty()
	var validations: Array = [f.w.validate(builder._content),g.w.validate(builder._content)]
	return {"ok":ordering and unique and routes and region and validations==["",""],"aged_before_pinned_then_other":ordering,"unique_assignment":unique,"actual_work_positions_reachable":routes,"region_and_unreachable_preserve_tasks":region,"validation":validations}
