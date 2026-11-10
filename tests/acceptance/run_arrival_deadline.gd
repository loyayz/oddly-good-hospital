extends SceneTree
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var content: HospitalContent = HospitalContent.new()
	var suite: RefCounted = load("res://tests/acceptance/public_area_use.gd").new()
	suite._content = content
	var x: Dictionary = suite._areas()
	suite._facility(x,"life_toilet","FUR07",[39,68],"west")
	x.world.touch()
	var visit: Dictionary = suite._visit(x,"life_patient",[38,90])
	x.world.facts.sim_tick = 1800
	x.l._begin_need(x.world,visit)
	var need: Dictionary = x.world.facts.waiting_life.needs[visit.id]
	var prefix: String = OS.get_cmdline_user_args()[0]
	FileAccess.open(prefix+"-outside-predecessor.bin",FileAccess.WRITE).store_var(x.world.freeze(),true)
	var arrived: bool = false
	var steps: int = 0
	for tick: int in 350:
		x.l._dispatch_need(x.world,visit,need)
		x.space.advance(x.world);x.world.facts.sim_tick += 1;x.world.touch(false);steps += 1
		var layout: Dictionary = x.space.facility_layout(x.world,"life_toilet")
		if not x.world.facts.moves.has(visit.actor_id) and x.space.at(x.world,visit.actor_id,1,layout.patient_cell): arrived=true;break
	if not arrived or need.phase=="using":
		FileAccess.open(prefix+".result.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":false,"fixture_real_arrival":arrived,"need":need}))
		quit(1);return
	FileAccess.open(prefix+"-inside-predecessor.bin",FileAccess.WRITE).store_var(x.world.freeze(),true)
	x.a.dispose()
	var result: Dictionary = load("res://tests/acceptance/waiting_need_deadline.gd").new().run_deadline_cases(content,prefix,prefix+"-boundary")
	result.fixture_actual_steps = steps
	result.fixture_scope = "New independent room fixture at tick1800; real initial departure and actual exact facility arrival before claim. Age449/450/451 remain declared input boundaries, not simulated history."
	FileAccess.open(prefix+".result.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("ARRIVAL_DEADLINE ",result.ok)
	quit(0 if result.ok else 1)
