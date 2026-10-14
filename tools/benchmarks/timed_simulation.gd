extends HospitalSimulation

var fixture: RefCounted
var raw: FileAccess
var step_usec: Array[int] = []
var command_usec: Array[int] = []
var dispatch_usec: Array[int] = []
var path_requests: int = 0
var path_refused: int = 0
var accepted_commands: int = 0
var rejected_commands: int = 0
var min_present: int = 0
var max_present: int = 0
var max_moves: int = 0
var max_sessions: int = 0
var _command_rows: Array[Dictionary] = []

func begin_capture(path: String) -> bool:
	raw = FileAccess.open(path,FileAccess.WRITE)
	min_present = world.present_actor_count()
	max_present = min_present
	_command_rows.clear()
	return raw!=null

func apply(command: GameCommand) -> CommandResult:
	var started: int = Time.get_ticks_usec()
	var result: CommandResult = super.apply(command)
	var elapsed: int = Time.get_ticks_usec()-started
	if raw!=null:
		command_usec.append(elapsed)
		accepted_commands += int(result.accepted)
		rejected_commands += int(not result.accepted)
		_command_rows.append({"kind":"command","real_usec":started,"sim_tick":world.sim_tick,"duration_usec":elapsed,
			"input":command.to_record(),"result":result.to_record()})
	return result

func step(state: WorldState = null, commands: Array[GameCommand] = []) -> TickResult:
	var work: Dictionary = fixture.before_tick(self)
	var started: int = Time.get_ticks_usec()
	var result: TickResult = super.step(state,commands)
	var elapsed: int = Time.get_ticks_usec()-started
	if raw!=null:
		step_usec.append(elapsed)
		dispatch_usec.append(work.dispatch_usec)
		path_requests += int(work.path_requests)
		path_refused += int(work.path_refused)
		var present: int = world.present_actor_count()
		min_present = mini(min_present,present)
		max_present = maxi(max_present,present)
		max_moves = maxi(max_moves,world.facts.moves.size())
		max_sessions = maxi(max_sessions,world.facts.sessions.size())
		raw.store_line(JSON.stringify({"kind":"step","real_usec":started,"sim_tick":result.sim_tick,"duration_usec":elapsed,
			"fixture_dispatch_usec":work.dispatch_usec,"path_requests":work.path_requests,"path_refused":work.path_refused,
			"actors":world.facts.actors.size(),"present_actors":present,"moves":world.facts.moves.size(),
			"sessions":world.facts.sessions.size(),"attempts":world.facts.attempts.size(),"tickets":world.facts.tickets.size()}))
		for row: Dictionary in _command_rows:
			raw.store_line(JSON.stringify(row))
		_command_rows.clear()
	return result
