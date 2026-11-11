extends "res://tests/acceptance/growth_fixtures.gd"

func run_case(t, database: HospitalContent) -> void:
	_content = database
	var protection: Dictionary = protection_case()
	for simulation: HospitalSimulation in _simulations: simulation.dispose()
	_simulations.clear()
	# Operational-department routing no longer exists. The current real-room
	# guidance contract is covered by GUIDE-01 through GUIDE-09.
	t.check("GROW-83",protection.passed,{"protection":protection})

func protection_case() -> Dictionary:
	var ctx: Dictionary = _context()
	var first: Dictionary = _resident(ctx,[46,93])
	var second: Dictionary = _resident(ctx,[44,93])
	if first.is_empty() or second.is_empty(): return {"passed":false,"errors":_fixture_errors}
	# Reference protection is a read-only query: these are legal reference
	# records at their active/terminal boundary, not simulated activity progress.
	ctx.world.facts.activities = {"active":{"state":"active","resident_ids":[first.resident.id,first.resident.id],"resident_id":first.resident.id},"ended":{"state":"ended","resident_ids":[second.resident.id]}}
	ctx.world.facts.community_activities = {"listed":{"phase":"recruiting","participants":[second.resident.id]}}
	ctx.world.facts.interactions = {"closed":{"state":"completed","resident_id":first.resident.id}}
	ctx.world.facts.visitor_stays = {"visiting":{"phase":"visiting","resident_id":first.resident.id}}
	ctx.world.facts.care_jobs = {"help":{"phase":"working","participants":[first.resident.id,second.resident.id]}}
	first.resident.story_binding = "protected_story"
	var before: Dictionary = ctx.world.freeze()
	var index: Dictionary = ctx.arrivals._resident_protection(ctx.world)
	var exact: bool = true
	for resident: Dictionary in [first.resident,second.resident]:
		for ignore_story: bool in [false,true]:
			exact = exact and ctx.arrivals._protected_reasons(ctx.world,resident,ignore_story)==ctx.arrivals._protected_reasons(ctx.world,resident,ignore_story,index)
	var expected: Array = ["本次实际离院后腾出位置","当前就诊尚未结束","仍关联活动、互动或照护","仍关联活动、互动或照护","仍关联活动、互动或照护","故事保留同一人物身份"]
	exact = exact and ctx.arrivals._protected_reasons(ctx.world,first.resident,false,index)==expected
	var readonly: bool = ctx.world.freeze()==before
	# A later boundary must see direct changes; no map survives the query.
	ctx.world.facts.activities.active.state = "completed"
	ctx.world.facts.visitor_stays.visiting.phase = "departed"
	ctx.world.facts.care_jobs.help.phase = "cancelled"
	ctx.world.facts.community_activities.listed.phase = "ended"
	var fresh: Dictionary = ctx.arrivals._resident_protection(ctx.world)
	var refreshed: bool = ctx.arrivals._protected_reasons(ctx.world,first.resident,true,fresh)==["本次实际离院后腾出位置","当前就诊尚未结束"] and ctx.arrivals._protected_reasons(ctx.world,first.resident,false,fresh)==ctx.arrivals._protected_reasons(ctx.world,first.resident)
	first.resident.pending_release = true
	first.resident.remembered = false
	ctx.arrivals.settle(ctx.world)
	var held: bool = ctx.world.facts.residents.has(first.resident.id)
	first.resident.story_binding = ""
	ctx.arrivals.settle(ctx.world)
	held = held and ctx.world.facts.residents.has(first.resident.id) and ctx.world.facts.residents.has(second.resident.id)
	return {"passed":exact and readonly and refreshed and held,"exact_reasons_and_multiplicity":exact,"readonly":readonly,"next_boundary_changes_visible":refreshed,"inpatient_identity_held":held}
