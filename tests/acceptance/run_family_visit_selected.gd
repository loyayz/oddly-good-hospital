extends SceneTree

# Functional inputs only. Never reads or rewrites mixed160 input/seed.
class SelectedFamily extends "res://tests/acceptance/inpatient_family.gd":
	var output_directory: String
	var artifacts: Array=[]
	var probability_inputs: Array=[]
	var source_saved: bool=false
	var sequence: int=0

	func _save_boundary(label: String, payload: Dictionary) -> void:
		sequence+=1
		var path: String=output_directory.path_join("%02d-%s.bin"%[sequence,label])
		assert(not FileAccess.file_exists(path),"Preserve earlier family evidence")
		var file: FileAccess=FileAccess.open(path,FileAccess.WRITE)
		assert(file!=null)
		file.store_var(payload,false)
		file.close()
		artifacts.append({"boundary":label,"path":path,"sha256":FileAccess.get_sha256(path),"bytes":FileAccess.get_file_as_bytes(path).size()})

	func _source(t) -> Dictionary:
		var result: Dictionary=await super._source(t)
		if not result.is_empty() and not source_saved:
			source_saved=true
			_save_boundary("before-admission",result.duplicate(true))
		return result

	func _exact_input(world: WorldState, stream: String, value: int) -> void:
		var before_facts: Dictionary=world.freeze()
		var before: Dictionary=world.facts.rng[stream].duplicate(true)
		super._exact_input(world,stream,value)
		probability_inputs.append({"stream":stream,"requested_draw":value,"tick":world.sim_tick,"before":before,"after":world.facts.rng[stream].duplicate(true),"scope":"Explicit dedicated functional probability boundary, not original mixed160 RNG or a naturally observed lottery"})
		# Save both complete sides of every explicit functional declaration.
		# No draw, request, admission or arrival is supplied by this capture.
		var label: String="before-daily-intent" if stream=="arrival" and value==2999 else "functional-rng-input"
		_save_boundary(label,{"before_facts":before_facts,"facts":world.freeze(),"content_identity":_content.snapshot_identity().duplicate(true),"engine":Engine.get_version_info().get("string",""),"tick":world.sim_tick,"validation":world.validate(_content),"input_boundary":probability_inputs.back().duplicate(true),"source":"Existing inpatient_family._exact_input functional declaration, before subsequent production ticks"})

	func _remember_source(name: String, c: Dictionary, generation_ms: int, extras: Dictionary={}) -> void:
		super._remember_source(name,c,generation_ms,extras)
		var saved: Dictionary=_named_sources[name].duplicate(true)
		_save_boundary("real-family-boundary",saved)

var selected: Array=[]
var rows: Array=[]
var errors: Array=[]
var preparations: Array=[]
var case_starts: Dictionary={}

func _initialize() -> void:
	call_deferred("_run")

func wants(id: String) -> bool:
	return id in selected

func begin_case(id: String) -> void:
	case_starts[id]=Time.get_ticks_usec()

func preparation_elapsed(started_ms: int) -> void:
	preparations.append({"wall_ms":Time.get_ticks_msec()-started_ms,"scope":"Existing suite reported preparation/read interval; nested intervals must not be summed as independent total"})

func check(id: String, passed: bool, details: Dictionary={}) -> void:
	rows.append({"case":id,"ok":passed,"wall_us":Time.get_ticks_usec()-int(case_starts.get(id,Time.get_ticks_usec())),"details":details})
	if not passed: errors.append(id)

func _run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=2:
		push_error("Expected output.json and comma-separated FAMILY-06,FAMILY-12")
		quit(2);return
	for id: String in args[1].split(","):
		if not id in ["FAMILY-06","FAMILY-12"] or id in selected:
			push_error("Unsupported or duplicate selected family case")
			quit(2);return
		selected.append(id)
	if selected.is_empty() or FileAccess.file_exists(args[0]):
		push_error("Require selected cases and a fresh output path")
		quit(2);return
	var directory: String=args[0].get_base_dir()
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))!=OK:
		quit(2);return
	var content: HospitalContent=HospitalContent.new()
	var suite:=SelectedFamily.new()
	suite.output_directory=directory
	var started: int=Time.get_ticks_usec()
	await suite.run(self,content,selected)
	if rows.size()!=selected.size(): errors.append("selected_case_result_count")
	var output: Dictionary={"ok":errors.is_empty(),"selected":selected,"rows":rows,"errors":errors,"artifacts":suite.artifacts,"probability_inputs":suite.probability_inputs,"preparation_intervals":preparations,"wall_us":Time.get_ticks_usec()-started,"scope":"Selected functional FAMILY-06/12, existing ClinicalStep/production family owners. Not mixed160, full simulation performance, probability-rate evidence, or medical interruption coverage."}
	var file: FileAccess=FileAccess.open(args[0],FileAccess.WRITE)
	assert(file!=null)
	file.store_string(JSON.stringify(output,"\t"));file.close()
	print("FAMILY_VISIT_SELECTED "+str(errors.is_empty()))
	quit(0 if errors.is_empty() else 1)
