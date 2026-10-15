class_name HospitalDepartmentsPanel
extends HospitalActionPanel

func build_controls() -> void:
	heading("科室与体验")
	var service: Variant = simulation.services.departments
	var summary: Dictionary = service.summary(simulation.world)
	note("医院评价：%s · 样本 %s" % [summary.hospital_rating.status,summary.hospital_rating.samples])
	for reason: Dictionary in summary.reasons.slice(0,8):
		note("%s：%s" % [reason.name,reason.reason])
	var units: OptionButton = choice("已有科室",summary.units)
	var focus: OptionButton = choice("专业",[{"id":"","name":"综合接诊"}]+simulation.content.catalog.get("specialties",[]))
	action("调整所选科室专业",func() -> void: send("department_set_focus",{"department_id":selected(units),"focus_id":selected(focus)}),not summary.units.is_empty())
	action("切换所选科室开诊",func() -> void:
		var unit: Dictionary = summary.units[units.selected]
		send("department_set_open",{"department_id":unit.id,"open":not bool(unit.open)}),not summary.units.is_empty())
	var detail: Label = note("")
	var show_unit: Callable = func() -> void:
		if summary.units.is_empty(): detail.text="尚无科室。选择实际房间和邻近入口可建立科室。"; return
		var unit: Dictionary = summary.units[units.selected]
		detail.text="%s · %s\n专业过渡剩余 %.1f秒\n评价：%s · 样本 %s" % [unit.name,"接诊中" if unit.open else "关诊",float(unit.focus_remaining_ticks)*0.1,unit.rating.status,unit.rating.samples]
	units.item_selected.connect(func(_index: int) -> void: show_unit.call())
	show_unit.call()
	heading("创建科室")
	var name_input: LineEdit = LineEdit.new()
	name_input.text="新科室"
	name_input.max_length=40
	field("科室名称",name_input)
	var room: OptionButton = choice("所属房间",entity_choices("rooms"))
	var shared: OptionButton = choice("共享房间（可不选）",[{"id":"","name":"不共享"}]+entity_choices("rooms"))
	var floor_input: SpinBox = number("入口楼层",1,999,1)
	var x: SpinBox = number("入口格 X",-999,999,0)
	var y: SpinBox = number("入口格 Y",-999,999,0)
	var scope: Array = []
	var disease: OptionButton = choice("接诊病症",simulation.content.catalog.get("diseases",[]))
	var scope_label: Label = note("范围：全部病症")
	action("加入所选病症",func() -> void:
		if not selected(disease) in scope: scope.append(selected(disease))
		var labels: Array = []
		for id: String in scope: labels.append(str(simulation.content.definition("diseases",id).get("name",id)))
		scope_label.text="范围："+"、".join(labels))
	action("恢复全部病症",func() -> void: scope.clear(); scope_label.text="范围：全部病症")
	note("入口需处于房间邻近的真实通行格。专业变更费用与过渡时间按当前规则核验；失败保留原配置。")
	action("创建科室",func() -> void:
		var shared_ids: Array = []
		if not selected(shared).is_empty(): shared_ids.append(selected(shared))
		send("department_create",{"name":name_input.text,"room_ids":[selected(room)],"shared_room_ids":shared_ids,"entry":{"floor_id":int(floor_input.value),"cell":[int(x.value),int(y.value)]},"intake_disease_ids":scope.duplicate(),"focus_id":selected(focus)}),room.item_count>0)
	action("刷新科室与原因",rebuild)
