extends RefCounted

const SCENARIOS: Array=["comprehensive160-clinical-family-v3","mixed160-clinical-ops-v1"]
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
var _geometry: HospitalSpace
var _initial_visits: Dictionary={}
var _completed_exams: Dictionary={}
var _saved_rolls: Dictionary={}
var _error_counts: Dictionary={}
var _scenario: String="comprehensive160-clinical-family-v3"

func _init(content: HospitalContent, scenario: String = "comprehensive160-clinical-family-v3") -> void:
	assert(scenario in SCENARIOS,"Unsupported comprehensive scenario")
	_scenario=scenario
	_geometry=HospitalSpace.new(content)

func capture(world: WorldState) -> Dictionary:
	var state: Dictionary={"tick":world.sim_tick,"progress":{},"actors":{},"attempts":{},"ledger":{},"staff_recovery":{},"visits":{},"wards":{},"families":{},"inventory_units":int(world.facts.inventory.units),"supply_orders":world.facts.inventory.get("orders",{}).keys()}
	for id: String in world.facts.actors:
		var actor: Dictionary=world.facts.actors[id]
		var location: Dictionary=actor.location
		state.actors[id]=[location.get("kind",""),int(location.get("floor_id",0)),location.get("cell",[]).duplicate(),str(location.get("connector_id",""))]
	for id: String in world.facts.attempts:
		var attempt: Dictionary=world.facts.attempts[id]
		var frozen: Dictionary={}
		for key: String in ["visit_id","plan_id","result","start_tick","probability_bp","work_ticks","recovery_ticks","supply_units","cure_fee","facility_fee","staff_ids","effective_level","bed_id","nurse_id","ward_fee"]:
			if attempt.has(key): frozen[key]=attempt[key].duplicate(true) if attempt[key] is Array or attempt[key] is Dictionary else attempt[key]
		state.attempts[id]=frozen
	for id: String in world.facts.ledger.entries: state.ledger[id]=true
	for id: String in world.facts.visits:
		var visit: Dictionary=world.facts.visits[id]
		state.visits[id]={"phase":visit.phase,"result":visit.get("final_result",""),"attempt_ids":visit.attempt_ids.duplicate(),"diagnosis":visit.get("diagnosis",{}).duplicate(true),"old_score_present":visit.has("evidence_by_source")}
		if not _initial_visits.has(id): _initial_visits[id]=state.visits[id].duplicate(true)
	for id: String in world.facts.sessions:
		var row: Dictionary=world.facts.sessions[id]
		_progress(state,"session:"+id,str(row.kind),int(row.remaining_ticks),int(row.total_ticks))
	for id: String in world.facts.get("floor_guidance",{}).get("visits",{}):
		var row: Dictionary=world.facts.floor_guidance.visits[id]
		if row.get("phase","")=="working": _progress(state,"guidance:"+id,"guidance",int(row.get("remaining_ticks",0)),60)
	for id: String in world.facts.ward_stays:
		var row: Dictionary=world.facts.ward_stays[id]
		state.wards[id]={"visit_id":row.visit_id,"bed_id":row.bed_id,"bed_owner_id":world.facts.adaptations.get(str(row.bed_id),{}).get("owner_id",""),"phase":row.phase,"attempt_id":row.attempt_id,"remaining_ticks":int(row.remaining_ticks),"care_completed":row.care_completed,"admitted_tick":int(row.get("admitted_tick",-1)),"transfer_from_bed_id":row.get("transfer_from_bed_id",""),"companion_evaluated":row.get("companion_evaluated",false),"companion_qualified":row.get("companion_qualified",false),"companion_actor_id":row.get("companion_actor_id",""),"visitor_day":int(row.get("visitor_day",-1)),"visitor_intent":row.get("visitor_intent",false),"patient_in_ward":_inside(world,world.facts.visits[row.visit_id].actor_id,row),"medical":_medical(world,row)}
		if row.get("phase","")=="recovery": _progress(state,"ward:"+id,"recovery",int(row.remaining_ticks),int(row.remaining_ticks))
	for id: String in world.facts.get("visitors",{}).get("stays",{}):
		var family: Dictionary=world.facts.visitors.stays[id]
		var ward: Dictionary={}
		for candidate: Dictionary in world.facts.ward_stays.values():
			if candidate.get("visit_id","")==family.visit_id: ward=candidate;break
		state.families[id]={"actor_id":family.actor_id,"visit_id":family.visit_id,"purpose":family.purpose,"phase":family.phase,"remaining_ticks":int(family.remaining_ticks),"life_phase":family.get("life_task",{}).get("phase",""),"return_ward_first":family.get("return_ward_first",false),"destination":family.get("destination",{}).duplicate(true),"own_family_move":world.facts.moves.get(str(family.actor_id),{}).get("visitor_stay_id","")==id,"inside_ward":not ward.is_empty() and _inside(world,family.actor_id,ward),"overlaps_ward":not ward.is_empty() and _overlaps(world,family.actor_id,ward),"patient_in_ward":not ward.is_empty() and _inside(world,world.facts.visits[family.visit_id].actor_id,ward),"medical":not ward.is_empty() and _medical(world,ward),"ward_phase":ward.get("phase",""),"yielding":family.get("yielding",false)}
		if family.purpose=="ward_visit": _progress(state,"visitor:"+id,"effective_ward_visit",int(family.remaining_ticks),int(family.remaining_ticks))
		var life: Dictionary=family.get("life_task",{})
		if life.get("phase","") in ["using","fallback"]: _progress(state,"family_life:"+id,"companion_life",int(life.get("remaining_ticks",0)),int(life.get("remaining_ticks",0)))
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

func _inside(world: WorldState, actor_id: String, ward: Dictionary) -> bool:
	var actor: Dictionary=world.facts.actors.get(actor_id,{})
	var bed: Dictionary=world.facts.facilities.get(str(ward.get("bed_id","")),{})
	if actor.is_empty() or bed.is_empty() or actor.location.kind!="floor" or int(actor.location.floor_id)!=int(bed.floor_id): return false
	var room: Dictionary=world.facts.rooms.get(str(bed.get("room_id","")),{})
	return not room.is_empty() and _geometry.room_contains(room,_geometry.body_rectangle(actor))

func _overlaps(world: WorldState, actor_id: String, ward: Dictionary) -> bool:
	var actor: Dictionary=world.facts.actors.get(actor_id,{})
	var bed: Dictionary=world.facts.facilities.get(str(ward.get("bed_id","")),{})
	if actor.is_empty() or bed.is_empty() or actor.location.kind!="floor" or int(actor.location.floor_id)!=int(bed.floor_id): return false
	var room: Dictionary=world.facts.rooms.get(str(bed.get("room_id","")),{})
	return not room.is_empty() and BuildGeometry.intersects_room(_geometry.body_rectangle(actor),room)

func _medical(world: WorldState, ward: Dictionary) -> bool:
	var bed: Dictionary=world.facts.facilities[ward.bed_id]
	for session: Dictionary in world.facts.sessions.values():
		var facility: Dictionary=world.facts.facilities[session.facility_id]
		if session.visit_id==ward.visit_id and session.kind in ["care","outpatient"] and int(facility.floor_id)==int(bed.floor_id) and facility.get("room_id","")==bed.get("room_id",""): return true
	for family: Dictionary in world.facts.get("visitors",{}).get("stays",{}).values():
		var requested: int=int(family.get("yield_requested_tick",-2))
		if family.visit_id==ward.visit_id and family.get("yielding",false) and requested>=world.sim_tick-1 and requested<=world.sim_tick: return true
	return false

func _terminal_visit(world: WorldState, visit_id: String) -> bool:
	return world.facts.visits.get(visit_id,{}).get("phase","") in ["leaving","departed","ward_referral"]

func _terminal_companion_retired(world: WorldState, ward: Dictionary, actor_id: String) -> bool:
	if not _terminal_visit(world,str(ward.visit_id)) or world.facts.actors.has(actor_id): return false
	for family: Dictionary in world.facts.get("visitors",{}).get("stays",{}).values():
		if family.actor_id==actor_id or family.visit_id==ward.visit_id and family.purpose=="companion": return false
	return true

func _terminal_family(world: WorldState, family: Dictionary) -> bool:
	if _terminal_visit(world,str(family.visit_id)): return true
	for ward: Dictionary in world.facts.ward_stays.values():
		if ward.visit_id==family.visit_id: return false
	return true

func _observe_ward_visit_progress(old: Dictionary, family: Dictionary, world: WorldState, bucket: Dictionary, id: String) -> void:
	var remaining: int=int(family.remaining_ticks)
	var delta: int=int(old.remaining_ticks)-remaining
	if delta<=0: return
	var terminal: bool=_terminal_family(world,family)
	# Dispatch cancels a terminal visit by setting zero before visitor work.
	# Even 1 -> 0 is cancellation here, not the final effective visit tick.
	if terminal and remaining==0 and family.phase in ["leaving","outside"] and not family.return_ward_first: return
	var phase_allows: bool=not old.phase in ["outside","leaving"] and family.phase!="outside" and (family.phase!="leaving" or remaining==0)
	var effective: bool=not terminal and delta==1 and remaining>=0 and phase_allows and str(family.life_phase).is_empty() and family.inside_ward and family.patient_in_ward and not family.medical and not family.yielding and not family.ward_phase in ["to_surgery","reserved","transfer","return_preop"]
	if not effective:
		_error("Effective visit time advanced outside its legal ward interval for "+id)
		return
	_work(bucket,"effective_ward_visit",1)

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
	_observe_clinical(before,after,world,bucket)
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
		# Ward-visit progress has an unworked terminal reset; its owner-specific
		# transition above is the only source of effective visit work.
		if now.kind=="effective_ward_visit": continue
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
		if event.kind=="service_completed" and str(event.details.get("kind","")) in ["spectrum","resonance"]:
			var visit_id: String=str(event.changed_ids[0])
			_completed_exams[visit_id]=int(_completed_exams.get(visit_id,0))+1
			var historical: bool=bool(_initial_visits.get(visit_id,{}).get("diagnosis",{}).get("exam_completed",false))
			if int(_completed_exams[visit_id])+(1 if historical else 0)>1: _error("More than one completed examination for "+visit_id)
		if event.kind in ["command_applied","command_rejected"] and str(event.details.get("command_id","")).begins_with("comprehensive160-v3-"):
			bucket.commands[event.details.command_id]={"kind":event.kind,"tick":event.sim_tick,"details":event.details.duplicate(true)}
			if event.kind=="command_rejected": _error("Measured command rejected: "+str(event.details.command_id)+" "+str(event.details.get("result",{})))
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

func _work(bucket: Dictionary, key: String, amount: int = 1) -> void:
	bucket.work[key]=int(bucket.work.get(key,0))+amount

func _error(message: String) -> void:
	_error_counts[message]=int(_error_counts.get(message,0))+1
	if not message in errors: errors.append(message)

func _observe_clinical(before: Dictionary, after: Dictionary, world: WorldState, bucket: Dictionary) -> void:
	for id: String in after.visits:
		var visit: Dictionary=after.visits[id]
		if visit.old_score_present: _error("Retired score fact remains on "+id)
		if visit.attempt_ids.size()>2: _error("More than two actual attempts for "+id)
		var previous: Dictionary=before.visits.get(id,{})
		if not previous.is_empty() and previous.phase!=visit.phase:
			if visit.phase=="departed": _work(bucket,"departed:"+str(visit.result))
	for id: String in after.wards:
		var ward: Dictionary=after.wards[id]
		var old: Dictionary=before.wards.get(id,{})
		if not ward.phase in ["release_wait","referral_release"] and str(ward.bed_owner_id)!=id: _error("Active ward bed has lost its stay owner for "+id)
		if str(ward.attempt_id).is_empty() and (int(ward.remaining_ticks)!=0 or ward.care_completed): _error("Future recovery/care supplied before first actual attempt on "+id)
		if not old.is_empty():
			if int(old.admitted_tick)<0 and int(ward.admitted_tick)>=0: _work(bucket,"actual_ward_admission")
			if old.bed_id!=ward.bed_id and ward.transfer_from_bed_id!=old.bed_id: _error("Reserved ward bed changed without an actual transfer for "+id)
			if old.companion_evaluated and (not ward.companion_evaluated or old.companion_qualified!=ward.companion_qualified): _error("Companion qualification changed during stay "+id)
			if not str(old.companion_actor_id).is_empty() and old.companion_actor_id!=ward.companion_actor_id:
				if not str(ward.companion_actor_id).is_empty() or not _terminal_companion_retired(world,ward,str(old.companion_actor_id)): _error("Fixed companion identity changed during stay "+id)
			if old.phase=="transfer" and ward.phase=="recovery" and ward.patient_in_ward: _work(bucket,"actual_surgical_ward_return")
		if int(ward.visitor_day)>=0:
			var key: String=id+":"+str(ward.visitor_day)
			if _saved_rolls.has(key) and _saved_rolls[key]!=ward.visitor_intent: _error("Saved daily visit outcome changed for "+key)
			_saved_rolls[key]=ward.visitor_intent
	for id: String in after.attempts:
		if before.attempts.has(id):
			if before.attempts[id]!=after.attempts[id]: _error("Frozen actual Attempt promise changed for "+id)
			continue
		var attempt: Dictionary=world.facts.attempts[id]
		var protocol: Dictionary=_geometry.content.definition("treatment_protocols",_geometry.content.definition("treatment_plans",attempt.plan_id).protocol_id)
		if protocol.kind=="surgery":
			var ward: Dictionary={}
			for candidate: Dictionary in after.wards.values():
				if candidate.visit_id==attempt.visit_id: ward=candidate;break
			if ward.is_empty() or int(ward.admitted_tick)<0 or int(ward.admitted_tick)>int(attempt.start_tick): _error("Surgery started without actual prior ward admission for "+id)
			if int(attempt.start_tick)%WorldState.TICKS_PER_DAY>=12000: _error("New surgery began at night for "+id)
		elif int(attempt.recovery_ticks)!=0: _error("Ordinary/palliative attempt supplied compulsory ward recovery for "+id)
	for id: String in after.families:
		var family: Dictionary=after.families[id]
		var old: Dictionary=before.families.get(id,{})
		if old.is_empty(): continue
		var actor_id: String=str(family.actor_id)
		if family.purpose=="ward_visit" and not str(family.life_phase).is_empty(): _error("Short ward visitor acquired a life task for "+id)
		if family.inside_ward and not old.inside_ward: _work(bucket,"family_ward_entry:"+str(family.purpose))
		if old.overlaps_ward and not family.overlaps_ward: _work(bucket,"family_ward_exit:"+str(family.purpose))
		if before.actors.get(actor_id,[])!=after.actors.get(actor_id,[]): _work(bucket,"family_movement:"+str(family.purpose))
		if family.purpose=="ward_visit": _observe_ward_visit_progress(old,family,world,bucket,id)
		if old.return_ward_first and not family.return_ward_first and not family.inside_ward and not _terminal_visit(world,str(family.visit_id)): _error("Companion skipped real ward return after life service for "+id)
		if old.return_ward_first and family.return_ward_first and str(family.life_phase).is_empty() and family.own_family_move and family.destination.get("kind","")=="surgery_outside": _error("Companion selected OR before its required post-life ward return for "+id)
		if family.destination.get("kind","")=="surgery_outside" and not family.inside_ward and before.actors.get(actor_id,[])==after.actors.get(actor_id,[]) and family.phase=="waiting": _work(bucket,"family_surgery_wait:"+str(family.purpose))
		for session: Dictionary in world.facts.sessions.values():
			if session.visit_id==family.visit_id and session.kind=="care" and family.overlaps_ward: _error("Bedside care began before a relative completely left the ward for "+id)

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
	var schedule_command: Dictionary=sample.commands.get("comprehensive160-v3-schedule",{})
	_check(coverage,"schedule",1 if schedule_command.get("kind","")=="command_applied" else 0,1,"applied production command")
	_check(coverage,"purchase",int(sample.ledger.get("supply_purchase",{}).get("count",0)),1,"new paid supply receipt")
	_check(coverage,"clinical_consumption",int(sample.consumed_units),1,"new Attempt committed supply units")
	_check(coverage,"actual_movement",int(sample.moving_actors),1,"observed real position changes")
	_check(coverage,"original_doctor_review",int(work.get("consult",0)),1,"actual free review ticks")
	_check(coverage,"actual_surgical_ward_return",int(work.get("actual_surgical_ward_return",0)),1,"actual transfer-to-recovery handoffs in the reserved ward")
	_check(coverage,"companion_ward_entry",int(work.get("family_ward_entry:companion",0)),1,"actual complete-body ward entries")
	_check(coverage,"effective_ward_visit",int(work.get("effective_ward_visit",0)),1,"effective ticks while visitor and patient are actually in the ward")
	for kind: String in ["gp","consult","outpatient","surgery","wake","care"]:
		_check(coverage,"completed_"+kind,int(sample.events.get("service_completed:"+kind,0)),1,"actual completed service events")
	_check(coverage,"completed_examination",int(sample.events.get("service_completed:spectrum",0))+int(sample.events.get("service_completed:resonance",0)),1,"one actual examination completed per participating Visit")
	_check(coverage,"completed_treatment_outcome",int(work.get("departed:cured",0))+int(work.get("departed:referred",0)),1,"actual final patient departures with settled clinical outcome")
	var missing: Array=[]
	for key: String in coverage:
		if not coverage[key].covered: missing.append(key)
	var facts_error: String=world.validate(HospitalContent.new())
	var output_errors: Array=errors.duplicate()
	if not facts_error.is_empty(): output_errors.append(facts_error)
	for key: String in missing: output_errors.append("No measured activity: "+key)
	return {"schema":3,"scenario":_scenario,"coverage_pass":output_errors.is_empty() and int(sample.steps)>0,"coverage":coverage,"errors":output_errors,"invariant_failure_counts":_error_counts.duplicate(),"uncovered":missing,"prefix":prefix.duplicate(true),"sample":sample.duplicate(true),"sample_first_tick":_sample_first_tick,"sample_last_tick":_sample_last_tick,"initial_core_ids":_initial_core.keys(),"initial_visit_boundaries":_initial_visits,"completed_examinations":_completed_exams,"present_min":_minimum_population,"present_max":_maximum_population,"natural_additional_actors":_external_ids,"scope":"Only sample deltas establish coverage. Historical input and prefix are separate. Measured entries, effective visit progress, original-doctor review, real ward return, completed examinations, actual attempts, outcomes and fees are recorded; work progress alone is not a cured or complete-job claim.","not_covered_by_this_scenario":["UI/rendering","save persistence","quarterly/full-day cycles","every possible clinical plan","all clinical/family acceptance boundaries"]}

func _check(coverage: Dictionary, key: String, actual: int, lower_bound: int, unit: String) -> void:
	coverage[key]={"covered":actual>=lower_bound,"actual":actual,"lower_bound":lower_bound,"unit":unit}
