extends SceneTree

const Observer = preload("res://tools/performance/current/comprehensive_observer.gd")
var _content: HospitalContent
var _checks: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_content=HospitalContent.new()
	if not _content.error.is_empty():
		_checks.content={"passed":false,"error":_content.error}
	else:
		_medical_cases()
		_identity_cases()
		_return_cases()
	var passed: bool=not _checks.is_empty()
	for row: Dictionary in _checks.values(): passed=passed and bool(row.passed)
	var result: Dictionary={"passed":passed,"checks":_checks,"scope":"Observer computation boundaries only; no production steps, completed clinical services or business coverage are claimed."}
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			var path: String=arg.trim_prefix("--output=")
			if path.is_empty() or FileAccess.file_exists(path): quit(2);return
			var file: FileAccess=FileAccess.open(path,FileAccess.WRITE)
			if file==null: quit(2);return
			file.store_string(JSON.stringify(result,"\t"));file.close()
	print("OBSERVER_CONTRACT "+JSON.stringify(result))
	quit(0 if passed else 1)

# These are observation inputs for the classifier, not gameplay checkpoints or
# evidence of prior medical work. Negative rows deliberately violate its rule.
func _world(phase: String = "wait_surgery") -> WorldState:
	var world: WorldState=HospitalFactory.create("observer-contract","观察器计算边界",false,_content)
	world.facts.sim_tick=100
	world.facts.visits["visit"]={"id":"visit","phase":phase}
	world.facts.facilities["bed"]={"id":"bed","floor_id":1,"room_id":"ward"}
	world.facts.facilities["same_ward"]={"id":"same_ward","floor_id":1,"room_id":"ward"}
	world.facts.facilities["other_ward"]={"id":"other_ward","floor_id":1,"room_id":"other"}
	world.facts.facilities["other_floor"]={"id":"other_floor","floor_id":2,"room_id":"ward"}
	world.facts.visitors={"stays":{}}
	return world

func _ward(actor_id: String = "companion") -> Dictionary:
	return {"id":"stay","visit_id":"visit","bed_id":"bed","bed_owner_id":"stay","phase":"waiting_surgery","attempt_id":"","remaining_ticks":0,"care_completed":false,"admitted_tick":1,"transfer_from_bed_id":"","companion_evaluated":true,"companion_qualified":true,"companion_actor_id":actor_id,"visitor_day":-1,"visitor_intent":false,"patient_in_ward":true,"medical":false}

func _frame() -> Dictionary:
	return {"visits":{},"wards":{},"attempts":{},"families":{},"actors":{}}

func _check(name: String, passed: bool, details: Dictionary) -> void:
	_checks[name]={"passed":passed,"details":details}

func _medical_cases() -> void:
	var rows: Array=[
		{"name":"future_care_does_not_exclude","kind":"","facility":"bed","visit":"visit","expected":false},
		{"name":"same_ward_care","kind":"care","facility":"same_ward","visit":"visit","expected":true},
		{"name":"same_ward_outpatient","kind":"outpatient","facility":"same_ward","visit":"visit","expected":true},
		{"name":"other_ward_care","kind":"care","facility":"other_ward","visit":"visit","expected":false},
		{"name":"other_floor_care","kind":"care","facility":"other_floor","visit":"visit","expected":false},
		{"name":"other_visit_care","kind":"care","facility":"bed","visit":"other_visit","expected":false},
		{"name":"nonmedical_session","kind":"gp","facility":"bed","visit":"visit","expected":false}]
	for row: Dictionary in rows:
		var world: WorldState=_world()
		var ward: Dictionary=_ward()
		ward.phase="recovery"
		if not str(row.kind).is_empty(): world.facts.sessions["session"]={"visit_id":row.visit,"kind":row.kind,"facility_id":row.facility}
		var actual: bool=Observer.new(_content)._medical(world,ward)
		_check(row.name,actual==bool(row.expected),{"actual":actual,"expected":row.expected})
	for offset: int in [-1,0,1,2]:
		var world: WorldState=_world()
		world.facts.visitors.stays["family"]={"visit_id":"visit","yielding":true,"yield_requested_tick":world.sim_tick-offset}
		var actual: bool=Observer.new(_content)._medical(world,_ward())
		_check("yield_request_age_"+str(offset),actual==(offset>=0 and offset<=1),{"actual":actual,"age_ticks":offset})
	for same_visit: bool in [false,true]:
		var world: WorldState=_world()
		world.facts.visitors.stays["family"]={"visit_id":"visit" if same_visit else "other_visit","yielding":not same_visit,"yield_requested_tick":world.sim_tick}
		var actual: bool=Observer.new(_content)._medical(world,_ward())
		_check("unrelated_yield" if not same_visit else "not_yielding",not actual,{"actual":actual})

func _identity_cases() -> void:
	var rows: Array=[
		{"name":"active_identity_kept","phase":"wait_surgery","new_id":"companion","actor":true,"stay":true,"reject":false},
		{"name":"active_identity_cleared","phase":"wait_surgery","new_id":"","actor":false,"stay":false,"reject":true},
		{"name":"active_identity_replaced","phase":"wait_surgery","new_id":"replacement","actor":true,"stay":true,"reject":true},
		{"name":"terminal_actor_still_present","phase":"ward_referral","new_id":"","actor":true,"stay":false,"reject":true},
		{"name":"terminal_family_still_present","phase":"ward_referral","new_id":"","actor":false,"stay":true,"reject":true},
		{"name":"terminal_other_family_role_remains","phase":"ward_referral","new_id":"","actor":false,"stay":true,"stay_actor":"short_visitor","purpose":"ward_visit","reject":false},
		{"name":"terminal_nonempty_replacement","phase":"ward_referral","new_id":"replacement","actor":false,"stay":false,"reject":true}]
	for phase: String in ["leaving","departed","ward_referral"]:
		rows.append({"name":"retired_identity_"+phase,"phase":phase,"new_id":"","actor":false,"stay":false,"reject":false})
	for row: Dictionary in rows:
		var world: WorldState=_world(str(row.phase))
		if row.actor: world.facts.actors["companion"]={"id":"companion","location":{"kind":"outside"}}
		if row.stay: world.facts.visitors.stays["family"]={"actor_id":row.get("stay_actor","companion"),"visit_id":"visit","purpose":row.get("purpose","companion"),"phase":"outside"}
		var before: Dictionary=_frame()
		var after: Dictionary=_frame()
		before.wards["stay"]=_ward()
		after.wards["stay"]=_ward(str(row.new_id))
		if row.phase in ["leaving","departed","ward_referral"]: after.wards.stay.phase="referral_release"
		var observer: RefCounted=Observer.new(_content)
		observer._observe_clinical(before,after,world,{"work":{}})
		var rejected: bool=observer.errors.any(func(message: String)->bool:return message.begins_with("Fixed companion identity changed"))
		_check(row.name,rejected==bool(row.reject) and observer.errors.size()==(1 if row.reject else 0),{"errors":observer.errors,"expected_rejection":row.reject})

func _return_cases() -> void:
	var rows: Array=[
		{"phase":"wait_surgery","inside":false,"reject":true},
		{"phase":"wait_surgery","inside":true,"reject":false},
		{"phase":"leaving","inside":false,"reject":false},
		{"phase":"departed","inside":false,"reject":false},
		{"phase":"ward_referral","inside":false,"reject":false}]
	for row: Dictionary in rows:
		var world: WorldState=_world(str(row.phase))
		var before: Dictionary=_frame()
		var after: Dictionary=_frame()
		var family: Dictionary={"actor_id":"companion","visit_id":"visit","purpose":"companion","phase":"walking","remaining_ticks":0,"life_phase":"returning","return_ward_first":true,"destination":{},"own_family_move":false,"inside_ward":false,"overlaps_ward":false,"patient_in_ward":true,"medical":false,"ward_phase":"waiting_surgery","yielding":false}
		before.families["family"]=family.duplicate(true)
		family.return_ward_first=false
		family.inside_ward=bool(row.inside)
		after.families["family"]=family
		var observer: RefCounted=Observer.new(_content)
		observer._observe_clinical(before,after,world,{"work":{}})
		var rejected: bool=observer.errors.any(func(message: String)->bool:return message.begins_with("Companion skipped real ward return"))
		_check("return_"+str(row.phase)+("_inside" if row.inside else "_outside"),rejected==bool(row.reject) and observer.errors.size()==(1 if row.reject else 0),{"errors":observer.errors,"expected_rejection":row.reject})
