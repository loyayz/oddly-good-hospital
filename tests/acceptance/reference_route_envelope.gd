extends RefCounted

const SMALL: String = "B_S06_D04_M04"
const LARGE: String = "B_S08_D04_M04"
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
	var small: Dictionary = {"patient_binding":SMALL,"offset":[-1,0],"width":3}
	var large: Dictionary = small.duplicate(true)
	large.patient_binding = LARGE
	var small_escort: Dictionary = {"patient_binding":HUMAN,"escort_binding":SMALL,"offset":[1,0],"width":3}
	var large_escort: Dictionary = small_escort.duplicate(true)
	large_escort.escort_binding = LARGE
	var nearby: Dictionary = small.duplicate(true)
	var distant: Dictionary = small.duplicate(true)
	distant.offset = [-2,0]
	var lying: Dictionary = {"patient_binding":LARGE,"posture":"lying","offset":[-1,0],"floor_leg":true}
	var standing: Dictionary = lying.duplicate(true)
	standing.posture = "standing"
	var member_lying: Dictionary = {"patient_binding":HUMAN,"escort_binding":LARGE,"escort_posture":"lying","offset":[1,0],"floor_leg":true}
	var member_standing: Dictionary = member_lying.duplicate(true)
	member_standing.escort_posture = "standing"
	var single_lying: Dictionary = lying.duplicate(true)
	single_lying.single = true
	var single_standing: Dictionary = standing.duplicate(true)
	single_standing.single = true
	var scenarios: Array = [
		{"name":"primary_binding","inputs":[small,large],"expected":[true,false]},
		{"name":"member_binding","inputs":[small_escort,large_escort],"expected":[true,false]},
		{"name":"offset","inputs":[nearby,distant],"expected":[true,false]},
		{"name":"primary_posture","inputs":[lying,standing],"expected":[true,false]},
		{"name":"member_posture","inputs":[member_lying,member_standing],"expected":[true,false]},
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
		# Both patients fit the three-cell opening alone. The rejected route is
		# the four-cell patient/escort unit, rather than an already illegal body.
		if scenario.name=="primary_binding":
			var alone: Array = []
			for index: int in 2:
				var selection: Dictionary = scenario.inputs[index].duplicate(true)
				selection.single = true
				var result: Dictionary = _quote(HospitalSpace.new(_content),worlds[index],selection,{"nominal":true})
				alone.append(result.ok)
				correct = correct and result.ok
			details.individual_routes = alone
			var body_space: HospitalSpace = HospitalSpace.new(_content)
			var a: Dictionary = body_space.body(worlds[0].facts.actors[PATIENT])
			var b: Dictionary = body_space.body(worlds[1].facts.actors[PATIENT])
			correct = correct and a.width_m==1.8 and a.depth_m==1.8 and a.height_m==1.6 and b.width_m==3.2 and b.depth_m==2.8 and b.height_m==4.6
			correct = correct and body_space.clearance(worlds[0].facts.actors[PATIENT])==2 and body_space.clearance(worlds[1].facts.actors[PATIENT])==3
			details.symptom_bodies = [a,b]
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
	# ends exists; x=44..46 is the only three-cell passage through y=80.
	var width: int = int(input.get("width",0))
	if width>0:
		for x: int in range(32,64):
			if x<44 or x>=44+width: floor.blocked.append([x,80])
	world.facts.actors[PATIENT] = _actor(PATIENT,str(input.patient_binding),START,str(input.get("posture","standing")))
	if not input.get("single",false):
		var offset: Array = input.offset
		world.facts.actors[ESCORT] = _actor(ESCORT,str(input.get("escort_binding",HUMAN)),[START[0]+offset[0],START[1]+offset[1]],str(input.get("escort_posture","standing")))
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
	var offsets: Dictionary = {}
	if not members.is_empty():
		offsets[PATIENT] = [0,0]
		offsets[ESCORT] = input.offset
	space.begin_route_query(world,reference)
	var result: Dictionary
	if input.get("floor_leg",false):
		result = space._floor_route(world,world.facts.actors[PATIENT],2,Vector2i(START[0],START[1]),Vector2i(GOAL[0],GOAL[1]),members,offsets,true)
	else:
		result = space.route(world,PATIENT,1,GOAL,members,offsets,true)
	space.end_route_query()
	return result
