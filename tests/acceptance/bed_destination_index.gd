extends RefCounted

const CASES: Array[String] = ["BED-INDEX-COUNT","BED-INDEX-LIFECYCLE","BED-INDEX-OWNER","BED-INDEX-ORACLE","BED-INDEX-STOPS"]
const Oracle = preload("res://tests/acceptance/bed_destination_oracle.gd")
var content: HospitalContent
var boundary: Dictionary = {}
var checks: Dictionary = {}
var details: Dictionary = {}

class CountedSpace extends HospitalSpace:
	var view_calls: int = 0
	func _init(database: HospitalContent) -> void: super(database)
	func reservation_view(world: WorldState) -> Dictionary:
		view_calls+=1
		return super.reservation_view(world)

class CountedMovement extends HospitalMovement:
	var goal_region_calls: int = 0
	func _init(geometry: HospitalSpace) -> void: super(geometry)
	func _bed_goal_regions(world: WorldState, actor: Dictionary, movement: Dictionary) -> Array[Rect2]:
		goal_region_calls+=1
		return super._bed_goal_regions(world,actor,movement)

func _check(name: String, passed: bool, observation: Variant = null) -> void:
	checks[name]=passed
	if not passed: details[name]=observation

# Independent full-facts oracle: no production reservation view/index, summary,
# permission helper or bed-destination helper supplies the expected answer.
func oracle(world: WorldState, actor_id: String, floor_id: int, rect: Rect2, members: Array = []) -> String:
	return Oracle.blocker(world,actor_id,floor_id,rect,members)

func _input() -> Dictionary:
	var h: RefCounted=load("res://tests/acceptance/space.gd").new();h.content=content
	var sim: HospitalSimulation=h._transit_fixture()
	var world: WorldState=sim.world
	for research: Dictionary in content.catalog.research:
		if research.id not in world.facts.research: world.facts.research.append(research.id)
	var build:=BuildService.new(content,sim.space);build._deferred_checks=true
	for floor_id: int in [1,2]:
		HospitalSpace.materialize_layout(world,floor_id)
		build._add_room(world,{"id":"index_ward_"+str(floor_id),"room_type_id":"ward","floor_id":floor_id,"origin":[34,76],"size":[28,16],"doors":[{"definition_id":"DR06","edge":"north","offset":2},{"definition_id":"DR06","edge":"south","offset":14}]})
	var reservations: Dictionary={}
	for row: Array in [["bed_z",1,40],["bed_a",1,50],["bed_c",2,40]]:
		var id: String=row[0];var floor_id: int=row[1];var x: int=row[2]
		build._add_facility(world,{"id":id,"definition_id":"EQ05","floor_id":floor_id,"cell":[x,79],"rotation":0,"room_id":"index_ward_"+str(floor_id)})
		for member: Array in [["p",44],["n",54],["d",58]]:
			h._add_actor(sim,str(member[0])+"_"+id,"S49",[int(member[1]),90 if id!="bed_a" else 87],floor_id)
		h._add_actor(sim,"walker_"+str(floor_id),"S49",[35,90],floor_id)
		var reason: String=sim.space.reserve_facility(world,id,"p_"+id,"p_"+id,["n_"+id,"d_"+id])
		reservations[id]={"reason":reason,"regions":world.facts.adaptations.get(id,{}).get("regions",[]).size()}
	var result: Dictionary={"facts":world.freeze(),"validation":world.validate(content),"reservations":reservations}
	sim.dispose()
	return result

func _case_input() -> Dictionary:
	if boundary.is_empty(): boundary=_input()
	var world:=WorldState.new(boundary.facts.duplicate(true))
	var space:=HospitalSpace.new(content)
	_check("legal_two_floor_boundary",str(boundary.validation).is_empty() and world.validate(content).is_empty(),boundary.validation)
	for id: String in boundary.reservations: _check(id+"_formal_reservation",str(boundary.reservations[id].reason).is_empty() and int(boundary.reservations[id].regions)>2,boundary.reservations[id])
	return {"w":world,"s":space}

func _summary(x: Dictionary, expected: Dictionary, label: String) -> void:
	var view: Dictionary=x.s.reservation_view(x.w)
	_check(label+"_world_valid",x.w.validate(content).is_empty(),x.w.validate(content))
	_check(label,view.destination_claim_floors==expected,{"expected":expected,"actual":view.destination_claim_floors.duplicate()})
	var counted: Dictionary={}
	for id: String in view.destination_claims:
		var floor_id: int=int(view.destination_claims[id]);counted[floor_id]=int(counted.get(floor_id,0))+1
	_check(label+"_one_per_reservation",counted==expected and view.destination_claims.size()==int(expected.get(1,0))+int(expected.get(2,0)),view.destination_claims.duplicate())

func _rect(world: WorldState, id: String, ordinal: int = 1) -> Rect2:
	var area: Array=world.facts.adaptations[id].regions[ordinal]
	return Rect2(float(area[0])+0.1,float(area[1])+0.1,0.2,0.2)

func _oracle_checks(x: Dictionary, label: String) -> void:
	var before: Dictionary=x.w.freeze()
	for id: String in x.w.ids("adaptations"):
		var claim: Dictionary=x.w.facts.adaptations[id]
		if claim.kind!="facility" or x.w.facts.facilities.get(id,{}).get("definition_id","")!="EQ05": continue
		for area: Array in claim.regions:
			var rect:=Rect2(float(area[0])+0.1,float(area[1])+0.1,0.2,0.2)
			for floor_id: int in [1,2]:
				for row: Array in [["walker_1",[]],[claim.actor_id,[]],[claim.staff_ids[0],[]],[claim.staff_ids[1],[]],["walker_1",[claim.actor_id]],["walker_1",[claim.staff_ids[0]]]]:
					var expected: String=oracle(x.w,row[0],floor_id,rect,row[1])
					var actual: String=x.s.bed_destination_blocker(x.w,row[0],floor_id,rect,row[1])
					_check(label+":"+id+":"+str(floor_id)+":"+str(area)+":"+str(row),actual==expected,{"actual":actual,"expected":expected})
	_check(label+"_all_facts_readonly",x.w.freeze()==before)

func _counts() -> void:
	var x: Dictionary=_case_input()
	_summary(x,{1:2,2:1},"three_beds_two_floors")
	for i: int in 3:
		x.s.reservation_changed(x.w,"bed_z")
		_summary(x,{1:2,2:1},"same_callback_"+str(i))
	_oracle_checks(x,"counts")

func _lifecycle() -> void:
	var x: Dictionary=_case_input();var world: WorldState=x.w
	var stop: Rect2=_rect(world,"bed_a")
	var saved: Dictionary=world.facts.adaptations.duplicate(true)
	_summary(x,{1:2,2:1},"initial")
	x.s.grant_facility_access(world,"bed_a","walker_1")
	_check("formal_grant_immediate",x.s.bed_destination_blocker(world,"walker_1",1,stop).is_empty())
	_summary(x,{1:2,2:1},"grant_not_new_claim")
	# A rights-revocation fact boundary, not an invented player command.
	world.facts.adaptations.bed_a.staff_ids.erase("walker_1")
	_check("revoke_immediate",x.s.bed_destination_blocker(world,"walker_1",1,stop)==oracle(world,"walker_1",1,stop) and oracle(world,"walker_1",1,stop)=="bed_a")
	x.s.reservation_changed(world,"bed_a")
	_summary(x,{1:2,2:1},"revoke_callback_not_new_claim")
	for id: String in ["bed_z","bed_a","bed_c"]:
		world.facts.adaptations.erase(id);x.s.reservation_changed(world,id)
		_summary(x,({1:1,2:1} if id=="bed_z" else ({2:1} if id=="bed_a" else {})),"removed_"+id)
		_oracle_checks(x,"after_remove_"+id)
	_check("empty_sparse_view",not x.s.has_bed_destination_claims(world) and x.s.bed_destination_view(world).is_empty())
	for id: String in ["bed_c","bed_a","bed_z"]:
		world.facts.adaptations[id]=saved[id].duplicate(true);x.s.reservation_changed(world,id)
		_summary(x,({2:1} if id=="bed_c" else ({1:1,2:1} if id=="bed_a" else {1:2,2:1})),"readded_"+id)
	_oracle_checks(x,"readded")

func _owners() -> void:
	var x: Dictionary=_case_input();var initial: Dictionary=x.w.freeze()
	_summary(x,{1:2,2:1},"original")
	var cold:=WorldState.new(initial.duplicate(true));var cold_x: Dictionary={"w":cold,"s":x.s}
	cold.facts.adaptations.erase("bed_c");x.s.reservation_changed(cold,"bed_c")
	_summary(cold_x,{1:2},"cold_world_different_summary")
	_summary(x,{1:2,2:1},"original_after_cold")
	_check("original_facts_unchanged",x.w.freeze()==initial)
	var replacement: Dictionary=initial.duplicate(true);replacement.adaptations.erase("bed_a")
	var revision: int=x.w.revision
	x.w.facts=replacement
	_check("equal_revision_replacement_boundary",x.w.revision==revision)
	_summary(x,{1:1,2:1},"equal_revision_new_facts")
	x.w.facts=initial.duplicate(true)
	_summary(x,{1:2,2:1},"facts_restored")
	var previous: Dictionary=x.s.reservation_view(x.w)
	var builds: int=int(x.s.query_counts.reservation_index_builds)
	x.w.invalidate_geometry()
	_summary(x,{1:2,2:1},"new_geometry_epoch")
	_check("geometry_epoch_rebuild",not is_same(previous,x.s.reservation_view(x.w)) and int(x.s.query_counts.reservation_index_builds)==builds+1)
	_oracle_checks(x,"owner_replacement")

func _oracle_case() -> void:
	var x: Dictionary=_case_input()
	_oracle_checks(x,"independent_oracle")
	var before: Dictionary=x.w.freeze()
	var broad:=Rect2(33,77,29,9)
	_check("first_blocker_sorted_not_inserted",oracle(x.w,"walker_1",1,broad)=="bed_a" and x.s.bed_destination_blocker(x.w,"walker_1",1,broad)=="bed_a")
	var area: Array=x.w.facts.adaptations.bed_a.regions[1]
	var edge:=Rect2(float(area[0])+float(area[2]),float(area[1]),0.1,0.1)
	_check("strict_edge_no_overlap",oracle(x.w,"walker_1",1,edge).is_empty() and x.s.bed_destination_blocker(x.w,"walker_1",1,edge).is_empty())
	_check("oracle_boundary_readonly",x.w.freeze()==before)

func _stops() -> void:
	var x: Dictionary=_case_input();var world: WorldState=x.w
	var space:=CountedSpace.new(content);var movement:=CountedMovement.new(space);space.movement=movement
	var upper: Dictionary=world.facts.adaptations.bed_c.duplicate(true)
	world.facts.adaptations.erase("bed_c");space.reservation_changed(world,"bed_c")
	var actor: Dictionary=world.facts.actors.walker_2
	var area: Array=upper.regions[1];var target: Array=[area[0],area[1]]
	var path: Array=[{"kind":"floor","floor_id":2,"cell":[target[0],float(target[1])-1.0]},{"kind":"floor","floor_id":2,"cell":target}]
	var journey: Dictionary={"actor_id":actor.id,"target_floor":2,"target_cell":target,"cursor":0,"path":path,"members":[actor.id]}
	var before: Dictionary=world.freeze()
	space.view_calls=0;movement.goal_region_calls=0
	_check("irrelevant_goal_clear",movement._bed_goal_blocker(world,actor,journey).is_empty())
	_check("irrelevant_goal_no_geometry",movement.goal_region_calls==0 and space.view_calls==1,{"goal_regions":movement.goal_region_calls,"view_calls":space.view_calls})
	space.view_calls=0
	_check("irrelevant_local_clear",movement._bed_local_path_blocker(world,actor,journey,path).is_empty() and space.view_calls==1)
	_check("irrelevant_queries_readonly",world.freeze()==before)
	world.facts.adaptations.bed_c=upper;space.reservation_changed(world,"bed_c")
	space.view_calls=0;movement.goal_region_calls=0
	_check("relevant_goal_blocks",movement._bed_goal_blocker(world,actor,journey)=="bed_c")
	_check("relevant_goal_borrows_once",space.view_calls==1 and movement.goal_region_calls==1,{"view_calls":space.view_calls,"goal_regions":movement.goal_region_calls})
	space.view_calls=0
	_check("relevant_local_borrows_once",movement._bed_local_path_blocker(world,actor,journey,path)=="bed_c" and space.view_calls==1)

func run_cases(database: HospitalContent, selected: Array) -> Dictionary:
	content=database
	var started: int=Time.get_ticks_usec();var rows: Array=[];var ok: bool=true
	for id: String in selected:
		if not id in CASES: return {"ok":false,"error":"Unknown explicit selector: "+id}
		checks={};details={};var case_started: int=Time.get_ticks_usec()
		match id:
			"BED-INDEX-COUNT": _counts()
			"BED-INDEX-LIFECYCLE": _lifecycle()
			"BED-INDEX-OWNER": _owners()
			"BED-INDEX-ORACLE": _oracle_case()
			"BED-INDEX-STOPS": _stops()
		var failed: Array=[]
		for key: String in checks:
			if not checks[key]: failed.append(key)
		rows.append({"id":id,"ok":failed.is_empty(),"check_count":checks.size(),"failed":failed,"details":details,"elapsed_us":Time.get_ticks_usec()-case_started})
		ok=ok and failed.is_empty()
	return {"ok":ok,"cases":rows,"elapsed_us":Time.get_ticks_usec()-started,"scope":"Legal declared two-floor/three-bed reservation boundary; independent full-facts stopping oracle and runtime-index lifecycle only. No actual admission, journey or medical handoff is claimed. Existing BED/ROOM cases cover those flows."}
