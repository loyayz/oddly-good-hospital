extends SceneTree

const SpaceCases = preload("res://tests/acceptance/space.gd")
var suite = SpaceCases.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	suite.content = HospitalContent.new()
	var started: int = Time.get_ticks_usec()
	var rows: Array = []
	var sim: HospitalSimulation = suite._fixture()
	suite._history_height(sim,2)
	suite._add_actor(sim,"leader","S49",[44,80])
	suite._add_actor(sim,"follower","S49",[42,80])
	suite._add_actor(sim,"owner","S49",[52,86])
	HospitalFactory._add_room(sim.world,{"id":"fixture_room","type":"gp","anchor":[48,84],"size":[6,6],"door":{"definition_id":"DR04","offset":1}},suite.content)
	HospitalFactory._add_facility(sim.world,{"id":"reserved_fixture","definition_id":"FUR01","anchor":[49,85],"room_id":"fixture_room","size":suite.content.facility_definition("FUR01").footprint},suite.content)
	var request: String = sim.space.request_group_move(sim.world,"leader",["leader","follower"],{},1,[48,80])
	var input: Dictionary = sim.world.freeze()
	var initial_error: String = WorldState.new(input.duplicate(true)).validate(suite.content)
	var all_ok: bool = request.is_empty() and initial_error.is_empty()
	for probe: String in ["unchanged","outsider_gap","outsider_other_floor","outsider_outside_trail","blocked_gap","facility_gap","foreign_reservation","member_reservation","crossing_convoy","wall_gap","low_ceiling"]:
		var world: WorldState = WorldState.new(input.duplicate(true))
		var geometry: HospitalSpace = HospitalSpace.new(suite.content)
		var expected_valid: bool = probe in ["unchanged","outsider_other_floor","outsider_outside_trail","member_reservation"]
		var actual_member_overlap: bool = false
		match probe:
			"outsider_gap", "outsider_other_floor", "outsider_outside_trail":
				world.facts.actors["outsider"] = suite._actor("outsider","S49",[43,81] if probe=="outsider_outside_trail" else [43,80],2 if probe=="outsider_other_floor" else 1)
				for id: String in ["leader","follower"]:
					actual_member_overlap = actual_member_overlap or geometry.body_rectangle(world.facts.actors[id]).intersects(geometry.body_rectangle(world.facts.actors.outsider),false)
			"blocked_gap": world.facts.floors.overrides["1"].blocked.append([43,80])
			"facility_gap": world.facts.facilities.reserved_fixture.cell=[43,80]
			"foreign_reservation", "member_reservation":
				var reservation: Dictionary=world.facts.facilities.reserved_fixture.duplicate(true)
				var owner: String="follower" if probe=="member_reservation" else "owner"
				reservation.merge({"kind":"facility","facility_id":"reserved_fixture","owner_id":owner,"actor_id":owner,"staff_ids":[],"regions":[[43,80,1,1]]},true)
				world.facts.adaptations["reserved_fixture"]=reservation
			"crossing_convoy":
				world.facts.actors["cross_head"]=suite._actor("cross_head","S49",[43,81])
				world.facts.actors["cross_tail"]=suite._actor("cross_tail","S49",[43,79])
				var created: Dictionary=ConvoyTrail.create(geometry,world,"cross_head",["cross_head","cross_tail"])
				var crossing: Dictionary=world.facts.moves.leader.duplicate(true)
				crossing.actor_id="cross_head"
				crossing.members=["cross_head","cross_tail"]
				crossing.convoy=created.convoy
				crossing.erase("request_sequence")
				crossing.route_pending=false
				world.facts.moves["cross_head"]=crossing
			"wall_gap":
				world.facts.rooms["restore_wall"]={"id":"restore_wall","kind":"gp","floor_id":1,"origin":[43,79],"size":[4,4],"wall_edges":[{"axis":"y","line":43,"low":79,"high":83}]}
			"low_ceiling":
				world.facts.floors.erase("completed_top_floor")
				world.facts.floors.height_intervals=[{"first":1,"last":2,"height_m":1.0}]
		var before: Dictionary=world.freeze()
		var error: String=world.validate(suite.content)
		var ok: bool=error.is_empty()==expected_valid and before==world.freeze()
		if not expected_valid: ok=ok and error.begins_with("保存队列尾迹")
		if probe=="outsider_gap": ok=ok and not actual_member_overlap and error.begins_with("保存队列尾迹")
		rows.append({"case":probe,"ok":ok,"expected_valid":expected_valid,"validation":error,"actual_member_overlap":actual_member_overlap,"readonly":before==world.freeze()})
		all_ok=all_ok and ok
	sim.dispose()
	var portal: Dictionary = _portal_boundaries()
	rows.append_array(portal.rows)
	all_ok = all_ok and portal.ok
	var result: Dictionary={"ok":all_ok,"initial_request":request,"initial_validation":initial_error,"rows":rows,"elapsed_us":Time.get_ticks_usec()-started,"scope":"Saved ground convoy invariant, including protected trail gaps. No malformed state is advanced as a valid game."}
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if not args.is_empty(): FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print(JSON.stringify(result))
	quit(0 if all_ok else 1)

# Declared input is a legal queue at its landing, matching the transit suite.
# Boarding, riding and alighting are advanced by the actual movement service.
func _portal_boundaries() -> Dictionary:
	var sim: HospitalSimulation = suite._transit_fixture()
	var world: WorldState = sim.world
	var connection: Dictionary = world.facts.connectors[suite._connection(sim)]
	var members: Array = ["portal_head","portal_tail"]
	for id: String in members: suite._add_actor(sim,id,"S49",connection.anchor)
	var form: Dictionary = ConvoyTrail.formation(sim.space,world,members[0],members,Vector2.UP)
	for id: String in members: world.facts.actors[id].location.cell = form.targets[id].duplicate()
	var created: Dictionary = ConvoyTrail.create(sim.space,world,members[0],members)
	var plan: Dictionary = ConvoyPortal.plan(sim.space,world,connection,members[0],members,created.convoy)
	var delta: Vector2 = ConvoyTrail.point(plan.entry)-ConvoyTrail.point(world.facts.actors[members[0]].location.cell)
	for id: String in members:
		var cell: Vector2 = ConvoyTrail.point(world.facts.actors[id].location.cell)+delta
		world.facts.actors[id].location.cell = [cell.x,cell.y]
		sim.space.sync_actor(world,id)
	created = ConvoyTrail.create(sim.space,world,members[0],members)
	var segment: Dictionary = {"kind":"connector","connector_id":connection.id,"from":1,"to":2}
	var movement: Dictionary = {"actor_id":members[0],"members":members,"convoy":created.convoy,"path":[segment],"cursor":0,"travelled":[],"blocked_since":-1,"yielding":false,"target_floor":2,"target_cell":plan.egress.duplicate()}
	world.facts.moves[members[0]]=movement
	world.touch()
	sim.space._sync_convoys(world)
	HospitalTransit.begin(sim.space,world,world.facts.actors[members[0]],movement,segment)
	var rows: Array=[]
	var checked: Dictionary={}
	var ok: bool=true
	for index: int in 150:
		var phase: String=connection.phase
		var regions: Array[Rect2]=ConvoyPortal.ground_regions(movement.convoy,connection)
		if not checked.has(phase) and (phase=="riding" or not regions.is_empty()) and phase in ["boarding","riding","alighting"]:
			checked[phase]=true
			var frozen: Dictionary=world.freeze()
			for probe: String in ["unchanged","outsider_ground","outsider_other_floor"]:
				var candidate: WorldState=WorldState.new(frozen.duplicate(true))
				var expected_valid: bool=probe!="outsider_ground" or phase=="riding"
				if probe!="unchanged":
					# The ride owns no ground. Its former source landing may be
					# occupied; boarding/alighting own only their clipped ground.
					var point: Vector2=ConvoyTrail.point(plan.entry) if phase=="riding" else regions[0].get_center()-Vector2.ONE*0.5
					var floor_id: int=int(movement.convoy.floor_id)
					if probe=="outsider_other_floor": floor_id=2 if floor_id==1 else 1
					candidate.facts.actors["outsider"]=suite._actor("outsider","S49",[point.x,point.y],floor_id)
				var before: Dictionary=candidate.freeze()
				var error: String=candidate.validate(suite.content)
				var passed: bool=error.is_empty()==expected_valid and before==candidate.freeze()
				if not expected_valid: passed=passed and error.begins_with("保存队列尾迹")
				rows.append({"case":phase+"_"+probe,"ok":passed,"expected_valid":expected_valid,"validation":error,"ground_region_count":regions.size(),"readonly":before==candidate.freeze()})
				ok=ok and passed
		if connection.phase=="idle": break
		suite._movement_tick(sim)
	ok=ok and checked.size()==3 and connection.phase=="idle"
	sim.dispose()
	return {"ok":ok,"rows":rows}
