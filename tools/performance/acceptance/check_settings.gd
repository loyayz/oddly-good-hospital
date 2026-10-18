extends SceneTree

# Standalone capture-tool contract check. No application or capture Node enters
# the tree, and no display, simulation, rendering or performance run is started.
class MockCapture:
	extends "visible_capture.gd"

	var actual: Dictionary = {}
	var rejected: Array[String] = []

	func _settings() -> Dictionary:
		return actual

	func _fail(reason: String) -> void:
		rejected.append(reason)

var failures: Array[Dictionary] = []
var checks: int = 0

func _initialize() -> void:
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(_config()))
	_check("json-float-request-int-display", typeof(parsed.window_pixels[0])==TYPE_FLOAT and typeof(_actual().window_pixels[0])==TYPE_INT and _accepted(parsed))
	_check("native-int-request-int-display", _accepted(_config()))
	for mismatch: Dictionary in [
		{"name":"wrong-window-width","key":"window_pixels","value":[2559,1440]},
		{"name":"wrong-window-height","key":"window_pixels","value":[2560,1439]},
		{"name":"wrong-scene-scale","key":"scene_scale","value":1.0},
		{"name":"wrong-ui-scale","key":"ui_scale_percent","value":200},
		{"name":"wrong-renderer","key":"renderer","value":"forward_plus"},
		{"name":"non-native-2d-output","key":"native_2d_output","value":false},
		{"name":"scene-texture-size-mismatch","key":"scene_output_matches_control","value":false},
	]:
		var capture := MockCapture.new()
		capture.config = parsed.duplicate(true)
		capture.actual = _actual()
		capture.actual[mismatch.key] = mismatch.value
		var valid: bool = capture._validate_config().is_empty()
		var accepted: bool = capture._verify_settings() if valid else true
		_check(str(mismatch.name), valid and not accepted and capture.rejected.size()==1)
		capture.free()
	for invalid: Dictionary in [
		{"name":"fractional-window","value":JSON.parse_string("[2560.25,1440]")},
		{"name":"text-window","value":JSON.parse_string("[\"2560\",1440]")},
		{"name":"boolean-window","value":JSON.parse_string("[true,1440]")},
		{"name":"null-window","value":JSON.parse_string("[null,1440]")},
		{"name":"infinite-window","value":[INF,1440]},
		{"name":"negative-infinite-window","value":[-INF,1440]},
		{"name":"nan-window","value":[NAN,1440]},
		{"name":"zero-window","value":[0,1440]},
		{"name":"negative-window","value":[2560,-1440]},
		{"name":"missing-window-dimension","value":[2560]},
		{"name":"non-array-window","value":"2560x1440"},
	]:
		var capture := MockCapture.new()
		capture.config = parsed.duplicate(true)
		capture.config.window_pixels = invalid.value
		var reason: String = capture._validate_config()
		_check(str(invalid.name), not reason.is_empty() and "window_pixels" in reason)
		capture.free()
	print(JSON.stringify({"ok":failures.is_empty(),"checks":checks,"failures":failures,"scope":"capture settings tool only; no game or performance acceptance"}))
	quit(0 if failures.is_empty() else 1)

func _accepted(requested: Dictionary) -> bool:
	var capture := MockCapture.new()
	capture.config = requested.duplicate(true)
	capture.actual = _actual()
	var valid: bool = capture._validate_config().is_empty()
	var accepted: bool = capture._verify_settings() if valid else false
	var result: bool = valid and accepted and capture.rejected.is_empty()
	capture.free()
	return result

func _check(name: String, passed: bool) -> void:
	checks += 1
	if not passed: failures.append({"check":name})

func _config() -> Dictionary:
	return {"output_dir":ProjectSettings.globalize_path("res://.cache/check-settings"),"input_path":ProjectSettings.globalize_path("res://.cache/check-settings/input.bin"),"run_id":"settings-contract","actors":160,"layout":"four_floors","floor_id":1,"window_pixels":[2560,1440],"scene_scale_bp":7500,"ui_scale_percent":100,"speed":1,"minimum_frame_samples":1000,"minimum_step_samples":1000,"operations":[]}

func _actual() -> Dictionary:
	return {"window_pixels":[2560,1440],"scene_scale":0.75,"ui_scale_percent":100,"renderer":"gl_compatibility","render_driver":"opengl3","native_2d_output":true,"scene_output_matches_control":true}
