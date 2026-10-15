class_name HospitalSimulation
extends RefCounted

const PHASES: Array[String] = ["commands","boundaries","arrivals","dispatch","movement","work","needs","interactions","settlement","snapshot"]

var world: WorldState
var content: HospitalContent
var space: HospitalSpace
var clinic: HospitalClinic
var _commands: Array[GameCommand] = []
var _rejected: Dictionary = {}
var _command_events: Array[SimEvent] = []

func _init(state: WorldState, database: HospitalContent) -> void:
	world = state
	content = database
	space = HospitalSpace.new(database)
	clinic = HospitalClinic.new(database,space)

func enqueue(command: Dictionary) -> void:
	_commands.append(GameCommand.from_record(command))

func drain_commands() -> Array[CommandResult]:
	var results: Array[CommandResult] = []
	for command: GameCommand in _commands:
		results.append(apply(command))
	_commands.clear()
	return results

func receipt(command_id: String) -> Dictionary:
	return world.facts.command_receipts.get(command_id,_rejected.get(command_id,{})).duplicate(true)

func apply(command: GameCommand) -> CommandResult:
	if command.hospital_id!=world.hospital_id:
		return CommandResult.new(false,"hospital_mismatch","命令属于另一座医院",[],world.revision)
	if command.id.is_empty():
		return CommandResult.new(false,"invalid_command","命令缺少稳定身份",[],world.revision)
	var original: Dictionary = receipt(command.id)
	if not original.is_empty():
		if original.has("command") and original.command!=command.identity():
			return CommandResult.new(false,"command_id_conflict","同一命令ID的已确认内容不同",[],world.revision)
		var previous: CommandResult = CommandResult.from_record(original)
		if not original.has("new_revision"):
			previous.new_revision = world.revision
		return previous
	var result: CommandResult = _execute(command)
	var record: Dictionary = result.to_record()
	record.tick = world.sim_tick
	record.command = command.identity()
	if result.accepted:
		world.touch()
		result.new_revision = world.revision
		record.new_revision = world.revision
		world.facts.command_receipts[command.id] = record
		_command_events.append(SimEvent.new(world.sim_tick,"command_applied",result.changed_ids,{"command_id":command.id,"command":command.to_record()}))
	else:
		_rejected[command.id] = record
		_command_events.append(SimEvent.new(world.sim_tick,"command_rejected",[],{"command_id":command.id,"result":record}))
	return result

func _execute(command: GameCommand) -> CommandResult:
	if command.kind!="move_actor":
		return CommandResult.new(false,"unknown_command","未知命令类型",[],world.revision)
	if not command.typed_payload is MoveActorPayload:
		return CommandResult.new(false,"invalid_payload","移动命令缺少有效的已确认目标",[],world.revision)
	var payload: MoveActorPayload = command.typed_payload
	if not world.facts.actors.has(payload.actor_id):
		return CommandResult.new(false,"actor_missing","原人物已不存在",[],world.revision)
	var actor: Dictionary = world.facts.actors[payload.actor_id]
	if not payload.confirmed_location.is_empty() and actor.location!=payload.confirmed_location:
		return CommandResult.new(false,"material_change","人物位置已改变，原目标保留供刷新",[],world.revision)
	if world.facts.staff.has(payload.actor_id) or _is_patient(payload.actor_id):
		return CommandResult.new(false,"clinical_occupancy","当前临床人物按实际工作路线移动",[],world.revision)
	if world.facts.moves.has(payload.actor_id):
		return CommandResult.new(false,"movement_in_progress","当前通行尚未完成，原移动请求保留",[],world.revision)
	if payload.floor_id<1 or not world.facts.floors.overrides.has(str(payload.floor_id)):
		return CommandResult.new(false,"floor_unavailable","目标楼层没有可用通行布局",[],world.revision)
	var quote: Dictionary = space.route(world,payload.actor_id,payload.floor_id,[payload.cell.x,payload.cell.y])
	if not quote.ok:
		return CommandResult.new(false,"route_unavailable",quote.reason,[],world.revision)
	var reason: String = space.request_move(world,payload.actor_id,payload.floor_id,[payload.cell.x,payload.cell.y])
	return CommandResult.new(reason.is_empty(),"applied" if reason.is_empty() else "route_unavailable",reason,[payload.actor_id] if reason.is_empty() else [],world.revision)

func step(state: WorldState = null, commands: Array[GameCommand] = []) -> TickResult:
	if state!=null:
		world = state
	var present_at_start: int = world.present_actor_count()
	for command: GameCommand in commands:
		_commands.append(GameCommand.from_record(command.to_record()))
	drain_commands() # 1: player commands; future automatic purchasing joins here.
	# 2: topology, schedules and equipment boundaries.
	# 3: day plans and arrivals; existing fixtures contain their arrived visits.
	clinic.dispatch(world) # 4: actors and clinical dispatch.
	var before_movement: Dictionary = {}
	for staff_id: String in world.ids("staff"):
		before_movement[staff_id] = world.facts.actors[staff_id].location.duplicate(true)
	space.advance(world,present_at_start) # 5: path FIFO, actual movement and vertical transit.
	clinic.advance(world) # 6: work and safe completion.
	_integrate_staff(before_movement) # 7: integrate actual work and movement.
	# 8: future interactions and event consequences.
	clinic.release_departed(world) # 9: occupancy after physical handoff/departure.
	clinic.settle_practice(world)
	var events: Array[SimEvent] = _command_events
	_command_events = []
	events.append_array(clinic.take_events())
	events.append_array(HospitalLedger.settle(world))
	world.facts.sim_tick += 1
	world.touch() # 10: complete snapshot boundary.
	space.finish_boundary(world)
	events.append(SimEvent.new(world.sim_tick,"tick_completed",[],{"revision":world.revision}))
	return TickResult.new(world.sim_tick,world.revision,events)

func take_command_events() -> Array[SimEvent]:
	var events: Array[SimEvent] = _command_events
	_command_events = []
	return events

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
			staff.energy = maxf(0.0,float(staff.energy)-float(rates.energy_work_per_second)*WorldState.TICK_SECONDS)
			staff.stress_milli = mini(100000,int(staff.stress_milli)+roundi(float(rates.stress_work_per_second)*1000*WorldState.TICK_SECONDS))
			if staff.role == "doctor":
				staff.fatigue = minf(100.0,float(staff.fatigue)+float(rates.fatigue_work_per_second)*WorldState.TICK_SECONDS)
		elif moved:
			staff.energy = maxf(0.0,float(staff.energy)-float(rates.energy_walk_per_second)*WorldState.TICK_SECONDS)
