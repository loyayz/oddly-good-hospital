class_name HospitalActionPanel
extends VBoxContainer

signal command_requested(kind: String, payload: Dictionary)

var simulation: HospitalSimulation
var session: GameSession
var _summary: Label
var _summary_source: Callable
var _next_summary_ms: int = 0

func attach(kernel: HospitalSimulation, active_session: GameSession) -> void:
	simulation = kernel
	session = active_session
	if is_node_ready():
		rebuild()

func _ready() -> void:
	add_theme_constant_override("separation",10)
	if simulation!=null:
		rebuild()

func rebuild() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_summary = null
	_summary_source = Callable()
	build_controls()

func build_controls() -> void:
	pass

func _process(_delta: float) -> void:
	if is_visible_in_tree() and _summary!=null and _summary_source.is_valid() and Time.get_ticks_msec()>=_next_summary_ms:
		_next_summary_ms = Time.get_ticks_msec()+500
		_summary.text = str(_summary_source.call())

func heading(text: String) -> Label:
	var label: Label = note(text)
	label.add_theme_font_size_override("font_size",22)
	return label

func note(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)
	return label

func field(text: String, control: Control) -> Control:
	var group: VBoxContainer = VBoxContainer.new()
	var label: Label = Label.new()
	label.text = text
	group.add_child(label)
	group.add_child(control)
	add_child(group)
	return control

func choice(text: String, entries: Array) -> OptionButton:
	var picker: OptionButton = OptionButton.new()
	for entry: Variant in entries:
		if entry is Dictionary:
			picker.add_item(str(entry.get("name",entry.get("id",""))))
			picker.set_item_metadata(picker.item_count-1,entry.get("id",""))
		else:
			picker.add_item(str(entry))
			picker.set_item_metadata(picker.item_count-1,entry)
	field(text,picker)
	return picker

func number(text: String, minimum: int, maximum: int, value: int) -> SpinBox:
	var input: SpinBox = SpinBox.new()
	input.min_value = minimum
	input.max_value = maximum
	input.step = 1
	input.value = value
	field(text,input)
	return input

func action(text: String, callback: Callable, enabled: bool = true) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size.y = 38
	button.disabled = not enabled
	button.pressed.connect(callback)
	add_child(button)
	return button

func selected(picker: OptionButton) -> String:
	return str(picker.get_item_metadata(picker.selected)) if picker.item_count>0 else ""

func refresh_choices(picker: OptionButton, entries: Array) -> void:
	var previous: String = selected(picker)
	var signature: Array = []
	for index: int in picker.item_count: signature.append([str(picker.get_item_metadata(index)),picker.get_item_text(index)])
	var next: Array = []
	for entry: Dictionary in entries: next.append([str(entry.id),str(entry.get("name",entry.id))])
	if signature==next: return
	picker.clear()
	for entry: Array in next:
		picker.add_item(entry[1])
		picker.set_item_metadata(picker.item_count-1,entry[0])
		if entry[0]==previous: picker.select(picker.item_count-1)

func send(kind: String, payload: Dictionary = {}) -> void:
	command_requested.emit(kind,payload.duplicate(true))

func payment_summary(cost: int, refund: int = 0) -> String:
	return format_payment_summary(simulation.world,cost,refund)

static func format_payment_summary(world: WorldState, cost: int, refund: int = 0) -> String:
	var cash_after: int = HospitalLedger.balance(world)-cost+refund
	var target: int = int(world.facts.get("economy",{}).get("saving_target_amount",0))
	var text: String = "购买后现金 %d" % cash_after
	if target>0:
		text += " · %s便签目标 %d" % ["低于" if cash_after<target else "不低于",target]
	return text

func report(source: Callable) -> void:
	_summary_source = source
	_summary = note(str(source.call()))

func entity_choices(collection: String) -> Array:
	var result: Array = []
	for id: String in simulation.world.ids(collection):
		var record: Dictionary = simulation.world.facts[collection][id]
		var name: String = str(record.get("name",id))
		if collection=="staff":
			name = str(simulation.world.facts.actors[id].name)
		elif collection=="facilities":
			name = str(simulation.content.facility_definition(record.definition_id).get("name",id))+" · "+id
		result.append({"id":id,"name":name})
	return result
