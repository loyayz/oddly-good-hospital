extends RefCounted

const FLOORS: Array[int] = [3,10,1000,10000]
var mobile_ids: Array[String] = []
var origins: Dictionary = {}
var world: WorldState
var _count: int
var _replacement_added: bool = false
var _dense: bool = false

func _init(count: int, content: HospitalContent, dense: bool = false) -> void:
	world = FeasibilityHospitals.create("00000000-0000-4000-8000-%012d" % count,true,content)
	_count = count
	_dense = dense
	world.facts.display_name = "正式内核基准 %d" % count
	for floor_id: int in FLOORS:
		var plots: Array = []
		for x: int in 3:
			for y: int in 3:
				plots.append([x,y])
		world.facts.floors.overrides[str(floor_id)] = {"plots":plots,"blocked":[],"doors":[]}
	var additional: int = count-world.facts.actors.size()
	for index: int in additional:
		_add_mobile()

func _add_mobile() -> void:
	var index: int = mobile_ids.size()
	var floor_id: int = FLOORS[0] if _dense else FLOORS[index%FLOORS.size()]
	var position_index: int = index if _dense else index/FLOORS.size()
	var columns: int = 24 if _dense else 12
	var spacing: int = 3 if _dense else 4
	var origin: Vector2i = Vector2i(3+(position_index%columns)*spacing,3+(position_index/columns)*spacing)
	var id: String = "mobile_%04d" % index
	world.facts.actors[id] = {"id":id,"name":"基准居民%04d" % index,"species_id":"S49",
		"location":{"kind":"floor","floor_id":floor_id,"cell":[origin.x,origin.y],"height_m":0.0},"facing":0.0,"posture":"standing"}
	mobile_ids.append(id)
	origins[id] = origin

func before_tick(simulation: HospitalSimulation) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var requests: int = 0
	var refused: int = 0
	if not _replacement_added and world.facts.visits.values()[0].phase=="departed":
		_add_mobile()
		world.touch()
		_replacement_added = true
	for id: String in mobile_ids:
		if world.facts.moves.has(id):
			continue
		var actor: Dictionary = world.facts.actors[id]
		var origin: Vector2i = origins[id]
		var x: int = origin.x+1 if roundi(float(actor.location.cell[0]))==origin.x else origin.x
		var reason: String = simulation.space.request_move(world,id,int(actor.location.floor_id),[x,origin.y])
		requests += 1
		if not reason.is_empty():
			refused += 1
	if world.sim_tick%100==0:
		var actor: Dictionary = world.facts.actors.sample_S21
		var x: int = 36 if roundi(float(actor.location.cell[0]))==35 else 35
		var payload: MoveActorPayload = MoveActorPayload.new(actor.id,1,Vector2i(x,65),actor.location)
		simulation.enqueue(GameCommand.new("fixture:%d" % world.sim_tick,world.hospital_id,world.revision,"move_actor",payload).to_record())
	return {"dispatch_usec":Time.get_ticks_usec()-started,"path_requests":requests,"path_refused":refused}

func describe() -> Dictionary:
	return {"fixture":"kernel-mobile-and-surgery-v1","target_present_actors":_count,"actor_records":world.facts.actors.size(),"mobile_actors":mobile_ids.size(),
		"distribution":"dense_mobile_floor" if _dense else "four_mobile_floors",
		"staff":world.facts.staff.size(),"clinical_visits":world.facts.visits.size(),"active_floors":FLOORS,
		"empty_structure_top":10000,"layout":"four actual 96x96 floors plus the stage01 surgical layout",
		"clinical_scope":"one real D23 pathway; additional bodies execute real repeated movement",
		"missing":"multiple simultaneous clinical stations and later daily systems"}
