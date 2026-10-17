class_name GameSession
extends RefCounted

signal tick_completed(result: TickResult)
signal playback_changed()

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
	if int(simulation.world.facts.get("gameplay_version",0))==1:
		simulation.services.arrivals.enable_preparation(simulation.world)

func actual_speed() -> int:
	if requested_speed==0 or not _pause_tokens.is_empty():
		return 0
	return 1 if _watching else requested_speed

func interpolation_alpha() -> float:
	return 1.0 if actual_speed()==0 else clampf(_accumulator/WorldState.TICK_SECONDS,0.0,1.0)

func set_speed(speed: int) -> void:
	requested_speed = clampi(speed,0,3)
	if requested_speed>0:
		last_running_speed = requested_speed
	_watching = false
	_accumulator = 0.0
	playback_changed.emit()

func pause(source: String) -> void:
	if _pause_tokens.has(source):
		return
	_pause_tokens[source] = true
	_accumulator = 0.0
	_skip_next_delta = true
	playback_changed.emit()

func resume(source: String) -> void:
	if not _pause_tokens.has(source):
		return
	_pause_tokens.erase(source)
	_accumulator = 0.0
	_skip_next_delta = true
	playback_changed.emit()

func pause_reasons() -> Array:
	var sources: Array = _pause_tokens.keys()
	sources.sort()
	return sources

func set_watching(enabled: bool) -> void:
	_watching = enabled
	_accumulator = 0.0
	playback_changed.emit()

func submit(command: GameCommand) -> CommandResult:
	if command.loading_session_id!=loading_session_id:
		return CommandResult.new(false,"session_mismatch","输入属于旧医院会话",[],simulation.world.revision)
	if command.hospital_id!=simulation.world.hospital_id:
		return CommandResult.new(false,"hospital_mismatch","输入属于另一座医院",[],simulation.world.revision)
	var captured: GameCommand = GameCommand.from_record(command.to_record())
	if actual_speed()==0:
		if not simulation.pending() and not simulation.saving_boundary():
			var hold: bool = captured.kind=="arrivals_scale" and captured.typed_payload is BusinessPayload and captured.typed_payload.to_record().get("mode","")=="hold_capacity"
			if not hold or not simulation.receipt(captured.id).is_empty(): return simulation.apply(captured)
		simulation.enqueue(captured.to_record())
		if not simulation.pending() and not simulation.saving_boundary(): simulation.drain_commands()
		var applied: Dictionary = simulation.receipt(captured.id)
		if not applied.is_empty(): return CommandResult.from_record(applied)
		return CommandResult.new(true,"queued","已接收，等待命令边界",[],simulation.world.revision)
	simulation.enqueue(captured.to_record())
	return CommandResult.new(true,"queued","已接收，等待命令边界",[],simulation.world.revision)

func drain_commands() -> Array[CommandResult]:
	return simulation.drain_commands()

func advance(real_delta: float) -> Array[TickResult]:
	var results: Array[TickResult] = []
	# A started step finishes even after pause/focus/save intent. Waiting never
	# accumulates elapsed frame deltas for a later burst of simulation ticks.
	if simulation.step_in_progress():
		var resumed: TickResult = simulation.step_nonblocking()
		_accumulator = 0.0
		if resumed!=null:
			results.append(resumed)
			tick_completed.emit(resumed)
			if not simulation.saving_boundary(): simulation.services.arrivals.prepare_next_day(simulation.world)
		running_slow = resumed==null
		return results
	if simulation.saving_boundary():
		simulation.save_boundary_ready()
		_accumulator = 0.0
		return results
	if real_delta>1.0 or _skip_next_delta or actual_speed()==0:
		_skip_next_delta = false
		_accumulator = 0.0
		drain_commands()
		running_slow = false
		return results
	_accumulator += maxf(real_delta,0.0)*actual_speed()
	while _accumulator+0.000000001>=WorldState.TICK_SECONDS and results.size()<8:
		var result: TickResult = simulation.step_nonblocking()
		_accumulator = maxf(0.0,_accumulator-WorldState.TICK_SECONDS)
		if result==null:
			_accumulator = 0.0
			break
		results.append(result)
		tick_completed.emit(result)
		if int(simulation.world.facts.get("gameplay_version",0))==1: simulation.services.arrivals.prepare_next_day(simulation.world)
	running_slow = simulation.pending() or _accumulator>=WorldState.TICK_SECONDS
	return results
