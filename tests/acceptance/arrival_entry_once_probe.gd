extends SceneTree

class CountingSpace extends HospitalSpace:
	var checks: int = 0
	var dynamics: int = 0
	var blocked: bool = false
	var occupied: bool = false
	func static_reason(world: WorldState, actor: Dictionary, floor_id: int, origin: Vector2i, members: Array = [], offsets: Dictionary = {}) -> String:
		checks += 1
		if blocked: return "blocked_for_boundary_test"
		return super.static_reason(world,actor,floor_id,origin,members,offsets)
	func _dynamic_clear(world: WorldState, actor_id: String, floor_id: int, rect: Rect2, members: Array = [], actors_checked: bool = false) -> bool:
		dynamics += 1
		if occupied: return false
		return super._dynamic_clear(world,actor_id,floor_id,rect,members,actors_checked)

class DenyingClinic extends HospitalClinic:
	var calls: int = 0
	func arrival_readiness(_world: WorldState, _binding_id: String, _complex_case: bool = false, _explain: bool = true) -> Dictionary:
		calls += 1
		return {"ok":false,"reason":"extension_denied","plans":[]}

var db: HospitalContent
var rows: Array = []
func context() -> Dictionary:
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"entry boundary",true,db)
	var space: CountingSpace = CountingSpace.new(db)
	return {"world":world,"space":space,"clinic":HospitalClinic.new(db,space)}
func payload() -> Dictionary:
	return {"arrival_key":"one","binding_id":"B_S13_D09_M09","requested_plan_id":"P_D09_COMMON","personality_id":"PP01"}
func check(name: String, ok: bool, detail: Dictionary) -> void:
	rows.append({"name":name,"ok":ok,"detail":detail})
func _initialize() -> void:
	db = HospitalContent.new()
	var c: Dictionary = context()
	var before: Dictionary = c.world.freeze()
	var ready: Dictionary = c.clinic.arrival_readiness(c.world,"B_S13_D09_M09")
	check("public_readiness_full_and_readonly",ready.ok and c.space.checks==1 and before==c.world.freeze(),ready)
	c.space.checks = 0
	var r: CommandResult = c.clinic._arrive(c.world,payload())
	check("standard_arrival_one_static_one_dynamic",r.accepted and c.space.checks==1 and c.space.dynamics==1,{"result":r.to_record(),"static":c.space.checks,"dynamic":c.space.dynamics})
	var duplicate: CommandResult = c.clinic._arrive(c.world,payload())
	check("duplicate_no_recheck",duplicate.accepted and c.space.checks==1 and c.space.dynamics==1,duplicate.to_record())
	c = context()
	c.space.blocked = true
	before = c.world.freeze()
	r = c.clinic._arrive(c.world,payload())
	check("blocked_entry_preserved",not r.accepted and c.space.checks==1 and c.space.dynamics==0 and before==c.world.freeze(),r.to_record())
	ready = c.clinic.arrival_readiness(c.world,"B_S13_D09_M09")
	check("public_readiness_still_checks_blockage",not ready.ok and c.space.checks==2,ready)
	c = context()
	c.space.occupied = true
	before = c.world.freeze()
	r = c.clinic._arrive(c.world,payload())
	check("occupied_entry_preserved",not r.accepted and c.space.checks==1 and c.space.dynamics==1 and before==c.world.freeze(),r.to_record())
	c = context()
	var custom: DenyingClinic = DenyingClinic.new(db,c.space)
	before = c.world.freeze()
	r = custom._arrive(c.world,payload())
	check("overridden_readiness_honored",not r.accepted and custom.calls==1 and before==c.world.freeze(),r.to_record())
	c = context()
	c.world.facts.gameplay_version = 0
	r = c.clinic._arrive(c.world,payload())
	check("legacy_arrival_unchanged",r.accepted and c.space.checks==1 and c.space.dynamics==1,r.to_record())
	c = context()
	var locked: Dictionary = {}
	for binding: Dictionary in db.catalog.treatment_bindings:
		if not HospitalResearch.disease_unlocked(c.world,db,binding.disease_id):
			locked = binding
			break
	var p: Dictionary = payload()
	if not locked.is_empty():
		p.binding_id = locked.id
		p.requested_plan_id = "P_"+str(locked.disease_id)+"_COMMON"
		before = c.world.freeze()
		ready = c.clinic.arrival_readiness(c.world,locked.id)
		r = c.clinic._arrive(c.world,p)
		check("research_locked_preserved",not ready.ok and not r.accepted and before==c.world.freeze(),{"readiness":ready,"arrival":r.to_record()})
	else: check("research_locked_preserved",false,{"error":"no locked binding"})
	var ok: bool = true
	for row: Dictionary in rows: ok = ok and row.ok
	var result: Dictionary = {"ok":ok,"checks":rows}
	print(JSON.stringify(result))
	FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	quit(0 if ok else 1)
