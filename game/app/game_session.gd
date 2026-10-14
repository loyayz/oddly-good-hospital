class_name GameSession
extends RefCounted

var simulation: HospitalSimulation
var loading_session_id: String
var requested_speed: int = 0
var last_running_speed: int = 1
var running_slow: bool = false
var _pause_tokens: Dictionary = {}
var _watching: bool = false
var _accumulator: float = 0.0
var _skip_next_delta: bool = false

func _init(kernel: HospitalSimulation, session_id: String) -> void:
	simulation = kernel
	loading_session_id = session_id

func actual_speed() -> int:
	if requested_speed==0 or not _pause_tokens.is_empty():
		return 0
	return 1 if _watching else requested_speed

func set_speed(speed: int) -> void:
	requested_speed = clampi(speed,0,3)
	if requested_speed>0:
		last_running_speed = requested_speed
	_watching = false
	_accumulator = 0.0

func pause(source: String) -> void:
	if _pause_tokens.has(source):
		return
	_pause_tokens[source] = true
	_accumulator = 0.0
	_skip_next_delta = true

func resume(source: String) -> void:
	if not _pause_tokens.has(source):
		return
	_pause_tokens.erase(source)
	_accumulator = 0.0
	_skip_next_delta = true

func pause_reasons() -> Array:
	var sources: Array = _pause_tokens.keys()
	sources.sort()
	return sources

func set_watching(enabled: bool) -> void:
	_watching = enabled
	_accumulator = 0.0

func submit(command: GameCommand) -> CommandResult:
	if command.loading_session_id!=loading_session_id:
		return CommandResult.new(false,"session_mismatch","输入属于旧医院会话",[],simulation.world.revision)
	if command.hospital_id!=simulation.world.hospital_id:
		return CommandResult.new(false,"hospital_mismatch","输入属于另一座医院",[],simulation.world.revision)
	var captured: GameCommand = GameCommand.from_record(command.to_record())
	if actual_speed()==0:
		return simulation.apply(captured)
	simulation.enqueue(captured.to_record())
	return CommandResult.new(true,"queued","已接收，等待命令边界",[],simulation.world.revision)

func drain_commands() -> Array[CommandResult]:
	return simulation.drain_commands()

func advance(real_delta: float) -> Array[TickResult]:
	var results: Array[TickResult] = []
	if real_delta>1.0 or _skip_next_delta or actual_speed()==0:
		_skip_next_delta = false
		_accumulator = 0.0
		drain_commands()
		running_slow = false
		return results
	_accumulator += maxf(real_delta,0.0)*actual_speed()
	while _accumulator+0.000000001>=WorldState.TICK_SECONDS and results.size()<8:
		results.append(simulation.step())
		_accumulator = maxf(0.0,_accumulator-WorldState.TICK_SECONDS)
	running_slow = _accumulator>=WorldState.TICK_SECONDS
	return results
