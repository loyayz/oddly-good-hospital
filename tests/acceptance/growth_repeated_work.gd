extends "res://tests/acceptance/growth_fixtures.gd"

const Jobs = preload("res://game/community/research_job_index.gd")

func run(t, database: HospitalContent, checkpoint_cache: RefCounted) -> void:
	_content = database
	_cache = checkpoint_cache
	var started: int = Time.get_ticks_usec()
	var index: Dictionary = _index()
	for simulation: HospitalSimulation in _simulations: simulation.dispose()
	_simulations.clear()
	t.check("GROW-85",index.ok and _fixture_errors.is_empty(),{"CL-A09":index,"fixture_errors":_fixture_errors,"elapsed_usec":Time.get_ticks_usec()-started})

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
