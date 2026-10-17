extends "res://game/app/app_root.gd"

# Only fixture composition differs from product startup. All visible controls,
# view construction, processing, commands and persistence use product classes.
var observer: Object
var quit_checkpoint_complete: bool = false

func _ready() -> void:
	get_tree().auto_accept_quit = false
	_build_ui()

func mount_fixture(world: WorldState, database: HospitalContent, floor_id: int) -> bool:
	_content = database
	_guard = ClassDB.instantiate("PlatformSessionGuard") as RefCounted
	var ownership: Dictionary = _guard.call("acquire")
	if not bool(ownership.get("ok", false)): return false
	var folder: String = get_script().resource_path.get_base_dir()
	_snapshots = load(folder.path_join("observed_snapshots.gd")).new(_content, _guard, observer)
	_library = load(folder.path_join("observed_library.gd")).new(_content, _snapshots, observer)
	_library_panel.attach(_library, world.hospital_id)
	_observed_floor = floor_id
	var session_id: String = HospitalSnapshots.uuid()
	_view = HospitalView.new(_content)
	_viewport.add_child(_view)
	_view.bind(world, _observed_floor, session_id)
	if not _view.bind_error.is_empty(): return false
	_simulation = HospitalSimulation.new(world, _content)
	_session = GameSession.new(_simulation, session_id)
	observer.observe_session(_session)
	_last_process_us = Time.get_ticks_usec()
	if not DisplayServer.window_is_focused(): _session.pause("focus")
	_saved_revision = -1
	_hospital_ids.assign([world.hospital_id])
	_auto_deadline_ms = Time.get_ticks_msec()+roundi(float(_content.balance.save.autosave_real_seconds)*1000)
	_bind_management_panels()
	return true

func _process(delta: float) -> void:
	var begin: int = Time.get_ticks_usec()
	if observer!=null and _simulation!=null: observer.before_frame(begin)
	super._process(delta)
	if observer != null and _simulation != null:
		observer.after_frame(begin, Time.get_ticks_usec())

func _begin_save(kind: String, slot: String) -> Dictionary:
	var begin: int = Time.get_ticks_usec()
	var started: Dictionary = super._begin_save(kind,slot)
	if observer!=null: observer.on_save_started(started,kind,slot,begin,Time.get_ticks_usec())
	return started

func _receipt(receipt: Dictionary) -> void:
	var expected_quit: bool = _leave_operation.get("kind","")=="quit" and str(receipt.get("request_id",""))==str(_leave_operation.get("request_id","")) and str(receipt.get("loading_session_id",""))==str(_leave_operation.get("source_session",""))
	super._receipt(receipt)
	if expected_quit and bool(receipt.get("ok",false)) and not bool(_guard.call("is_held")):
		quit_checkpoint_complete = true
	if observer != null: observer.on_receipt(receipt)

func _exit_tree() -> void:
	# A failed capture can still own an actual writer. Join that original writer
	# before releasing its native profile; never force an unfinished step forward.
	if _snapshots!=null and _snapshots._deferred_source==null and _snapshots.busy():
		_snapshots.wait_for_idle()
	super._exit_tree()
	if _guard!=null and bool(_guard.call("is_held")): _guard.call("release")
	if observer!=null: observer.on_root_released(_guard==null or not bool(_guard.call("is_held")),quit_checkpoint_complete)

func _prepare_switch_candidate() -> void:
	var begin: int = Time.get_ticks_usec()
	var old_session_instance: int = _session.get_instance_id() if _session!=null else 0
	var source_hospital: String = _simulation.world.hospital_id if _simulation!=null else ""
	super._prepare_switch_candidate()
	var end: int = Time.get_ticks_usec()
	observer._emit("main_phase", {"stage":"prepare_switch_candidate_main_inclusive","begin_us":begin,"end_us":end,"elapsed_us":end-begin,"source_hospital":source_hospital,"published_hospital":_simulation.world.hospital_id if _simulation!=null else "","inclusive":true,"scope":"original load/migration/view/old disposal/kernel/session/UI publication"}, end)
	if _session!=null and _session.get_instance_id()!=old_session_instance: observer.observe_session(_session)

func _bind_management_panels() -> void:
	var begin: int = Time.get_ticks_usec()
	super._bind_management_panels()
	var end: int = Time.get_ticks_usec()
	if observer!=null: observer._emit("main_phase", {"stage":"management_panels_bind_main","begin_us":begin,"end_us":end,"elapsed_us":end-begin,"inclusive":true}, end)
