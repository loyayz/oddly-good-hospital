extends RefCounted

# Published positions remain binary32. This is the already adopted fixed-floor
# numerical allowance, not a physical overlap tolerance or arbitrary-double
# arrival promise. Assertions measure scalar distances independently.
const ROUNDING: float = 2.0*96.0/8388608.0

class ContactObserver extends HospitalMovement:
	var blocked_step: bool = false
	var rejected_pose_atomic: bool = false
	func _move_step(world: WorldState, actor: Dictionary, movement: Dictionary, segment: Dictionary) -> HospitalMovement.MotionResult:
		var before: Dictionary = actor.duplicate(true)
		var result: HospitalMovement.MotionResult = super._move_step(world,actor,movement,segment)
		if actor.id=="walker":
			blocked_step=result.blocked
			rejected_pose_atomic=result.blocked and before==actor
		return result

func run(suite: RefCounted, selected: PackedStringArray = [], evidence: String = "") -> Dictionary:
	var rows: Array = []
	if selected.is_empty() or "budget" in selected:
		for group: bool in [false,true]:
			for boundary: Array in [
				["below",40.1999969482421875,1],
				["nearest_binary32",40.200000762939453125,1],
				["inside_allowance",40.20001983642578125,1],
				["outside_allowance",40.200023651123046875,2],
				["old_snap_overspend",40.20050048828125,2]]:
				rows.append(_journey(suite,{"name":("convoy_" if group else "single_")+boundary[0],"start":[40,80],"goal":[boundary[1],80],"group":group,"expected_motion_steps":boundary[2]},evidence))
	if selected.is_empty() or "initial" in selected:
		for item: Array in [
			["tiny_positive_x",[35.000499725341796875,80],[40.625,80]],
			["tiny_negative_x",[40.999500274658203125,80],[35.375,80]],
			["tiny_positive_y",[40,80.0005035400390625],[40,85.625]],
			["tiny_negative_y",[40,85.9994964599609375],[40,80.375]],
			["near_collinear_retained",[35.25,80.01],[40.625,80]]]:
			rows.append(_journey(suite,{"name":item[0],"start":item[1],"goal":item[2],"forward_first":true},evidence))
		rows.append(_journey(suite,{"name":"tiny_rear_body","start":[35.000499725341796875,80],"goal":[40.625,80],"rear":true,"forward_first":true},evidence))
		rows.append(_journey(suite,{"name":"off_line_alignment_retained","start":[35.25,80.02],"goal":[40.625,80]},evidence))
	if selected.is_empty() or "timing" in selected:
		for item: Array in [
			["integer_x_positive",[40,80],[41,80],"S49",5,false],
			["integer_x_negative",[41,80],[40,80],"S49",5,false],
			["integer_y_rounding_witness",[35,64],[35,65],"S49",5,false],
			["integer_y_negative",[35,65],[35,64],"S49",5,false],
			["convoy_integer_y_rounding_witness",[35,66],[35,67],"S49",5,true],
			["two_cell_speed",[40,80],[41,80],"S01",7,false],
			["three_cell_speed",[40,80],[41,80],"S59",8,false]]:
			rows.append(_journey(suite,{"name":item[0],"start":item[1],"goal":item[2],"species":item[3],"expected_motion_steps":item[4],"group":item[5]},evidence))
		rows.append(_journey(suite,{"name":"fractional_two_axis_stub","start":[40.125,80.375],"goal":[40.625,80.625]},evidence))
	if selected.is_empty() or "restore" in selected:
		for group: bool in [false,true]: rows.append(_blocked_restore(suite,group,evidence))
	if selected.is_empty() or "support" in selected:
		var row: Dictionary = preload("res://tests/acceptance/movement_review.gd").new()._ready_support_exit(suite)
		row.name = "support_exit_handoff"; rows.append(row)
	if selected.is_empty() or "door" in selected:
		var row: Dictionary = preload("res://tests/acceptance/movement_review.gd").new()._group_door(suite)
		row.name = "mixed_group_door_handoff"; rows.append(row)
	var ok: bool = not rows.is_empty()
	for row: Dictionary in rows: ok = ok and row.ok
	return {"ok":ok,"rows":rows,"fixed_tick_seconds":WorldState.TICK_SECONDS,"position_rounding_cells":ROUNDING,"scope":"Selected actual binary32 motion boundaries and handoffs; no arbitrary binary64 timing, performance, full-suite or SQLite persistence claim"}

func _distance(a: Array, b: Array) -> float:
	var dx: float = float(b[0])-float(a[0]); var dy: float = float(b[1])-float(a[1])
	return sqrt(dx*dx+dy*dy)

func _save(prefix: String, label: String, value: Variant) -> void:
	if not prefix.is_empty(): FileAccess.open(prefix+"."+label+".json",FileAccess.WRITE).store_string(JSON.stringify(value,"\t"))

func _observe(suite: RefCounted, sim: HospitalSimulation, trace: Array, errors: Array) -> void:
	var before: Dictionary = {}
	for id: String in sim.world.ids("actors"):
		var actor: Dictionary = sim.world.facts.actors[id]
		before[id] = {"cell":actor.location.cell.duplicate(),"rect":sim.space.body_rectangle(actor)}
	var tick: int = sim.world.sim_tick
	suite._movement_tick(sim)
	if sim.world.sim_tick!=tick+1: errors.append("Changed fixed boundary")
	var poses: Dictionary = {}; var ids: Array = sim.world.ids("actors")
	for index: int in ids.size():
		var id: String = ids[index]; var actor: Dictionary = sim.world.facts.actors[id]
		var rectangle: Rect2 = sim.space.body_rectangle(actor)
		var distance: float = _distance(before[id].cell,actor.location.cell)
		var budget: float = sim.space.walking_speed(actor)*0.1
		if distance>budget+ROUNDING: errors.append("Step budget exceeded: "+id)
		poses[id] = {"cell":actor.location.cell.duplicate(),"facing":actor.facing,"step_cells":distance,"nominal_budget":budget}
		for other_index: int in range(index+1,ids.size()):
			var other: String = ids[other_index]; var other_rect: Rect2 = sim.space.body_rectangle(sim.world.facts.actors[other])
			if rectangle.intersects(other_rect,false) or BodySweep.intersects(before[id].rect,rectangle,before[other].rect,other_rect): errors.append("Strict body/sweep overlap: "+id+"/"+other)
	var validation: String = sim.world.validate(suite.content)
	if not validation.is_empty(): errors.append(validation)
	trace.append({"tick":sim.world.sim_tick,"poses":poses,"movement":sim.world.facts.moves.get("walker",{}).duplicate(true)})

func _journey(suite: RefCounted, data: Dictionary, evidence: String) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	var start: Array = data.start; var goal: Array = data.goal; var group: bool = data.get("group",false)
	suite._add_actor(sim,"walker",data.get("species","S49"),start)
	var members: Array = ["walker","follower"]
	if group:
		var direction: Vector2 = (ConvoyTrail.point(goal)-ConvoyTrail.point(start)).normalized()
		var tail: Vector2 = ConvoyTrail.point(start)-direction*2.0
		suite._add_actor(sim,"follower","S49",[tail.x,tail.y])
	var rear_gap: float = 0.0; var backstep_blocked: bool = false
	if data.get("rear",false):
		suite._add_actor(sim,"rear","S49",[34.53363037109375,80])
		var a: Rect2 = sim.space.body_rectangle(sim.world.facts.actors.walker)
		var b: Rect2 = sim.space.body_rectangle(sim.world.facts.actors.rear)
		rear_gap = a.position.x-b.end.x
		var rounded: Dictionary = sim.world.facts.actors.walker.duplicate(true); rounded.location.cell=[35,80]
		backstep_blocked = BodySweep.intersects(a,sim.space.body_rectangle(rounded),b,b)
	var initial_validation: String = sim.world.validate(suite.content)
	_save(evidence,data.name+".input",sim.world.freeze())
	var location: Dictionary = sim.world.facts.actors.walker.location.duplicate(true)
	var request: String = sim.space.request_group_move(sim.world,"walker",members,{},1,goal) if group else sim.space.request_move(sim.world,"walker",1,goal)
	var no_jump: bool = location==sim.world.facts.actors.walker.location
	var sequence: int = int(sim.world.facts.moves.get("walker",{}).get("request_sequence",-1))
	var trace: Array = []; var errors: Array = []; var motion_steps: int = 0; var original: bool = true; var first_dot: float = 0.0
	for tick: int in 180:
		var before: Array = sim.world.facts.actors.walker.location.cell.duplicate()
		_observe(suite,sim,trace,errors)
		var actual: Array = sim.world.facts.actors.walker.location.cell
		if _distance(before,actual)>0.0: motion_steps+=1
		if tick==0: first_dot=(float(actual[0])-float(start[0]))*(float(goal[0])-float(start[0]))+(float(actual[1])-float(start[1]))*(float(goal[1])-float(start[1]))
		var movement: Dictionary = sim.world.facts.moves.get("walker",{})
		if movement.is_empty(): break
		original = original and movement.target_cell==goal and int(movement.request_sequence)==sequence
		# A completed path must describe an actually reached binary32 endpoint.
		if int(movement.cursor)>=movement.path.size() and not movement.get("route_pending",false) and ConvoyTrail.point(actual)!=ConvoyTrail.point(goal): errors.append("Premature endpoint checkpoint")
	var actual: Array = sim.world.facts.actors.walker.location.cell.duplicate()
	var arrival: bool = ConvoyTrail.point(actual)==ConvoyTrail.point(goal) and not sim.world.facts.moves.has("walker")
	var expected_steps: int = data.get("expected_motion_steps",-1)
	var checks: Dictionary = {"valid_input":initial_validation.is_empty(),"accepted":request.is_empty(),"request_no_jump":no_jump,"safe_bounded_real_steps":errors.is_empty(),"original_goal_and_sequence":original,"exact_published_arrival":arrival,"selected_motion_step_count":expected_steps<0 or motion_steps==expected_steps,"first_boundary_forward":not data.get("forward_first",false) or first_dot>0.0,"legal_rear_witness":not data.get("rear",false) or rear_gap>0.0 and backstep_blocked}
	var ok: bool = true
	for value: bool in checks.values(): ok=ok and value
	var row: Dictionary = {"name":data.name,"ok":ok,"checks":checks,"input_validation":initial_validation,"request":request,"start":start,"goal":goal,"final":actual,"expected_motion_steps":expected_steps,"motion_steps":motion_steps,"boundaries":trace.size(),"first_boundary_dot":first_dot,"rear_gap":rear_gap,"old_backward_sweep_blocked":backstep_blocked,"speed":sim.space.walking_speed(sim.world.facts.actors.walker),"errors":errors,"trace":trace}
	_save(evidence,data.name+".final",sim.world.freeze()); sim.dispose(); return row

func _blocked_restore(suite: RefCounted, group: bool, evidence: String) -> Dictionary:
	var name: String = "convoy_blocked_restore_resume" if group else "single_blocked_restore_resume"
	var sim: HospitalSimulation = suite._fixture()
	var observer: ContactObserver = ContactObserver.new(sim.space)
	sim.space.movement=observer
	suite._add_actor(sim,"walker","S49",[40,80])
	if group: suite._add_actor(sim,"follower","S49",[38,80])
	suite._add_actor(sim,"blocker","S49",[41.2,80])
	var validation: String = sim.world.validate(suite.content)
	_save(evidence,name+".input",sim.world.freeze())
	var goal: Array = [44.625,80]
	var request: String = sim.space.request_group_move(sim.world,"walker",["walker","follower"],{},1,goal) if group else sim.space.request_move(sim.world,"walker",1,goal)
	var sequence: int = int(sim.world.facts.moves.get("walker",{}).get("request_sequence",-1))
	var trace: Array = []; var errors: Array = []; var blocked: bool = false; var atomic: bool = false
	for tick: int in 12:
		_observe(suite,sim,trace,errors)
		# Courtesy can reset blocked_since while installing the detour during
		# this same boundary. Observe the actual rejected attempt instead.
		if observer.blocked_step:
			blocked=true; atomic=observer.rejected_pose_atomic; break
	var frozen: Dictionary = sim.world.freeze(); _save(evidence,name+".blocked",frozen)
	sim.dispose(); sim=HospitalSimulation.new(WorldState.new(frozen),suite.content)
	var restored: bool = frozen==sim.world.freeze()
	var release: String = sim.space.request_move(sim.world,"blocker",1,[41.2,84])
	var original: bool = true
	for tick: int in 180:
		_observe(suite,sim,trace,errors)
		var movement: Dictionary = sim.world.facts.moves.get("walker",{})
		if movement.is_empty(): break
		original=original and movement.target_cell==goal and int(movement.request_sequence)==sequence
	var arrived: bool = not sim.world.facts.moves.has("walker") and ConvoyTrail.point(sim.world.facts.actors.walker.location.cell)==ConvoyTrail.point(goal)
	var row: Dictionary = {"name":name,"ok":validation.is_empty() and request.is_empty() and blocked and atomic and restored and release.is_empty() and original and arrived and errors.is_empty(),"input_validation":validation,"request":request,"blocked":blocked,"rejected_pose_atomic":atomic,"cold_runtime_facts_equal":restored,"blocker_release_request":release,"original_goal_and_sequence":original,"actual_arrival":arrived,"errors":errors,"trace":trace}
	_save(evidence,name+".final",sim.world.freeze()); sim.dispose(); return row
