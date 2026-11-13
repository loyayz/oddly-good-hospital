extends SceneTree
func original(movement: Dictionary) -> Dictionary:
	var path: Array = movement.get("route_waypoint",{}).get("continuation",movement.get("path",[]).slice(int(movement.get("cursor",0))))
	for segment: Dictionary in path:
		if segment.kind=="connector": return segment
	return {}
func _initialize() -> void:
	var checked: int=0
	for size: int in range(0,12):
		for connector: int in range(-1,size):
			var path: Array=[]
			for index: int in size: path.append({"kind":"connector" if index==connector else "walk","index":index})
			for cursor: int in range(-20,21):
				for mode: int in 4:
					var movement: Dictionary={"path":path,"cursor":cursor}
					if mode==1: movement.route_waypoint={}
					elif mode==2: movement.route_waypoint={"continuation":[]}
					elif mode==3: movement.route_waypoint={"continuation":[{"kind":"walk"},{"kind":"connector","index":99}]}
					var before: Dictionary=movement.duplicate(true)
					var expected: Dictionary=original(movement)
					var actual: Dictionary=HospitalTransit.journey(movement)
					if expected!=actual or before!=movement or (not expected.is_empty() and not is_same(expected,actual)):
						push_error("journey mismatch");quit(2);return
					checked+=1
	print("JOURNEY_EQUIVALENCE="+JSON.stringify({"passed":true,"checked":checked,"scope":"slice boundary, waypoint override, input unchanged, returned dictionary identity"}))
	quit(0)
