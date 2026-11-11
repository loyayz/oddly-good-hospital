extends RefCounted

# A second matrix row. These are declared pre-operation histories, not replayed
# service completions, and they never alter the original v3 input or its load.
const SCENARIO: String="mixed160-clinical-ops-v1"
const SPEC: String="docs/specs/26-11/2026-11-11-clinical-flow-and-inpatient-family.md §§14–18"

static func declare(pending: Dictionary, world: WorldState, content: HospitalContent, cohorts: Dictionary) -> Dictionary:
	if pending.visits.size()!=128 or pending.actors.size()!=128 or not world.facts.visits.is_empty():
		return {"ok":false,"reason":"Mixed histories require all 128 unstarted patients before any live patient ticket"}
	var rows: Array=[]
	var staged: Dictionary={}
	var by_floor: Dictionary={}
	var added_receipt_total: int=0
	var added_receipt_count: int=0
	for index: int in range(44,128):
		var id: String="bench_visit_%04d"%index
		var original: Dictionary=pending.visits.get(id,{})
		var actor: Dictionary=pending.actors.get("bench_patient_%04d"%index,{})
		if original.get("actor_id","")!=actor.get("id","") or original.get("phase","")!="arrival" or not str(original.get("ticket_id","")).is_empty() or not original.get("diagnosis",{}).is_empty() or not original.get("attempt_ids",[]).is_empty() or not original.get("plan_decision",{}).is_empty():
			return {"ok":false,"reason":"Cannot replace a participating patient's current GP request","visit_id":id}
		if original.get("binding_id","")!="B_S13_D09_M09" or original.get("disease_id","")!="D09" or actor.get("location",{}).get("kind","")!="floor":
			return {"ok":false,"reason":"Mixed A cohort differs from the retained complete original case","visit_id":id}
		var floor_id: int=int(actor.location.floor_id)
		var doctor_id: String="bench_staff_%04d"%(floor_id-1)
		var facility_id: String="bench_room_%d_00_0"%floor_id
		var doctor: Dictionary=world.facts.staff.get(doctor_id,{})
		var facility: Dictionary=world.facts.facilities.get(facility_id,{})
		var room_id: String="bench_room_%d_00"%floor_id
		if doctor.get("role","")!="doctor" or int(doctor.get("abilities",{}).get("diagnosis",0))<1 or facility.get("definition_id","")!="FUR02" or facility.get("room_id","")!=room_id:
			return {"ok":false,"reason":"Historical GP has no lawful original doctor/table identity","visit_id":id}
		var kind: String="examination" if index<54 else "consult" if index<60 else "outpatient"
		var visit: Dictionary=original.duplicate(true)
		var diagnosis: Dictionary={"state":"diagnosed","gp_completed":true,"exam_kind":"","exam_completed":false,"review_completed":false,"doctor_id":doctor_id,"facility_id":facility_id,"insufficient_bp":int(content.balance.clinical.diagnosis_insufficient_bp[int(doctor.abilities.diagnosis)]),"insufficient":false}
		if kind in ["examination","consult"]:
			diagnosis.state="insufficient";diagnosis.insufficient=true
		if kind=="consult":
			diagnosis.state="review_pending"
			diagnosis.exam_kind="spectrum" if index%2==0 else "resonance"
			diagnosis.exam_completed=true
		visit.diagnosis=diagnosis
		visit.doctor_fee_quote=content.doctor_fee(doctor.title_id)
		visit.requested_plan_id="P_D09_COMMON"
		if kind=="outpatient":
			var plan: Dictionary=content.definition("treatment_plans",visit.requested_plan_id)
			if plan.get("disease_id","")!=visit.disease_id: return {"ok":false,"reason":"Saved mixed plan is not a legal plan for this disease","visit_id":id}
			for research_id: String in plan.requires_research:
				if not research_id in world.facts.research: return {"ok":false,"reason":"Saved mixed plan lacks its research","visit_id":id,"research_id":research_id}
			visit.plan_decision={"plan_id":plan.id,"source":"director","doctor_id":doctor_id,"revision":1,"reason":"Saved diagnosis and lawful plan before unstarted mixed-row treatment"}
		var receipts: Array=[{"component":"consultation","amount":int(visit.doctor_fee_quote)},{"component":"gp","amount":content.facility_fee("FUR02","gp")}]
		if diagnosis.exam_completed: receipts.append({"component":diagnosis.exam_kind,"amount":content.facility_fee("FUR02",diagnosis.exam_kind)})
		for receipt: Dictionary in receipts:
			added_receipt_total+=int(receipt.amount);added_receipt_count+=1
		by_floor[str(floor_id)]=int(by_floor.get(str(floor_id),0))+1
		rows.append({"visit_id":id,"actor_id":actor.id,"binding_id":visit.binding_id,"disease_id":visit.disease_id,"profile":"A","next_service":kind,"diagnosis":diagnosis.duplicate(true),"receipts":receipts,"original_body_dimensions":content.actor_body(actor),"body_dimensions":content.actor_body(actor),"history_origin":"declared_requirement_boundary","history_basis":SPEC,"original_current_v3_need":"gp","scope":"New independent matrix input: an unstarted v3 GP case is represented after historical GP, and after one historical examination only for consult. Historical services and receipts are input, not sampled completions. All subsequent examination, review, treatment, travel, admission and family decisions run in production."})
		staged[id]=visit
	# Commit only complete declarations; the live employee world, all Actor
	# records, current RNG and every pre-existing request remain untouched.
	for id: String in staged: pending.visits[id]=staged[id]
	cohorts.historical=cohorts.historical+rows
	cohorts.additional_fresh_records=[]
	for additional: Dictionary in cohorts.additional_records:
		additional.next_service="outpatient"
		additional.history_origin="declared_requirement_boundary"
		additional.scope="One of the eight retained additional complete identities. This mixed row supplies historical GP and a legal common plan before its first step; it is not a fresh GP case in this row. The original v3 version of this identity remains a fresh GP case in its separate immutable input."
	cohorts.patient_boundary_description="All original 120 patients and eight additional complete patients join once before any patient step. This row has 20 fresh B GP cases and 108 explicitly declared clinical histories. No participating employee is moved and no admission, family, Attempt or future recovery is supplied."
	cohorts.mixed_declaration={"scenario":SCENARIO,"basis":SPEC,"replaced_current_v3_gp_inputs":84,"new_pending_needs":{"examination":10,"consult":6,"outpatient":68},"complete_cohorts":{"gp":20,"surgery":12,"outpatient_common":72,"outpatient_gentle":4,"examination":12,"consult":8},"additional_history_by_floor":by_floor,"additional_history_visit_ids":staged.keys(),"additional_declared_receipt_count":added_receipt_count,"additional_declared_receipt_total":added_receipt_total,"additional_patients":8,"additional_fresh_patients":0,"history_execution":"Declared legal pre-operation inputs; no historical sim.step, service_completed event or claimed past RNG replay is generated.","rng":"No draw or reset. Future production decisions continue from the actual employee-opening RNG state. Different later draw consumption belongs to this distinct workload.","comparison":"The original v3 retains its 84 current GP requests. This row replaces those inputs with 10 pending examinations, 6 pending reviews and 68 pending common treatments before issuing its own patient tickets. Results between rows are not optimization evidence."}
	return cohorts
