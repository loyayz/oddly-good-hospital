extends RefCounted

# Observation is outside Simulation.step. A populated room, an enqueued order,
# a route intention or a historical input receipt never establishes coverage.
var prefix: Dictionary={"steps":0,"work":{},"events":{},"commands":{},"ledger":{},"moving_actors":0,"floor_transitions":0,"new_attempts":0,"consumed_units":0,"purchased_units":0,"inventory_delta":0}
var sample: Dictionary={"steps":0,"work":{},"events":{},"commands":{},"ledger":{},"moving_actors":0,"floor_transitions":0,"new_attempts":0,"consumed_units":0,"purchased_units":0,"inventory_delta":0}
var errors: Array[String]=[]
var _initial_core: Dictionary={}
var _maximum_population: int=0
var _minimum_population: int=2147483647
var _sample_first_tick: int=-1
var _sample_last_tick: int=-1
var _external_ids: Dictionary={}
var _last_floor: Dictionary={}

func capture(world: WorldState) -> Dictionary:
	var state: Dictionary={"tick":world.sim_tick,"progress":{},"actors":{},"attempts":{},"ledger":{},"staff_recovery":{},"inventory_units":int(world.facts.inventory.units),"supply_orders":world.facts.inventory.get("orders",{}).keys()}
	for id: String in world.facts.actors:
		var actor: Dictionary=world.facts.actors[id]
		var location: Dictionary=actor.location
		state.actors[id]=[location.get("kind",""),int(location.get("floor_id",0)),location.get("cell",[]).duplicate(),str(location.get("connector_id",""))]
	for id: String in world.facts.attempts: state.attempts[id]=true
	for id: String in world.facts.ledger.entries: state.ledger[id]=true
	for id: String in world.facts.sessions:
		var row: Dictionary=world.facts.sessions[id]
		_progress(state,"session:"+id,str(row.kind),int(row.remaining_ticks),int(row.total_ticks))
	for id: String in world.facts.get("floor_guidance",{}).get("visits",{}):
		var row: Dictionary=world.facts.floor_guidance.visits[id]
		if row.get("phase","")=="working": _progress(state,"guidance:"+id,"guidance",int(row.get("remaining_ticks",0)),60)
	for id: String in world.facts.ward_stays:
		var row: Dictionary=world.facts.ward_stays[id]
		if row.get("phase","")=="recovery": _progress(state,"ward:"+id,"recovery",int(row.remaining_ticks),int(row.remaining_ticks))
	for collection: String in ["research_jobs","training_jobs"]:
		for id: String in world.facts.get(collection,{}):
			var row: Dictionary=world.facts[collection][id]
			_progress(state,collection+":"+id,"research" if collection=="research_jobs" else "training",int(row.get("remaining_work_milli",0)),int(row.get("total_work_milli",0)))
	for collection: String in ["jobs","upgrades"]:
		for id: String in world.facts.get("maintenance",{}).get(collection,{}):
			var row: Dictionary=world.facts.maintenance[collection][id]
			_progress(state,"maintenance:"+id,"maintenance" if collection=="jobs" else "upgrade",int(row.get("remaining_milli",0)),int(row.get("total_milli",row.get("remaining_milli",0))))
	for id: String in world.facts.get("environment",{}).get("dirt",{}):
		var row: Dictionary=world.facts.environment.dirt[id]
		_progress(state,"dirt:"+id,"cleaning",int(row.get("remaining_milli",0)),int(row.get("total_milli",0)))
	for id: String in world.facts.get("environment",{}).get("orders",{}):
		for row: Dictionary in world.facts.environment.orders[id].get("units",[]):
			_progress(state,"surface:"+str(row.id),"renovation",int(row.get("remaining_milli",0)),int(row.get("total_milli",0)))
	for id: String in world.facts.staff:
		var staff: Dictionary=world.facts.staff[id]
		var task: Dictionary=staff.get("life_task",{})
		var phase: String=str(task.get("phase",""))
		if phase in ["using","visiting"]:
			_progress(state,"life:"+id+":"+str(task.get("id","")),"staff_life",int(task.get("remaining_ticks",0)),int(task.get("remaining_ticks",0)))
		if phase=="sleep": _progress(state,"sleep:"+id,"staff_life",int(staff.get("sleep_remaining_ticks",0)),int(staff.get("sleep_remaining_ticks",0)))
		if phase in ["rest","recreation"]: state.staff_recovery[id]={"phase":phase,"energy":float(staff.energy),"fatigue":float(staff.get("fatigue",0))}
		var base: Dictionary=staff.get("base_task",{})
		if base.get("phase","")=="working": _progress(state,"base:"+id,"nurse_handoff",int(base.get("remaining_ticks",0)),60)
	for id: String in world.facts.connectors:
		var connector: Dictionary=world.facts.connectors[id]
		if connector.get("phase","") in ["boarding","riding","alighting"]:
			_progress(state,"lift:"+id,"transport",int(connector.get("remaining_ticks",0)),int(connector.get("remaining_ticks",0)))
	return state

func _progress(state: Dictionary, id: String, kind: String, remaining: int, total: int) -> void:
	state.progress[id]={"kind":kind,"remaining":remaining,"total":total}

func observe(before: Dictionary, world: WorldState, result: TickResult, measured: bool) -> void:
	var bucket: Dictionary=sample if measured else prefix
	bucket.steps+=1
	if measured:
		if _sample_first_tick<0: _sample_first_tick=world.sim_tick
		_sample_last_tick=world.sim_tick
	if _initial_core.is_empty():
		for id: String in before.actors:
			if id.begins_with("bench_patient_") or world.facts.staff.has(id): _initial_core[id]=true
		for stay: Dictionary in world.facts.get("visitors",{}).get("stays",{}).values():
			if before.actors.has(stay.actor_id): _initial_core[stay.actor_id]=true
	var after: Dictionary=capture(world)
	bucket.inventory_delta+=int(after.inventory_units)-int(before.inventory_units)
	for id: String in world.facts.inventory.get("orders",{}):
		if not id in before.supply_orders: bucket.purchased_units+=int(world.facts.inventory.orders[id].units)
	for id: String in after.staff_recovery:
		var now: Dictionary=after.staff_recovery[id]
		var old: Dictionary=before.staff_recovery.get(id,{})
		if not old.is_empty() and old.phase==now.phase and (float(now.energy)>float(old.energy) or float(now.fatigue)<float(old.fatigue)):
			bucket.work.staff_life=int(bucket.work.get("staff_life",0))+1
	for id: String in after.progress:
		var now: Dictionary=after.progress[id]
		var old: Dictionary=before.progress.get(id,{})
		var amount: int=maxi(0,int(old.remaining)-int(now.remaining)) if not old.is_empty() and old.kind==now.kind else maxi(0,int(now.total)-int(now.remaining))
		if amount>0: bucket.work[now.kind]=int(bucket.work.get(now.kind,0))+amount
	for id: String in before.actors:
		if not after.actors.has(id): continue
		if not _last_floor.has(id) and before.actors[id][0]=="floor": _last_floor[id]=int(before.actors[id][1])
		if before.actors[id]!=after.actors[id]:
			bucket.moving_actors+=1
		if after.actors[id][0]=="floor":
			if _last_floor.has(id) and int(_last_floor[id])!=int(after.actors[id][1]): bucket.floor_transitions+=1
			_last_floor[id]=int(after.actors[id][1])
	for id: String in world.facts.attempts:
		if not before.attempts.has(id):
			bucket.new_attempts+=1
			bucket.consumed_units+=int(world.facts.attempts[id].get("supply_units",0))
	for id: String in world.facts.ledger.entries:
		if before.ledger.has(id): continue
		var entry: Dictionary=world.facts.ledger.entries[id]
		var component: String=str(entry.get("component",""))
		var values: Dictionary=bucket.ledger.get_or_add(component,{"count":0,"amount":0})
		values.count+=1;values.amount+=int(entry.amount)
	for event: SimEvent in result.facts:
		var key: String=event.kind
		if key in ["service_started","service_completed"]: key+=":"+str(event.details.get("kind",""))
		bucket.events[key]=int(bucket.events.get(key,0))+1
		if event.kind in ["command_applied","command_rejected"] and str(event.details.get("command_id","")).begins_with("comprehensive160-v1-"):
			bucket.commands[event.details.command_id]={"kind":event.kind,"tick":event.sim_tick,"details":event.details.duplicate(true)}
			if event.kind=="command_rejected": errors.append("Measured command rejected: "+str(event.details.command_id)+" "+str(event.details.get("result",{})))
	var population: int=world.present_actor_count()
	if measured:
		_maximum_population=maxi(_maximum_population,population);_minimum_population=mini(_minimum_population,population)
	var owners: Dictionary={}
	for visit: Dictionary in world.facts.visits.values(): owners[visit.actor_id]={"kind":"patient","visit_id":visit.id}
	for stay: Dictionary in world.facts.get("visitors",{}).get("stays",{}).values(): owners[stay.actor_id]={"kind":"visitor","stay_id":stay.id,"visit_id":stay.visit_id}
	for id: String in world.facts.actors:
		if _initial_core.has(id): continue
		var actor: Dictionary=world.facts.actors[id]
		var owner: Dictionary=owners.get(id,{"kind":"staff" if world.facts.staff.has(id) else "contractor" if world.facts.get("maintenance",{}).get("contractors",{}).has(id) else "other"})
		_external_ids[id]={"present":actor.location.kind!="outside","owner":owner}

func report(world: WorldState) -> Dictionary:
	var coverage: Dictionary={}
	var work: Dictionary=sample.work
	_check(coverage,"gp",int(work.get("gp",0)),1,"actual clinical ticks")
	_check(coverage,"examination",int(work.get("spectrum",0))+int(work.get("resonance",0)),1,"actual clinical ticks")
	_check(coverage,"outpatient_treatment",int(work.get("outpatient",0)),1,"actual clinical ticks")
	_check(coverage,"surgery",int(work.get("surgery",0)),1,"actual clinical ticks")
	_check(coverage,"bedside_care",int(work.get("care",0)),1,"actual clinical ticks")
	_check(coverage,"ward_recovery",int(work.get("recovery",0)),1,"actual recovery ticks")
	_check(coverage,"guidance",int(work.get("guidance",0)),1,"actual nurse ticks")
	_check(coverage,"floor_transport",int(work.get("transport",0)),1,"actual connector ticks")
	_check(coverage,"staff_life",int(work.get("staff_life",0)),1,"actual shared-facility or sleep ticks")
	_check(coverage,"research",int(work.get("research",0)),1,"actual work milli-ticks")
	_check(coverage,"training",int(work.get("training",0)),1,"actual work milli-ticks")
	_check(coverage,"cleaning",int(work.get("cleaning",0)),1,"actual work milliseconds")
	_check(coverage,"renovation",int(work.get("renovation",0)),1,"actual work milliseconds")
	_check(coverage,"maintenance",int(work.get("maintenance",0)),1,"actual work milliseconds")
	_check(coverage,"upgrade",int(work.get("upgrade",0)),1,"actual work milliseconds")
	var schedule_command: Dictionary=sample.commands.get("comprehensive160-v1-schedule",{})
	_check(coverage,"schedule",1 if schedule_command.get("kind","")=="command_applied" else 0,1,"applied production command")
	_check(coverage,"purchase",int(sample.ledger.get("supply_purchase",{}).get("count",0)),1,"new paid supply receipt")
	_check(coverage,"clinical_consumption",int(sample.consumed_units),1,"new Attempt committed supply units")
	_check(coverage,"actual_movement",int(sample.moving_actors),1,"observed real position changes")
	var missing: Array=[]
	for key: String in coverage:
		if not coverage[key].covered: missing.append(key)
	var facts_error: String=world.validate(HospitalContent.new())
	var output_errors: Array=errors.duplicate()
	if not facts_error.is_empty(): output_errors.append(facts_error)
	for key: String in missing: output_errors.append("No measured activity: "+key)
	return {"schema":1,"scenario":"comprehensive160-v1","coverage_pass":output_errors.is_empty() and int(sample.steps)>0,"coverage":coverage,"errors":output_errors,"uncovered":missing,"prefix":prefix.duplicate(true),"sample":sample.duplicate(true),"sample_first_tick":_sample_first_tick,"sample_last_tick":_sample_last_tick,"initial_core_ids":_initial_core.keys(),"present_min":_minimum_population,"present_max":_maximum_population,"natural_additional_actors":_external_ids,"scope":"Only sample deltas establish coverage. Initial history and prefix are separately reported. Work/progress does not assert complete treatment, cured outcome or full-job completion; exact events, receipts, payments and consumption remain visible.","not_covered_by_this_scenario":["UI/rendering","save persistence","quarterly/full-day cycles","every possible clinical plan"]}

func _check(coverage: Dictionary, key: String, actual: int, lower_bound: int, unit: String) -> void:
	coverage[key]={"covered":actual>=lower_bound,"actual":actual,"lower_bound":lower_bound,"unit":unit}
