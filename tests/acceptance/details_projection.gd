extends "res://tests/acceptance/clinical_fixtures.gd"

const App = preload("res://game/app/app_root.gd")
const Palette = preload("res://game/view/hospital_palette.gd")

func run(t, content: HospitalContent) -> void:
	_content = content
	_cache = t.checkpoints(content,"res://tests/acceptance/clinical_fixtures.gd",self)
	var started: int = Time.get_ticks_msec()
	var ready: bool = await _ensure_boundary(t,"gp_started") and await _ensure_boundary(t,"outpatient_started")
	t.preparation_elapsed(started)
	if not ready:
		t.check("CORE-47",false,{"fixture_prerequisites":_fixture_failures})
		_dispose_simulations()
		return
	var c: Dictionary = _copy("outpatient_started")
	var early: Dictionary = _snapshots.gp_started
	# Legal archived input rows use an unserved visit and an outside actor.
	# They are display inputs; no earlier discharge is under test here.
	_add_archived_inputs(c.world,early,3)
	var validation: String = c.world.validate(content)
	var actual = _app(c)
	var original = _app(c)
	actual._selected_actor = _visit(c).actor_id
	original._selected_actor = actual._selected_actor
	actual._selected_object = _session(c,"outpatient").facility_id
	original._selected_object = actual._selected_object
	var before: Dictionary = c.world.freeze()
	actual._update_details()
	_original_details(original)
	var first: String = actual._details.text
	var observations: Dictionary = {"validation":validation,"full_text_equal":first==original._details.text,"clock_equal":actual._clock.text==original._clock.text,"readonly":c.world.freeze()==before,"sessions":c.world.facts.sessions.size(),"visits":c.world.facts.visits.size()}
	var histories: bool = true
	for index: int in 3: histories = histories and first.contains("历史病例%02d"%index)
	observations.all_archived_rows = histories
	var remaining_lines: int = 0
	for line: String in first.split("\n"):
		if line.begins_with("剩余 "): remaining_lines += 1
	observations.every_session_line = remaining_lines==c.world.facts.sessions.size() and remaining_lines>0
	for tick: int in 13: _tick(c)
	before = c.world.freeze()
	actual._update_details()
	_original_details(original)
	observations.live_progress = actual._details.text==original._details.text and actual._details.text!=first and c.world.freeze()==before
	actual._details.visible = false
	actual._clock.text = ""
	var hidden: String = actual._details.text
	actual._update_details()
	observations.hidden_details_clock_updates = actual._details.text==hidden and not actual._clock.text.is_empty()
	actual.free()
	original.free()
	_dispose_simulations()
	var valid: bool = validation.is_empty()
	for field: String in ["full_text_equal","clock_equal","readonly","all_archived_rows","every_session_line","live_progress","hidden_details_clock_updates"]:
		valid = valid and bool(observations[field])
	t.check("CORE-47",valid,observations)

func _add_archived_inputs(world: WorldState, early: Dictionary, count: int) -> void:
	var template: Dictionary = early.facts.visits[early.visit_id]
	var actor_template: Dictionary = early.facts.actors[template.actor_id]
	for index: int in count:
		var id: String = "details_history_%02d"%index
		var visit: Dictionary = template.duplicate(true)
		visit.merge({"id":id,"actor_id":id,"arrival_key":id,"phase":"departed","ticket_id":"","final_result":"referred","departed_tick":world.sim_tick,"departure_recorded":true,"companion_intent":false},true)
		var actor: Dictionary = actor_template.duplicate(true)
		actor.merge({"id":id,"name":"历史病例%02d"%index,"location":{"kind":"outside"}},true)
		world.facts.actors[id] = actor
		world.facts.visits[id] = visit
		world.facts.arrival_receipts[id] = id

# Explicit diagnostic entry only. Acceptance does not implicitly benchmark UI.
func profile(content: HospitalContent, facts: Dictionary, early: Dictionary) -> Dictionary:
	_content = content
	var report: Dictionary = {"kind":"paired full details-renderer headless CPU probe; no frame/GPU claim","observations":[],"valid":true}
	for history: int in [0,256,1024]:
		var world: WorldState = WorldState.new(facts.duplicate(true))
		_add_archived_inputs(world,early,history)
		var validation: String = world.validate(content)
		if not validation.is_empty(): return {"valid":false,"validation":validation}
		var simulation: HospitalSimulation = HospitalSimulation.new(world,content)
		var c: Dictionary = {"world":world,"sim":simulation}
		var actual = _app(c)
		var original = _app(c)
		var old_samples: Array = []
		var new_samples: Array = []
		var before: Dictionary = world.freeze()
		var equal: bool = true
		_original_details(original)
		actual._update_details()
		for iteration: int in 21:
			var started: int = Time.get_ticks_usec()
			_original_details(original)
			old_samples.append(Time.get_ticks_usec()-started)
			started = Time.get_ticks_usec()
			actual._update_details()
			new_samples.append(Time.get_ticks_usec()-started)
			equal = equal and original._clock.text==actual._clock.text and original._details.text==actual._details.text
		var readonly: bool = world.freeze()==before
		report.observations.append({"history":history,"visits":world.facts.visits.size(),"sessions":world.facts.sessions.size(),"before_us":_stats(old_samples),"after_us":_stats(new_samples),"complete_clock_and_text_equal":equal,"readonly":readonly,"validation":validation})
		report.valid = report.valid and equal and readonly
		actual.free()
		original.free()
		simulation.dispose()
	return report

func _stats(values: Array) -> Dictionary:
	var ordered: Array = values.duplicate()
	ordered.sort()
	var total: float = 0
	for value: int in ordered: total += value
	return {"count":values.size(),"median":ordered[ordered.size()/2],"mean":total/values.size(),"max":ordered.back(),"samples":values}

func _app(c: Dictionary):
	var app = App.new()
	app._content = _content
	app._simulation = c.sim
	# One real session owns this simulation and its preparation worker. Both
	# renderers observe it; constructing a second session would replace that owner.
	if not c.has("details_session"): c.details_session = GameSession.new(c.sim,"details-projection")
	app._session = c.details_session
	app._clock = Label.new()
	app.add_child(app._clock)
	app._details = RichTextLabel.new()
	app.add_child(app._details)
	return app

# Frozen 83cc36a details renderer. This compatibility oracle compares complete
# text; the assertions above independently require current progress, every
# actual session, archived rows and a read-only visible/hidden handoff.
func _original_details(app) -> void:
	var world: WorldState = app._simulation.world
	var actual_speed: int = app._session.actual_speed()
	var playback: String = "暂停" if actual_speed==0 else str(actual_speed)+"×"
	if app._session.running_slow:
		playback += " · 运行稍慢"
	app._clock.text = "%s   %s   %s   资金 %d · 治疗包 %d" % [world.facts.display_name,world.clock_text(),playback,HospitalLedger.balance(world),int(world.facts.inventory.units)]
	if not app._details.visible: return
	var lines: PackedStringArray = PackedStringArray(["[b]院内情况[/b]","观察 %dF" % app._observed_floor])
	if not app._session.pause_reasons().is_empty():
		var reasons: PackedStringArray = []
		for source: String in app._session.pause_reasons():
			reasons.append({"focus":"窗口未聚焦"}.get(source,source))
		lines.append("暂停原因："+", ".join(reasons))
	for visit_id: String in world.ids("visits"):
		var visit: Dictionary = world.facts.visits[visit_id]
		var evidence: float = 0.0
		for value: Variant in visit.evidence_by_source.values():
			evidence += float(value)
		lines.append("\n[b]"+str(world.facts.actors[visit.actor_id].name)+"[/b]")
		lines.append(str(_content.definition("diseases",visit.disease_id).name) if evidence>=90 else str(_content.definition("treatment_bindings",visit.binding_id).symptom_variant))
		lines.append("诊断进度 %d / 90" % mini(90,floori(evidence)))
		lines.append(app._phase_name(visit.phase))
		if not visit.waiting_reason.is_empty():
			lines.append(visit.waiting_reason)
		if not visit.plan_decision.is_empty():
			lines.append(str(_content.definition("treatment_plans",visit.plan_decision.plan_id).name))
		for session: Dictionary in world.facts.sessions.values():
			if session.visit_id == visit.id:
				lines.append("剩余 %d 医院分钟" % ceili(float(session.remaining_ticks)*4.8/60.0))
		if visit.final_result == "cured":
			lines.append("[color=#"+Palette.SUCCESS.to_html(false)+"]已治愈，沿原流程离院[/color]")
		elif visit.final_result == "retry":
			lines.append("本次未治愈，继续原方案复治")
		elif visit.final_result == "referred":
			lines.append("已安排友好转诊")
	if world.facts.actors.has(app._selected_actor):
		var actor: Dictionary = world.facts.actors[app._selected_actor]
		var body: Dictionary = _content.definition("species",actor.species_id).body
		lines.append("\n[b]"+str(actor.name)+"[/b]")
		lines.append("宽 %.1f米 · 深 %.1f米 · 高 %.1f米" % [float(body.width_m),float(body.depth_m),float(body.height_m)])
	if world.facts.facilities.has(app._selected_object):
		var facility: Dictionary = world.facts.facilities[app._selected_object]
		lines.append("\n[b]"+str(_content.facility_definition(facility.definition_id).get("name",app._selected_object))+"[/b]")
		lines.append("%dF · 等级%d · 完好度%d%%" % [int(facility.floor_id),int(facility.grade),roundi(facility.condition)])
		lines.append("当前故障，等待维修" if facility.failed else "按真实岗位与路线接单")
	var text: String = "\n".join(lines)
	if app._details.text!=text: app._details.text = text
