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
	var content_script: Script = ResourceLoader.load("res://game/content/content_db.gd")
	var content: RefCounted = content_script.new() if content_script!=null else null
	var content_error: String = str(content.error) if content!=null else "Content script unavailable"
	valid = valid and content_error.is_empty()
	loaded["HospitalContent.initialized"] = {"error":content_error,"fingerprint":str(content.content_fingerprint) if content!=null else "","locale_csv_sha256":FileAccess.get_sha256("res://content/core/locale/zh_CN.csv")}
	var resources: Dictionary = _production_resources()
	loaded["ViewResources.production_assets"] = resources
	valid = valid and resources.valid
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

func _production_resources() -> Dictionary:
	var script: Script = ResourceLoader.load("res://game/view/view_resources.gd")
	if script==null:
		return {"valid":false,"error":"ViewResources unavailable"}
	var owner = script.new()
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(owner.MANIFEST))
	if not manifest is Dictionary or not manifest.get("assets") is Array or manifest.assets.is_empty():
		return {"valid":false,"error":"Published asset manifest unavailable"}
	var valid: bool = owner.errors.is_empty()
	var records: Array = []
	for definition: Dictionary in manifest.assets:
		var path: String = "res://"+str(definition.asset_path)
		var actual_hash: String = FileAccess.get_sha256(path)
		var actual_bytes: int = FileAccess.get_file_as_bytes(path).size()
		var node: Node3D = owner.acquire(path)
		var accepted: bool = node!=null and actual_hash==definition.asset_sha256 and actual_bytes==int(definition.bytes)
		records.append({"path":path,"source_sha256":actual_hash,"expected_sha256":definition.asset_sha256,"source_bytes":actual_bytes,"expected_bytes":int(definition.bytes),"original_owner_acquired_and_validated":node!=null,"valid":accepted})
		valid = valid and accepted
		if node!=null:
			owner.release_tree(node)
			node.free()
	var released: Dictionary = owner.usage()
	valid = valid and owner.errors.is_empty() and released.shared_scenes==0 and released.instance_users==0
	var first: String = "res://"+str(manifest.assets[0].asset_path)
	var invalid_hash = script.new()
	invalid_hash._definitions[first].asset_sha256 = "0".repeat(64)
	var rejected: Node3D = invalid_hash.acquire(first)
	var atomic_rejection: bool = rejected==null and invalid_hash._entries.is_empty() and invalid_hash.usage().instance_users==0 and invalid_hash.errors.size()==1
	if rejected!=null:
		invalid_hash.release_tree(rejected)
		rejected.free()
	return {"valid":valid and atomic_rejection,"assets":records,"released":released,"hash_rejection_atomic":atomic_rejection,"scope":"published source identity and original remapped scene validation; no timing, GPU allocation or residency claim"}
