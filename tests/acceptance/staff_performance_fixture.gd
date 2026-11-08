extends SceneTree

# Input integrity only: no measured simulation steps or performance claims.
func _initialize() -> void:
	var content: HospitalContent = HospitalContent.new()
	var fixture = preload("res://tools/performance/fixture.gd").new(content,160)
	var world: WorldState = fixture.world
	var summary: Dictionary = fixture.describe()
	var checks: Dictionary = {"content":content.error.is_empty(),"input":fixture.errors.is_empty(),"population":summary.actors==160 and summary.staff==32 and summary.patients==120 and summary.visitors==8,"roles":true,"desks":true}
	for staff: Dictionary in world.facts.staff.values():
		checks.roles = checks.roles and staff.role in ["doctor","nurse","cleaner","researcher"]
	for floor_id: int in [1,2,3,4]:
		var found: bool = false
		for facility: Dictionary in world.facts.facilities.values():
			if facility.definition_id=="SE01" and int(facility.floor_id)==floor_id: found = true
			checks.desks = checks.desks and facility.definition_id!="FUR01"
		checks.desks = checks.desks and found
	var validation: String = world.validate(content)
	checks.world = validation.is_empty()
	print(JSON.stringify({"checks":checks,"summary":summary,"validation":validation,"performance_measurement":false}))
	quit(1 if checks.values().has(false) else 0)
