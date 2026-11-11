extends "res://tests/acceptance/staff_fixtures.gd"

var family_input: Dictionary = {}
var family_source: Dictionary = {}

class ProbeSpace extends HospitalSpace:
	var source: WorldState
	var exclusion_calls: int = 0
	var excluded: Array = []
	var projected_actor_visits: int = 0
	func begin_actor_exclusion_query(owner: WorldState, projected: WorldState, ids: Array) -> void:
		exclusion_calls += 1;excluded.append(ids.duplicate())
		super.begin_actor_exclusion_query(owner,projected,ids)
	func _sync_actor(world: WorldState, id: String, notify: bool = true) -> void:
		if source!=null and world!=source: projected_actor_visits += 1
		super._sync_actor(world,id,notify)

class ProbeWaiting extends HospitalWaitingLife:
	var projections: int = 0
	func _availability_projection(world: WorldState, facility_id: String, user_id: String, need: Dictionary, source_floor: int) -> Dictionary:
		projections += 1
		return super._availability_projection(world,facility_id,user_id,need,source_floor)

# Frozen pre-optimization outer projection. Both versions still call the same
# current complete facility quote, including every unrelated body and exit.
class OriginalWaiting extends HospitalWaitingLife:
	var projections: int = 0
	func _facility_availability(world: WorldState, actor_id: String, facility_id: String) -> Dictionary:
		var candidate: WorldState = world
		var using: Dictionary = space.read_view(world,"waiting_using_facilities",_using_facilities.bind(world))
		for need: Dictionary in using.get(facility_id,[]):
			var user_id: String=str(need.get("actor_id",world.facts.visits.get(str(need.get("visit_id","")),{}).get("actor_id","")))
			if need.get("facility_id","")!=facility_id or need.phase!="using" or user_id==actor_id: continue
			var facts: Dictionary=world.facts.duplicate();facts.actors=world.facts.actors.duplicate();facts.actors[user_id]=world.facts.actors[user_id].duplicate()
			if need.get("owner_kind","")=="visitor":
				facts.visitors=world.facts.visitors.duplicate();facts.visitors.stays=world.facts.visitors.stays.duplicate()
				for id: String in world.facts.visitors.stays:
					if world.facts.visitors.stays[id].actor_id!=user_id: continue
					facts.visitors.stays[id]=world.facts.visitors.stays[id].duplicate();facts.visitors.stays[id].life_task=need.duplicate();facts.visitors.stays[id].life_task.facility_id=""
			elif world.facts.staff.has(user_id):
				facts.staff=world.facts.staff.duplicate();facts.staff[user_id]=world.facts.staff[user_id].duplicate();facts.staff[user_id].life_task=need.duplicate();facts.staff[user_id].life_task.facility_id=""
			else:
				facts.waiting_life=world.facts.waiting_life.duplicate();facts.waiting_life.needs=world.facts.waiting_life.needs.duplicate();facts.waiting_life.needs[need.visit_id]=need.duplicate();facts.waiting_life.needs[need.visit_id].facility_id=""
			facts.adaptations=world.facts.adaptations.duplicate();candidate=WorldState.new(facts)
			candidate.facts.actors[user_id].location={"kind":"outside"};candidate.facts.adaptations.erase(facility_id);projections+=1
			break
		var quote: Dictionary=_facility_quote(candidate,{"actor_id":actor_id},facility_id)
		if quote.ok: quote.cell=quote.patient_cell.duplicate()
		return quote

func _input(owner: String) -> Dictionary:
	var x: Dictionary=_fixture({"water_staff":"cleaner"} if owner=="staff" else {})
	_facility(x,"water","FUR17",[42,75])
	var cell: Array=x.space.facility_layout(x.world,"water").patient_cell.duplicate()
	var resident: Dictionary={"id":"water_staff","actor_id":"water_staff"} if owner=="staff" else _visit(x,"water_user",cell)
	if owner=="staff": _position(x,resident.actor_id,cell)
	var a: Dictionary=_visit(x,"request_a",[38,80]);var b: Dictionary=_visit(x,"request_b",[49,82])
	x.large_binding={}
	for binding: Dictionary in _content.catalog.treatment_bindings:
		var actor: Dictionary=x.world.facts.actors[b.actor_id].duplicate();actor.species_id=binding.species_id;actor.body_binding_id=binding.id
		if x.space.clearance(actor)!=2: continue
		x.large_binding=binding;break
	var need: Dictionary={"id":resident.id+":water","visit_id":resident.id,"actor_id":resident.actor_id,"ticket_id":resident.get("ticket_id",""),"kind":"amenity","purpose":"water","public_purpose":"water","started_tick":x.world.sim_tick,"queued_ticks":0,"remaining_ticks":0,"phase":"local_travel","facility_id":"","return_to":{},"return_area":{},"scene_id":"","mode":"auto","area":x.space.public_areas.for_facility(x.world,"water"),"arrived_tick":x.world.sim_tick}
	if owner=="staff": x.world.facts.staff.water_staff.life_task=need
	else:
		x.world.facts.waiting_life.needs[resident.id]=need;x.world.facts.tickets[resident.ticket_id].pause_reasons.need_service=need.id
	x.claimed=x.l._claim_need(x.world,resident,need,"water",x.l._amenity("water"))
	x.owner=owner;x.user_id=resident.actor_id;x.requesters=[a.actor_id,b.actor_id];x.need=need
	x.world.touch();x.validation=x.world.validate(_content)
	return x

func _large_blocker(x: Dictionary) -> bool:
	if x.large_binding.is_empty(): return false
	var visit: Dictionary=x.world.facts.visits.request_b;var actor: Dictionary=x.world.facts.actors[visit.actor_id];var binding: Dictionary=x.large_binding
	actor.species_id=binding.species_id;actor.body_binding_id=binding.id
	visit.binding_id=binding.id;visit.disease_id=binding.disease_id;visit.requested_plan_id="P_"+str(binding.disease_id)+"_COMMON"
	x.world.touch()
	var available: bool=OriginalWaiting.new(_content,HospitalSpace.new(_content)).facility_availability(x.world,visit.actor_id,"water").get("ok",false)
	var cell: Array=x.space.facility_layout(x.world,"water").patient_cell
	var blocker: Dictionary=_visit(x,"unrelated_blocker",[int(cell[0])+1,int(cell[1])])
	var future: Dictionary=actor.duplicate();future.location={"kind":"floor","floor_id":1,"cell":cell.duplicate(),"height_m":0.0}
	var obstructs: bool=x.space.body_rectangle(future).intersects(x.space.body_rectangle(x.world.facts.actors[blocker.actor_id]),false)
	var distinct: bool=not x.space.body_rectangle(x.world.facts.actors[x.user_id]).intersects(x.space.body_rectangle(x.world.facts.actors[blocker.actor_id]),false)
	x.world.touch();return available and obstructs and distinct

func _pair(x: Dictionary) -> Dictionary:
	var actual: ProbeSpace=ProbeSpace.new(_content);var original: ProbeSpace=ProbeSpace.new(_content)
	actual.source=x.world;original.source=x.world
	return {"a":ProbeWaiting.new(_content,actual),"b":OriginalWaiting.new(_content,original),"aspace":actual,"bspace":original}

func _visitor_input(require_public: bool = false) -> Dictionary:
	if family_input.is_empty(): return {"claimed":false,"validation":"Missing unchanged real family boundary"}
	var original: Dictionary=family_input.facts.duplicate(true)
	var relative: Dictionary={}
	for stay: Dictionary in original.visitors.stays.values():
		if stay.purpose=="companion" and original.actors[stay.actor_id].location.kind=="floor": relative=stay;break
	if relative.is_empty(): return {"claimed":false,"validation":"The real boundary has no present companion"}
	var definitions: Array=[]
	for service: Dictionary in _content.catalog.amenity_services:
		if service.purpose=="water": definitions=[service.ordinary_facility_id,service.universal_facility_id]
	var facilities: Array=original.facilities.keys();facilities.sort()
	for id: String in facilities:
		if not original.facilities[id].definition_id in definitions or original.facilities[id].get("failed",false): continue
		var x: Dictionary=_bind(WorldState.new(original.duplicate(true)))
		var stay: Dictionary=x.world.facts.visitors.stays[relative.id];var actor: Dictionary=x.world.facts.actors[stay.actor_id]
		var layout: Dictionary=x.space.facility_layout(x.world,id);var floor_id: int=int(layout.floor_id)
		var cell: Array=layout.patient_cell.duplicate()
		if require_public and not x.space.public_areas.public_point(x.world,floor_id,Vector2i(int(cell[0]),int(cell[1]))): continue
		# This is an explicit calculation boundary, not a simulated arrival.
		x.world.facts.moves.erase(actor.id);actor.location={"kind":"floor","floor_id":floor_id,"cell":cell,"height_m":0.0}
		actor.posture="standing";actor.erase("support_facility_id")
		stay.return_ward_first=false
		stay.life_task={"id":stay.id+":water_calculation","owner_kind":"visitor","actor_id":actor.id,"purpose":"water","public_purpose":"water","phase":"local_travel","facility_id":"","area":x.space.public_areas.for_facility(x.world,id),"arrived_tick":x.world.sim_tick,"remaining_ticks":0,"queued_ticks":0,"started_tick":x.world.sim_tick,"mode":"auto","return_to":{},"return_area":{},"scene_id":""}
		var body: Rect2=x.space.body_rectangle(actor);var clear: bool=x.space.static_reason(x.world,actor,floor_id,Vector2i(int(cell[0]),int(cell[1]))).is_empty()
		for other: Dictionary in x.world.facts.actors.values():
			if other.id!=actor.id and other.location.kind=="floor" and int(other.location.floor_id)==floor_id and body.intersects(x.space.body_rectangle(other),false): clear=false;break
		if not clear: continue
		if not x.l._claim_need(x.world,{"id":stay.id,"actor_id":actor.id},stay.life_task,id,x.l._amenity("water")): continue
		var requesters: Array=[]
		for visit_id: String in x.world.active_visit_ids():
			var patient: Dictionary=x.world.facts.actors[x.world.facts.visits[visit_id].actor_id]
			if patient.location.kind=="floor": requesters.append(patient.id)
			if requesters.size()==2: break
		if requesters.size()!=2: continue
		x.owner="visitor";x.user_id=actor.id;x.requesters=requesters;x.water_id=id;x.claimed=true
		x.world.touch();x.validation=x.world.validate(_content)
		var changed: Array=[]
		for key: String in original:
			if original[key]!=x.world.facts[key]: changed.append(key)
		var allowed: bool=changed.all(func(key: String)->bool:return key in ["actors","moves","visitors","adaptations","world_revision"])
		var others: bool=original.actors.size()==x.world.facts.actors.size()
		for actor_id: String in original.actors:
			if actor_id!=actor.id: others=others and original.actors[actor_id]==x.world.facts.actors[actor_id]
		for collection: String in ["moves","adaptations"]:
			var left: Dictionary=original[collection].duplicate();var right: Dictionary=x.world.facts[collection].duplicate()
			left.erase(actor.id if collection=="moves" else id);right.erase(actor.id if collection=="moves" else id);others=others and left==right
		var old_visitors: Dictionary=original.visitors.duplicate(true);var new_visitors: Dictionary=x.world.facts.visitors.duplicate(true)
		old_visitors.stays.erase(relative.id);new_visitors.stays.erase(relative.id);others=others and old_visitors==new_visitors
		x.prerequisite={"source":family_source,"original_boundary_unchanged":family_input.facts==original,"other_actors_moves_reservations_and_family_unchanged":others,"original_final_tick":int(original.sim_tick),"original_present_companion":relative.id,"only_declared_top_level_changes":allowed,"changed_top_level_keys":changed,"world_revision_before":original.world_revision,"world_revision_after":x.world.facts.world_revision,"declarations":["Companion initial location is the existing water service point; standing without seat support","Its original move is absent at this calculation boundary","Companion has already returned to the ward before this new water need (return_ward_first=false)","Its water task begins immediately before _claim_need; _claim_need and reserve execute normally, including revision notification"],"body_static_and_other_actor_checks_passed":clear,"scope":"Calculation quote fixture only. No arrival, prior task completion, family admission, actual ward return, or comprehensive160 performance is established."}
		x.claimed=x.claimed and allowed and others and x.prerequisite.original_boundary_unchanged
		return x
	return {"claimed":false,"validation":"No existing water service point supplied a legal companion calculation boundary"}

func _quotes(x: Dictionary, pair: Dictionary, scoped: bool = true) -> Dictionary:
	var before: Dictionary=x.world.freeze();var rows: Array=[];var valid: bool=true
	var a_before: int=pair.a.projections;var b_before: int=pair.b.projections
	var av: int=pair.aspace.projected_actor_visits;var bv: int=pair.bspace.projected_actor_visits
	var ab: int=int(pair.aspace.query_counts.actor_index_builds);var bb: int=int(pair.bspace.query_counts.actor_index_builds)
	var aa: int=int(pair.aspace.query_counts.actor_index_actor_visits);var ba: int=int(pair.bspace.query_counts.actor_index_actor_visits)
	if scoped:
		pair.aspace.begin_dynamic_route_query(x.world);pair.bspace.begin_dynamic_route_query(x.world)
	for actor_id: String in x.requesters+[x.requesters[0],x.user_id]:
		var a: Dictionary=pair.a.facility_availability(x.world,actor_id,str(x.get("water_id","water")))
		var b: Dictionary=pair.b.facility_availability(x.world,actor_id,str(x.get("water_id","water")))
		var equal: bool=var_to_bytes(a)==var_to_bytes(b);valid=valid and equal
		rows.append({"actor":actor_id,"complete_typed_quote_equal":equal,"actual":a,"original":b if not equal else {}})
	if scoped: pair.aspace.end_route_query();pair.bspace.end_route_query()
	var closed: bool=pair.aspace._route_queries.is_empty() and pair.bspace._route_queries.is_empty()
	return {"ok":valid and before==x.world.freeze() and closed,"rows":rows,"facts_rng_and_positions_unchanged":before==x.world.freeze(),"scopes_closed":closed,"projection_builds_a":pair.a.projections-a_before,"projection_builds_b":pair.b.projections-b_before,"projected_actor_visits_a":pair.aspace.projected_actor_visits-av,"projected_actor_visits_b":pair.bspace.projected_actor_visits-bv,"actor_index_builds_a":int(pair.aspace.query_counts.actor_index_builds)-ab,"actor_index_builds_b":int(pair.bspace.query_counts.actor_index_builds)-bb,"actor_index_actor_visits_a":int(pair.aspace.query_counts.actor_index_actor_visits)-aa,"actor_index_actor_visits_b":int(pair.bspace.query_counts.actor_index_actor_visits)-ba,"only_user_excluded":pair.aspace.excluded.all(func(ids: Array)->bool:return ids==[x.user_id])}

func run_selected(c: HospitalContent, selected: Array) -> Dictionary:
	_content=c;var cases: Dictionary={}
	for id: String in selected:
		if id!="WATER-PROJECTION": return {"ok":false,"unknown_case":id}
		var rows: Array=[]
		for owner: String in ["patient","staff"]:
			var x: Dictionary=_input(owner)
			if not x.claimed or not x.validation.is_empty(): return {"ok":false,"failure_kind":"fixture","owner":owner,"claimed":x.claimed,"validation":x.validation}
			var pair: Dictionary=_pair(x)
			for state: String in ["using","repeat_new_scope","failed","restored","facts_replace","new_world"]:
				if state=="failed": x.world.facts.facilities.water.failed=true
				if state=="restored": x.world.facts.facilities.water.failed=false
				if state=="facts_replace": x.world.facts=x.world.freeze()
				if state=="new_world": x.world=WorldState.new(x.world.freeze());pair.aspace.source=x.world;pair.bspace.source=x.world
				var row: Dictionary=_quotes(x,pair);row.owner=owner;row.state=state
				row.ok=row.ok and row.only_user_excluded and row.projection_builds_a==1 and row.projection_builds_b==2 and x.world.validate(_content).is_empty()
				if state!="failed": row.ok=row.ok and row.rows[0].actual.get("ok",false) and row.rows[1].actual.get("ok",false)
				rows.append(row)
			var cold: Dictionary=_quotes(x,pair,false);cold.owner=owner;cold.state="unscoped";rows.append(cold)
			var blocker_setup: bool=_large_blocker(x)
			var blocked: Dictionary=_quotes(x,pair);blocked.owner=owner;blocked.state="unrelated_body_blocks_larger_requester"
			blocked.ok=blocked.ok and blocker_setup and not blocked.rows[1].actual.get("ok",true) and x.world.validate(_content).is_empty();rows.append(blocked)
			var active_need: Dictionary=x.world.facts.waiting_life.needs.water_user if owner=="patient" else x.world.facts.staff.water_staff.life_task
			active_need.phase="returning";active_need.remaining_ticks=0;x.world.touch(false)
			var ended: Dictionary=_quotes(x,pair);ended.owner=owner;ended.state="ordinary_use_finished_body_still_present"
			ended.ok=ended.ok and ended.projection_builds_a==0 and ended.projection_builds_b==0 and not ended.rows[0].actual.get("ok",true) and x.world.validate(_content).is_empty();rows.append(ended)
		var visitor: Dictionary=_visitor_input()
		if not visitor.claimed or not visitor.validation.is_empty(): return {"ok":false,"failure_kind":"fixture","owner":"visitor","validation":visitor.validation,"claimed":visitor.claimed,"prerequisite":visitor.get("prerequisite",{})}
		var family_pair: Dictionary=_pair(visitor);var family: Dictionary=_quotes(visitor,family_pair)
		family.owner="visitor";family.prerequisite=visitor.prerequisite;family.ok=family.ok and family.only_user_excluded and family.projection_builds_a==1 and family.projection_builds_b==2
		rows.append(family)
		cases[id]={"ok":rows.all(func(row: Dictionary)->bool:return row.ok),"rows":rows,"scope":"Legal already-at-service calculation inputs use real _claim_need and reservation; no movement, admission or service completion is claimed. Complete quotes retain current Space internals in both versions. Counts diagnose only the outer departure projection."}
	return {"ok":not cases.is_empty() and cases.values().all(func(row: Dictionary)->bool:return row.ok),"cases":cases}
