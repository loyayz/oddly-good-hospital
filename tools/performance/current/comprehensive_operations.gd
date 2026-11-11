extends RefCounted

# Only commands are submitted here. The measured production step owns dispatch,
# travel, attendance, reservations, payments and every unit of actual work.
const PREFIX: String = "comprehensive160-v2-"
const STUDENT: String = "bench_staff_0015"
const RESEARCHER: String = "bench_staff_0011"
const CLEANERS: Array = ["bench_staff_0028","bench_staff_0029","bench_staff_0030","bench_staff_0031"]
const RESEARCH_DESK: String = "comprehensive_research_desk"
const TRAINING_DESK: String = "comprehensive_training_desk"
const MAINTENANCE_ITEM: String = "bench_room_2_12_0"
const UPGRADE_ITEM: String = "bench_room_2_15_0"
var submitted: Dictionary = {}

func enqueue(sim: HospitalSimulation, measured_index: int) -> void:
	if measured_index<0: return
	var world: WorldState = sim.world
	if not submitted.has("schedule"):
		var shift: int=sim.clinic.scheduler.shift_index(world)
		var schedule: Array = world.facts.staff[STUDENT].schedule.duplicate(true)
		schedule[shift] = {"kind":"training","pools":[],"locked":false}
		var changes: Array=[{"staff_id":STUDENT,"schedule":schedule}]
		for id: String in CLEANERS:
			var cleaning_schedule: Array=world.facts.staff[id].schedule.duplicate(true)
			cleaning_schedule[shift]={"kind":"work","pools":[],"locked":false}
			changes.append({"staff_id":id,"schedule":cleaning_schedule})
		_send(sim,"schedule","apply_schedule",{"id":PREFIX+"schedule","basis":sim.clinic.scheduler._basis(world),"changes":changes})
		var training_quote: Dictionary=sim.services.development.preview(world,STUDENT,"treatment","course")
		_send(sim,"training","train_staff",{"staff_id":STUDENT,"track":"treatment","desk_id":TRAINING_DESK,"confirmed_quote":training_quote.get("basis",{})})
		_send(sim,"maintenance","maintenance_order",{"facility_id":MAINTENANCE_ITEM})
		_send(sim,"upgrade","machine_upgrade",{"facility_id":UPGRADE_ITEM,"target_level":1})
		_send(sim,"renovation","renovation_order",{"material_id":"MAT01","floor_id":1,"units":[{"cell":[42,87]},{"cell":[44,87]},{"cell":[46,87]},{"cell":[48,87]}],"allow_waiting":false})
		_send(sim,"purchase","purchase_supplies",{"units":20,"order_id":PREFIX+"purchase-order"})
	if not submitted.has("research") and sim.services.research.opened(world):
		for definition: Dictionary in sim.content.catalog.research:
			if not definition.id in world.facts.research and definition.disease_ids.is_empty():
				var quote: Dictionary=sim.services.research.preview(world,definition.id,RESEARCH_DESK,false,RESEARCHER)
				_send(sim,"research","research_start",{"research_id":definition.id,"desk_id":RESEARCH_DESK,"worker_id":RESEARCHER,"allow_waiting":true,"confirmed_quote":quote.get("basis",{})})
				break

func _send(sim: HospitalSimulation, key: String, kind: String, payload: Dictionary) -> void:
	if submitted.has(key): return
	var command: Dictionary = {"id":PREFIX+key,"hospital_id":sim.world.hospital_id,"expected_revision":sim.world.revision,"kind":kind,"typed_payload":payload,"loading_session_id":"comprehensive160"}
	submitted[key] = command.duplicate(true)
	sim.enqueue(command)
