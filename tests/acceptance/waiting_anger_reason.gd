extends "res://tests/acceptance/waiting_query_batches.gd"

# The legacy anger caller sees only patient_summary. This wrapper forces that
# compatibility path while delegating the observation to the native service.
class LegacySummary extends RefCounted:
	var life: HospitalWaitingLife
	var reads: int = 0
	func patient_summary(w: WorldState, id: String) -> Dictionary:
		reads += 1
		return life.patient_summary(w,id)
	func noise_multiplier(w: WorldState, id: String) -> float:
		return life.noise_multiplier(w,id)

func _observe(x: Dictionary, label: String, expected: Variant = null) -> Dictionary:
	var w: WorldState = x.world
	var visit: Dictionary = w.facts.visits.choice
	var before: Dictionary = w.freeze()
	var summary: Dictionary = x.l.patient_summary(w,visit.id)
	var legacy: bool = not summary.get("seat",{}).is_empty() and summary.seat.phase=="seated" and not summary.get("reasons",[]).is_empty()
	var value: bool = x.l.has_positive_seat_reason(w,visit.id)
	var readonly: bool = before==w.freeze()
	var old: LegacySummary = LegacySummary.new(); old.life=x.l
	var a: Dictionary = {"anger_sources":{},"cause_clocks":{}}
	var b: Dictionary = {"anger_sources":{},"cause_clocks":{}}
	var anger: float = float(visit.anger)
	# Independent anger-boundary input has no elapsed growth causes. Real
	# environmental transitions are tested separately below.
	var observation: Dictionary = {"value":43.0,"noise":0.0,"clean":true}
	x.p.waiting_life = old
	x.p._sample_anger(w,visit,a,observation)
	var old_anger: float = float(visit.anger)
	visit.anger=anger
	x.p.waiting_life=x.l
	x.p._sample_anger(w,visit,b,observation)
	var new_anger: float = float(visit.anger)
	visit.anger=anger
	var decay: float = float(_content.balance.anger.natural_decay)*float(_content.definition("patient_personalities",visit.personality_id).anger_decay_multiplier)+(float(_content.balance.anger.preferred_seat_decay) if value else 0.0)
	var expected_anger: float = clampf(anger-decay,0,100)
	var row: Dictionary = {"case":label,"personality":visit.personality_id,"legacy":legacy,"value":value,"reasons":summary.get("reasons",[]),"readonly":readonly,"anger_equal":old_anger==new_anger and a==b,"anger":new_anger,"expected_anger":expected_anger,"fallback_summary_reads":old.reads,"validation":w.validate(_content)}
	row.ok = value==legacy and readonly and row.anger_equal and is_equal_approx(new_anger,expected_anger) and old.reads==1 and (expected==null or value==expected)
	return row

func _input_reason(criterion: String) -> Dictionary:
	var x: Dictionary = _input("crowded_friend")
	preload("res://tests/acceptance/waiting_environment_sample.gd").new().canonical_floors(x.world)
	x.world.facts.tickets[x.world.facts.visits.choice.ticket_id].waited_ticks=0
	if criterion!="friendly_neighbor":x.world.facts.relationships.clear()
	if criterion=="less_crowded":
		for id: String in x.world.facts.actors.keys():
			if id!=x.world.facts.visits.choice.actor_id and not x.world.facts.staff.has(id):x.world.facts.actors.erase(id)
	if criterion in ["calm_available","calm_below","calm_claimed"]:
		_facility(x,"seat_A","FUR49",[42,75])
		x.world.facts.visits.choice.anger=float(_content.balance.seat_choice.calm_minimum_anger)-(0.01 if criterion=="calm_below" else 0.0)
		x.world.facts.visits.choice.chair_calm_claimed=criterion=="calm_claimed"
	if criterion=="noise_reduction":_facility(x,"seat_A","FUR50",[42,75])
	x.world.touch()
	var visit: Dictionary=x.world.facts.visits.choice
	x.seated=_seat_checkpoint(x,visit,"seat_A")
	var observation: SeatObservations=SeatObservations.new()
	observation.fallback={"value":40.0,"noise":0.0 if criterion=="quiet" else 15.0,"clean":criterion=="clean_ground","water":false,"decor_nearby":criterion=="decor_nearby","casual_scene_nearby":criterion=="casual_scene_nearby"}
	x.l.environment=observation
	return x

func matrix(only_chairs: bool = false)->Dictionary:
	var rows:Array=[]
	for criterion:String in ["none","quiet","less_crowded","friendly_neighbor","calm_available","calm_below","calm_claimed","noise_reduction","clean_ground","decor_nearby","casual_scene_nearby"]:
		if only_chairs and not criterion in ["calm_available","calm_below","calm_claimed","noise_reduction"]: continue
		var x:Dictionary=_input_reason(criterion)
		for personality:Dictionary in _content.catalog.patient_personalities:
			x.world.facts.visits.choice.personality_id=personality.id
			var expected:bool=int(personality.seating.weights.get(criterion,0))>0
			var row:Dictionary=_observe(x,criterion,expected)
			row.ok=row.ok and x.seated and row.validation.is_empty()
			rows.append(row)
	return {"ok":rows.all(func(r:Dictionary)->bool:return r.ok),"rows":rows}

func boundaries()->Dictionary:
	var rows:Array=[]
	for kind:String in ["failed","removed","remodel","not_public","not_seated","need","no_seat","missing_visit"]:
		var x:Dictionary=_input_reason("quiet")
		var visit:Dictionary=x.world.facts.visits.choice
		if kind=="failed":x.world.facts.facilities.seat_A.failed=true
		elif kind=="removed":x.world.facts.facilities.erase("seat_A")
		elif kind=="remodel":x.world.facts.get_or_add("remodels",{})["test"]={"id":"test","state":"preparing","target_ids":["seat_A"],"member_ids":["seat_A"],"facility_ids":["seat_A"],"room_ids":[]}
		elif kind=="not_public":x.world.facts.facilities.seat_A.definition_id="SE02";x.world.invalidate_geometry()
		elif kind=="not_seated":x.world.facts.waiting_life.seats.choice.phase="area_travel"
		elif kind=="need":x.world.facts.waiting_life.needs.choice={"phase":"fallback","purpose":"water","remaining_ticks":10}
		elif kind=="no_seat":x.world.facts.waiting_life.seats.erase("choice")
		elif kind=="missing_visit":
			var before:Dictionary=x.world.freeze()
			rows.append({"case":kind,"ok":not x.l.has_positive_seat_reason(x.world,"missing") and before==x.world.freeze()})
			continue
		# Removed/invalid/stale ownership inputs explicitly test rejection, not a
		# legal progression into those states. They do not assert whole-world validity.
		var row:Dictionary=_observe(x,kind,kind=="failed")
		rows.append(row)
	return {"ok":rows.all(func(r:Dictionary)->bool:return r.ok),"rows":rows}

func run_cases_selected(database:HospitalContent,selected:Array)->Dictionary:
	_content=database
	var rows:Dictionary={}
	for id:String in selected:
		if id=="ANGER-SEAT-MATRIX":rows[id]=matrix()
		elif id=="ANGER-SEAT-MATRIX-CHAIRS":rows[id]=matrix(true)
		elif id=="ANGER-SEAT-BOUNDARIES":rows[id]=boundaries()
		elif id=="ANGER-SEAT-LIVE":rows[id]=live()
		elif id=="ANGER-SEAT-FRIENDS":rows[id]=friends()
		elif id=="ANGER-SEAT-FRIENDS-OWNERS":rows[id]=friends(["convoy","transit"])
		else:return {"ok":false,"unknown_case":id}
	return {"ok":not rows.is_empty() and rows.values().all(func(r:Dictionary)->bool:return r.ok),"cases":rows}

func live()->Dictionary:
	var x:Dictionary=_fixture()
	preload("res://tests/acceptance/waiting_environment_sample.gd").new().canonical_floors(x.world)
	_facility(x,"seat_A","FUR06",[42,75])
	_facility(x,"tool","SE02",[38,80])
	var visit:Dictionary=_visit(x,"choice",[38,76],"PP02")
	x.world.facts.tickets[visit.ticket_id].waited_ticks=0
	var seated:bool=_seat_checkpoint(x,visit,"seat_A")
	var rows:Array=[];var started:bool=false;var order_id:String=""
	for state:String in ["quiet","working","paused","restore"]:
		if state=="working":
			var order:CommandResult=x.e.execute(x.world,"renovation_order",{"material_id":"MAT01","floor_id":1,"units":[{"cell":[42,78]}],"allow_waiting":true})
			if not order.accepted:return {"ok":false,"reason":order.reason}
			order_id=str(order.changed_ids[0])
			for tick:int in 400:
				x.e.dispatch(x.world);x.space.advance(x.world);x.e.advance(x.world)
				x.world.facts.sim_tick+=1;x.world.touch(false);x.space.finish_boundary(x.world)
				if x.world.facts.environment.orders[order_id].units[0].phase=="working":started=true;break
		elif state=="paused":x.e.execute(x.world,"renovation_pause",{"order_id":order_id})
		elif state=="restore":x=_restore(x)
		var row:Dictionary=_observe(x,"native_"+state,state!="working")
		var o:Dictionary=x.e.sample_at(x.world,1,x.world.facts.facilities.seat_A.patient_cell,visit.actor_id)
		row.noise=o.noise;row.value=o.value
		row.ok=row.ok and row.validation.is_empty() and int(o.noise)==(int(_content.balance.environment.construction_noise_penalty) if state=="working" else 0)
		rows.append(row)
	return {"ok":seated and started and rows.all(func(r:Dictionary)->bool:return r.ok),"actual_work_started":started,"native_environment":x.e.get_script()==HospitalEnvironment,"rows":rows}

func friends(selected: Array = ["own_move","convoy","transit"])->Dictionary:
	var rows:Array=[]
	for kind:String in selected:
		var x:Dictionary=_input_reason("friendly_neighbor")
		var w:WorldState=x.world
		var visit:Dictionary=w.facts.visits.choice;visit.personality_id="PP08"
		for id:String in w.facts.actors.keys():
			if id!=visit.actor_id and id!="z_neighbor" and not w.facts.staff.has(id):w.facts.actors.erase(id)
		if kind=="convoy":
			w.facts.actors["leader"]={"id":"leader","name":"leader","species_id":"S49","location":{"kind":"floor","floor_id":1,"cell":[46,76],"height_m":0.0},"facing":0.0,"posture":"standing"}
		if kind=="transit":
			var plots:Array=HospitalSpace.floor_plots(w,1).duplicate(true)
			for plot:Array in plots:w.facts.floors.completed_top_floor[HospitalSpace.plot_key(plot)]=2
			w.facts.floors.height_intervals=[{"first":1,"last":2,"height_m":float(_content.balance.floors.clear_height_m)}]
			w.facts.floors.overrides["2"]={"plots":plots,"blocked":[],"doors":[],"paths":[]}
			w.facts.connectors["lift"]={"id":"lift","definition_id":"VC02","stops":[1,2],"cell":[58,84],"footprint":[4,4],"rotation":0,"anchor":[59,88],"repair_cell":[57,85],"floor_id":1,"phase":"idle","riders":[],"remaining_ticks":0,"ticket_next":0,"condition":100.0,"failed":false,"pending_failure":false,"use_receipts":{},"paid_cost":3200,"used":false}
			x.m.ensure(w)
		w.touch()
		var initial:Dictionary=_observe(x,kind+"_idle",true)
		var origin:Dictionary=w.facts.actors.z_neighbor.location.duplicate(true)
		var request:String=x.space.request_group_move(w,"leader",["leader","z_neighbor"],{},1,[53,80]) if kind=="convoy" else x.space.request_move(w,"z_neighbor",2,[52,88]) if kind=="transit" else x.space.request_move(w,"z_neighbor",1,[53,80])
		var progressed:bool=false
		for tick:int in (1000 if kind=="transit" else 4):
			x.space.advance(w);w.facts.sim_tick+=1;w.touch(false)
			if kind=="transit" and w.facts.actors.z_neighbor.location.kind=="transit":progressed=true;break
		if kind!="transit":progressed=origin!=w.facts.actors.z_neighbor.location
		var current:Dictionary=_observe(x,kind+"_active",false)
		var no_follower_move:bool=kind!="convoy" or not w.facts.moves.has("z_neighbor")
		var restored:Dictionary=_restore(x)
		var saved:Dictionary=_observe(restored,kind+"_restored",false)
		rows.append({"case":kind,"ok":request.is_empty() and progressed and no_follower_move and initial.ok and current.ok and saved.ok and current.validation.is_empty() and saved.validation.is_empty(),"request":request,"actual_progress":progressed,"convoy_follower_without_own_move":no_follower_move,"initial":initial,"current":current,"restored":saved})
	return {"ok":rows.all(func(r:Dictionary)->bool:return r.ok),"rows":rows}
