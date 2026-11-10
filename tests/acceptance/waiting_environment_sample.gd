extends RefCounted

const FixtureInput = preload("res://tests/acceptance/waiting_query_batches.gd")
const Raw = preload("res://tests/acceptance/environment_direct_reference.gd")
class OldLife extends HospitalWaitingLife:
	func _environment(w: WorldState, id: String, floor_id: int, cell: Array) -> Dictionary:
		if environment!=null: return environment.environment_at(w,floor_id,cell,id)
		return {"value":float(content.balance.environment.base)+float(content.balance.environment.clean_bonus),"noise":0.0,"dirt":false,"clean":true,"water":false}
func bind_view(c: HospitalContent, old: bool) -> Dictionary:
	var s: HospitalSpace=HospitalSpace.new(c)
	var l: HospitalWaitingLife=OldLife.new(c,s) if old else HospitalWaitingLife.new(c,s)
	var e: HospitalEnvironment=HospitalEnvironment.new(c,s)
	l.environment=e;e.waiting_life=l
	return {"s":s,"l":l,"e":e}
func canonical_floors(w: WorldState) -> void:
	w.facts.floors.completed_top_floor = {}
	for plot: Array in w.facts.floors.overrides["1"].plots:
		w.facts.floors.completed_top_floor["%d:%d" % plot] = 1
	w.invalidate_geometry()

func people_builds(v: Dictionary) -> int:
	return int(v.s.query_counts.get("environment_actor_source_builds",0))

func release(v: Dictionary) -> void: v.l.environment=null;v.e.waiting_life=null
func values(d: Dictionary) -> Dictionary:
	var result: Dictionary=d.duplicate(true);result.erase("nearby_count");result.erase("sources");return result
func compare_case(c: HospitalContent, helper: RefCounted, kind: String) -> Dictionary:
	var x: Dictionary=helper._input(kind)
	var w: WorldState=x.world
	canonical_floors(w)
	var a: Dictionary=bind_view(c,true);var b: Dictionary=bind_view(c,false)
	var before: Dictionary=w.freeze()
	var old: Array=a.l.seat_candidates(w,"choice")
	b.e.begin_query(w)
	var current: Array=b.l.seat_candidates(w,"choice")
	var native_bounds: bool=b.e.get_script()==HospitalEnvironment and b.e._query.get("observation_bounds") is Dictionary
	b.e.end_query()
	var old_quote: Dictionary=a.l._seat_quote(w,w.facts.visits.choice,"seat_A")
	var current_quote: Dictionary=b.l._seat_quote(w,w.facts.visits.choice,"seat_A")
	var row: Dictionary={"kind":kind,"legal":w.validate(c),"nonempty":not old.is_empty(),"candidates_equal":old==current,"manual_quote_equal":old_quote==current_quote,"readonly":w.freeze()==before,"native_bounds":native_bounds,"old_people_builds":people_builds(a),"new_people_builds":people_builds(b)}
	row.ok=row.legal.is_empty() and row.nonempty and row.candidates_equal and row.manual_quote_equal and row.readonly and row.native_bounds and row.old_people_builds>0 and row.new_people_builds==0
	release(a);release(b);return row
func live_sources(c: HospitalContent, helper: RefCounted) -> Dictionary:
	var x: Dictionary=helper._input("open_friend")
	canonical_floors(x.world)
	helper._facility(x,"sample_light","FUR19",[42,79])
	helper._facility(x,"sample_water","FUR17",[43,80])
	var patch: String=x.e.spawn_dirt(x.world,"CL01","sample_patch","sample_patch:1",1,[42,78])
	x.world.touch()
	var a: Dictionary=bind_view(c,true);var b: Dictionary=bind_view(c,false)
	var rows: Array=[]
	for state: String in ["initial","failed_light","removed_dirt","restore"]:
		if state=="failed_light":x.world.facts.facilities.sample_light.failed=true
		if state=="removed_dirt":x.world.facts.environment.dirt.erase(patch)
		if state=="restore":x.world=WorldState.new(x.world.freeze())
		var before: Dictionary=x.world.freeze()
		var old: Dictionary=a.l._environment(x.world,"patient_choice",1,[42,78])
		var current: Dictionary=b.l._environment(x.world,"patient_choice",1,[42,78])
		var reference: HospitalEnvironment=Raw.new(c,HospitalSpace.new(c));reference.waiting_life=x.l
		var detailed: Dictionary=b.e.environment_at(x.world,1,[42,78],"patient_choice")
		var raw: Dictionary=reference.environment_at(x.world,1,[42,78],"patient_choice")
		detailed.sources.sort_custom(func(p: Dictionary,q: Dictionary)->bool:return JSON.stringify(p)<JSON.stringify(q))
		raw.sources.sort_custom(func(p: Dictionary,q: Dictionary)->bool:return JSON.stringify(p)<JSON.stringify(q))
		var row: Dictionary={"state":state,"legal":x.world.validate(c),"values_equal":values(old)==values(current),"public_detail_equal":detailed==raw,"sources":detailed.sources,"nearby":detailed.nearby_count,"water":current.water,"light":current.light,"clean":current.clean,"value":current.value,"readonly":x.world.freeze()==before}
		row.ok=row.legal.is_empty() and row.values_equal and row.public_detail_equal and row.readonly and current.water
		row.ok=row.ok and current.light==(state=="initial") and current.clean==(state in ["removed_dirt","restore"])
		if state=="failed_light": row.ok=row.ok and current.value==int(rows[0].value)-int(c.balance.environment.light_bonus)
		rows.append(row)
		reference.waiting_life=null
	release(a);release(b)
	return {"ok":rows.all(func(row: Dictionary)->bool:return row.ok),"rows":rows}
func run_cases(c: HospitalContent, selected: Array) -> Dictionary:
	var helper: RefCounted=FixtureInput.new();helper._content=c
	var cases: Dictionary={}
	for id: String in selected:
		if id=="WAIT-ENV-CONSUMERS":
			var rows: Array=[]
			for kind: String in ["open_friend","wall","moving_friend","large_body","radius_boundary","bucket_float_boundary","crowded_friend"]:rows.append(compare_case(c,helper,kind))
			cases[id]={"ok":rows.all(func(row: Dictionary)->bool:return row.ok),"rows":rows}
		elif id=="WAIT-ENV-LIVE":cases[id]=live_sources(c,helper)
		elif id=="WAIT-ENV-SUMMARY":cases[id]=summary_sources(c,helper)
		else:return {"ok":false,"unknown_case":id}
	return {"ok":not cases.is_empty() and cases.values().all(func(row: Dictionary)->bool:return row.ok),"cases":cases}

func summary_sources(c: HospitalContent, helper: RefCounted) -> Dictionary:
	var x: Dictionary = helper._fixture()
	canonical_floors(x.world)
	helper._facility(x,"shield_seat","FUR50",[42,75])
	helper._facility(x,"construction_tools","SE02",[38,80])
	var visit: Dictionary = helper._visit(x)
	# The tested operation is the summary of an already occupied chair. Use
	# its legal seated boundary; construction below must reach actual work.
	var seated: bool = helper._seat_checkpoint(x,visit,"shield_seat")
	var a: Dictionary = bind_view(c,true)
	var b: Dictionary = bind_view(c,false)
	var variants: Dictionary = x.l._chair("FUR50")
	var rows: Array = []
	var started: bool = false
	var order_id: String = ""
	for state: String in ["quiet","working","paused"]:
		if state=="working":
			var order: CommandResult = x.e.execute(x.world,"renovation_order",{"material_id":"MAT01","floor_id":1,"units":[{"cell":[42,78]}],"allow_waiting":true})
			if not order.accepted: return {"ok":false,"order_reason":order.reason}
			order_id = str(order.changed_ids[0])
			for tick: int in 400:
				x.e.dispatch(x.world)
				x.space.advance(x.world)
				x.e.advance(x.world)
				x.world.facts.sim_tick += 1
				x.world.touch(false)
				x.space.finish_boundary(x.world)
				if x.world.facts.environment.orders[order_id].units[0].phase=="working":
					started = true
					break
		if state=="paused": x.e.execute(x.world,"renovation_pause",{"order_id":order_id})
		var before: Dictionary = x.world.freeze()
		var old: Dictionary = a.l.patient_summary(x.world,visit.id)
		var current: Dictionary = b.l.patient_summary(x.world,visit.id)
		b.e.begin_query(x.world)
		var observation: Dictionary = b.l._environment(x.world,visit.actor_id,1,x.world.facts.facilities.shield_seat.patient_cell)
		var native_bounds: bool = b.e._query.get("observation_bounds") is Dictionary
		b.e.end_query()
		var noisy: bool = state=="working"
		var noise: int = int(c.balance.environment.construction_noise_penalty) if noisy else 0
		var expected: int = clampi(int(c.balance.environment.base)+int(c.balance.environment.clean_bonus)-noise,0,100)
		var row: Dictionary = {"state":state,"legal":x.world.validate(c),"environment_legal":x.e.validate(x.world),"summary_equal":old==current,"native_bounds":native_bounds,"noise":observation.noise,"value":observation.value,"scene":current.get("scene",""),"readonly":x.world.freeze()==before}
		row.ok = row.legal.is_empty() and row.environment_legal.is_empty() and row.summary_equal and native_bounds and row.readonly and row.noise==noise and row.value==expected and row.scene==variants.get("effect_scene" if noisy else "ordinary_scene","")
		rows.append(row)
	var result: Dictionary = {"ok":seated and started and rows.all(func(row: Dictionary)->bool:return row.ok) and people_builds(b)==0,"seated_input":seated,"actual_construction_started":started,"new_people_builds":people_builds(b),"rows":rows}
	release(a)
	release(b)
	return result
