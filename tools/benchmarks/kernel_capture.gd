extends Node

const Fixture = preload("res://tools/benchmarks/kernel_fixture.gd")
const TimedSimulation = preload("res://tools/benchmarks/timed_simulation.gd")
const ProfileSpace = preload("res://tools/benchmarks/profile_space.gd")
const DisplayProjection = preload("res://tools/benchmarks/display_projection.gd")
var _simulation: TimedSimulation
var _session: GameSession
var _output: String
var _warmup: float = 60.0
var _sample: float = 600.0
var _speed: int = 1
var _actors: int = 160
var _warm_started: int
var _sample_started: int = -1
var _last_frame: int
var _first_tick: int
var _timer_overhead: Dictionary
var _profile: bool = false
var _display: bool = false
var _dense: bool = false
var _window: Vector2i = Vector2i(2560,1440)
var _scene_scale: float = 0.75
var _ui_scale: int = 1
var _projection: DisplayProjection

func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg=="--profile":
			_profile = true
		elif arg=="--display":
			_display = true
		elif arg=="--dense":
			_dense = true
		elif arg.begins_with("--window="):
			var size: String = arg.get_slice("=",1)
			_window = Vector2i(size.get_slice("x",0).to_int(),size.get_slice("x",1).to_int())
		elif arg.begins_with("--scene-scale="):
			_scene_scale = arg.get_slice("=",1).to_float()
		elif arg.begins_with("--ui-scale="):
			_ui_scale = arg.get_slice("=",1).to_int()
		elif arg.begins_with("--actors="):
			_actors = arg.get_slice("=",1).to_int()
		elif arg.begins_with("--speed="):
			_speed = arg.get_slice("=",1).to_int()
		elif arg.begins_with("--warmup="):
			_warmup = arg.get_slice("=",1).to_float()
		elif arg.begins_with("--sample="):
			_sample = arg.get_slice("=",1).to_float()
		elif arg.begins_with("--output="):
			_output = arg.trim_prefix("--output=")
	if _output.is_empty() or not _actors in [160,320,640] or not _speed in [1,3] or _sample<=0 or _warmup<0:
		push_error("Supply output, actors=160/320/640, speed=1/3 and positive capture duration.")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_output)
	var content: HospitalContent = HospitalContent.new()
	var fixture: RefCounted = Fixture.new(_actors,content,_dense)
	var reason: String = fixture.world.validate(content)
	if not content.error.is_empty() or not reason.is_empty():
		push_error(content.error+reason)
		get_tree().quit(2)
		return
	_simulation = TimedSimulation.new(fixture.world,content)
	_simulation.fixture = fixture
	if _profile:
		_simulation.space = ProfileSpace.new(content)
		_simulation.clinic.space = _simulation.space
	_session = GameSession.new(_simulation,"kernel-benchmark")
	_session.set_speed(_speed)
	if _display:
		_projection = DisplayProjection.new(self,content,fixture.world,_window,_scene_scale,_ui_scale,_output)
	_timer_overhead = _measure_timer()
	Engine.max_fps = 60
	_warm_started = Time.get_ticks_usec()
	_last_frame = _warm_started
	_write("capture-start.json",{"engine":Engine.get_version_info(),"debug_build":OS.is_debug_build(),"fixture":fixture.describe(),
		"warmup_real_seconds":_warmup,"sample_real_seconds":_sample,"speed":_speed,"timer_overhead":_timer_overhead,
		"renderer":_projection.describe() if _display else {"mode":"headless","presented_frames":"missing","GPU":"missing"},"started_utc":Time.get_datetime_string_from_system(true)})

func _process(_delta: float) -> void:
	if _simulation==null:
		return
	var now: int = Time.get_ticks_usec()
	if _sample_started<0 and now-_warm_started>=int(_warmup*1000000):
		if not _simulation.begin_capture(_output.path_join("raw.ndjson")):
			get_tree().quit(2)
			return
		_sample_started = now
		_first_tick = _simulation.world.sim_tick
		_last_frame = now
		if _profile:
			_simulation.space.call("reset_profile")
	if _sample_started>=0 and now-_sample_started>=int(_sample*1000000):
		_finish(now)
		return
	_session.advance(float(now-_last_frame)/1000000.0)
	if _projection!=null:
		_projection.update(_simulation.world)
	_last_frame = now

func _finish(now: int) -> void:
	set_process(false)
	var real_seconds: float = float(now-_sample_started)/1000000.0
	var ticks: int = _simulation.world.sim_tick-_first_tick
	var targets: Dictionary = _simulation.content.balance.performance_targets.metrics
	var steps: Dictionary = _statistics(_simulation.step_usec)
	var commands: Dictionary = _statistics(_simulation.command_usec)
	var ratio: float = float(ticks)/(real_seconds*10.0*_speed)
	var formal: bool = not _display and not _profile and not OS.is_debug_build() and _warmup>=60 and _sample>=600
	var final: String = JSON.stringify(_simulation.world.facts,"",true,true)
	_write("final-world.json",_simulation.world.facts)
	_simulation.raw.close()
	var report: Dictionary = {"schema_version":1,"status":"measured" if formal else "diagnostic","formal_capture":formal,
		"debug_build":OS.is_debug_build(),"actors":_actors,"speed":_speed,"fixture":_simulation.fixture.describe(),
		"warmup_real_seconds":float(_sample_started-_warm_started)/1000000.0,"sample_real_seconds":real_seconds,
		"first_tick":_first_tick,"last_tick":_simulation.world.sim_tick,"executed_ticks":ticks,"speed_ratio":ratio,
		"step":steps,"command_boundary":commands,"fixture_dispatch":_statistics(_simulation.dispatch_usec),
		"timer_overhead":_timer_overhead,"path_requests":_simulation.path_requests,"path_refused":_simulation.path_refused,
		"accepted_commands":_simulation.accepted_commands,"rejected_commands":_simulation.rejected_commands,
		"present_actors_range":[_simulation.min_present,_simulation.max_present],"peak_moves":_simulation.max_moves,
		"walking_bodies_per_step":_counts(_simulation.walking_bodies),"pending_routes_per_step":_counts(_simulation.pending_routes),
		"population_observer":_statistics(_simulation.observer_usec),
		"navigation_cache_at_end":{"graphs":_simulation.space._navigation._entries.size(),"capacity_charge_bytes":_simulation.space._navigation._charged,
			"target_bytes":int(_simulation.content.balance.pathfinding.graph_cache_target_bytes),"native_allocation_measured":false},
		"peak_clinical_sessions":_simulation.max_sessions,"actual_attempts":_simulation.world.facts.attempts.size(),
		"clinical_phase":_simulation.world.facts.visits.values()[0].phase,"final_world_sha256":final.sha256_text(),
		"rng_end":_simulation.world.facts.rng.duplicate(true),"targets":targets,
		"passed":formal and steps.get("p95_ms",INF)<=float(targets.sim_step_p95_ms)
			and steps.get("p99_ms",INF)<=float(targets.sim_step_p99_ms)
			and steps.get("max_ms",INF)<=float(targets.sim_step_ordinary_max_ms) and ratio>=float(targets.sim_speed_ratio_min),
		"missing_metrics":["presented_frames","GPU","graphics_resources","save_restore","full_daily_systems","multiple_clinical_stations"],
		"measurement_scope":"complete production Simulation.step; fixture dispatch and raw logging are separate, all contribute to real throughput"}
	if _profile:
		report.diagnostic_profile = _simulation.space.profile()
	_write("summary.json",report)
	print("KERNEL_CAPTURE="+_output)
	get_tree().quit(0 if not formal or report.passed else 1)

func _write(name: String, value: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(_output.path_join(name),FileAccess.WRITE)
	file.store_string(JSON.stringify(value,"\t",true,true))

static func _statistics(values: Array) -> Dictionary:
	if values.is_empty():
		return {"count":0,"status":"missing"}
	var sorted: Array = values.duplicate()
	sorted.sort()
	var total: int = 0
	for value: int in sorted:
		total += value
	return {"count":sorted.size(),"mean_ms":float(total)/sorted.size()/1000.0,"p50_ms":float(sorted[ceili(sorted.size()*0.5)-1])/1000.0,
		"p95_ms":float(sorted[ceili(sorted.size()*0.95)-1])/1000.0,"p99_ms":float(sorted[ceili(sorted.size()*0.99)-1])/1000.0,
		"max_ms":float(sorted[-1])/1000.0}

static func _measure_timer() -> Dictionary:
	var values: Array[int] = []
	for index: int in 10000:
		var started: int = Time.get_ticks_usec()
		values.append(Time.get_ticks_usec()-started)
	return _statistics(values)

static func _counts(values: Array[int]) -> Dictionary:
	if values.is_empty():
		return {"status":"missing"}
	var sorted: Array[int] = values.duplicate()
	sorted.sort()
	var total: int = 0
	for value: int in sorted:
		total += value
	return {"count":values.size(),"min":sorted[0],"p05":sorted[ceili(sorted.size()*0.05)-1],"p50":sorted[ceili(sorted.size()*0.5)-1],"p95":sorted[ceili(sorted.size()*0.95)-1],"max":sorted[-1],"mean":float(total)/values.size()}
