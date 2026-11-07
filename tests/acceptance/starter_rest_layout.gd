extends RefCounted

const IDS: Array[String] = ["staff_bed_a","staff_bed_b","rest_sofa"]
const GEOMETRY: Array[String] = ["cell","footprint","rotation","patient_cell","operator_cells","repair_cell"]

func run(t, content: HospitalContent) -> void:
	var world: WorldState = HospitalFactory.create("starter_rest_layout","Starter rest layout",true,content)
	var space: HospitalSpace = HospitalSpace.new(content)
	var builder: BuildService = BuildService.new(content,space)
	var original: Dictionary = world.freeze()
	var quotes: Array = []
	var legal: bool = true
	for id: String in IDS:
		for staff_id: String in world.ids("staff"):
			var geometry: Dictionary = space.facility_geometry_quote(world,id,staff_id)
			var trip: Dictionary = space.facility_trip_quote(world,id,staff_id)
			quotes.append({"facility":id,"staff":staff_id,"geometry":geometry,"trip":trip})
			legal = legal and geometry.ok and trip.ok
	var commands: Array = []
	var parity: bool = true
	for id: String in IDS:
		var result: CommandResult = builder.execute(world,"build_store",{"target_id":id})
		commands.append({"kind":"build_store","payload":{"target_id":id},"result":result.to_record()})
		parity = parity and result.accepted
	for id: String in IDS:
		var old: Dictionary = original.facilities[id]
		var payload: Dictionary = {"inventory_id":id,"definition_id":old.definition_id,"cell":old.cell,"floor_id":old.floor_id,"room_id":old.room_id,"rotation":old.rotation}
		var result: CommandResult = builder.execute(world,"build_facility",payload)
		commands.append({"kind":"build_facility","payload":payload,"result":result.to_record()})
		parity = parity and result.accepted
		if result.accepted:
			for field: String in GEOMETRY: parity = parity and world.facts.facilities[id][field]==old[field]
	# A normal no-displacement move still resolves the ordinary move anchor path.
	for id: String in IDS:
		var payload: Dictionary = {"target_id":id,"cell":original.facilities[id].cell}
		var result: CommandResult = builder.execute(world,"build_move",payload)
		commands.append({"kind":"build_move","payload":payload,"result":result.to_record()})
		parity = parity and result.accepted
		if result.accepted:
			for field: String in GEOMETRY: parity = parity and world.facts.facilities[id][field]==original.facilities[id][field]
	var untouched: bool = world.facts.rooms==original.rooms and world.facts.staff==original.staff and world.facts.actors==original.actors
	for id: String in original.facilities:
		if not id in IDS: untouched = untouched and world.facts.facilities[id]==original.facilities[id]
	var economy: Dictionary = preload("res://tests/acceptance/starter_economy.gd").new().run_case(world,content)
	var lifecycle: Dictionary = _lifecycle(world,content) if legal and parity else {"ok":false,"not_run":"layout or ordinary command geometry failed"}
	t.check("CORE-55",legal and parity and untouched and economy.ok and lifecycle.ok,{"quotes":quotes,"ordinary_commands":commands,"factory_build_move_parity":parity,"other_facilities_rooms_staff_actors_unchanged":untouched,"economy":economy,"lifecycle":lifecycle})

func _lifecycle(world: WorldState, content: HospitalContent) -> Dictionary:
	# Legal boundary input, not historical completion: the two automatically
	# assigned owners have reached the 13500 awake-tick limit; the nurse needs
	# short rest. No actor position, sleep progress or ownership is supplied.
	var sim: HospitalSimulation = HospitalSimulation.new(world,content)
	var owners: Dictionary = world.facts.staff_life.personal_beds.duplicate(true)
	var slept: Dictionary = {}
	var returned: Dictionary = {}
	var starts: Dictionary = {}
	for bed_id: String in owners:
		var id: String = owners[bed_id].staff_id
		world.facts.staff[id].awake_ticks = 13500
		slept[id] = 0
		starts[id] = world.facts.actors[id].location.duplicate(true)
	var rest_id: String = "starter_nurse"
	world.facts.staff[rest_id].energy = 20.0
	starts[rest_id] = world.facts.actors[rest_id].location.duplicate(true)
	var before_cash: int = HospitalLedger.balance(world)
	var close: CommandResult = sim.apply(GameCommand.from_record({"id":"rest_test_close_intake","hospital_id":world.hospital_id,"kind":"set_intake_open","typed_payload":{"open":false},"expected_revision":world.revision}))
	var transitions: Array = []
	var previous: Dictionary = {}
	var violations: Array = []
	var sofa_ticks: int = 0
	var simultaneous: bool = false
	var steps: int = 0
	for tick: int in 6500:
		var old_sleep: Dictionary = {}
		for id: String in slept: old_sleep[id] = int(world.facts.staff[id].sleep_remaining_ticks)
		var step = sim.step()
		steps += 1
		if step==null:
			violations.append({"tick":world.sim_tick,"reason":"whole simulation did not complete"})
			break
		var asleep: int = 0
		for id: String in starts:
			var staff: Dictionary = world.facts.staff[id]
			var task: Dictionary = staff.life_task
			var phase: String = task.phase
			if slept.has(id):
				if int(old_sleep[id])>int(staff.sleep_remaining_ticks): slept[id] += int(old_sleep[id])-int(staff.sleep_remaining_ticks)
				if phase=="sleep": asleep += 1
			if id==rest_id and phase=="rest" and task.get("facility_id","")=="rest_sofa": sofa_ticks += 1
			if previous.get(id,"")!=phase:
				transitions.append({"tick":world.sim_tick,"staff":id,"phase":phase,"task":task.duplicate(true),"actor":world.facts.actors[id].duplicate(true),"sleep_remaining_ticks":staff.sleep_remaining_ticks})
				previous[id] = phase
			if not returned.has(id) and phase=="idle" and (slept.get(id,0)==4500 or id==rest_id and sofa_ticks>0): returned[id] = {"tick":world.sim_tick,"location":world.facts.actors[id].location.duplicate(true)}
		if asleep==2 and world.facts.staff[rest_id].life_task.phase=="rest" and world.facts.staff[rest_id].life_task.get("facility_id","")=="rest_sofa": simultaneous = true
		var bodies: Array = []
		for id: String in world.ids("actors"):
			var actor: Dictionary = world.facts.actors[id]
			if actor.location.kind=="floor": bodies.append({"id":id,"floor":actor.location.floor_id,"rect":sim.space.body_rectangle(actor)})
		for a: int in bodies.size():
			for b: int in range(a+1,bodies.size()):
				if bodies[a].floor==bodies[b].floor and bodies[a].rect.intersects(bodies[b].rect,false): violations.append({"tick":world.sim_tick,"overlap":[bodies[a].id,bodies[b].id]})
		if not violations.is_empty() or returned.size()==3: break
	var fully_slept: bool = slept.size()==2
	for id: String in slept: fully_slept = fully_slept and slept[id]==4500 and int(world.facts.staff[id].sleep_remaining_ticks)==0
	var released: bool = true
	for id: String in IDS: released = released and not world.facts.staff_life.reservations.has(id) and not world.facts.adaptations.has(id)
	var validation: String = world.validate(content)
	var life_validation: String = sim.services.wellbeing.validate(world)
	var result: Dictionary = {"ok":close.accepted and owners.size()==2 and fully_slept and returned.size()==3 and sofa_ticks>0 and simultaneous and released and owners==world.facts.staff_life.personal_beds and violations.is_empty() and validation.is_empty() and life_validation.is_empty(),"input":"fresh current-content starter after normal store/place/move; automatic owners at mandatory-sleep boundary, nurse energy20; no actor relocation or progress completion","close_intake":close.to_record(),"owners":owners,"unassigned_staff":world.facts.staff.size()-owners.size(),"starts":starts,"sleep_ticks":slept,"sofa_rest_ticks":sofa_ticks,"simultaneous_two_beds_and_sofa":simultaneous,"returned":returned,"released":released,"owners_unchanged":owners==world.facts.staff_life.personal_beds,"steps":steps,"cash_before":before_cash,"cash_after":HospitalLedger.balance(world),"violations":violations,"validation":validation,"life_validation":life_validation,"transitions":transitions,"final_staff":world.facts.staff.duplicate(true)}
	sim.dispose()
	return result
