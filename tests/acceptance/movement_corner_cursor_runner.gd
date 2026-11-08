extends SceneTree

# A published position beside a corner has not reached the next route leg.
# Calculation boundary regression; actual detour/convoy movement stays in
# SPACE-10/55/56. No saved world, timing thresholds or production snapping.
func _initialize() -> void:
	var space: HospitalSpace = HospitalSpace.new(HospitalContent.new())
	var movement: HospitalMovement = space.movement
	var actor: Dictionary = {"location":{"kind":"floor","floor_id":1,"cell":[52.0,79.9999694824219]}}
	var path: Array = [_point(1,[52,80]),_point(1,[51,80])]
	var checks: Dictionary = {}
	checks.near_perpendicular_corner_not_skipped = movement._initial_route_cursor(actor,path)==0
	checks.existing_step_reaches_corner_exactly = movement._step_toward(Vector2(52,79.9999694824219),Vector2(52,80),0.2)==Vector2(52,80)
	var axes: Array = [[[52,80],[53,80],[52.5,80]],[[52,80],[51,80],[51.5,80]],[[52,80],[52,81],[52,80.5]],[[52,80],[52,79],[52,79.5]]]
	for index: int in axes.size():
		var row: Array = axes[index]
		path = [_point(1,row[0]),_point(1,row[1])]
		actor.location.cell = row[2]
		checks["between_axis_"+str(index)] = movement._initial_route_cursor(actor,path)==1
		var leg: Vector2 = Vector2(row[1][0]-row[0][0],row[1][1]-row[0][1])
		actor.location.cell = [float(row[0][0])-leg.y*0.00003,float(row[0][1])+leg.x*0.00003]
		checks["perpendicular_corner_"+str(index)] = movement._initial_route_cursor(actor,path)==0
		actor.location.cell = [float(row[2][0])-leg.y*0.01,float(row[2][1])+leg.x*0.01]
		checks["off_line_requires_geometry_"+str(index)] = movement._initial_route_cursor(actor,path)==0
	actor.location.cell = [52.5,80.0]
	checks.beyond_first_not_skipped = movement._initial_route_cursor(actor,[_point(1,[52,80]),_point(1,[51,80])])==0
	checks.beyond_second_not_skipped = movement._initial_route_cursor(actor,[_point(1,[54,80]),_point(1,[53,80])])==0
	checks.connector_first_not_skipped = movement._initial_route_cursor(actor,[{"kind":"connector","from":1,"to":2},_point(1,[53,80])])==0
	checks.connector_second_not_skipped = movement._initial_route_cursor(actor,[_point(1,[52,80]),{"kind":"connector","from":1,"to":2}])==0
	checks.other_floor_not_skipped = movement._initial_route_cursor(actor,[_point(2,[52,80]),_point(2,[53,80])])==0
	checks.cross_floor_not_skipped = movement._initial_route_cursor(actor,[_point(1,[52,80]),_point(2,[53,80])])==0
	checks.single_point_not_skipped = movement._initial_route_cursor(actor,[_point(1,[52,80])])==0
	actor.location.cell = [52.5,80.5]
	checks.diagonal_midpoint_keeps_forward_travel = movement._initial_route_cursor(actor,[_point(1,[52,80]),_point(1,[53,81])])==1
	var ok: bool = not checks.values().has(false)
	print(JSON.stringify({"ok":ok,"checks":checks}))
	quit(0 if ok else 1)

func _point(floor_id: int, cell: Array) -> Dictionary:
	return {"kind":"floor","floor_id":floor_id,"cell":cell}
