class_name HospitalTrainingPanel
extends HospitalActionPanel

const TRACK_NAMES: Dictionary = {"diagnosis":"诊断", "treatment":"治疗", "care":"护理", "surgery":"手术"}
var _staff: OptionButton
var _track: OptionButton
var _quote: Dictionary = {}
var _preview: Label
var _kind: String = "course"
var _queue: CheckBox

func build_controls() -> void:
	heading("医护培养")
	var people: Array = []
	for entry: Dictionary in entity_choices("staff"):
		if simulation.world.facts.staff[entry.id].role in ["doctor","nurse"]:
			people.append(entry)
	_staff = choice("选择医护",people)
	_track = choice("课程方向",[])
	_staff.item_selected.connect(func(_index: int) -> void: _refresh_tracks())
	_track.item_selected.connect(func(_index: int) -> void: _refresh_preview("course"))
	action("设为成长方向",func() -> void: send("set_growth_direction",{"staff_id":selected(_staff),"track":selected(_track)}),not people.is_empty())
	_preview = note("")
	action("预览课程",func() -> void: _refresh_preview("course"),not people.is_empty())
	action("预览职称评估",func() -> void: _refresh_preview("promotion"),not people.is_empty())
	_queue = CheckBox.new()
	_queue.text = "无研究桌时付费排队"
	add_child(_queue)
	action("确认支付并安排",_confirm,not people.is_empty())
	action("取消当前培养",func() -> void: send("cancel_training",{"staff_id":selected(_staff)}),not people.is_empty())
	note("培养需要培训班和可用研究桌；取消退款以实际进度结算。")
	report(_status)
	_refresh_tracks()

func _refresh_tracks() -> void:
	_track.clear()
	var staff: Dictionary = simulation.world.facts.staff.get(selected(_staff),{})
	if staff.is_empty():
		_preview.text = "暂无可培养医护"
		return
	for track: String in HospitalClinicalDevelopment.tracks(staff):
		_track.add_item(TRACK_NAMES[track])
		_track.set_item_metadata(_track.item_count-1,track)
	_refresh_preview("course")

func _refresh_preview(kind: String) -> void:
	_kind = kind
	_quote = simulation.services.development.preview(simulation.world,selected(_staff),selected(_track),kind)
	if not _quote.get("ok",false):
		_preview.text = str(_quote.get("reason","请选择医护"))
		return
	_preview.text = "%s · 费用 %d · 预计工作 %.1f 秒" % ["职称评估" if kind=="promotion" else "%s %d级" % [TRACK_NAMES.get(_quote.track,_quote.track),_quote.target_level],_quote.cost,float(_quote.work_ticks)*WorldState.TICK_SECONDS]

func _confirm() -> void:
	if not _quote.get("ok",false):
		return
	send("promote_staff" if _kind=="promotion" else "train_staff",{"staff_id":selected(_staff),"track":selected(_track),"confirmed_quote":_quote.basis,"queue_without_desk":_queue.button_pressed})

func _status() -> String:
	var staff: Dictionary = simulation.world.facts.staff.get(selected(_staff),{})
	if staff.is_empty():
		return ""
	var lines: PackedStringArray = []
	for track: String in HospitalClinicalDevelopment.tracks(staff):
		lines.append("%s：%d级 · 实践%d次" % [TRACK_NAMES[track],int(staff.abilities.get(track,0)),int(staff.get("practice",{}).get(track,0))])
	var job: Dictionary = simulation.world.facts.get("training_jobs",{}).get(staff.get("training_job_id",""),{})
	if not job.is_empty():
		lines.append("培养进度 %d%% · %s" % [100-int(100.0*float(job.remaining_work_milli)/float(job.total_work_milli)),str(job.get("reason",""))])
	return "\n".join(lines)
