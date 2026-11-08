extends "res://tests/acceptance/floor_guidance.gd"

func run_placement(database: HospitalContent) -> Dictionary:
	_content = database
	var x: Dictionary = _base()
	var builder: BuildService = BuildService.new(database,x.space)
	var checks: Dictionary = {"existing_guidance_fixture":builder.guidance_floor_error(x.world,1).ok}
	# This is a placement geometry fixture, not a claimed patient journey.
	x.world.facts.rooms.clear()
	x.world.facts.facilities.clear()
	x.world.facts.connectors.clear()
	x.world.facts.floors.overrides["1"].blocked = []
	x.world.facts.floors.overrides["1"].doors = []
	var desk: Dictionary = {"id":"placement_desk","definition_id":"SE01","floor_id":1,"cell":[44,84],"footprint":[2,1],"rotation":0}
	x.world.facts.facilities[desk.id] = desk
	for rotation: int in 4:
		desk.rotation = rotation
		desk.footprint = [2,1] if rotation%2==0 else [1,2]
		builder._set_anchors(desk,database.facility_definition("SE01"))
		checks["open_"+str(rotation)] = builder.guidance_front_error(x.world,desk).ok
		var direction: Vector2i = BuildService._rotate_offset(Vector2i(0,1),[2,1],rotation)-BuildService._rotate_offset(Vector2i.ZERO,[2,1],rotation)
		var front: Vector2i = Vector2i(44,84)+BuildService._rotate_offset(Vector2i(0,1),[2,1],rotation)
		for gap: int in [0,1,2,3]:
			# Ray-facing wall edge after gap complete free cells. Negative
			# directions start at the high edge of the first free cell.
			var line: int = (front.y if direction.y!=0 else front.x)+(1 if direction.x+direction.y<0 else 0)+gap*(direction.x+direction.y)
			var wall: Dictionary = {"axis":"x" if direction.y!=0 else "y","line":line,"low":0,"high":96}
			x.world.facts.rooms = {"test_wall":{"id":"test_wall","floor_id":1,"wall_edges":[wall]}}
			checks["wall_"+str(rotation)+"_"+str(gap)] = builder.guidance_front_error(x.world,desk).ok==(gap==3)
		x.world.facts.rooms.clear()
		var blocked: Vector2i = front+direction*2
		x.world.facts.floors.overrides["1"].blocked = [[blocked.x,blocked.y]]
		checks["blocked_"+str(rotation)] = not builder.guidance_front_error(x.world,desk).ok
		x.world.facts.floors.overrides["1"].blocked = []
	# Changes on another floor do not reject this desk; changed-floor safety
	# catches a newly introduced obstacle even when the desk itself is unchanged.
	desk.rotation = 0;desk.footprint = [2,1]
	builder._set_anchors(desk,database.facility_definition("SE01"))
	x.world.facts.floors.overrides["1"].blocked = [[44,86]]
	checks.affected_floor = not builder.guidance_floor_error(x.world,1).ok and builder.guidance_floor_error(x.world,2).ok
	x.world.facts.floors.overrides["1"].blocked = []
	x.world.facts.floors.overrides["1"].doors = [{"id":"front_door","axis":"x","cell":[44,86],"span":2}]
	checks.door_buffer = not builder.guidance_front_error(x.world,desk).ok
	x.world.facts.floors.overrides["1"].doors = []
	desk.cell = [44,94]
	checks.floor_boundary = not builder.guidance_front_error(x.world,desk).ok
	var ok: bool = true
	for value: bool in checks.values(): ok = ok and value
	_dispose(x)
	return {"ok":ok,"checks":checks,"scope":"placement geometry; no engine run claimed by author"}
