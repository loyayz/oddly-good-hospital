extends Node

# Launch only with the exported executable and its matching original PCK.
# This probe does not instantiate AppRoot or open the player's data library.
func _ready() -> void:
	var out: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): out = argument.trim_prefix("--output=")
	var paths: Array[String] = ["res://game/app/main.tscn", "res://game/app/app_root.gd", "res://game/app/game_session.gd", "res://game/sim/world_state.gd", "res://game/sim/types/tick_result.gd", "res://game/content/content_db.gd"]
	var loaded: Dictionary = {}
	var valid: bool = OS.has_feature("template") and OS.has_feature("release") and not OS.has_feature("editor") and not OS.has_feature("debug")
	for path: String in paths:
		var resource: Resource = ResourceLoader.load(path)
		loaded[path] = resource != null
		valid = valid and resource != null
	for name: String in ["PlatformSessionGuard", "PlatformSQLite", "PlatformArrivalMath"]:
		loaded[name] = ClassDB.class_exists(name)
		valid = valid and bool(loaded[name])
	var has_tick_signal: bool = false
	var session_script: Script = ResourceLoader.load("res://game/app/game_session.gd")
	if session_script!=null:
		for declared: Dictionary in session_script.get_script_signal_list():
			if str(declared.name)=="tick_completed": has_tick_signal = true
	loaded["GameSession.tick_completed"] = has_tick_signal
	valid = valid and has_tick_signal
	var tick_script: Script = ResourceLoader.load("res://game/sim/types/tick_result.gd")
	var tick_fields: Dictionary = {}
	if tick_script!=null:
		for property: Dictionary in tick_script.get_script_property_list(): tick_fields[str(property.name)] = true
	for name: String in ["elapsed_us", "main_elapsed_us", "started_engine_us", "completed_engine_us"]:
		loaded["TickResult."+name] = tick_fields.has(name)
		valid = valid and tick_fields.has(name)
	var clock_api: Script = ResourceLoader.load(get_script().resource_path.get_base_dir().path_join("native_clock.gd"))
	var method_available: bool = clock_api!=null and clock_api.available()
	var first_clock: Dictionary = clock_api.read() if method_available else {}
	var second_clock: Dictionary = clock_api.read() if method_available else {}
	var has_clock: bool = first_clock.get("qpc_ticks")!=null and second_clock.get("qpc_ticks")!=null and int(first_clock.get("qpc_frequency", 0))>0 and first_clock.get("qpc_frequency")==second_clock.get("qpc_frequency") and int(first_clock.get("qpc_ticks", -1))<=int(second_clock.get("qpc_ticks", -1))
	loaded["PlatformArrivalMath.monotonic_clock"] = {"available":has_clock,"first":first_clock,"second":second_clock}
	valid = valid and has_clock
	var result: Dictionary = {"valid":valid,"engine":Engine.get_version_info(),"executable":OS.get_executable_path(),"features":{"template":OS.has_feature("template"),"release":OS.has_feature("release"),"debug":OS.has_feature("debug"),"editor":OS.has_feature("editor")},"disable_project_settings_override":ProjectSettings.get_setting("application/config/disable_project_settings_override",false),"loaded":loaded,"external_script":get_script().resource_path,"external_script_sha256":FileAccess.get_sha256(get_script().resource_path),"renderer":RenderingServer.get_current_rendering_method(),"display_server":DisplayServer.get_name(),"global_classes":ProjectSettings.get_global_class_list().size()}
	if not out.is_empty():
		var file: FileAccess = FileAccess.open(out, FileAccess.WRITE)
		if file == null:
			valid = false
			result.valid = false
		else:
			file.store_string(JSON.stringify(result, "\t"))
			file.close()
	print("FORMAL_EXPORT_PROBE="+JSON.stringify(result))
	get_tree().quit(0 if valid else 2)
