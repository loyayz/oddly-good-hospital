class_name HospitalSimulation
extends RefCounted

var world: HospitalWorld
var content: HospitalContent
var space: HospitalSpace
var clinic: HospitalClinic
var _commands: Array[Dictionary] = []

func _init(state: HospitalWorld, database: HospitalContent) -> void:
	world = state
	content = database
	space = HospitalSpace.new(database)
	clinic = HospitalClinic.new(database,space)

func enqueue(command: Dictionary) -> void:
	_commands.append(command.duplicate(true))

func drain_commands() -> void:
	for command: Dictionary in _commands:
		if command.hospital_id != world.facts.hospital_id or world.facts.command_receipts.has(command.id):
			continue
		var reason: String = "未知命令"
		if command.kind == "move_actor" and world.facts.actors.has(command.actor_id):
			if world.facts.staff.has(command.actor_id) or _is_patient(command.actor_id):
				reason = "当前临床人物按实际工作路线移动"
			elif world.facts.moves.has(command.actor_id):
				reason = "当前通行尚未完成，原移动请求保留"
			else:
				reason = space.request_move(world,command.actor_id,int(command.floor_id),command.cell)
		world.facts.command_receipts[command.id] = {"accepted":reason.is_empty(),"reason":reason,"tick":world.facts.sim_tick}
		world.touch()
	_commands.clear()

func step() -> void:
	# One ordered fixed step; systems join their original phase as later stages arrive.
	drain_commands() # 1: accepted player commands
	# 2: topology, schedules and equipment scans
	# 3: opportunities (the feasibility fixtures already contain their arrived visit)
	clinic.dispatch(world) # 4: actors and clinical dispatch
	var before_movement: Dictionary = {}
	for staff_id: String in world.ids("staff"):
		before_movement[staff_id] = world.facts.actors[staff_id].location.duplicate(true)
	space.advance(world) # 5: actual movement and vertical transit
	clinic.advance(world) # 6: actual work and completion
	_integrate_staff(before_movement) # 7: actual work and movement for this step
	# 8: interactions and event consequences
	clinic.release_departed(world) # 9: occupancy after physical handoff/departure
	clinic.settle_practice(world)
	world.settle_ledger()
	world.facts.sim_tick += 1
	world.touch() # 10: complete snapshot boundary

func _is_patient(actor_id: String) -> bool:
	for visit: Dictionary in world.facts.visits.values():
		if visit.actor_id == actor_id:
			return true
	return false

func _integrate_staff(before_movement: Dictionary) -> void:
	var worked: Dictionary = clinic.worked_staff()
	var rates: Dictionary = content.balance.wellbeing
	for staff_id: String in world.ids("staff"):
		var staff: Dictionary = world.facts.staff[staff_id]
		var moved: bool = before_movement[staff_id] != world.facts.actors[staff_id].location
		if worked.has(staff_id):
			staff.energy = maxf(0.0,float(staff.energy)-float(rates.energy_work_per_second)*HospitalWorld.TICK_SECONDS)
			staff.stress_milli = mini(100000,int(staff.stress_milli)+roundi(float(rates.stress_work_per_second)*1000*HospitalWorld.TICK_SECONDS))
			if staff.role == "doctor":
				staff.fatigue = minf(100.0,float(staff.fatigue)+float(rates.fatigue_work_per_second)*HospitalWorld.TICK_SECONDS)
		elif moved:
			staff.energy = maxf(0.0,float(staff.energy)-float(rates.energy_walk_per_second)*HospitalWorld.TICK_SECONDS)
