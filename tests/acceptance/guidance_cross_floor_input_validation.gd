extends "res://tests/acceptance/guidance_cross_floor_exit.gd"

# Independently reproduces the starting boundary used by _actual_exit, without
# calling advance(), route(), or changing the original execution/test files.
func validate_inputs(database: HospitalContent) -> Dictionary:
	_content=database
	var cases: Array=[]
	var passed: bool=true
	for source_floor: int in [2,3]:
		for variant: String in ["RIGHT-LIFT-SAFE-FALLBACK","LEFT-LIFT","ROOM-TAIL-DOOR"]:
			var x: Dictionary=_exit_fixture(source_floor)
			if variant=="LEFT-LIFT":
				x.world.facts.connectors.lift.cell=[35,84]
				x.world.facts.connectors.lift.anchor=[36,88]
				x.world.facts.connectors.lift.repair_cell=[34,85]
			if variant=="ROOM-TAIL-DOOR":
				var ground_layout: Dictionary=x.world.facts.floors.overrides["1"]
				x.world.facts.floors.overrides["1"]=x.world.facts.floors.overrides[str(source_floor)]
				HospitalFactory._add_room(x.world,{"id":"departure_room","type":"gp","anchor":[45,81],"size":[10,10],"door":{"definition_id":"DR04","offset":5}},_content)
				x.world.facts.floors.overrides["1"]=ground_layout
				x.world.facts.rooms.departure_room.floor_id=source_floor
				x.world.facts.facilities.upper_guide.room_id="departure_room"
			x.world.touch()
			var stationary: Dictionary=_visit(x,"stationary_queue_member",[48,85])
			x.world.facts.actors[stationary.actor_id].location.floor_id=source_floor
			x.world.touch()
			var reason: String=x.world.validate(_content)
			var row: Dictionary={"source_floor":source_floor,"variant":variant,"ok":reason.is_empty(),"input_validation":reason,"departure_room":x.world.facts.rooms.get("departure_room",{}).duplicate(true),"lift":x.world.facts.connectors.lift.duplicate(true),"source_doors":x.world.facts.floors.overrides[str(source_floor)].doors.duplicate(true),"actor":x.world.facts.actors[x.exit_visit.actor_id].duplicate(true),"stationary_actor":x.world.facts.actors[stationary.actor_id].duplicate(true),"scope":"starting-world schema/business validation only; no movement or final-world validation"}
			cases.append(row);passed=passed and row.ok
			_dispose(x)
	return {"passed":passed,"cases":cases,"fixture_source_sha256":FileAccess.get_sha256("res://tests/acceptance/guidance_cross_floor_exit.gd")}
