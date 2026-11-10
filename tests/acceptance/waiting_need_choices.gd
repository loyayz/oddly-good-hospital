extends "res://tests/acceptance/staff_fixtures.gd"

class ForcedWaiting extends HospitalWaitingLife:
	func _public_need_choices(w:WorldState,v:Dictionary,n:Dictionary,d:Array,t:int,_scan:Dictionary={})->Array:
		return super._public_need_choices(w,v,n,d,t,{})

func fixture() -> Dictionary:
	var helper:RefCounted=preload("res://tests/acceptance/public_area_use.gd").new();helper._content=_content
	var x:Dictionary=helper._areas()
	_facility(x,"toilet","FUR07",[39,68],"west")
	preload("res://tests/acceptance/waiting_environment_sample.gd").new().canonical_floors(x.world)
	x.world.facts.sim_tick=1800
	for index:int in 6:
		var v:Dictionary=_visit(x,"need_%02d"%index,[35+(index%3)*3,73+(index/3)*2])
		x.world.register_visit(str(v.id))
		var n:Dictionary={"id":"need_"+v.id,"visit_id":v.id,"ticket_id":v.ticket_id,"purpose":"toilet","started_tick":1800,"queued_ticks":0,"phase":"local_wait","facility_id":"","remaining_ticks":0,"return_to":{},"return_area":{},"scene_id":"","public_purpose":"toilet","actor_id":v.actor_id,"mode":"auto","area":x.space.public_areas.for_facility(x.world,"toilet"),"arrived_tick":1800}
		x.world.facts.waiting_life.needs[v.id]=n
		x.world.facts.tickets[v.ticket_id].pause_reasons.need_service=n.id
	x.world.facts.actors["blocker"]={"id":"blocker","name":"blocker","species_id":"S49","location":{"kind":"floor","floor_id":1,"cell":[41,76],"height_m":0.0},"posture":"standing","facing":0.0}
	x.world.touch()
	return x

func bind_copy(w:WorldState,force:bool)->Dictionary:
	var x:Dictionary=_bind(w)
	if force:
		x.l=ForcedWaiting.new(_content,x.space)
		x.l.environment=x.e;x.l.visitors=x.c.visitors;x.p.waiting_life=x.l
	return x

func choices(x:Dictionary,scan:Dictionary,visit_id:String="need_00")->Array:
	var v:Dictionary=x.world.facts.visits[visit_id]
	return x.l._public_need_choices(x.world,v,x.world.facts.waiting_life.needs[visit_id],["FUR07","AE02"],2250,scan)

func warm(x:Dictionary)->void:
	x.space.begin_dynamic_route_query(x.world);x.space.end_route_query()
	x.space.query_counts.actor_index_builds=0
	x.space.query_counts.actor_index_actor_visits=0

func closed(x:Dictionary)->bool:
	return x.space._route_queries.is_empty() and x.space._indexed_actor_scope.is_empty()

func read_boundaries(selected: Array = ["plain","raw_before","sync_between","facts_replaced","other_world","independent_raw","reservation"])->Dictionary:
	var rows:Array=[]
	for kind:String in selected:
		var input:Dictionary=fixture()
		if kind=="posture_release":
			var seated:Dictionary=_visit(input,"seated",[36,70])
			if not _seat_checkpoint(input,seated,"west_chair"):return {"ok":false,"input_error":"seat checkpoint rejected"}
		var a:Dictionary=bind_copy(WorldState.new(input.world.freeze()),true)
		var b:Dictionary=bind_copy(WorldState.new(input.world.freeze()),false)
		warm(a);warm(b)
		var old:Array=[];var current:Array=[];var readonly:bool=true;var reservations_ok:bool=true
		var scan:Dictionary={"refreshed":false}
		for number:int in 4:
			for x:Dictionary in [a,b]:
				if (kind=="raw_before" and number==0) or (kind in ["sync_between","independent_raw"] and number==1):
					x.world.facts.actors.blocker.location.cell=x.space.facility_layout(x.world,"toilet").patient_cell.duplicate()
					if kind=="sync_between":x.space.sync_actor(x.world,"blocker")
				if kind=="facts_replaced" and number==1:
					var f:Dictionary=x.world.freeze();f.actors.blocker.location.cell=x.space.facility_layout(x.world,"toilet").patient_cell.duplicate();x.world.facts=f
				if kind=="other_world" and number==1:
					x.world=WorldState.new(x.world.freeze())
					x.world.facts.actors.blocker.location.cell=x.space.facility_layout(x.world,"toilet").patient_cell.duplicate()
				if kind=="posture_release" and number==1:x.l._release_seat(x.world,"seated")
				if kind=="reservation" and number==1:
					reservations_ok=reservations_ok and x.space.reserve_facility(x.world,"toilet","blocker","blocker").is_empty()
				var before:Dictionary=x.world.freeze()
				var found:Array=choices(x,{} if x==a or kind=="independent_raw" else scan)
				readonly=readonly and before==x.world.freeze()
				if x==a:old.append(found)
				else:current.append(found)
		var expected:bool=not current[0].is_empty() if kind!="raw_before" else current[0].is_empty()
		if not kind in ["plain","posture_release"]:expected=expected and current[1].is_empty()
		var row:Dictionary={"case":kind,"equal":old==current,"choice_counts":current.map(func(v:Array)->int:return v.size()),"forced_builds":a.space.query_counts.actor_index_builds,"shared_builds":b.space.query_counts.actor_index_builds,"forced_actor_visits":a.space.query_counts.actor_index_actor_visits,"shared_actor_visits":b.space.query_counts.actor_index_actor_visits,"readonly":readonly,"closed":closed(a) and closed(b),"validation":b.world.validate(_content),"reservation_created":reservations_ok}
		row.ok=row.equal and readonly and row.closed and row.validation.is_empty() and expected and reservations_ok
		if kind=="plain":row.ok=row.ok and row.forced_builds==4 and row.shared_builds==1
		if kind=="independent_raw":row.ok=row.ok and row.shared_builds==4
		if kind=="posture_release":row.ok=row.ok and b.world.facts.actors.patient_seated.posture=="standing" and b.space._actor_shapes.patient_seated.posture=="standing" and row.shared_builds==1
		rows.append(row)
	return {"ok":rows.all(func(r:Dictionary)->bool:return r.ok),"rows":rows}

func dispatch_compare()->Dictionary:
	var x:Dictionary=fixture()
	var a:Dictionary=bind_copy(WorldState.new(x.world.freeze()),true)
	var b:Dictionary=bind_copy(WorldState.new(x.world.freeze()),false)
	warm(a);warm(b)
	var before:Dictionary=b.world.freeze()
	a.l.dispatch(a.world);b.l.dispatch(b.world)
	var row:Dictionary={"same_facts_rng_ids_tickets":a.world.freeze()==b.world.freeze(),"forced_builds":a.space.query_counts.actor_index_builds,"shared_builds":b.space.query_counts.actor_index_builds,"forced_actor_visits":a.space.query_counts.actor_index_actor_visits,"shared_actor_visits":b.space.query_counts.actor_index_actor_visits,"validation":b.world.validate(_content),"closed":closed(a) and closed(b),"needs":b.world.facts.waiting_life.needs.size(),"real_move_intents":b.world.facts.moves.size(),"no_early_reservation":b.world.facts.adaptations.is_empty()}
	row.ok=row.same_facts_rng_ids_tickets and row.validation.is_empty() and row.closed and row.needs==6 and row.real_move_intents>0 and row.no_early_reservation and row.shared_builds<row.forced_builds
	return row

func run_selected(c:HospitalContent,selected:Array)->Dictionary:
	_content=c
	var cases:Dictionary={}
	for id:String in selected:
		if id=="NEED-CHOICES-READ":cases[id]=read_boundaries()
		elif id=="NEED-CHOICES-DISPATCH":cases[id]=dispatch_compare()
		elif id=="NEED-CHOICES-POSTURE":cases[id]=read_boundaries(["posture_release"])
		else:return {"ok":false,"unknown_case":id}
	return {"ok":not cases.is_empty() and cases.values().all(func(r:Dictionary)->bool:return r.ok),"cases":cases}
