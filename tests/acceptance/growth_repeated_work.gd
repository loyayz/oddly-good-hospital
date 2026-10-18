extends "res://tests/acceptance/growth_fixtures.gd"

const Jobs = preload("res://game/community/research_job_index.gd")

class Budgets extends HospitalArrivalService:
	var maintenance_builds: int = 0
	var facility_queries: int = 0
	func _maintenance_view(world: WorldState) -> Dictionary:
		maintenance_builds += 1
		return super._maintenance_view(world)
	func _maintenance_remaining(world: WorldState, facility_id: String, shift: int, view: Dictionary = {}) -> int:
		facility_queries += 1
		return super._maintenance_remaining(world,facility_id,shift,view)

func run(t, database: HospitalContent, checkpoint_cache: RefCounted) -> void:
	_content = database
	_cache = checkpoint_cache
	var started: int = Time.get_ticks_usec()
	var budgets: Dictionary = _budgets()
	var index: Dictionary = _index()
	for simulation: HospitalSimulation in _simulations: simulation.dispose()
	_simulations.clear()
	t.check("GROW-85",budgets.ok and index.ok and _fixture_errors.is_empty(),{"CL-A07":budgets,"CL-A09":index,"fixture_errors":_fixture_errors,"elapsed_usec":Time.get_ticks_usec()-started})

# A budget calculation consumes remaining work and worker availability. These
# declared inputs do not advance, complete or replace actual maintenance work.
func _budgets() -> Dictionary:
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"三班剩余工单预算",true,_content)
	var space: HospitalSpace = HospitalSpace.new(_content)
	var service: Budgets = Budgets.new(_content,space)
	service.ensure(world)
	var ids: Array = world.ids("facilities")
	if ids.size()<2: return {"ok":false,"reason":"two real facilities required"}
	var first: String = ids[0]
	var second: String = ids[1]
	world.facts.maintenance = {"jobs":{
		"first":{"facility_id":first,"phase":"working","worker_id":"budget_worker","worker_rate":1.0,"remaining_milli":250,"paused":false},
		"second":{"facility_id":first,"phase":"working","worker_id":"budget_worker","worker_rate":2.0,"remaining_milli":999,"paused":false},
		"ignored":{"facility_id":first,"phase":"completed","worker_id":"budget_worker","worker_rate":1.0,"remaining_milli":9999999,"paused":false}},
		"upgrades":{"blocked":{"facility_id":second,"phase":"inventory","worker_id":"","worker_rate":0.0,"remaining_milli":1000,"paused":true}}}
	var before: Dictionary = world.freeze()
	var view: Dictionary = service._maintenance_view(world)
	var actual: Array = []
	var expected: Array = []
	var resources: Array = ["facility:"+first,"facility:"+second]
	for shift: int in 3:
		var budget: Dictionary = service._resource_budgets(world,[],shift,resources,view)
		for id: String in [first,second]:
			var shift_ticks: int = ceili(float(_content.balance.schedule.shift_seconds)/WorldState.TICK_SECONDS)
			var facility: Dictionary = world.facts.facilities[id]
			var available: int = 0 if facility.get("failed",false) or not facility.get("open",true) or not facility.get("intake_open",true) else shift_ticks
			actual.append(budget["facility:"+id])
			expected.append(F.make(maxi(0,available-_original_remaining(world,id,shift))))
	var unchanged: bool = before==world.freeze()
	return {"ok":actual==expected and int(view.remaining.get(first,-1))==8 and service.maintenance_builds==1 and service.facility_queries==6 and unchanged,"budgets_equal_independent_original":actual==expected,"per_job_rounding_total_ticks":view.remaining.get(first,-1),"maintenance_builds":service.maintenance_builds,"facility_queries":service.facility_queries,"readonly":unchanged}

func _original_remaining(world: WorldState, facility_id: String, shift: int) -> int:
	var remaining: int = 0
	for collection: Dictionary in [world.facts.maintenance.jobs,world.facts.maintenance.upgrades]:
		for job: Dictionary in collection.values():
			if job.get("facility_id","")!=facility_id or job.get("phase","") in ["completed","cancelled"]: continue
			var rate: float = float(job.get("worker_rate",0))
			if rate<=0 or str(job.get("worker_id","")).is_empty() or job.get("paused",false): return ceili(float(_content.balance.schedule.shift_seconds)/WorldState.TICK_SECONDS)
			remaining += ceili(float(job.get("remaining_milli",0))/1000.0/rate/WorldState.TICK_SECONDS)
	var ticks: int = ceili(float(_content.balance.schedule.shift_seconds)/WorldState.TICK_SECONDS)
	return clampi(remaining-shift*ticks,0,ticks)

func _index() -> Dictionary:
	var ctx: Dictionary = _research_context(false,false)
	var start: CommandResult = _start(ctx,"R12",{"allow_waiting":true})
	var first: Dictionary = ctx.research.active_job(ctx.world,"R12")
	if not start.accepted or first.is_empty(): return {"ok":false,"start":start.to_record()}
	var readonly: Dictionary = ctx.world.freeze()
	var calls: int = 0
	var current: bool = true
	for _query: int in 32:
		current = current and ctx.research.active_job(ctx.world,"R12").id==first.id and is_same(ctx.research.rewards(ctx.world,"R12"),first.rewards)
		calls += 2
	var query_readonly: bool = readonly==ctx.world.freeze()
	current = current and query_readonly
	var pause: CommandResult = ctx.research.execute(ctx.world,"research_pause",{"research_id":"R12"})
	var paused: bool = ctx.research.active_job(ctx.world,"R12").state=="paused"
	var resume: CommandResult = ctx.research.execute(ctx.world,"research_resume",{"research_id":"R12"})
	var resumed: bool = ctx.research.active_job(ctx.world,"R12").state=="waiting"
	var cancel: CommandResult = ctx.research.execute(ctx.world,"research_cancel",{"research_id":"R12"})
	var removed: bool = ctx.research.active_job(ctx.world,"R12").is_empty()
	var restart: CommandResult = _start(ctx,"R12",{"allow_waiting":true})
	var second: Dictionary = ctx.research.active_job(ctx.world,"R12")
	if second.is_empty(): return {"ok":false,"restart":restart.to_record()}
	var records: Dictionary = ctx.world.facts.research_jobs
	# Same-size collection replacement must return the current frozen record,
	# even though values and identities intentionally remain business-equivalent.
	ctx.world.facts.research_jobs = records.duplicate(true)
	var replacement: bool = is_same(ctx.research.rewards(ctx.world,"R12"),ctx.world.facts.research_jobs[second.id].rewards) and not is_same(ctx.research.rewards(ctx.world,"R12"),second.rewards)
	var source: Dictionary = ctx.world.facts.research_jobs
	source[second.id] = source[second.id].duplicate(true)
	ctx.world.fact_record_changed("research_jobs",second.id)
	var in_place: bool = is_same(ctx.research.rewards(ctx.world,"R12"),source[second.id].rewards)
	var restored: WorldState = WorldState.new(ctx.world.freeze())
	var restored_current: bool = is_same(ctx.research.rewards(restored,"R12"),restored.facts.research_jobs[second.id].rewards)
	# Emptying a collection is a standalone index lifecycle boundary. No job is
	# run or completed in this copy; the actual paid source remains untouched.
	var observer: RefCounted = Jobs.new()
	observer.view(restored)
	restored.facts.research_jobs.clear()
	var empty: bool = observer.view(restored).groups.is_empty()
	var actual_validation: String = ctx.world.validate(_content)
	return {"ok":current and pause.accepted and paused and resume.accepted and resumed and cancel.accepted and removed and restart.accepted and second.id!=first.id and replacement and in_place and restored_current and empty and actual_validation.is_empty(),"actual_query_calls":calls,"readonly":query_readonly,"real_pause_resume_cancel_restart":pause.accepted and paused and resume.accepted and resumed and cancel.accepted and removed and restart.accepted,"same_size_collection_replacement":replacement,"owner_notified_same_id_replacement":in_place,"restored_world_current_rewards":restored_current,"empty_collection_rebuilt":empty,"source_validation":actual_validation}
