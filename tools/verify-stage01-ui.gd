extends SceneTree

var _app: Control
var _results: Dictionary = {}
var _failures: Array[String] = []
var _output: String

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not "Stage01 验收 UI" in OS.get_user_data_dir() or DisplayServer.get_name()=="headless":
		push_error("Actual Windows renderer and isolated UI user directory required")
		quit(2)
		return
	_app = (load("res://game/app/main.tscn") as PackedScene).instantiate() as Control
	root.add_child(_app)
	await process_frame
	_app.set_process(false)
	_output = OS.get_user_data_dir().get_base_dir().path_join("evidence")
	DirAccess.make_dir_recursive_absolute(_output)
	_results.engine = Engine.get_version_info()
	_results.display_driver = DisplayServer.get_name()
	_results.rendering_method = RenderingServer.get_current_rendering_method()
	_results.rendering_driver = RenderingServer.get_current_rendering_driver_name()
	_results.adapter = RenderingServer.get_video_adapter_name()
	_results.adapter_vendor = RenderingServer.get_video_adapter_vendor()
	_results.user_directory = OS.get_user_data_dir()
	_results.window_size = str(DisplayServer.window_get_size())
	_check("actual_compatibility",_results.rendering_method=="gl_compatibility")
	_check("boot_after_native_guard",_app.get("_simulation")!=null)
	if _app.get("_simulation")==null:
		_finish()
		return
	if "--case=startup" in OS.get_cmdline_user_args():
		await _startup_recovery_cases()
		_app.get("_guard").call("release")
		root.remove_child(_app)
		_app.free()
		_finish()
		return
	_check_control_contrast()
	_app.call("_notification",MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	var initial: HospitalSimulation = _app.get("_simulation")
	for speed: int in [1,2,3]:
		_app.call("_set_speed",speed)
		var before_tick: int = int(initial.world.facts.sim_tick)
		for frame: int in 10:
			_app.call("_process",0.1)
		_check("actual_speed_"+str(speed),int(initial.world.facts.sim_tick)-before_tick==10*speed)
	var paused_tick: int = int(initial.world.facts.sim_tick)
	_app.call("_notification",MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_app.call("_process",0.25)
	_check("focus_pauses_and_preserves_intent",int(initial.world.facts.sim_tick)==paused_tick and _app.get("_speed")==3)
	_app.call("_notification",MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	_app.call("_process",4.0)
	_check("sleep_delta_does_not_catch_up",int(initial.world.facts.sim_tick)==paused_tick and _app.get("_speed")==3)
	_app.call("_set_speed",0)
	var initial_camera: Transform3D = (_app.get("_view") as HospitalView).camera.transform
	_app.call("_follow_selected")
	_check("product_follow_respects_18_metre_minimum",is_equal_approx((_app.get("_view") as HospitalView).camera.size,18.0))
	await _capture("ui100-follow-selected")
	(_app.get("_view") as HospitalView).follow_actor = ""
	(_app.get("_view") as HospitalView).camera.size = 42.0
	(_app.get("_view") as HospitalView).camera.transform = initial_camera
	var before_view: String = JSON.stringify(initial.world.facts,"",true,true)
	await _capture("ui100-outpatient")
	_pressed("界面200%")
	await _capture("ui200-outpatient")
	_check("ui_scale_and_render_are_readonly",before_view==JSON.stringify(initial.world.facts,"",true,true))
	_pressed("界面100%")
	var source_id: String = _app.get("_simulation").world.facts.hospital_id
	_pressed("切换医院")
	await _wait_storage()
	_check("switch_publishes_other_world",_app.get("_simulation").world.facts.hospital_id!=source_id)
	_check("switch_target_paused",_app.get("_speed")==0)
	var simulation: HospitalSimulation = _app.get("_simulation")
	for tick: int in 1300:
		simulation.step()
	_app.get("_view").update_facts()
	await _capture("surgery-actual-work")
	var surgery_view: HospitalView = _app.get("_view")
	surgery_view.follow_actor = "patient"
	# The 8 m probe magnifies attachment geometry; product controls stop at 18 m.
	surgery_view.camera.size = 8.0
	for tick: int in 4700:
		simulation.step()
		if simulation.world.facts.visits.values()[0].phase=="recovery":
			surgery_view.update_facts()
			await _capture("dream-awaiting-actual-result")
			break
	surgery_view.follow_actor = ""
	surgery_view.camera.size = 42.0
	_pressed("2F")
	await _capture("floor2-spatial-widths")
	_pressed("1F")
	var snapshot: Dictionary = simulation.world.freeze()
	_pressed("切换医院")
	_pressed("取消切院")
	await _wait_storage()
	_check("cancel_keeps_original_world",JSON.stringify(snapshot,"",true,true)==JSON.stringify(_app.get("_simulation").world.facts,"",true,true))
	_check("cancel_keeps_paused",_app.get("_speed")==0)
	await _switch_failure_cases()
	var newer: Dictionary = _app.call("_begin_save","manual","1")
	var newer_sim: HospitalSimulation = _app.get("_simulation")
	newer_sim.step()
	await _wait_storage()
	_check("newer_revision_remains_dirty",newer.ok and int(_app.get("_saved_revision"))<int(newer_sim.world.facts.world_revision))
	var old_request: Dictionary = _app.call("_begin_save","manual","1")
	var old_receipt: Dictionary = await _wait_raw_receipt()
	var other_id: String = _app.get("_hospital_ids")[0]
	if other_id==newer_sim.world.facts.hospital_id:
		other_id = _app.get("_hospital_ids")[1]
	var other_records: Array[Dictionary] = _app.get("_snapshots").list_commits(other_id)
	var loaded: Dictionary = _app.get("_snapshots").load_commit(other_id,other_records[0].snapshot_id)
	_check("late_receipt_target_loaded",loaded.ok and _app.call("_activate",loaded.world,true))
	var late_before: int = int(_app.get("_saved_revision"))
	_app.call("_receipt",old_receipt)
	_check("late_other_hospital_receipt_ignored",old_request.ok and old_receipt.get("ok",false) and int(_app.get("_saved_revision"))==late_before and _app.get("_leave_operation").is_empty())
	var valid_candidate: HospitalWorld = HospitalWorld.new((_app.get("_simulation") as HospitalSimulation).world.freeze())
	valid_candidate.facts.actors.sample_S21.species_id = "S22"
	var original_world: HospitalWorld = (_app.get("_simulation") as HospitalSimulation).world
	_check("missing_core_asset_keeps_world",not _app.call("_activate",valid_candidate) and (_app.get("_simulation") as HospitalSimulation).world==original_world)
	await _space_captures()
	_results.view_size = str(_app.get("_viewport").size)
	_results.scaling_3d_scale = _app.get("_viewport").scaling_3d_scale
	_results.product_camera_range_m = [18.0,90.0]
	_results.attachment_probe_camera_size_m = 8.0
	_results.render_objects = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	_results.render_primitives = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	_results.draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	_results.note = "Actual Compatibility drawing and UI only; no presented-frame performance acceptance."
	_app.get("_guard").call("release")
	root.remove_child(_app)
	_app.queue_free()
	await process_frame
	_finish()

func _capture(name: String) -> void:
	_app.call("_process",0.0)
	for frame: int in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var result: Error = image.save_png(_output.path_join(name+".png"))
	_check(name+"_capture",result==OK and image.get_width()>0)
	print("CAPTURE="+name)

func _pressed(text: String) -> void:
	for button: Node in _app.get("_toolbar").get_children():
		if button is Button and button.text==text:
			button.pressed.emit()
			return
	_check("button_present_"+text,false)

func _check_control_contrast() -> void:
	var text_pass: bool = true
	var boundary_pass: bool = true
	var focus_pass: bool = true
	var header: PanelContainer = _app.get("_header")
	var canvas: Color = (header.get_theme_stylebox("panel") as StyleBoxFlat).bg_color
	for child: Node in _app.get("_toolbar").get_children():
		var button: Button = child as Button
		for state: String in ["normal","hover","pressed","disabled"]:
			var style: StyleBoxFlat = button.get_theme_stylebox(state)
			var color_name: String = "font_color" if state=="normal" else "font_"+state+"_color"
			text_pass = text_pass and _contrast(button.get_theme_color(color_name),style.bg_color)>=4.5
			if state!="disabled":
				boundary_pass = boundary_pass and maxf(_contrast(style.bg_color,canvas),_contrast(style.border_color,canvas))>=3.0
		var focus: StyleBoxFlat = button.get_theme_stylebox("focus")
		focus_pass = focus_pass and not focus.draw_center and focus.expand_margin_left>=2.0 and _contrast(focus.border_color,canvas)>=3.0
	_check("button_state_text_contrast",text_pass)
	_check("button_boundary_contrast",boundary_pass)
	_check("keyboard_focus_contrast",focus_pass)

static func _contrast(first: Color, second: Color) -> float:
	var a: Color = first.srgb_to_linear()
	var b: Color = second.srgb_to_linear()
	var first_luma: float = a.r*0.2126+a.g*0.7152+a.b*0.0722
	var second_luma: float = b.r*0.2126+b.g*0.7152+b.b*0.0722
	return (maxf(first_luma,second_luma)+0.05)/(minf(first_luma,second_luma)+0.05)

func _wait_storage() -> void:
	while _app.get("_snapshots").busy():
		await process_frame
		_app.call("_process",0.0)
	await process_frame

func _wait_raw_receipt() -> Dictionary:
	var storage: HospitalSnapshots = _app.get("_snapshots")
	while storage.busy():
		await process_frame
		var receipt: Dictionary = storage.poll()
		if not receipt.is_empty():
			return receipt
	return {}

func _switch_failure_cases() -> void:
	var simulation: HospitalSimulation = _app.get("_simulation")
	var source_id: String = simulation.world.facts.hospital_id
	var ids: Array[String] = _app.get("_hospital_ids")
	var target: String = ids[(ids.find(source_id)+1)%ids.size()]
	var storage: HospitalSnapshots = _app.get("_snapshots")
	var records: Array[Dictionary] = storage.list_commits(target)
	if records.is_empty():
		_check("bad_target_has_real_commit",false)
		return
	var path: String = HospitalSnapshots.ROOT.path_join(target).path_join("commits").path_join(records[0].snapshot_id).path_join("world.json")
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var damaged: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	damaged.store_string("{")
	damaged.close()
	_app.set("_drafts",{"placement":{"definition_id":"FUR01","cell":[35,93]}})
	var before: String = JSON.stringify(simulation.world.facts,"",true,true)
	_pressed("切换医院")
	await _wait_storage()
	_check("corrupt_target_keeps_original_and_draft",before==JSON.stringify((_app.get("_simulation") as HospitalSimulation).world.facts,"",true,true) and not _app.get("_drafts").is_empty() and _app.get("_speed")==0)
	var repaired: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	repaired.store_buffer(bytes)
	repaired.close()
	_check("test_target_restored",storage.load_commit(target,records[0].snapshot_id).ok)

func _space_captures() -> void:
	var evidence_path: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--runtime-evidence="):
			evidence_path = argument.trim_prefix("--runtime-evidence=")
	if evidence_path.is_empty():
		_check("spatial_capture_evidence_supplied",false)
		return
	var raw: PackedByteArray = FileAccess.get_file_as_bytes(evidence_path)
	var digest: String = HospitalSnapshots._sha(raw)
	var decoded: Dictionary = HospitalJsonStream.new().decode(evidence_path,raw.size(),digest,func(_size:int) -> bool: return true)
	if not decoded.ok:
		_check("spatial_capture_facts_decoded",false)
		return
	for key: String in ["door_world","expanded_bed_world"]:
		var world: HospitalWorld = HospitalWorld.new(decoded.value.artifacts[key])
		_app.set("_observed_floor",2)
		_app.set("_selected_actor","sample_S59")
		_check(key+"_view_ready",_app.call("_activate",world))
		(_app.get("_status") as Label).text = "空间样板：石巨人保持原身体尺寸，门与承托按实际预约展开。"
		var view: HospitalView = _app.get("_view")
		view.follow_actor = "sample_S59"
		view.camera.size = 18.0
		view.update_facts()
		await _capture(key)
	var clinic: HospitalWorld = FeasibilityHospitals.create(HospitalSnapshots.uuid(),false,_app.get("_content"))
	_app.set("_observed_floor",1)
	_app.set("_selected_actor","patient")
	_check("case_capture_view_ready",_app.call("_activate",clinic))
	(_app.get("_status") as Label).text = "门诊样板：纸巾绑定原手插槽，风车和滤袋读取真实治疗进度。"
	var view: HospitalView = _app.get("_view")
	view.follow_actor = "patient"
	# Technical attachment close-up, outside the product camera control range.
	view.camera.size = 8.0
	var simulation: HospitalSimulation = _app.get("_simulation")
	for tick: int in 1600:
		simulation.step()
		if clinic.facts.visits.values()[0].phase=="outpatient":
			view.update_facts()
			await _capture("tissue-and-filter-actual-work")
			view.camera.size = 18.0
			await _capture("outpatient-product-follow")
			break

func _restart_app() -> void:
	_app.get("_guard").call("release")
	root.remove_child(_app)
	_app.free()
	_app = (load("res://game/app/main.tscn") as PackedScene).instantiate() as Control
	root.add_child(_app)
	await process_frame
	_app.set_process(false)

func _startup_recovery_cases() -> void:
	var content: HospitalContent = _app.get("_content")
	var storage: HospitalSnapshots = _app.get("_snapshots")
	var healthy_id: String = "00000000-0000-4000-8000-000000000002"
	var interrupted_id: String = "00000000-0000-4000-8000-000000000001"
	var healthy: HospitalWorld = FeasibilityHospitals.create(healthy_id,true,content)
	var simulation: HospitalSimulation = HospitalSimulation.new(healthy,content)
	for tick: int in 137:
		simulation.step()
	var before: String = JSON.stringify(healthy.facts,"",true,true)
	var saved: Dictionary = storage.begin(healthy,"startup-baseline","manual","startup")
	_check("startup_baseline_save_started",saved.ok)
	if not saved.ok:
		return
	var receipt: Dictionary = await _wait_raw_receipt()
	_check("startup_baseline_save_committed",receipt.get("ok",false))
	if not receipt.get("ok",false):
		return
	var commits: String = HospitalSnapshots.ROOT.path_join(healthy_id).path_join("commits")
	var baseline: String = commits.path_join(receipt.snapshot_id)
	var baseline_hash: String = FileAccess.get_sha256(baseline.path_join("world.json"))
	var pending: String = HospitalSnapshots.ROOT.path_join(interrupted_id).path_join("commits").path_join(".pending-"+HospitalSnapshots.uuid())
	DirAccess.make_dir_recursive_absolute(pending)
	var partial: String = pending.path_join("world.json")
	HospitalSnapshots._store(partial,"{\"schema_version\":1,".to_utf8_buffer())
	var partial_hash: String = FileAccess.get_sha256(partial)
	await _restart_app()
	var loaded: HospitalSimulation = _app.get("_simulation")
	_check("startup_skips_first_interrupted_hospital",loaded!=null and loaded.world.facts.hospital_id==healthy_id)
	_check("startup_preserves_healthy_facts",loaded!=null and JSON.stringify(loaded.world.facts,"",true,true)==before and _app.get("_speed")==0)
	_check("startup_preserves_interrupted_files",FileAccess.get_sha256(partial)==partial_hash and FileAccess.get_sha256(baseline.path_join("world.json"))==baseline_hash)
	storage = _app.get("_snapshots")
	simulation.step()
	var newer: Dictionary = storage.begin(healthy,"startup-newer","manual","startup")
	_check("startup_newer_save_started",newer.ok)
	if not newer.ok:
		return
	var newer_receipt: Dictionary = await _wait_raw_receipt()
	_check("startup_newer_save_committed",newer_receipt.get("ok",false))
	if not newer_receipt.get("ok",false):
		return
	var damaged: String = commits.path_join(newer_receipt.snapshot_id).path_join("world.json")
	HospitalSnapshots._store(damaged,"{".to_utf8_buffer())
	await _restart_app()
	_check("startup_waits_for_older_recovery",_app.get("_simulation")==null)
	_pressed("恢复上一有效保存点")
	loaded = _app.get("_simulation")
	_check("startup_older_recovery_keeps_facts",loaded!=null and JSON.stringify(loaded.world.facts,"",true,true)==before and _app.get("_speed")==0)
	_check("startup_older_recovery_retains_bad_files",FileAccess.get_file_as_string(damaged)=="{" and FileAccess.get_sha256(partial)==partial_hash)
	HospitalSnapshots._store(baseline.path_join("COMMITTED"),"invalid".to_utf8_buffer())
	await _restart_app()
	_check("startup_no_valid_hospital_keeps_files",_app.get("_simulation")==null and _app.get("_snapshots").hospital_ids().size()==2 and FileAccess.get_sha256(partial)==partial_hash and FileAccess.get_file_as_string(baseline.path_join("COMMITTED"))=="invalid")
	_check("startup_keeps_native_guard",_app.get("_guard").call("is_held"))
	_results.startup_recovery = {"healthy_hospital_id":healthy_id,"interrupted_hospital_id":interrupted_id,"saved_tick":137,"partial_world_sha256":partial_hash,"healthy_world_sha256":baseline_hash}

func _check(name: String, passed: bool) -> void:
	_results[name] = passed
	if not passed:
		_failures.append(name)
		push_error("Stage01 UI feasibility failure: "+name)

func _finish() -> void:
	_results.failures = _failures
	_results.ok = _failures.is_empty()
	var file: FileAccess = FileAccess.open(_output.path_join("ui-evidence.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(_results,"\t",true))
	file.close()
	print("STAGE01_UI_PASS="+str(_results.ok))
	quit(0 if _results.ok else 1)
