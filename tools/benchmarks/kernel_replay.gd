extends SceneTree

const Fixture = preload("res://tools/benchmarks/kernel_fixture.gd")
var _actors: int = 160
var _ticks: int = 80
var _output: String = ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--actors="):
			_actors = argument.get_slice("=",1).to_int()
		elif argument.begins_with("--ticks="):
			_ticks = argument.get_slice("=",1).to_int()
		elif argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
	call_deferred("_run")

func _run() -> void:
	if _output.is_empty() or not _actors in [160,320,640] or _ticks<0:
		quit(2)
		return
	var content: HospitalContent = HospitalContent.new()
	var fixture: RefCounted = Fixture.new(_actors,content)
	var simulation: HospitalSimulation = HospitalSimulation.new(fixture.world,content)
	for index: int in _ticks:
		fixture.before_tick(simulation)
		simulation.step()
	var file: FileAccess = FileAccess.open(_output,FileAccess.WRITE)
	if file==null:
		quit(2)
		return
	file.store_string(JSON.stringify({"actors":_actors,"sim_tick":fixture.world.sim_tick,"facts_sha256":JSON.stringify(fixture.world.facts,"",true,true).sha256_text(),
		"rng_end":fixture.world.facts.rng,"world":fixture.world.freeze()},"\t",true,true))
	quit(0)
