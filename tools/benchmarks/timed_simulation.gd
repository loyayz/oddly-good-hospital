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
var walking_bodies: Array[int] = []
var pending_routes: Array[int] = []
var observer_usec: Array[int] = []
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
	var observe_started: int = Time.get_ticks_usec()
	var before: Dictionary = {}
	if raw!=null:
		for id: String in world.facts.actors:
			var location: Dictionary = world.facts.actors[id].location
			if location.kind=="floor":
				before[id] = Vector3(float(location.cell[0]),float(location.cell[1]),float(location.floor_id))
	var observe_elapsed: int = Time.get_ticks_usec()-observe_started
	var started: int = Time.get_ticks_usec()
	var result: TickResult = super.step(state,commands)
	var elapsed: int = Time.get_ticks_usec()-started
	if raw!=null:
		observe_started = Time.get_ticks_usec()
		var walking: int = 0
		var pending: int = 0
		for id: String in before:
			var location: Dictionary = world.facts.actors[id].location
			if location.kind=="floor" and before[id].z==float(location.floor_id) and Vector2(before[id].x,before[id].y)!=Vector2(float(location.cell[0]),float(location.cell[1])):
				walking += 1
		for movement: Dictionary in world.facts.moves.values():
			pending += int(movement.get("route_pending",false))
		walking_bodies.append(walking)
		pending_routes.append(pending)
		observer_usec.append(observe_elapsed+Time.get_ticks_usec()-observe_started)
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
			"walking_bodies":walking,"pending_routes":pending,
			"sessions":world.facts.sessions.size(),"attempts":world.facts.attempts.size(),"tickets":world.facts.tickets.size()}))
		for row: Dictionary in _command_rows:
			raw.store_line(JSON.stringify(row))
		_command_rows.clear()
	return result
