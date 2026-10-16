class_name HospitalRecruitmentPanel
extends HospitalActionPanel

const ROLE_NAMES: Dictionary = {"receptionist":"接待员","doctor":"医生","nurse":"护士","cleaner":"保洁员","researcher":"研究员","decorator":"装修员"}
const TRACK_NAMES: Dictionary = {"diagnosis":"诊断","treatment":"治疗","care":"护理","surgery":"手术","skill":"岗位技能"}
var _role: OptionButton
var _species: OptionButton
var _track: OptionButton
var _title: OptionButton
var _ability: SpinBox
var _cards: VBoxContainer
var _page: int = 0

func build_controls() -> void:
	heading("招聘与寻访")
	var roles: Array = []
	for key: String in ROLE_NAMES:
		roles.append({"id":key,"name":ROLE_NAMES[key]})
	_role = choice("招聘岗位",roles)
	var species: Array = [{"id":"","name":"不限种族"}]
	for row: Dictionary in simulation.content.catalog.species:
		species.append({"id":row.id,"name":row.name})
	_species = choice("定向种族",species)
	var titles: Array = []
	for row: Dictionary in simulation.content.catalog.doctor_titles:
		titles.append({"id":row.id,"name":row.name})
	_title = choice("医生职称",titles)
	_track = choice("医生主方向",[{"id":"diagnosis","name":"诊断"},{"id":"treatment","name":"治疗"},{"id":"surgery","name":"手术"}])
	_ability = number("寻访最低主能力",1,5,1)
	_role.item_selected.connect(func(_index: int) -> void: _page=0; _refresh())
	_species.item_selected.connect(func(_index: int) -> void: _page=0; _refresh())
	_title.item_selected.connect(func(_index: int) -> void: _refresh())
	_track.item_selected.connect(func(_index: int) -> void: _refresh())
	note("寻访费用 %d；未开放的职称或能力会说明原因。" % int(simulation.content.balance.recruitment.search_fee))
	note(payment_summary(int(simulation.content.balance.recruitment.search_fee)))
	action("开始定向寻访",func() -> void:
		var filter: Dictionary = _filter()
		filter.min_ability = int(_ability.value)
		filter.ability = selected(_track) if selected(_role)=="doctor" else "care" if selected(_role)=="nurse" else "skill"
		send("recruitment_search",{"filter":filter})
	)
	action("取消进行中的寻访",func() -> void: send("recruitment_cancel_search"))
	action("刷新简历与报价",_refresh)
	action("上一页",func() -> void: _page=maxi(0,_page-1); _refresh())
	action("下一页",func() -> void: _page+=1; _refresh())
	_cards = VBoxContainer.new()
	_cards.add_theme_constant_override("separation",10)
	add_child(_cards)
	report(_search_status)
	_refresh()

func _filter() -> Dictionary:
	var filter: Dictionary = {"role":selected(_role)}
	if not selected(_species).is_empty():
		filter.species_id = selected(_species)
	if selected(_role)=="doctor":
		filter.title_id = selected(_title)
		filter.primary_track = selected(_track)
	return filter

func _refresh() -> void:
	if _cards==null:
		return
	for child: Node in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()
	var filter: Dictionary = _filter()
	var result: Dictionary = simulation.services.recruitment.query(simulation.world,filter)
	_title.visible = selected(_role)=="doctor"
	_track.visible = selected(_role)=="doctor"
	_add_text("标准候选")
	if result.standard.get("ok",false):
		_add_card(result.standard,filter,true)
	else:
		_add_text(str(result.standard.get("reason","暂无标准候选")))
	var candidates: Array = result.candidates
	_page = mini(_page,maxi(0,ceili(float(candidates.size())/4.0)-1))
	_add_text("现有简历 · 第%d页 · 共%d份" % [_page+1,candidates.size()])
	for index: int in range(_page*4,mini(candidates.size(),(_page+1)*4)):
		_add_card(candidates[index],filter,false)
	if candidates.is_empty():
		_add_text("暂无符合条件的简历，可等待来信或主动寻访。")

func _add_text(value: String) -> void:
	var label: Label = Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cards.add_child(label)

func _add_button(value: String, callback: Callable) -> void:
	var button: Button = Button.new()
	button.text = value
	button.custom_minimum_size.y = 38
	button.pressed.connect(callback)
	_cards.add_child(button)

func _add_card(card: Dictionary, filter: Dictionary, standard: bool) -> void:
	var species: Dictionary = simulation.content.definition("species",str(card.species_id))
	_add_text("%s · %s · %s\n录用费 %d · 日薪 %d" % [card.name,ROLE_NAMES.get(card.role,card.role),species.get("name",""),card.hire,card.wage_day])
	var hospital_paid: int = int(card.hire)
	_add_text(payment_summary(hospital_paid))
	var abilities: PackedStringArray = []
	for key: String in card.get("abilities",{}):
		if int(card.abilities[key])>0:
			abilities.append("%s%d" % [TRACK_NAMES.get(key,key),int(card.abilities[key])])
	if int(card.get("skill",0))>0:
		abilities.append("岗位技能%d" % int(card.skill))
	_add_text(" · ".join(abilities))
	if not card.get("entry",{}).get("ok",false):
		_add_text(str(card.get("entry",{}).get("reason","入口暂不可用")))
	if not standard:
		_add_text("已关注" if card.pool=="bookmarked" else "剩余%d天" % int(card.remaining_days))
	var payload: Dictionary = {"quote_hash":card.quote_hash}
	if standard:
		payload.merge({"standard_key":card.standard_key,"ordinal":card.ordinal,"filter":filter.duplicate(true)})
	else:
		payload.candidate_id = card.id
	_add_button("按以上报价录用",func() -> void: send("recruitment_hire",payload))
	if not standard:
		_add_button("取消关注" if card.pool=="bookmarked" else "关注简历",func() -> void: send("recruitment_bookmark",{"candidate_id":card.id,"enabled":card.pool!="bookmarked"}))
		_add_button("关闭简历",func() -> void: send("recruitment_dismiss",{"candidate_id":card.id}))

func _search_status() -> String:
	var search: Dictionary = simulation.services.recruitment.query(simulation.world,_filter()).active_search
	return "暂无正在进行的寻访" if search.is_empty() else "寻访进行中 · 剩余 %.1f 秒" % (float(search.get("remaining_ticks",0))*WorldState.TICK_SECONDS)
