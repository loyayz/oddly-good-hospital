extends RefCounted

const SMALL: String = "B_S06_D04_M04"
const WIDE_TURN: String = "B_S11_D07_M07"
const TALL: String = "B_S08_D04_M04"
const HUMAN: String = "B_S49_D23_M23"
const PATIENT: String = "reference_patient"
const ESCORT: String = "reference_escort"
const START: Array = [45,72]
const GOAL: Array = [45,86]

var _content: HospitalContent
var _base: Dictionary

func run_case(t, database: HospitalContent) -> void:
	_content = database
	_base = HospitalFactory.create(HospitalSnapshots.uuid(),"参考通行包络",false,_content).freeze()
	var small: Dictionary = {"patient_binding":SMALL,"width":2}
	var large: Dictionary = small.duplicate(true)
	large.patient_binding = WIDE_TURN
	var small_escort: Dictionary = {"patient_binding":HUMAN,"escort_binding":HUMAN,"width":2}
	var large_escort: Dictionary = small_escort.duplicate(true)
	large_escort.escort_binding = WIDE_TURN
	var nearby: Dictionary = small.duplicate(true)
	var distant: Dictionary = small.duplicate(true)
	nearby.width = 0
	distant.width = 0
	distant.extra_spacing = 2.0
	# A travelling front/back group can only contain standing participants.
	# Check clearance for both roles there; lying/standing remains a solo
	# prospective clearance distinction before a supported body can get up.
	var short_primary: Dictionary = {"patient_binding":SMALL,"floor_leg":true}
	var tall_primary: Dictionary = short_primary.duplicate(true)
	tall_primary.patient_binding = TALL
	var short_member: Dictionary = {"patient_binding":HUMAN,"escort_binding":SMALL,"floor_leg":true}
	var tall_member: Dictionary = short_member.duplicate(true)
	tall_member.escort_binding = TALL
	var single_lying: Dictionary = {"patient_binding":TALL,"posture":"lying","floor_leg":true,"single":true}
	var single_standing: Dictionary = single_lying.duplicate(true)
	single_standing.posture = "standing"
	var scenarios: Array = [
		{"name":"primary_binding","inputs":[small,large],"expected":[true,false]},
		{"name":"member_binding","inputs":[small_escort,large_escort],"expected":[true,false]},
		{"name":"front_back_spacing","inputs":[nearby,distant],"expected":[true,true]},
		{"name":"primary_height","inputs":[short_primary,tall_primary],"expected":[true,false]},
		{"name":"member_height","inputs":[short_member,tall_member],"expected":[true,false]},
		{"name":"single_posture","inputs":[single_lying,single_standing],"expected":[true,false]}]
	var correct: bool = true
	var observations: Array = []
	for scenario: Dictionary in scenarios:
		var worlds: Array[WorldState] = []
		var snapshots: Array = []
		var cold: Array = []
		var details: Dictionary = {"name":scenario.name,"validation":[],"cold":[],"orders":[]}
		for index: int in 2:
			var world: WorldState = _world(scenario.inputs[index])
			var validation: String = world.validate(_content)
			worlds.append(world)
			snapshots.append(world.freeze())
			var geometry: HospitalSpace = HospitalSpace.new(_content)
			var result: Dictionary = _quote(geometry,world,scenario.inputs[index],{"nominal":true})
			cold.append(result)
			details.validation.append(validation)
			details.cold.append(result)
			correct = correct and validation.is_empty() and result.ok==scenario.expected[index] and geometry._route_queries.is_empty()
		if scenario.name=="front_back_spacing":
			var near: Dictionary = ConvoyTrail.create(HospitalSpace.new(_content),worlds[0],PATIENT,[PATIENT,ESCORT])
			var far: Dictionary = ConvoyTrail.create(HospitalSpace.new(_content),worlds[1],PATIENT,[PATIENT,ESCORT])
			correct = correct and near.ok and far.ok
			if near.ok and far.ok:
				correct = correct and far.convoy.spacing==near.convoy.spacing+2.0 and near.convoy.size==far.convoy.size
			details.front_back = [near,far]
		# Both patients fit alone. The rejected geometry is the front/back
		# convoy's turning envelope, rather than an already illegal body.
		if scenario.name=="primary_binding" or scenario.name=="member_binding":
			var alone: Array = []
			for index: int in 2:
				var selection: Dictionary = scenario.inputs[index].duplicate(true)
				selection.single = true
				var solo_space: HospitalSpace = HospitalSpace.new(_content)
				var leader_ok: bool = _quote(solo_space,worlds[index],selection,{"nominal":true}).ok
				var escort_ok: bool = solo_space.route(worlds[index],ESCORT,1,GOAL,[],{},true).ok
				alone.append([leader_ok,escort_ok])
				correct = correct and leader_ok and escort_ok
			details.individual_routes = alone
			var body_space: HospitalSpace = HospitalSpace.new(_content)
			var subject: String = PATIENT if scenario.name=="primary_binding" else ESCORT
			var a: Dictionary = body_space.body(worlds[0].facts.actors[subject])
			var b: Dictionary = body_space.body(worlds[1].facts.actors[subject])
			var small_form: Dictionary = ConvoyTrail.create(body_space,worlds[0],PATIENT,[PATIENT,ESCORT])
			var large_form: Dictionary = ConvoyTrail.create(body_space,worlds[1],PATIENT,[PATIENT,ESCORT])
			correct = correct and a!=b and small_form.ok and large_form.ok
			if small_form.ok and large_form.ok:
				correct = correct and small_form.convoy.size<=2 and large_form.convoy.size>2
			details.symptom_bodies = [a,b]
			details.forms = [small_form,large_form]

		# A→B→A and B→A→B share one nominal cache, just as successive cases
		# reuse query.geometry while replacing the reference patient record.
		for order: Array in [[0,1,0],[1,0,1]]:
			var geometry: HospitalSpace = HospitalSpace.new(_content)
			var reference: Dictionary = {"nominal":true}
			var equal: bool = true
			for index: int in order:
				var warm: Dictionary = _quote(geometry,worlds[index],scenario.inputs[index],reference)
				equal = equal and warm==cold[index] and geometry._route_queries.is_empty()
			correct = correct and equal
			details.orders.append({"indices":order,"complete_cold_equal":equal})
		for index: int in 2: correct = correct and worlds[index].freeze()==snapshots[index]
		observations.append(details)
	t.check("GROW-78",correct,{"cases":observations,"no_simulation_steps":true})

func _world(input: Dictionary) -> WorldState:
	var world: WorldState = WorldState.new(_base.duplicate(true))
	var floor: Dictionary = world.facts.floors.overrides["1"]
	floor.plots = [[1,2]]
	# The transverse strip spans the complete owned plot. No detour around its
	# ends exists; the opening at x=45 is the only passage through y=80.
	var width: int = int(input.get("width",0))
	if width>0:
		for x: int in range(32,64):
			if x<45 or x>=45+width: floor.blocked.append([x,80])
	world.facts.actors[PATIENT] = _actor(PATIENT,str(input.patient_binding),START,str(input.get("posture","standing")))
	if not input.get("single",false):
		world.facts.actors[ESCORT] = _actor(ESCORT,str(input.get("escort_binding",HUMAN)),START,"standing")
		var formation: Dictionary = ConvoyTrail.formation(HospitalSpace.new(_content),world,PATIENT,[PATIENT,ESCORT],Vector2.DOWN)
		var cell: Array = formation.targets[ESCORT].duplicate()
		cell[1] -= float(input.get("extra_spacing",0.0))
		world.facts.actors[ESCORT].location.cell = cell
	if input.get("floor_leg",false):
		# A prospective floor leg is also queried before a transit passenger has
		# arrived. Actors remain on the legal high-ceiling source floor; nobody
		# is placed standing inside the three-metre destination ceiling.
		world.facts.floors.height_intervals.append({"first":2,"last":2,"height_m":3.0})
		world.facts.floors.overrides["2"] = {"plots":[[1,2]],"blocked":[],"doors":[],"paths":[]}
	world.touch()
	return world

func _actor(id: String, binding_id: String, cell: Array, posture: String) -> Dictionary:
	var binding: Dictionary = _content.definition("treatment_bindings",binding_id)
	return {"id":id,"name":id,"species_id":binding.species_id,"body_binding_id":binding_id,
		"location":{"kind":"floor","floor_id":1,"cell":cell.duplicate(),"height_m":0.0},"facing":0.0,"posture":posture}

func _quote(space: HospitalSpace, world: WorldState, input: Dictionary, reference: Dictionary) -> Dictionary:
	var members: Array = [] if input.get("single",false) else [PATIENT,ESCORT]
	space.begin_route_query(world,reference)
	var result: Dictionary
	if input.get("floor_leg",false):
		# A prospective leg uses the same convoy proxy as transit, not the
		# retired lateral-offset floor-route interface. No group is moved.
		var actor: Dictionary = world.facts.actors[PATIENT]
		var shift: Vector2 = Vector2.ZERO
		if not members.is_empty():
			var movement: Dictionary = space.navigation._convoy_query_movement(world,PATIENT,members)
			actor = ConvoyTrail.proxy(world,movement)
			shift = Vector2.ONE*float(movement.convoy.shift)
		var start: Vector2i = Vector2i((ConvoyTrail.point(START)+shift).round())
		var goal: Vector2i = Vector2i((ConvoyTrail.point(GOAL)+shift).round())
		result = space._floor_route(world,actor,2,start,goal,[],{},true)
	else:
		result = space.route(world,PATIENT,1,GOAL,members,{},true)
	space.end_route_query()
	return result
