extends "res://tests/acceptance/clinical_fixtures.gd"

# The complete pre-optimization enumeration is frozen independently of the
# optimized entry, including its full bundle-validation call and tie ordering.
# Source: 83cc36ae6a8cb28272ba523b984128fae54a7dae.
class OriginalEnumeration extends HospitalClinic:
	func _surgery_quote(world: WorldState, visit: Dictionary, requested_team: Array = [], options: Dictionary = {}) -> Dictionary:
		var plan: Dictionary = content.definition("treatment_plans",visit.plan_decision.get("plan_id",""))
		if plan.is_empty():
			return {"ok":false,"structural_ok":false,"reason":"缺少原手术方案"}
		var protocol: Dictionary = content.definition("treatment_protocols",plan.protocol_id)
		var pools: Array = [[],[],[]]
		var structural: bool = bool(options.get("structural_only",false))
		var requirements: Array = [protocol.min_surgeon_surgery,protocol.min_anesthetist_surgery,protocol.min_nurse_surgery]
		var titles: Array = [protocol.min_surgeon_title_id,protocol.min_anesthetist_title_id,""]
		var tables: Array = []
		var table_ids: Array = [str(options.facility_id)] if options.has("facility_id") else world.facility_ids("EQ01")
		for facility_id: String in table_ids:
			if not world.facts.facilities.has(facility_id): continue
			var table: Dictionary = world.facts.facilities[facility_id]
			if table.definition_id=="EQ01" and (not options.has("facility_id") or options.facility_id==facility_id) and not HospitalRemodel.blocked(world,facility_id):
				tables.append(facility_id)
		var team_ids: Array = requested_team if not requested_team.is_empty() else world.ids("staff")
		for staff_id: String in team_ids:
			if not world.facts.staff.has(staff_id): continue
			var staff: Dictionary = world.facts.staff[staff_id]
			for index: int in 3:
				if not requested_team.is_empty() and (requested_team.size()!=3 or staff_id!=requested_team[index]):
					continue
				if staff.role!=("nurse" if index==2 else "doctor") or int(staff.abilities.surgery)<int(requirements[index]):
					continue
				if index==2 and not "q_or" in staff.certificates:
					continue
				if index<2 and int(content.definition("doctor_titles",staff.title_id).rank)<int(content.definition("doctor_titles",titles[index]).rank):
					continue
				if not structural and (not staff.on_shift or not _can_start(world,staff) or _staff_busy(world,staff_id,visit.id)):
					continue
				pools[index].append(staff_id)
		# This read-only enumeration shares bed checks only until it returns.
		# The doctors cannot be ward-nurse candidates; only the team's nurse is excluded.
		var bed_quotes: Dictionary = options.get("bed_quotes",{})
		var alternatives: Variant = options.get("alternatives")
		space.begin_route_query(world)
		var best: Dictionary = {"ok":false,"structural_ok":false,"reason":"缺少当前可执行的三个互异手术岗位"}
		if not pools[0].is_empty() and not pools[1].is_empty() and not pools[2].is_empty() and not tables.is_empty():
			var has_bed: bool = false
			for facility_id: String in tables:
				var table: Dictionary = world.facts.facilities[facility_id]
				for nurse_id: String in pools[2]:
					var key: String = JSON.stringify([int(table.floor_id),nurse_id,structural,str(options.get("bed_id","")),bool(options.get("reference_schedule",false))])
					if not bed_quotes.has(key):
						if structural and bool(options.get("reference_schedule",false)) and str(options.get("bed_id","")).is_empty():
							var beds: Array = _reference_bed_alternatives(world,visit,int(table.floor_id),[nurse_id],bed_quotes)
							bed_quotes[key] = beds[0] if not beds.is_empty() else {"ok":false,"reason":"等待同层兼容床位、真实护理覆盖与出院查房医生"}
						else: bed_quotes[key] = _compatible_bed(world,visit,int(table.floor_id),[nurse_id],structural,str(options.get("bed_id","")),bool(options.get("reference_schedule",false)))
					has_bed = has_bed or bool(bed_quotes[key].ok)
					best = bed_quotes[key]
			if not has_bed:
				space.end_route_query()
				return best
			best = {"ok":false,"structural_ok":false,"reason":"缺少当前可执行的三个互异手术岗位"}
		for surgeon_id: String in pools[0]:
			for anesthetist_id: String in pools[1]:
				if surgeon_id==anesthetist_id:
					continue
				for nurse_id: String in pools[2]:
					for facility_id: String in tables:
						var table: Dictionary = world.facts.facilities[facility_id]
						if best.ok and alternatives==null:
							var predicted: Dictionary = _surgery_probability(world,visit,[surgeon_id,anesthetist_id,nurse_id],table,protocol)
							if int(predicted.probability_bp)<int(best.probability_bp) or (int(predicted.probability_bp)==int(best.probability_bp) and str([surgeon_id,anesthetist_id,nurse_id])+facility_id>=str(best.staff_ids)+str(best.facility_id)):
								continue
						var quote: Dictionary = _surgery_bundle_quote(world,visit,[surgeon_id,anesthetist_id,nurse_id],facility_id,options,bed_quotes)
						if quote.ok and alternatives!=null: alternatives.append(quote)
						if quote.ok and (not best.ok or int(quote.probability_bp)>int(best.probability_bp) or (int(quote.probability_bp)==int(best.probability_bp) and str(quote.staff_ids)+facility_id<str(best.staff_ids)+str(best.facility_id))):
							best = quote
						elif not best.ok:
							best = quote
		space.end_route_query()
		return best

	func _surgery_bundle_quote(world: WorldState, visit: Dictionary, team: Array, facility_id: String, options: Dictionary, bed_quotes: Dictionary) -> Dictionary:
		var plan: Dictionary = content.definition("treatment_plans",visit.plan_decision.get("plan_id",""))
		if plan.is_empty():
			return {"ok":false,"reason":"缺少原手术方案"}
		var protocol: Dictionary = content.definition("treatment_protocols",plan.protocol_id)
		if visit.attempt_ids.size()>=int(content.balance.max_treatment_attempts):
			return {"ok":false,"reason":"已达到实际治疗次数上限"}
		for research_id: String in plan.requires_research:
			if not research_id in world.facts.research:
				return {"ok":false,"reason":"手术研究尚未完成"}
		var requirements: Array = [protocol.min_surgeon_surgery,protocol.min_anesthetist_surgery,protocol.min_nurse_surgery]
		var titles: Array = [protocol.min_surgeon_title_id,protocol.min_anesthetist_title_id,""]
		for index: int in team.size():
			var staff_id: String = team[index]
			if not world.facts.staff.has(staff_id):
				return {"ok":false,"reason":"手术团队缺员"}
			var staff: Dictionary = world.facts.staff[staff_id]
			if int(staff.abilities.surgery) < int(requirements[index]):
				return {"ok":false,"reason":"手术人员未在班或资格不足"}
			if index < 2 and int(content.definition("doctor_titles",staff.title_id).rank) < int(content.definition("doctor_titles",titles[index]).rank):
				return {"ok":false,"reason":"外科职称不足"}
			if index == 2 and not "q_or" in staff.certificates:
				return {"ok":false,"reason":"护士未取得手术资格"}
		if team[0] == team[1] or team[0] == team[2] or team[1] == team[2]:
			return {"ok":false,"reason":"手术岗位必须互异"}
		var table: Dictionary = world.facts.facilities[facility_id]
		var structural: bool = bool(options.get("structural_only",false))
		if not structural or bool(options.get("reference_schedule",false)):
			for staff_id: String in team:
				if not _reference_assignment_allows(world,staff_id,"surgery",visit,facility_id):
					return {"ok":false,"structural_ok":true,"reason":"等待排班手术池内的完整团队"}
		if not world.facts.rooms.has(table.get("room_id","")):
			return {"ok":false,"reason":"手术台缺少合法手术室"}
		var operating_room: Dictionary = world.facts.rooms[table.room_id]
		if table.failed or not bool(table.get("open",true)) or not bool(table.get("intake_open",true)) or not bool(operating_room.get("open",true)) or operating_room.kind!="operating_room" or int(operating_room.size[0])<8 or int(operating_room.size[1])<8:
			return {"ok":false,"reason":"手术室未满足最小内部8×8"}
		if not structural and (_facility_unavailable(table) or _facility_busy(world,facility_id,visit.id)):
			return {"ok":false,"structural_ok":true,"reason":"等待原手术台安全可用"}
		var bed_key: String = JSON.stringify([int(table.floor_id),team[2],structural,str(options.get("bed_id","")),bool(options.get("reference_schedule",false))])
		if not bed_quotes.has(bed_key):
			if structural and bool(options.get("reference_schedule",false)) and str(options.get("bed_id","")).is_empty():
				var beds: Array = _reference_bed_alternatives(world,visit,int(table.floor_id),team,bed_quotes)
				bed_quotes[bed_key] = beds[0] if not beds.is_empty() else {"ok":false,"reason":"等待同层兼容床位、真实护理覆盖与出院查房医生"}
			else: bed_quotes[bed_key] = _compatible_bed(world,visit,int(table.floor_id),team,structural,str(options.get("bed_id","")),bool(options.get("reference_schedule",false)))
		var bed_bundle: Dictionary = bed_quotes[bed_key]
		if not bed_bundle.ok:
			return bed_bundle
		if options.has("bed_id") and options.bed_id!=bed_bundle.bed_id:
			return {"ok":false,"reason":"原准备床位已失效，需要重新取得完整资源束"}
		if not bool(options.get("ignore_supplies",false)) and _available_supplies(world,visit.id) < int(protocol.supply_units):
			return {"ok":false,"reason":"治疗包不足"}
		var compatible: bool = false
		for adapter: Dictionary in content.catalog.surgical_adapters:
			if adapter.binding_id == visit.binding_id and adapter.plan_id == plan.id:
				compatible = true
		if not compatible:
			return {"ok":false,"reason":"病例缺少合法手术承托适配"}
		var fit: Dictionary = space.facility_quote(world,facility_id,visit.actor_id,team)
		if not fit.ok:
			return fit
		var layout: Dictionary = space.facility_layout(world,facility_id) if fit.get("unchanged",false) else fit
		if layout.operator_cells.size()!=3:
			return {"ok":false,"reason":"手术台缺少三个互异实际医护站位"}
		var gathering_ticks: int = 0
		for index: int in 4:
			var actor_id: String = visit.actor_id if index==0 else str(team[index-1])
			var position: Array = layout.patient_cell if index==0 else layout.operator_cells[index-1]
			var route: Dictionary = space.travel_quote(world,actor_id,int(table.floor_id),position)
			if not route.ok:
				return route
			gathering_ticks = maxi(gathering_ticks,int(route.travel_ticks))
		var predicted: Dictionary = _surgery_probability(world,visit,team,table,protocol)
		var effective: float = float(predicted.effective_level)
		var seconds: float = _surgery_work_seconds(world,visit,team[0],protocol,effective)
		for staff_id: String in team:
			var consumption: float = float(content.balance.wellbeing.energy_work_per_second)*(seconds+float(content.balance.clinical.wake_seconds)+float(content.balance.clinical.or_setup_seconds))
			if not structural and float(world.facts.staff[staff_id].energy)-consumption<=15.0:
				return {"ok":false,"reason":"团队体力不足以安全覆盖操作和苏醒全过程"}
		var quote: Dictionary = {"ok":true,"structural_ok":true,"plan_id":plan.id,"probability_bp":int(predicted.probability_bp),"work_ticks":ceili(seconds*10),
			"recovery_ticks":ceili(float(protocol.recovery_seconds)*10),"supply_units":int(protocol.supply_units),
			"cure_fee":_quoted_fee(int(content.definition("diseases",visit.disease_id).cure_fee),protocol.cure_fee_multiplier),
			"facility_fee":content.facility_fee(table.definition_id,"surgery"),"staff_ids":team.duplicate(),"effective_level":effective,"facility_id":facility_id,
			"gathering_ticks":gathering_ticks,"estimated_total_ticks":gathering_ticks+ceili(seconds*10)+ceili(float(protocol.recovery_seconds)*10)+int(content.balance.clinical.wake_seconds)*10}
		quote.merge(bed_bundle)
		return quote

func run_case(t, database: HospitalContent) -> void:
	_content = database
	var observation: Dictionary = qualification_case()
	_dispose_simulations()
	t.check("GROW-84",observation.passed,observation)

func qualification_case() -> Dictionary:
	var fixture: Dictionary = _context(true)
	var world: WorldState = fixture.world
	_add_worker(world,"clin_extra_surgeon","doctor",[35,78],"surgery",{"diagnosis":1,"treatment":1,"care":0,"surgery":4},"DT02")
	_add_worker(world,"clin_extra_or_nurse","nurse",[39,78],"work",{"diagnosis":1,"treatment":0,"care":1,"surgery":1})
	world.facts.staff.clin_extra_or_nurse.certificates = ["q_or","q_ward"]
	world.touch()
	var clinic: HospitalClinic = fixture.sim.clinic
	var old: OriginalEnumeration = OriginalEnumeration.new(_content,clinic.space)
	for property: Dictionary in clinic.get_property_list():
		if (int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE)!=0: old.set(property.name,clinic.get(property.name))
	var nominal: WorldState = fixture.sim.services.arrivals._capacity_reference_world(world)
	var candidate: Dictionary = clinic._arrival_candidate(nominal,"B_S13_D09_M09",false)
	if not candidate.ok: return {"passed":false,"candidate":candidate.reason}
	candidate.visit.plan_decision = {"plan_id":"P_D09_SURGERY"}
	var original: Dictionary = candidate.world.freeze()
	var observations: Array = []
	var equal: bool = true
	var nonempty: int = 0
	for condition: String in ["ordinary","ability","title","certificate","research","attempt_limit","low_probability","off_shift"]:
		for retry: bool in [false,true]:
			var facts: Dictionary = original.duplicate(true)
			var visit: Dictionary = facts.visits[candidate.visit.id]
			if retry: visit.attempt_ids = ["reference_completed_attempt"]
			if condition=="ability": facts.staff.clin_extra_surgeon.abilities.surgery = 0
			if condition=="title": facts.staff.clin_extra_surgeon.title_id = "DT01"
			if condition=="certificate": facts.staff.clin_extra_or_nurse.certificates = []
			if condition=="research": facts.research.clear()
			if condition=="attempt_limit": visit.attempt_ids = ["reference_attempt_a","reference_attempt_b"]
			if condition=="low_probability":
				for staff: Dictionary in facts.staff.values(): staff.energy = 10.0
				facts.facilities.clin_or_0.condition = 39.0
			if condition=="off_shift":
				for staff: Dictionary in facts.staff.values(): staff.on_shift = false
			var query: WorldState = WorldState.new(facts)
			var before: Dictionary = query.freeze()
			var actual: Array = []
			var previous: Array = []
			var selected: Dictionary = clinic._surgery_quote(query,visit,[],{"structural_only":true,"ignore_supplies":true,"reference_schedule":true,"alternatives":actual})
			var original_selected: Dictionary = old._surgery_quote(query,visit,[],{"structural_only":true,"ignore_supplies":true,"reference_schedule":true,"alternatives":previous})
			var identical: bool = actual==previous and selected==original_selected and query.freeze()==before
			equal = equal and identical
			if condition=="ordinary" and not retry: nonempty = actual.size()
			observations.append({"condition":condition,"retry":retry,"complete_ordered_quotes_equal":identical,"quotes":actual.size()})
	# The direct entry still checks changed qualifications and distinct posts,
	# and failure must not create reservations, attempts, supply use or RNG work.
	var direct: WorldState = WorldState.new(original.duplicate(true))
	var visit: Dictionary = direct.facts.visits[candidate.visit.id]
	var team: Array = ["clin_surgeon","clin_anesthesia","clin_or_nurse"]
	direct.facts.staff.clin_anesthesia.abilities.surgery = 0
	var before: Dictionary = direct.freeze()
	var invalid: Dictionary = clinic._surgery_bundle_quote(direct,visit,team,"clin_or_0",{},{})
	var duplicate: Dictionary = clinic._surgery_bundle_quote(direct,visit,["clin_surgeon","clin_surgeon","clin_or_nurse"],"clin_or_0",{},{})
	var protected: bool = not invalid.ok and not duplicate.ok and direct.freeze()==before
	return {"passed":equal and nonempty==12 and protected and clinic.space._route_queries.is_empty(),"complete_ordered_quotes_equal":equal,"baseline_quote_count":nonempty,"actual_validation_and_failure_atomicity":protected,"observations":observations}
