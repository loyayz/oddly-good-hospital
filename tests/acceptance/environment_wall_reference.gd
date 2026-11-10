extends HospitalEnvironment

# Independent raw-fact predicates for wall/door and material scoring checks.
# No prepared geometry, candidate index or environment edge mask is borrowed.
var room_visits: int = 0
var door_visits: int = 0

func _wall_edge(world: WorldState, floor_id: int, cell: Array, edge: String) -> bool:
	var offset: Array = {"north":[0,-1],"south":[0,1],"west":[-1,0],"east":[1,0]}.get(edge,[])
	if offset.is_empty():
		return false
	var other: Array = [int(cell[0])+int(offset[0]),int(cell[1])+int(offset[1])]
	return other in world.facts.floors.overrides.get(str(floor_id),{}).get("blocked",[]) or _wall_between(world,floor_id,cell,other)

func _wall_between(world: WorldState, floor_id: int, first: Array, second: Array, _geometry: FloorStaticGeometry = null) -> bool:
	if first==second:
		return false
	var horizontal: bool = int(first[1])!=int(second[1])
	var axis: String = "x" if horizontal else "y"
	var line: int = maxi(int(first[1]),int(second[1])) if horizontal else maxi(int(first[0]),int(second[0]))
	var along: int = int(first[0]) if horizontal else int(first[1])
	for room: Dictionary in world.facts.rooms.values():
		room_visits += 1
		if int(room.floor_id)!=floor_id:
			continue
		for wall: Dictionary in BuildGeometry.room_walls(room):
			if wall.axis!=axis or int(wall.line)!=line or along<int(wall.low) or along>=int(wall.high):
				continue
			var opening: bool = false
			for door: Dictionary in world.facts.floors.overrides.get(str(floor_id),{}).get("doors",[]):
				door_visits += 1
				var door_line: int = int(door.cell[1] if horizontal else door.cell[0])
				var door_start: int = int(door.cell[0] if horizontal else door.cell[1])
				var span: int = int(world.facts.adaptations.get(door.id,{}).get("span",door.span))
				if door.room_id==room.id and door.axis==axis and door_line==line and along>=door_start and along<door_start+span:
					opening = true
					break
			if not opening:
				return true
	return false
