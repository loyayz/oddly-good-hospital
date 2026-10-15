extends SceneTree

var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var content: HospitalContent = HospitalContent.new()
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"空间边界",false,content)
	var space: HospitalSpace = HospitalSpace.new(content)
	var building: BuildService = BuildService.new(content,space)
	var cells: Array = []
	for y: int in range(68,76):
		for x: int in range(34,42):
			if x<38 or y<72:
				cells.append([x,y])
	var built: CommandResult = building.execute(world,"build_room",{"id":"review_rest","room_type_id":"rest","floor_id":1,"cells":cells,"door":{"edge":"west","offset":1}})
	_check("normal_build_accepts_L_room",built.accepted)
	if not built.accepted:
		print(built.reason)
		_finish()
		return
	var room: Dictionary = world.facts.rooms.review_rest
	var finance: FinanceService = FinanceService.new(content,space)
	finance.ensure(world)
	_check("operating_cost_uses_48_actual_cells",finance.operating_rate(world)==848)
	_check("L_room_forecast_charges_42_not_43",finance.forecast(world)[0].operations==42)
	var environment: HospitalEnvironment = HospitalEnvironment.new(content,space)
	environment.ensure(world)
	var before: Dictionary = world.freeze()
	_check("actual_room_wall_can_be_painted",environment.renovation_quote(world,{"floor_id":1,"material_id":"MAT05","allow_waiting":true,"units":[{"cell":[36,68],"edge":"north"}]}).ok)
	_check("door_opening_is_not_paintable_wall",not environment.renovation_quote(world,{"floor_id":1,"material_id":"MAT05","allow_waiting":true,"units":[{"cell":[34,69],"edge":"west"}]}).ok)
	_check("unowned_plot_boundary_is_not_wall",not environment.renovation_quote(world,{"floor_id":1,"material_id":"MAT05","allow_waiting":true,"units":[{"cell":[32,80],"edge":"west"}]}).ok)
	_check("closed_wall_blocks_environment",not environment._coverage(world,1,[36,68],1,false).has("36:67"))
	_check("closed_wall_blocks_noise",not environment._coverage(world,1,[36,68],1,true).has("36:67"))
	_check("actual_door_allows_environment",environment._coverage(world,1,[33,69],1,false).has("34:69"))
	_check("actual_door_allows_noise",environment._coverage(world,1,[33,69],1,true).has("34:69"))
	_check("L_notch_is_public_region",environment._room_at(world,1,[40,74]).is_empty())
	_check("actual_interior_keeps_room_identity",environment._room_at(world,1,[35,74])=="review_rest")
	_check("spatial_and_financial_queries_are_read_only",before==world.freeze())
	var dirt_id: String = environment.spawn_dirt(world,"CL01","review-outside","review-outside:1",1,[36,67])
	_check("outside_dirt_is_real",not dirt_id.is_empty() and world.facts.environment.dirt[dirt_id].cell==[36,67])
	_check("real_dirt_does_not_cross_closed_wall",environment.environment_at(world,1,[36,68]).dirt==0)
	world.facts.environment.surfaces["near"] = {"floor_id":1,"cell":[36,68],"surface":"wall","edge":"north","material_id":"MAT05","paid_cost":20,"order_id":"near"}
	world.facts.environment.surfaces["far"] = {"floor_id":1,"cell":[37,68],"surface":"wall","edge":"north","material_id":"MAT08","paid_cost":50,"order_id":"far"}
	var base: int = int(content.balance.environment.base)+int(content.balance.environment.clean_bonus)
	_check("nearest_wall_owns_material_effect",environment.environment_at(world,1,[36,68]).value==base+4)
	world.facts.actors.review_staff = {"id":"review_staff","name":"茶歇员工","species_id":"S49","location":{"kind":"floor","floor_id":1,"cell":[40,74],"height_m":0.0},"facing":0.0,"posture":"standing"}
	world.facts.staff.review_staff = {"id":"review_staff","role":"cleaner","energy":50.0,"life_task":{"phase":"idle"}}
	var wellbeing: HospitalStaffWellbeing = HospitalStaffWellbeing.new(content,space)
	_check("tea_rejects_outdoor_notch",not wellbeing._tea_cell(world,"review_staff",room,[40,74]))
	_check("tea_accepts_actual_interior",wellbeing._tea_cell(world,"review_staff",room,[35,74]))
	before = world.freeze()
	var tea: Dictionary = wellbeing._tea_position(world,"review_staff")
	_check("automatic_tea_target_is_inside_L_room",not tea.is_empty() and BuildGeometry.contains(room,tea.cell))
	_check("tea_query_does_not_move_staff",before==world.freeze())
	_finish()

func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures.append(label)
	print(("PASS " if passed else "FAIL ")+label)

func _finish() -> void:
	print("REVIEW_SPACE checks="+str(checks)+" failures="+str(failures))
	quit(0 if failures.is_empty() else 1)
