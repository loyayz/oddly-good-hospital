extends RefCounted

class FullEnumerationClinic extends HospitalClinic:
	func service_candidates(world: WorldState, visit: Dictionary, kind: String, structural_only: bool = false, reference_schedule: bool = false, selection: Dictionary = {}) -> Array:
		var full_selection: Dictionary = selection.duplicate()
		if kind=="outpatient" and structural_only: full_selection.erase("staff_id")
		# Control materializes every complete route before evaluating quotes.
		# This retains the former eager order independently of early acceptance.
		if not full_selection.has("accept"):
			return super.service_candidates(world,visit,kind,structural_only,reference_schedule,full_selection)
		var accept: Callable = full_selection.accept
		full_selection.erase("accept")
		full_selection.erase("first_only")
		var pairs: Array = super.service_candidates(world,visit,kind,structural_only,reference_schedule,full_selection)
		var accepted: Array = []
		for pair: Dictionary in pairs:
			if not accept.call(pair): continue
			accepted.append(pair)
			if selection.get("first_only",false): break
		return accepted

class CountedSpace extends HospitalSpace:
	var observed_routes: Array = []
	var reject_actor: String = ""
	var fit_before_routes: bool = false
	var pending_fits: Dictionary = {}
	func facility_preflight_quote(world: WorldState, facility_id: String, actor_id: String, staff_ids: Array = []) -> Dictionary:
		if fit_before_routes:
			var full: Dictionary = super.facility_quote(world,facility_id,actor_id,staff_ids)
			pending_fits[JSON.stringify([world.get_instance_id(),facility_id,actor_id,staff_ids])] = full
			return full
		return super.facility_preflight_quote(world,facility_id,actor_id,staff_ids)
	func facility_quote(world: WorldState, facility_id: String, actor_id: String, staff_ids: Array = []) -> Dictionary:
		var key: String = JSON.stringify([world.get_instance_id(),facility_id,actor_id,staff_ids])
		if pending_fits.has(key):
			var full: Dictionary = pending_fits[key]
			pending_fits.erase(key)
			return full
		return super.facility_quote(world,facility_id,actor_id,staff_ids)
	func route(world: WorldState, actor_id: String, floor_id: int, target: Array, members: Array = [], offsets: Dictionary = {}, ignore_people: bool = false) -> Dictionary:
		observed_routes.append([actor_id,floor_id,target.duplicate(),ignore_people])
		if actor_id==reject_actor: return {"ok":false,"status":"no_route","reason":"controlled selected doctor route failure"}
		return super.route(world,actor_id,floor_id,target,members,offsets,ignore_people)

func run_case(t, content: HospitalContent) -> void:
	var builder: RefCounted = load("res://tests/acceptance/clinical_gathering.gd").new()
	var source: WorldState = builder._context(content,"gp").world
	for index: int in 2:
		var room_id: String = "quote_room_"+str(index)
		var origin: Array = [46+index*18,30]
		HospitalFactory._add_room(source,{"id":room_id,"type":"T01","anchor":origin,"size":[8,8],"door":{"definition_id":"DR04","offset":3}},content)
		HospitalFactory._add_facility(source,{"id":"quote_facility_"+str(index),"definition_id":"M09","anchor":[int(origin[0])+1,int(origin[1])+1],"size":content.facility_definition("M09").footprint,"room_id":room_id},content)
		var id: String = "quote_doctor_"+str(index)
		HospitalFactory._add_staff(source,id,"治疗医生","doctor",[44+index*4,24],content)
		source.facts.staff[id].abilities.treatment = index+2
	for definition: Dictionary in content.catalog.research: source.facts.research.append(definition.id)
	source.touch()
	var validation: String = source.validate(content)
	var base: Dictionary = source.freeze()
	var passed: bool = validation.is_empty()
	var checked: int = 0
	var full_unrelated: int = 0
	var selected_unrelated: int = 0
	var routes_saved: int = 0
	var failures: Array = []
	for condition: String in ["ordinary","supplies","off_shift","failed_facilities","unqualified","blocked_route","first_unavailable","first_unqualified"]:
		for plan_id: String in ["P_D09_COMMON","P_D09_GENTLE"]:
			for structural: bool in [false,true]:
				for doctor_id: String in ["gather_worker","quote_doctor_0","quote_doctor_1","missing_doctor","","no_selection"]:
					var facts: Dictionary = base.duplicate(true)
					if condition=="supplies": facts.inventory.units = 0
					if condition=="off_shift":
						for staff: Dictionary in facts.staff.values(): staff.on_shift = false
					if condition=="failed_facilities":
						for facility: Dictionary in facts.facilities.values():
							if facility.definition_id=="M09": facility.failed = true
					if condition=="unqualified":
						for staff: Dictionary in facts.staff.values(): staff.abilities.treatment = 0
					if condition=="first_unavailable": facts.facilities.quote_facility_0.stop_new_service = true
					if condition=="first_unqualified": facts.staff.gather_worker.abilities.treatment = 0
					var actual_world: WorldState = WorldState.new(facts.duplicate(true))
					var control_world: WorldState = WorldState.new(facts.duplicate(true))
					var actual_space: CountedSpace = CountedSpace.new(content)
					var control_space: CountedSpace = CountedSpace.new(content)
					control_space.fit_before_routes = true
					if condition=="blocked_route":
						actual_space.reject_actor = "gather_worker" if doctor_id=="no_selection" else doctor_id
						control_space.reject_actor = actual_space.reject_actor
					var actual: HospitalClinic = HospitalClinic.new(content,actual_space)
					var control: HospitalClinic = FullEnumerationClinic.new(content,control_space)
					var options: Dictionary = {"structural_only":structural}
					if doctor_id!="no_selection": options.doctor_id = doctor_id
					var quote: Dictionary = actual.plan_quote(actual_world,"gather_visit_0",plan_id,options)
					var full: Dictionary = control.plan_quote(control_world,"gather_visit_0",plan_id,options)
					var equal: bool = quote==full and actual_world.freeze()==facts and control_world.freeze()==facts
					var extra_actual: int = _unrelated(actual_space.observed_routes,actual_world,doctor_id)
					var extra_control: int = _unrelated(control_space.observed_routes,control_world,doctor_id)
					if doctor_id=="no_selection":
						equal = equal and actual_space.observed_routes.size()<=control_space.observed_routes.size()
						routes_saved += control_space.observed_routes.size()-actual_space.observed_routes.size()
					else:
						equal = equal and extra_actual==0
						full_unrelated += extra_control
						selected_unrelated += extra_actual
					if condition=="ordinary" and doctor_id not in ["missing_doctor","","no_selection"]:
						equal = equal and bool(quote.get("ok",false)) and quote.get("staff_ids",[])==[doctor_id] and quote.get("facility_id","")=="quote_facility_0"
					if condition=="first_unavailable" and not structural and doctor_id not in ["missing_doctor",""]:
						equal = equal and bool(quote.get("ok",false)) and quote.get("facility_id","")=="quote_facility_1"
					if not equal: failures.append({"condition":condition,"plan":plan_id,"structural":structural,"doctor":doctor_id,"actual":quote,"full":full,"unrelated_routes":extra_actual})
					passed = passed and equal
					checked += 1
	t.check("CLIN-34",passed and full_unrelated>0 and selected_unrelated==0 and routes_saved>0,{"input_validation":validation,"checked_variants":checked,"full_enumeration_unrelated_doctor_routes":full_unrelated,"selected_enumeration_unrelated_doctor_routes":selected_unrelated,"eager_route_calls_saved":routes_saved,"complete_quotes_and_facts_rng_equal":passed,"failures":failures})

func _unrelated(routes: Array, world: WorldState, doctor_id: String) -> int:
	var count: int = 0
	for route: Array in routes:
		if world.facts.staff.has(route[0]) and route[0]!=doctor_id: count += 1
	return count
