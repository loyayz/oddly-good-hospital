extends SceneTree
const Phase=preload("res://tests/acceptance/public_phase_use.gd")
const Boundary=preload("res://tests/acceptance/public_arrival_boundaries.gd")
class TraceSpace extends HospitalSpace:
	var events: Array=[]
	func can_reach(world: WorldState, actor_id: String, floor_id: int, target: Array, members: Array=[], offsets: Dictionary={}, ignore_people: bool=false, route_filter: Dictionary = {}) -> bool:
		var result: bool=super.can_reach(world,actor_id,floor_id,target,members,offsets,ignore_people,route_filter)
		events.append({"kind":"reach","cell":target.duplicate(),"result":result})
		return result
class TraceAreas extends HospitalPublicAreas:
	var before: Array=[]
	var after: Array=[]
	func _sort_floor_waiting_points(points: Array, origin: Vector2) -> void:
		before=points.duplicate()
		super._sort_floor_waiting_points(points,origin)
		after=points.duplicate()
	func safe_wait(world: WorldState, actor_id: String, floor_id: int, cell: Array, geometry: Dictionary={}) -> bool:
		var result: bool=super.safe_wait(world,actor_id,floor_id,cell,geometry)
		space.events.append({"kind":"safe","cell":cell.duplicate(),"result":result})
		return result
class ReferenceAreas extends TraceAreas:
	func _sort_floor_waiting_points(points: Array, origin: Vector2) -> void:
		before=points.duplicate()
		points.sort_custom(func(a: Vector2i,b: Vector2i)->bool:
			var da: float=origin.distance_squared_to(Vector2(a))
			var db: float=origin.distance_squared_to(Vector2(b))
			return da<db if da!=db else a.y<b.y if a.y!=b.y else a.x<b.x)
		after=points.duplicate()
class SortAdapter extends RefCounted:
	var areas: HospitalPublicAreas
	func baseline(points: Array, origin: Vector2) -> void:
		points.sort_custom(func(a: Vector2i,b: Vector2i)->bool:
			var da: float=origin.distance_squared_to(Vector2(a))
			var db: float=origin.distance_squared_to(Vector2(b))
			return da<db if da!=db else a.y<b.y if a.y!=b.y else a.x<b.x)
	func candidate(points: Array, origin: Vector2) -> void:
		areas._sort_floor_waiting_points(points,origin)
class CountAreas extends HospitalPublicAreas:
	static var calls: int=0
	func floor_waiting_point(world: WorldState, actor_id: String) -> Dictionary:
		calls+=1
		return super.floor_waiting_point(world,actor_id)
class CountPhase extends Phase:
	func _areas(staff: Dictionary={}) -> Dictionary:
		var x: Dictionary=_fixture(staff)
		for entry: Array in [["west",34],["east",48]]:
			HospitalFactory._add_room(x.world,{"id":entry[0],"type":"toilet" if entry[0]=="west" else "rest","anchor":[entry[1],66],"size":[10,12],"door":{"definition_id":"DR04","offset":3}},_content)
			_facility(x,str(entry[0])+"_chair","FUR09",[int(entry[1])+2,68],str(entry[0]))
		x.world.touch()
		x.space.public_areas=CountAreas.new(x.space)
		return x
class CurrentBoundary extends Boundary:
	func _areas(staff: Dictionary={}) -> Dictionary:
		var x: Dictionary=_fixture(staff)
		for entry: Array in [["west",34],["east",48]]:
			HospitalFactory._add_room(x.world,{"id":entry[0],"type":"toilet" if entry[0]=="west" else "rest","anchor":[entry[1],66],"size":[10,12],"door":{"definition_id":"DR04","offset":3}},_content)
			_facility(x,str(entry[0])+"_chair","FUR09",[int(entry[1])+2,68],str(entry[0]))
		x.world.touch()
		x.space.public_areas=CountAreas.new(x.space)
		return x
	func _fallback_waypoint() -> Dictionary:
		var rows: Array = []
		for foreign: bool in [false,true]:
			var x: Dictionary = _areas()
			_facility(x,"toilet","FUR07",[39,68],"west")
			var visit: Dictionary = _visit(x,"waypoint",[37,78])
			var actor: Dictionary = x.world.facts.actors[visit.actor_id]
			var blocker: Dictionary = actor.duplicate(true)
			blocker.id="waypoint_blocker";blocker.name="waypoint_blocker";blocker.location.cell=[42,90]
			x.world.facts.actors[blocker.id]=blocker;x.space.sync_actor(x.world,blocker.id);x.world.touch(false)
			var unsafe: bool = not x.space.public_areas.safe_wait(x.world,actor.id,1,actor.location.cell)
			x.l._begin_need(x.world,visit)
			var need: Dictionary = x.world.facts.waiting_life.needs[visit.id]
			var start: int = int(need.started_tick)
			x.world.facts.sim_tick=start+451
			x.l._dispatch_need(x.world,visit,need)
			var pending: bool = need.phase=="fallback_travel" and need.remaining_ticks==0
			# A legitimate safety trip may have a distant static waypoint which
			# becomes occupied. The movement and safe intermediate arrival below
			# are real; no fallback work or position is supplied by this fixture.
			var reason: String = x.l._request_need_move(x.world,need,actor.id,1,[42,90])
			if foreign and x.world.facts.moves.has(actor.id): x.world.facts.moves[actor.id].waiting_need_id="another_task"
			var safe_seen: bool = false
			var completion: bool = false
			var steps: int = 0
			for _tick: int in 100:
				x.world.facts.sim_tick+=1
				x.l._dispatch_need(x.world,visit,need)
				var safe: bool = x.space.public_areas.safe_wait(x.world,actor.id,1,actor.location.cell)
				if safe:
					safe_seen=true
					completion=need.phase=="fallback_travel" and x.world.facts.moves.has(actor.id) and need.remaining_ticks==0 if foreign else need.phase=="fallback" and not x.world.facts.moves.has(actor.id) and need.remaining_ticks==80
					break
				x.space.advance(x.world);x.world.touch(false);steps+=1
			var checks: Dictionary = {"unsafe_input_and_real_pending_need":unsafe and pending,"real_safety_journey":reason.is_empty() and steps>0,"actual_safe_intermediate_position":safe_seen and actor.location.cell!=[37,78] and actor.location.cell!=[42,90],"correct_owner_controls_completion":completion,"original_clock_kept":int(need.started_tick)==start,"valid_world":x.world.validate(_content).is_empty()}
			rows.append({"foreign":foreign,"ok":checks.values().all(func(v: Variant)->bool:return v==true),"checks":checks,"steps":steps,"actual":actor.location.cell.duplicate(),"phase":need.phase,"remaining_ticks":need.remaining_ticks,"movement":x.world.facts.moves.get(actor.id,{}).duplicate(true),"actual_current_area":x.space.public_areas.current_area(x.world,actor.id),"full_body_in_current_area":x.space.public_areas.contains(x.world,x.space.public_areas.current_area(x.world,actor.id),actor.id)})
			x.a.dispose()
		return {"case":"safe_fallback_before_busy_waypoint","ok":rows.all(func(row: Dictionary)->bool:return row.ok),"variants":rows}

class BaselineOnlyAreas extends HospitalPublicAreas:
	func _sort_floor_waiting_points(points: Array, origin: Vector2) -> void:
		points.sort_custom(func(a: Vector2i,b: Vector2i)->bool:
			var da: float=origin.distance_squared_to(Vector2(a))
			var db: float=origin.distance_squared_to(Vector2(b))
			return da<db if da!=db else a.y<b.y if a.y!=b.y else a.x<b.x)
class BaselineBoundary extends CurrentBoundary:
	func _areas(staff: Dictionary={}) -> Dictionary:
		var x: Dictionary=super._areas(staff)
		x.space.public_areas=BaselineOnlyAreas.new(x.space)
		return x
var content: HospitalContent
var sorter: RefCounted
var errors: Array=[]
var checks: Array=[]
func _initialize() -> void: call_deferred("_run")
func _expect(ok: bool, label: String) -> void:
	if not ok: errors.append(label)
func check(id: String, passed: bool, details: Variant=null) -> void:
	checks.append({"case":id,"ok":passed,"details":details})
	_expect(passed,id)
func _pure_case(label: String, original: Array, origin: Vector2, literal: Array=[]) -> Dictionary:
	var before: Array=original.duplicate()
	var a: Array=original.duplicate()
	var b: Array=original.duplicate()
	sorter.baseline(a,origin)
	sorter.candidate(b,origin)
	var ok: bool=a==b and original==before
	if not literal.is_empty(): ok=ok and a==literal
	_expect(ok,"pure:"+label)
	return {"case":label,"ok":ok,"origin":[origin.x,origin.y],"input":original,"expected":a,"candidate":b}

func _correctness() -> Array:
	var rows: Array=[]
	rows.append(_pure_case("empty",[],Vector2.ZERO))
	rows.append(_pure_case("single",[Vector2i(95,95)],Vector2(40,71)))
	rows.append(_pure_case("duplicates",[Vector2i(31,32),Vector2i(31,32),Vector2i(32,31),Vector2i(32,31)],Vector2(31.5,31.5)))
	rows.append(_pure_case("literal_integer_y_x_ties",[Vector2i(41,40),Vector2i(40,41),Vector2i(40,39),Vector2i(39,40)],Vector2(40,40),[Vector2i(40,39),Vector2i(39,40),Vector2i(41,40),Vector2i(40,41)]))
	rows.append(_pure_case("literal_half_grid_ties",[Vector2i(32,32),Vector2i(31,32),Vector2i(32,31),Vector2i(31,31)],Vector2(31.5,31.5),[Vector2i(31,31),Vector2i(32,31),Vector2i(31,32),Vector2i(32,32)]))
	var grid: Array=[]
	for y: int in [0,31,32,40,41,63,64,70,71,95]:
		for x: int in [0,31,32,39,40,41,63,64,95]: grid.append(Vector2i(x,y))
	grid.reverse()
	for origin: Vector2 in [Vector2(40,70),Vector2(40.5,70.5),Vector2(40.000003814697265625,70.00000762939453125),Vector2(39.999996185302734375,69.99999237060546875),Vector2(63.5,63.5),Vector2(95,95),Vector2(1.0e12,1.0e12),Vector2(-1.0e12,-1.0e12),Vector2(-0.5,32.5),Vector2(1.0e12,-1.0e12)]:
		rows.append(_pure_case("numeric_domain_"+str(rows.size()),grid,origin))
	return rows


func _trace_valid(points: Array, events: Array, result: Dictionary, floor_id: int) -> bool:
	var index: int=0
	var reach: bool=false
	var success: bool=false
	for event: Dictionary in events:
		if success or index>=points.size(): return false
		var point: Vector2i=points[index]
		if event.cell!=[point.x,point.y] or event.kind!=("reach" if reach else "safe"): return false
		if reach:
			success=event.result;reach=false
			if not success: index+=1
		elif event.result: reach=true
		else: index+=1
	if reach: return false
	return result=={"floor_id":floor_id,"cell":[points[index].x,points[index].y]} if success else result.is_empty() and index==points.size()
func _query(label: String, world: WorldState, actor: String, actual: TraceSpace, reference: TraceSpace) -> Dictionary:
	actual.events.clear();reference.events.clear()
	actual.public_areas.before=[];actual.public_areas.after=[]
	reference.public_areas.before=[];reference.public_areas.after=[]
	var frozen: Dictionary=world.freeze()
	var validation: String=world.validate(content)
	var a: Dictionary=actual.public_areas.floor_waiting_point(world,actor)
	var mid: bool=world.freeze()==frozen
	var b: Dictionary=reference.public_areas.floor_waiting_point(world,actor)
	var same: bool=actual.public_areas.before==reference.public_areas.before and actual.public_areas.after==reference.public_areas.after and actual.events==reference.events and a==b
	var short_circuit: bool=_trace_valid(actual.public_areas.after,actual.events,a,int(world.facts.actors[actor].location.floor_id))
	var row: Dictionary={"case":label,"ok":validation.is_empty() and same and short_circuit and mid and world.freeze()==frozen,"validation":validation,"full_order_and_call_trace_equal":same,"short_circuit":short_circuit,"world_rng_unchanged":mid and world.freeze()==frozen,"count":actual.public_areas.after.size(),"events":actual.events.duplicate(true),"returned":a}
	_expect(row.ok,label)
	return row
func _inputs(manifest: Dictionary, sequence_only: bool) -> Array:
	var rows: Array=[]
	var actual:=TraceSpace.new(content);actual.public_areas=TraceAreas.new(actual)
	var reference:=TraceSpace.new(content);reference.public_areas=ReferenceAreas.new(reference)
	var adapter:=SortAdapter.new();adapter.areas=actual.public_areas;sorter=adapter
	if sequence_only: rows.append_array(_correctness())
	for entry: Dictionary in manifest.corpus:
		_expect(FileAccess.get_sha256(entry.path)==entry.sha256,"corpus hash")
		var f:=FileAccess.open(entry.path,FileAccess.READ);var d: Dictionary=f.get_var(false);f.close()
		var original: PackedByteArray=var_to_bytes(d)
		if sequence_only:
			var points: Array=d.points_before.duplicate()
			actual.public_areas._sort_floor_waiting_points(points,Vector2(float(d.origin[0]),float(d.origin[1])))
			var ok: bool=points==d.points_after
			_expect(ok,"captured:"+d.actor_id);rows.append({"case":d.actor_id,"ok":ok,"points":points.size()})
		else:
			var world:=WorldState.new(d.facts.duplicate(true))
			rows.append(_query(d.actor_id,world,d.actor_id,actual,reference))
			if rows.size()==1:
				var cold:=WorldState.new(world.freeze())
				rows.append(_query("cold_world",cold,d.actor_id,actual,reference))
				cold.facts=cold.freeze().duplicate(true)
				rows.append(_query("replaced_facts",cold,d.actor_id,actual,reference))
		_expect(original==var_to_bytes(d) and FileAccess.get_sha256(entry.path)==entry.sha256,"corpus unchanged")
	return rows
func _fixture_queries() -> Array:
	var fixture:=CountPhase.new();fixture._content=content
	var x: Dictionary=fixture._areas()
	var visit: Dictionary=fixture._visit(x,"public_order",[38,90])
	var a:=TraceSpace.new(content);a.public_areas=TraceAreas.new(a)
	var b:=TraceSpace.new(content);b.public_areas=ReferenceAreas.new(b)
	var rows: Array=[_query("room_public_before",x.world,visit.actor_id,a,b)]
	x.world.facts.rooms.west.kind="doctor_office";x.world.touch()
	rows.append(_query("room_public_to_private",x.world,visit.actor_id,a,b))
	x.world.facts.rooms.west.kind="rest";x.world.touch()
	rows.append(_query("room_public_restored",x.world,visit.actor_id,a,b))
	# Existing complete upper-floor ownership facts are supplied by captured
	# inputs; assert those inputs exercise derived floor_plots in the report.
	x.a.dispose()
	return rows
func _derived_floor() -> Dictionary:
	var fixture:=CountPhase.new();fixture._content=content
	var x: Dictionary=fixture._fixture()
	var visit: Dictionary=fixture._visit(x,"derived_order",[38,90])
	x.world.facts.floors.completed_top_floor={}
	for plot: Array in x.world.facts.floors.overrides["1"].plots:
		x.world.facts.floors.completed_top_floor[HospitalSpace.plot_key(plot)]=2
	x.world.facts.actors[visit.actor_id].location.floor_id=2
	x.world.touch()
	var a:=TraceSpace.new(content);a.public_areas=TraceAreas.new(a)
	var b:=TraceSpace.new(content);b.public_areas=ReferenceAreas.new(b)
	var row: Dictionary=_query("derived_upper_without_override",x.world,visit.actor_id,a,b)
	var plots: Array=HospitalSpace.floor_plots(x.world,2)
	row.owned_plots=plots
	row.has_override=x.world.facts.floors.overrides.has("2")
	row.independent_expected_public_points=plots.size()*1024
	row.public_enumeration_correct=not row.has_override and not plots.is_empty() and row.count==row.independent_expected_public_points
	row.original_comparator_same_omission=row.count==0 and b.public_areas.after.is_empty()
	row.ok=row.ok and row.public_enumeration_correct
	_expect(row.ok,"derived public floor independently complete")
	x.a.dispose()
	return row
func _run() -> void:
	var args:=OS.get_cmdline_user_args();content=HospitalContent.new()
	var mode: String=args[0];var rows: Array=[]
	if mode in ["sequence","query"]:
		var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[2]))
		rows=_inputs(manifest,mode=="sequence")
		if mode=="query":rows.append_array(_fixture_queries())
	elif mode=="fixtures":
		rows=_fixture_queries()
	elif mode=="waypoint_reference":
		var boundary:=BaselineBoundary.new();boundary._content=content
		var row: Dictionary=boundary._fallback_waypoint();rows.append(row);_expect(row.ok,row.case)
	elif mode=="waypoint":
		var boundary:=CurrentBoundary.new();boundary._content=content
		var row: Dictionary=boundary._fallback_waypoint();rows.append(row);_expect(row.ok,row.case)
	elif mode=="derived":
		rows=[_derived_floor()]
	elif mode=="flow":
		var phase:=CountPhase.new();phase._content=content;phase._case_74(self)
		check("STAFF-74-floor-fallback-hit",CountAreas.calls>0,{"calls":CountAreas.calls})
		var boundary:=CurrentBoundary.new();boundary._content=content
		var row: Dictionary=boundary._fallback_waypoint();rows.append(row);_expect(row.ok,row.case)
		rows.append_array(checks)
	else:errors.append("unknown mode")
	var out:=FileAccess.open(args[1],FileAccess.WRITE)
	out.store_string(JSON.stringify({"ok":errors.is_empty(),"mode":mode,"rows":rows,"errors":errors},"\t"));out.close()
	print("FLOOR_WAIT_ORDER "+mode+" "+str(errors.is_empty()))
	quit(0 if errors.is_empty() else 1)
