class_name HospitalResearchPanel
extends HospitalActionPanel

signal page_requested(id: String)

var _filter: OptionButton
var _research: OptionButton
var _desk: OptionButton
var _worker: OptionButton
var _community: CheckBox
var _waiting: CheckBox
var _quote_label: Label
var _details: Label
var _readiness: Label
var _quote: Dictionary = {}
var _was_open: bool = false
var _selected_research: String = ""
var _selected_filter: String = "all"

func build_controls() -> void:
	heading("研究与资料柜")
	_was_open = simulation.services.research.opened(simulation.world)
	if not _was_open:
		note("完成第一次初诊后，研究员会开放资料柜与38项研究。研究室和研究桌现在即可建造。")
		action("查看建设",func() -> void: page_requested.emit("building"))
		return
	var filters: Array = [{"id":"all","name":"全部课题"},{"id":"todo","name":"有序待办"},{"id":"cases","name":"病例课题"},{"id":"functions","name":"功能课题"}]
	for trail: Dictionary in simulation.content.catalog.research_trails:
		filters.append({"id":trail.id,"name":trail.name})
	_filter = choice("浏览或关注兴趣路线",filters)
	for index: int in _filter.item_count:
		if str(_filter.get_item_metadata(index))==_selected_filter:
			_filter.select(index)
	_filter.item_selected.connect(func(_index: int) -> void:
		_selected_filter = selected(_filter)
		_populate_research())
	_research = choice("研究课题",[])
	_research.item_selected.connect(func(_index: int) -> void:
		_selected_research = selected(_research)
		_refresh_quote())
	_details = note("")
	var desks: Array = [{"id":"","name":"自动选择共享研究桌"}]
	for entry: Dictionary in entity_choices("facilities"):
		if simulation.world.facts.facilities[entry.id].definition_id=="FUR05":
			desks.append(entry)
	_desk = choice("桌位偏好",desks)
	var workers: Array = [{"id":"","name":"自动选择实际当班研究员"}]
	for entry: Dictionary in entity_choices("staff"):
		var staff: Dictionary = simulation.world.facts.staff[entry.id]
		if staff.role=="researcher" and not staff.get("departed",false):
			workers.append(entry)
	_worker = choice("研究员偏好",workers)
	_desk.item_selected.connect(func(_index: int) -> void: _refresh_quote())
	_worker.item_selected.connect(func(_index: int) -> void: _refresh_quote())
	action("免费请求远程简报",func() -> void: _send_research("research_request_mail"))
	action("加入无费用待办",func() -> void: _send_research("research_todo_add"))
	action("移出待办",func() -> void: _send_research("research_todo_remove"))
	var todo_buttons: HBoxContainer = HBoxContainer.new()
	add_child(todo_buttons)
	for entry: Array in [["待办上移",-1],["待办下移",1]]:
		var button: Button = Button.new()
		button.text = entry[0]
		button.pressed.connect(_move_todo.bind(int(entry[1])))
		todo_buttons.add_child(button)
	_community = CheckBox.new()
	_community.text = "现金不足时选择社区课题：0费用、双倍工作量"
	_community.toggled.connect(func(_pressed: bool) -> void: _refresh_quote())
	add_child(_community)
	_waiting = CheckBox.new()
	_waiting.text = "缺少工作资源时，明确支付并保留研究待办"
	add_child(_waiting)
	_quote_label = note("")
	action("刷新研究报价",_refresh_quote)
	action("确认开始研究",_start)
	action("暂停并释放桌位与研究员",func() -> void: _send_research("research_pause"))
	action("恢复原研究",func() -> void: _send_research("research_resume"))
	action("将当前偏好用于原研究",func() -> void:
		_send_research("research_assign",{"desk_id":selected(_desk),"worker_id":selected(_worker)}))
	action("取消研究并按未完成比例退款",func() -> void: _send_research("research_cancel"))
	note("计划排序不收费、不抢占已有工作。社区方式与实付款在开题时冻结，改方式须先取消。")
	action("检查当前真实接诊缺项",_show_readiness)
	_readiness = note("研究开放选项后，仍需准备房间、设备、医护、兼容床位及正常往返路线。")
	action("查看建设",func() -> void: page_requested.emit("building"))
	action("查看医护资格与培养",func() -> void: page_requested.emit("training"))
	action("查看招聘",func() -> void: page_requested.emit("recruitment"))
	action("查看来院设置",func() -> void: page_requested.emit("arrivals"))
	action("刷新课题与人员列表",rebuild)
	report(_status)
	_populate_research()

func _process(delta: float) -> void:
	super._process(delta)
	if simulation!=null and is_visible_in_tree() and simulation.services.research.opened(simulation.world)!=_was_open:
		rebuild()

func _populate_research() -> void:
	_research.clear()
	var filter: String = selected(_filter)
	var allowed: Array = []
	if filter=="todo":
		allowed = simulation.world.facts.research_progress.todo
	elif filter.begins_with("RT"):
		allowed = simulation.services.research.trail_research(filter)
	var definitions: Array = simulation.content.catalog.research.duplicate()
	if filter=="todo" or filter.begins_with("RT"):
		definitions = []
		for id: String in allowed:
			definitions.append(simulation.content.definition("research",id))
	for definition: Dictionary in definitions:
		if filter=="cases" and definition.disease_ids.is_empty() or filter=="functions" and not definition.disease_ids.is_empty():
			continue
		_research.add_item(("✓ " if definition.id in simulation.world.facts.research else "")+str(definition.id)+" · "+str(definition.name))
		_research.set_item_metadata(_research.item_count-1,definition.id)
		if definition.id==_selected_research:
			_research.select(_research.item_count-1)
	_selected_research = selected(_research)
	_refresh_quote()

func _refresh_quote() -> void:
	if _quote_label==null:
		return
	if _readiness!=null:
		_readiness.text = "点击检查，按当前医院事实查看接诊缺项。"
	var id: String = selected(_research)
	if id.is_empty():
		_quote = {}
		_quote_label.text = "当前筛选没有课题。"
		_details.text = "待办只是计划，可随时回到全部课题。"
		return
	_quote = simulation.services.research.preview(simulation.world,id,selected(_desk),_community.button_pressed,selected(_worker))
	var total: float = float(_quote.get("total_work_milli",0))*WorldState.TICK_SECONDS/1000.0
	_quote_label.text = "本次费用 %d · 冻结标准工作量 %.1f 秒\n%s" % [int(_quote.get("cost",0)),total,str(_quote.get("reason",""))]
	if not _quote.get("resource_ready",false):
		_quote_label.text += "\n"+str(_quote.get("resource_reason",""))
	_community.disabled = not _quote.get("community_available",false) and not _community.button_pressed
	var definition: Dictionary = simulation.content.definition("research",id)
	var requirements: PackedStringArray = []
	for required: String in definition.requires:
		requirements.append(("✓ " if required in simulation.world.facts.research else "○ ")+str(simulation.content.definition("research",required).name))
	var lines: PackedStringArray = ["前置："+("无" if requirements.is_empty() else "、".join(requirements))]
	var trail: Dictionary = simulation.content.definition("research_trails",selected(_filter))
	if not trail.is_empty():
		lines.append(str(trail.flavor)+"\n接着布置："+str(trail.next_idea))
	var rewards: Dictionary = simulation.services.research.rewards(simulation.world,id)
	var known: PackedStringArray = []
	for disease_id: String in rewards.disease_ids:
		known.append(str(simulation.content.definition("diseases",disease_id).name))
	for item: Dictionary in rewards.definitions:
		known.append(str(item.name))
	lines.append(("新内容已知：" if id in simulation.world.facts.research else "完成后开放：")+("开放该研究对应的原有能力选项" if known.is_empty() else "、".join(known)))
	_details.text = "\n".join(lines)

func _start() -> void:
	if not _quote.get("ok",false):
		_refresh_quote()
		return
	_send_research("research_start",{"desk_id":selected(_desk),"worker_id":selected(_worker),"community":_community.button_pressed,
		"allow_waiting":_waiting.button_pressed,"confirmed_quote":_quote.basis})

func _send_research(kind: String, extra: Dictionary = {}) -> void:
	var id: String = selected(_research)
	if id.is_empty():
		return
	var payload: Dictionary = extra.duplicate(true)
	payload.research_id = id
	send(kind,payload)

func _move_todo(direction: int) -> void:
	var todo: Array = simulation.world.facts.research_progress.todo
	var index: int = todo.find(selected(_research))
	if index>=0:
		_send_research("research_todo_move",{"index":index+direction})

func _show_readiness() -> void:
	var lines: PackedStringArray = []
	var id: String = selected(_research)
	if not id in simulation.world.facts.research:
		lines.append("该课题尚未完成；以下仍按当前医院事实检查。")
	for ready: Dictionary in simulation.services.research.reception_readiness(simulation.world,id):
		lines.append("%s · %s：%s" % [simulation.content.definition("diseases",ready.disease_id).name,
			simulation.content.definition("species",ready.species_id).name,"当前具有普通病例接诊结构" if ready.ok else ready.reason])
		for plan: Dictionary in ready.plans:
			if not plan.get("ok",false):
				lines.append(str(simulation.content.definition("treatment_plans",plan.plan_id).name)+"："+str(plan.reason))
		if ready.ok:
			for plan: Dictionary in ready.plans:
				if not plan.get("ok",false):
					continue
				var team: PackedStringArray = []
				for staff_id: String in plan.get("staff_ids",[]):
					if simulation.world.facts.staff.has(staff_id):
						team.append("%s %d币/日" % [simulation.world.facts.actors[staff_id].name,simulation.services.finance.wage(simulation.world.facts.staff[staff_id])])
				if not team.is_empty():
					lines.append("当前可用团队："+"、".join(team))
	if lines.is_empty():
		lines.append("本课题开放建设或学习选项，没有新增病例；操作仍沿用对应页面的实际条件。")
	_readiness.text = "\n".join(lines)

func _status() -> String:
	var progress: Dictionary = simulation.world.facts.research_progress
	var id: String = selected(_research)
	var lines: PackedStringArray = ["已完成 %d / %d · 待办 %d" % [simulation.world.facts.research.size(),simulation.content.catalog.research.size(),progress.todo.size()]]
	var source: Dictionary = progress.materials.get(id,{})
	if not source.is_empty():
		lines.append("资料："+{"initial":"随课题附送","mail":"社区简报","diagnosis":"真实确诊"}.get(source.kind,source.kind)+" · 第%d医院日" % (int(source.tick)/WorldState.TICKS_PER_DAY+1))
		if source.kind=="diagnosis":
			lines.append(str(source.case_name)+" · "+str(simulation.content.definition("diseases",source.disease_id).name))
	elif progress.mail.has(id):
		lines.append("简报将在 %.1f 模拟秒后到达；重复请求不会改期" % (maxi(0,int(progress.mail[id])-simulation.world.sim_tick)*WorldState.TICK_SECONDS))
	else:
		lines.append("资料尚未具备")
	var job: Dictionary = simulation.services.research.active_job(simulation.world,id)
	if not job.is_empty():
		lines.append("%s · 已付%d · 进度%d%% · %s" % ["社区课题" if job.mode=="community" else "现金课题",job.cost,100-int(100.0*int(job.remaining_work_milli)/int(job.total_work_milli)),job.reason])
		if not str(job.worker_id).is_empty():
			lines.append("实际研究员："+str(simulation.world.facts.actors[job.worker_id].name)+" · 桌位 "+str(job.desk_id))
	return "\n".join(lines)
