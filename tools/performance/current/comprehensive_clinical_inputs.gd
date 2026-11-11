extends RefCounted

# Requirement-defined saved boundaries, declared before each patient's first
# step. Historical work and money are inputs, never measured accomplishments.
const PREOP_COUNT: int=12

static func unstarted_reason(world: WorldState) -> String:
	if world.sim_tick!=0 or not world.facts.sessions.is_empty() or not world.facts.attempts.is_empty(): return "Expected an unstarted construction fixture"
	for visit: Dictionary in world.facts.visits.values():
		if visit.has("evidence_by_source") or not visit.get("diagnosis") is Dictionary or not visit.diagnosis.is_empty(): return "Expected a current, unstarted diagnosis input"
	return ""

static func prepare(pending: Dictionary, world: WorldState, content: HospitalContent) -> Dictionary:
	var rows: Array=[]
	var fresh: Array=[]
	var installed_equipment: Array=[]
	for facility: Dictionary in world.facts.facilities.values():
		if not facility.definition_id in installed_equipment: installed_equipment.append(facility.definition_id)
	for index: int in 24:
		var visit: Dictionary=pending.visits["bench_visit_%04d"%index]
		var actor: Dictionary=pending.actors[visit.actor_id]
		var original: Dictionary=content.actor_body(actor).duplicate(true)
		var kind: String="surgery" if index<PREOP_COUNT else "outpatient" if index<20 else "examination" if index<22 else "consult"
		var gentle: bool=index>=16 and index<20
		if gentle:
			var binding: Dictionary=body_compatible_binding(content,"C",actor,installed_equipment)
			if binding.is_empty(): return {"ok":false,"reason":"No full-body-compatible C palliative input","visit_id":visit.id}
			visit.binding_id=binding.id
			visit.disease_id=binding.disease_id
			actor.species_id=binding.species_id
			actor.body_binding_id=binding.id
		var floor_id: int=int(actor.location.floor_id)
		# Two saved examination results deliberately originated on another
		# floor. Their unmeasured exam is complete; actual return and review are
		# still required from the current physical public position.
		var original_floor: int=(1 if floor_id>2 else 3) if kind=="consult" else floor_id
		var doctor_id: String="bench_staff_%04d"%(original_floor-1)
		var facility_id: String="bench_room_%d_00_0"%original_floor
		var doctor: Dictionary=world.facts.staff.get(doctor_id,{})
		var facility: Dictionary=world.facts.facilities.get(facility_id,{})
		if doctor.get("role","")!="doctor" or int(doctor.get("abilities",{}).get("diagnosis",0))<1 or facility.get("definition_id","")!="FUR02": return {"ok":false,"reason":"Historical original GP has no lawful identity/qualification/table","visit_id":visit.id}
		var diagnosis: Dictionary={"state":"diagnosed","gp_completed":true,"exam_kind":"","exam_completed":false,"review_completed":false,"doctor_id":doctor_id,"facility_id":facility_id,"insufficient_bp":int(content.balance.clinical.diagnosis_insufficient_bp[int(doctor.abilities.diagnosis)]),"insufficient":false}
		if kind in ["examination","consult"]:
			diagnosis.insufficient=true
			diagnosis.state="insufficient"
		if kind=="consult":
			diagnosis.exam_kind="spectrum" if index==22 else "resonance"
			diagnosis.exam_completed=true
			diagnosis.state="review_pending"
		visit.diagnosis=diagnosis
		visit.doctor_fee_quote=content.doctor_fee(doctor.title_id)
		visit.requested_plan_id="P_"+str(visit.disease_id)+("_SURGERY" if kind=="surgery" else "_GENTLE" if gentle else "_COMMON")
		if not kind in ["examination","consult"]:
			var plan: Dictionary=content.definition("treatment_plans",visit.requested_plan_id)
			if plan.get("disease_id","")!=visit.disease_id: return {"ok":false,"reason":"Historical plan is not a catalog plan for this disease","visit_id":visit.id}
			for research_id: String in plan.requires_research:
				if not research_id in world.facts.research: return {"ok":false,"reason":"Historical plan research is unavailable","research_id":research_id}
			visit.plan_decision={"plan_id":plan.id,"source":"director","doctor_id":doctor_id,"revision":1,"reason":"Saved diagnosis and lawful plan before unstarted admission/treatment"}
		var receipts: Array=[{"component":"consultation","amount":int(visit.doctor_fee_quote)},{"component":"gp","amount":content.facility_fee("FUR02","gp")}]
		if diagnosis.exam_completed: receipts.append({"component":diagnosis.exam_kind,"amount":content.facility_fee("FUR02",diagnosis.exam_kind)})
		rows.append({"visit_id":visit.id,"actor_id":actor.id,"binding_id":visit.binding_id,"disease_id":visit.disease_id,"profile":content.definition("diseases",visit.disease_id).profile,"next_service":kind,"diagnosis":diagnosis.duplicate(true),"receipts":receipts,"original_body_dimensions":original,"body_dimensions":content.actor_body(actor),"scope":"Saved legal business input from unified specification §§14–18. Completed GP/exam/result/receipts are historical input; admission, original-doctor review, treatment, return and all later progress execute in production. No fresh GP result is supplied."})
		if content.actor_body(actor)!=original: return {"ok":false,"reason":"Clinical cohort altered a complete body","visit_id":visit.id}
	var binding: Dictionary=content.definition("treatment_bindings","B_S13_D53_M51")
	if binding.get("species_id","")!="S13" or content.definition("diseases",str(binding.get("disease_id",""))).get("profile","")!="B" or content.definition("treatment_routines",str(binding.get("routine_id",""))).get("equipment_id","")!="M37": return {"ok":false,"reason":"The fixed fresh B case differs from current catalog"}
	for index: int in range(24,44):
		var visit: Dictionary=pending.visits["bench_visit_%04d"%index]
		var actor: Dictionary=pending.actors[visit.actor_id]
		var original: Dictionary=content.actor_body(actor).duplicate(true)
		if not visit.diagnosis.is_empty() or not visit.attempt_ids.is_empty() or not visit.plan_decision.is_empty(): return {"ok":false,"reason":"Fresh GP cohort already has a clinical result","visit_id":visit.id}
		visit.binding_id=binding.id
		visit.disease_id=binding.disease_id
		visit.requested_plan_id="P_"+str(binding.disease_id)+"_COMMON"
		actor.body_binding_id=binding.id
		if content.actor_body(actor)!=original: return {"ok":false,"reason":"Fresh case changes its complete original S13 body","visit_id":visit.id}
		fresh.append({"visit_id":visit.id,"actor_id":actor.id,"binding_id":binding.id,"next_service":"gp","original_body_dimensions":original,"body_dimensions":content.actor_body(actor),"diagnosis":{},"scope":"Unstarted GP input. The production GP start owns its one probability draw and no result/fee is supplied."})
	return {"ok":true,"historical":rows,"fresh":fresh,"preop_count":PREOP_COUNT}

static func body_compatible_binding(content: HospitalContent, profile: String, original: Dictionary, installed_equipment: Array) -> Dictionary:
	var dimensions: Dictionary=content.actor_body(original)
	for same_species: bool in [true,false]:
		for binding: Dictionary in content.catalog.treatment_bindings:
			if (binding.species_id==original.species_id)!=same_species or content.definition("diseases",binding.disease_id).profile!=profile: continue
			if not content.definition("treatment_routines",str(binding.routine_id)).get("equipment_id","") in installed_equipment: continue
			if content.actor_body({"species_id":binding.species_id,"body_binding_id":binding.id})==dimensions: return binding
	return {}

static func add_fresh(pending: Dictionary, content: HospitalContent) -> Dictionary:
	var ids: Array=[]
	var original: Dictionary=pending.visits["bench_visit_0104"]
	for ordinal: int in 8:
		var index: int=120+ordinal
		var visit_id: String="bench_visit_%04d"%index
		var actor_id: String="bench_patient_%04d"%index
		if pending.visits.has(visit_id) or pending.actors.has(actor_id): return {"ok":false,"reason":"Additional declared identity already exists"}
		var visit: Dictionary=original.duplicate(true)
		var actor: Dictionary=pending.actors[original.actor_id].duplicate(true)
		visit.id=visit_id
		visit.actor_id=actor_id
		visit.arrival_key=visit_id
		actor.id=actor_id
		actor.name="患者%04d"%index
		pending.visits[visit_id]=visit
		pending.actors[actor_id]=actor
		pending.receipts[visit_id]=visit_id
		ids.append({"visit_id":visit_id,"actor_id":actor_id,"body_dimensions":content.actor_body(actor),"scope":"One of eight fixed additional full-body fresh patients, declared with all original 120 patients before any patient step. Family and other natural actors later join through unchanged production rules, without replacing or removing any actor or request."})
	return {"ok":true,"records":ids}
