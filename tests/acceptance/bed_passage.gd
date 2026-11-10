extends RefCounted

class ObservedSpace:
	extends HospitalSpace
	var exit_witness_calls: int=0
	func _init(c: HospitalContent) -> void: super(c)
	func _exit_witness(w: WorldState,a: Dictionary,f: int,start: Vector2i,goal: Vector2i) -> Dictionary:
		exit_witness_calls+=1
		return super._exit_witness(w,a,f,start,goal)

var content: HospitalContent
var checks: Dictionary={}
var observations: Dictionary={}

func person(id: String,species: String,cell: Array) -> Dictionary:
	return {"id":id,"name":id,"species_id":species,"location":{"kind":"floor","floor_id":1,"cell":cell,"height_m":0.0},"facing":0.0,"posture":"standing"}

func fixture(species: String="S49", reserve: bool=true, rotation: int=0) -> Dictionary:
	var w: WorldState=HospitalFactory.create(HospitalSnapshots.uuid(),"护理床通行专项",false,content)
	for r: Dictionary in content.catalog.research:w.facts.research.append(r.id)
	var s: ObservedSpace=ObservedSpace.new(content)
	var b: BuildService=BuildService.new(content,s)
	b._deferred_checks=true
	b._add_room(w,{"id":"ward","room_type_id":"ward","floor_id":1,"origin":[34,66],"size":[28,26],"doors":[{"definition_id":"DR06","edge":"south","offset":14}]})
	b._add_facility(w,{"id":"bed","definition_id":"EQ05","floor_id":1,"cell":[44,70],"rotation":rotation,"room_id":"ward"})
	w.facts.actors.p=person("p",species,[54,88]);w.facts.actors.n=person("n","S49",[57,88]);w.facts.actors.d=person("d","S49",[59,88]);w.facts.actors.walker=person("walker","S49",[42,73]);w.touch()
	var fit: Dictionary=s.facility_geometry_quote(w,"bed","p",["n","d"])
	var reason: String=""
	if reserve and fit.ok:
		# Declared input: this patient is already at the bedside. Admission and
		# actual escorted arrival are covered separately by CLIN-20.
		w.facts.actors.p.location.cell=fit.patient_cell.duplicate();w.touch()
		reason=s.reserve_facility(w,"bed","p","p",["n","d"])
		if reason.is_empty():HospitalClinic.new(content,s)._support(w,{"actor_id":"p"},s.facility_layout(w,"bed"),"lying")
	return {"w":w,"s":s,"fit":fit,"reserve":reason}

func tick(x: Dictionary) -> void:
	x.s.advance(x.w,x.w.present_actor_count());x.w.facts.sim_tick+=1;x.w.touch(false);x.s.finish_boundary(x.w)

func walk(x: Dictionary,id: String,target: Array,limit: int=800) -> Dictionary:
	var reason: String=x.s.request_floor_move(x.w,id,1,target)
	var ticks: int=0;var overlaps: Array=[];var maximum: float=0.0;var support_seen: bool=false
	while reason.is_empty() and x.w.facts.moves.has(id) and ticks<limit:
		var previous: Vector2=ConvoyTrail.point(x.w.facts.actors[id].location.cell)
		support_seen=support_seen or x.w.facts.actors[id].posture=="lying"
		tick(x);ticks+=1
		var actor: Dictionary=x.w.facts.actors[id]
		maximum=maxf(maximum,previous.distance_to(ConvoyTrail.point(actor.location.cell)))
		if actor.posture!="lying" and x.s.overlaps_facility(x.w,id,"bed"):overlaps.append({"tick":ticks,"bed":true})
		for other: Dictionary in x.w.facts.actors.values():
			if other.id!=id and other.location.kind=="floor" and x.s.body_rectangle(actor).intersects(x.s.body_rectangle(other),false):overlaps.append({"tick":ticks,"actor":other.id})
	return {"reason":reason,"arrived":x.s.at(x.w,id,1,target),"ticks":ticks,"maximum_step":maximum,"overlaps":overlaps,"support_seen":support_seen,"last":x.w.facts.actors[id].location.cell.duplicate()}

func passage() -> void:
	for row: Array in [["patient",[42,73],[49,73]],["operator",[43,69],[43,74]],["repair",[43,69],[48,69]]]:
		var x: Dictionary=fixture();x.w.facts.actors.walker.location.cell=row[1].duplicate();x.w.touch()
		var before: Dictionary=x.w.freeze();var q: Dictionary=x.s.facility_quote(x.w,"bed","p",["n","d"])
		checks[str(row[0])+"_quote_readonly"]=q.ok and before==x.w.freeze() and x.s.exit_witness_calls==0
		var moved: Dictionary=walk(x,"walker",row[2]);observations[str(row[0])+"_passage"]=moved
		checks[str(row[0])+"_actual_passage"]=x.reserve.is_empty() and moved.arrived and moved.overlaps.is_empty() and moved.maximum_step<=0.201
		checks[str(row[0])+"_owner_retained"]=x.w.facts.adaptations.has("bed") and x.w.facts.actors.p.posture=="lying"

func claims() -> void:
	var x: Dictionary=fixture();var w: WorldState=x.w;var s: HospitalSpace=x.s
	var post: Array=x.fit.patient_cell;var a: Dictionary=w.facts.actors.walker
	var body: Rect2=s._actor_rect(a,ConvoyTrail.point(post))
	checks.empty_passage_but_not_use=s._dynamic_clear(w,a.id,1,body,[],false,true) and not s._dynamic_clear(w,a.id,1,body)
	# A single actor's terminal facing is known only after a route is issued.
	# Admitting its journey must not admit standing in another task's post.
	var requested: String=s.request_move(w,a.id,1,post)
	for i: int in 8:tick(x)
	checks.foreign_goal_waits=requested.is_empty() and w.facts.moves.has(a.id) and not s.body_rectangle(a).intersects(body,false) and not w.facts.moves[a.id].get("waiting_reason","").is_empty()
	var fractional: Array=[float(post[0])+0.15,float(post[1])+0.10]
	var fractional_request: String=s.request_move(w,a.id,1,fractional)
	for i: int in 8:tick(x)
	checks.fractional_goal_waits=fractional_request.is_empty() and w.facts.moves.has(a.id) and not s.body_rectangle(a).intersects(body,false) and not w.facts.moves[a.id].get("waiting_reason","").is_empty()
	s.movement.cancel_ground(w,a.id)

	var build: Dictionary=BuildService.new(content,s).preview(w,{"kind":"build_facility","definition_id":"FUR09","floor_id":1,"cell":post,"room_id":"ward"})
	checks.build_claim_preserved=not build.ok
	var n: Dictionary=walk(x,"n",x.fit.operator_cells[0]);var ne: Dictionary=walk(x,"n",[57,88]);var d: Dictionary=walk(x,"d",x.fit.operator_cells[1]);var de: Dictionary=walk(x,"d",[59,88])
	observations.team={"nurse":n,"nurse_exit":ne,"doctor":d,"doctor_exit":de}
	checks.authorized_team_walks=n.arrived and ne.arrived and d.arrived and de.arrived and n.overlaps.is_empty() and ne.overlaps.is_empty() and d.overlaps.is_empty() and de.overlaps.is_empty()

func late_goal() -> void:
	var x: Dictionary=fixture("S49",false);var w: WorldState=x.w;var s: HospitalSpace=x.s
	w.facts.actors.walker.location.cell=[39,73];w.facts.actors.p.location.cell=x.fit.patient_cell.duplicate();w.touch()
	var reason: String=s.request_move(w,"walker",1,x.fit.patient_cell)
	var sequence: int=w.facts.moves.walker.get("request_sequence",-1)
	var reserved: String=s.reserve_facility(w,"bed","p","p",["n","d"])
	HospitalClinic.new(content,s)._support(w,{"actor_id":"p"},s.facility_layout(w,"bed"),"lying")
	for i: int in 100:tick(x)
	var goal_body: Rect2=Rect2(x.fit.patient_cell[0],x.fit.patient_cell[1],1,1)
	checks.late_claim_not_occupied=reason.is_empty() and reserved.is_empty() and not s.body_rectangle(w.facts.actors.walker).intersects(goal_body,false)
	checks.late_claim_intent_retained=w.facts.moves.has("walker") and w.facts.moves.walker.target_cell==x.fit.patient_cell and int(w.facts.moves.walker.get("request_sequence",-2))==sequence
	observations.late_goal={"location":w.facts.actors.walker.location.cell.duplicate(),"move":w.facts.moves.get("walker",{}).duplicate(true)}
	# The owner really stands and leaves; no adaptation is erased by the test.
	var exit: Dictionary=walk(x,"p",[54,88]);for i: int in 500:
		if not w.facts.moves.has("walker"):break
		tick(x)
	checks.late_goal_resumes_after_release=exit.arrived and not w.facts.adaptations.has("bed") and s.at(w,"walker",1,x.fit.patient_cell)

func collision() -> void:
	var x: Dictionary=fixture();var w: WorldState=x.w;var s: HospitalSpace=x.s
	w.facts.actors.blocker=person("blocker","S49",x.fit.patient_cell.duplicate());w.touch()
	var rectangle: Rect2=s._actor_rect(w.facts.actors.walker,ConvoyTrail.point(x.fit.patient_cell))
	checks.real_body_still_blocks=not s._dynamic_clear(w,"walker",1,rectangle,[],false,true)
	# A frozen accepted sweep is an explicit calculation boundary, not a
	# claim that this fixture performed the preceding movement.
	s.movement._sweep_index.begin_boundary(w.facts.actors)
	s.movement._sweep_index.update("blocker",1,Rect2(46,69,1,1))
	checks.accepted_sweep_still_blocks=not s._dynamic_clear(w,"walker",1,Rect2(46.2,69.2,0.4,0.4),[],false,true)

func expansion() -> void:
	for alternative: bool in [false,true]:
		var x: Dictionary=fixture("S59",false);var w: WorldState=x.w;var s: ObservedSpace=x.s
		w.facts.actors.walker.location.cell=[59,68]
		for xx: int in range(34,62):
			if xx not in [44,45,46] and not (alternative and xx in [55,56,57]):w.facts.floors.overrides["1"].blocked.append([xx,74])
		w.touch();var before: Dictionary=w.freeze();var q: Dictionary=s.facility_quote(w,"bed","p",["n","d"])
		checks["extension_"+str(alternative)]=bool(q.ok)==alternative and w.freeze()==before and s.exit_witness_calls>0
		observations["extension_"+str(alternative)]=q
	var x: Dictionary=fixture("S59",false);x.w.facts.actors.n.location.cell=[44,74];x.w.touch()
	var q: Dictionary=x.s.facility_quote(x.w,"bed","p",["n","d"])
	checks.extension_cannot_cover_team=not q.ok and not x.w.facts.adaptations.has("bed")
	observations.extension_team=q
	var swept: Dictionary=fixture("S59",false)
	swept.s.movement._sweep_index.begin_boundary(swept.w.facts.actors)
	swept.s.movement._sweep_index.update("n",1,Rect2(44,74,1,1))
	var sweep_quote: Dictionary=swept.s.facility_quote(swept.w,"bed","p",["n","d"])
	checks.extension_cannot_cover_accepted_sweep=not sweep_quote.ok and not swept.w.facts.adaptations.has("bed")

func release() -> void:
	var x: Dictionary=fixture();var before: Array=x.w.facts.adaptations.bed.footprint.duplicate()
	var departure: Dictionary=walk(x,"p",[54,88]);for i: int in 2:tick(x)
	checks.actual_supported_exit=departure.support_seen and departure.arrived and departure.maximum_step<=0.201 and not x.w.facts.adaptations.has("bed")
	var next: String=x.s.request_move(x.w,"walker",1,x.fit.patient_cell)
	checks.released_post_reusable=next.is_empty()
	observations.release=departure
	var rotated: Dictionary=fixture("S49",true,1)
	var area: Array=rotated.fit.regions[1];var rect: Rect2=Rect2(area[0],area[1],area[2],area[3])
	checks.rotated_empty_post=rotated.reserve.is_empty() and rotated.s._dynamic_clear(rotated.w,"walker",1,rect,[],false,true) and not rotated.s._dynamic_clear(rotated.w,"walker",1,rect)

func groups() -> void:
	var x: Dictionary=fixture();var w: WorldState=x.w;var s: HospitalSpace=x.s
	w.facts.actors.follower=person("follower","S49",[40,73]);w.touch()
	var requested: String=s.request_group_move(w,"walker",["walker","follower"],{},1,[49,73])
	var crossed: bool=false;var clean: bool=true;var maximum: float=0.0
	for i: int in 100:
		var previous: Vector2=ConvoyTrail.point(w.facts.actors.walker.location.cell)
		tick(x)
		maximum=maxf(maximum,previous.distance_to(ConvoyTrail.point(w.facts.actors.walker.location.cell)))
		crossed=crossed or s.body_rectangle(w.facts.actors.walker).intersects(Rect2(44,73,1,1),false)
		for id: String in ["walker","follower"]:
			clean=clean and not s.overlaps_facility(w,id,"bed") and not s.body_rectangle(w.facts.actors[id]).intersects(s.body_rectangle(w.facts.actors.p),false)
		clean=clean and not s.body_rectangle(w.facts.actors.walker).intersects(s.body_rectangle(w.facts.actors.follower),false)
		if not w.facts.moves.has("walker"):break
	checks.group_actual_passage=requested.is_empty() and crossed and clean and maximum<=0.201 and s.at(w,"walker",1,[49,73]) and not w.facts.moves.has("walker")
	var held: Dictionary=fixture();var hw: WorldState=held.w;var hs: HospitalSpace=held.s
	hw.facts.actors.walker.location.cell=[39,73];hw.facts.actors.follower=person("follower","S49",[37,73]);hw.touch()
	var admission: String=hs.request_group_move(hw,"walker",["walker","follower"],{},1,[46,73])
	for i: int in 12:tick(held)
	checks.group_tail_cannot_park=admission.is_empty() and hs.at(hw,"walker",1,[39,73]) and not hw.facts.moves.walker.get("waiting_reason","").is_empty()
	# Calculation boundary: a legal issued right-angle suffix. The tail turns
	# through the patient post although the head and a straight rear do not.
	var m: Dictionary=hw.facts.moves.walker.duplicate(true)
	m.target_cell=[45,74];m.path=[{"kind":"floor","floor_id":1,"cell":[43,73]},{"kind":"floor","floor_id":1,"cell":[45,73]},{"kind":"floor","floor_id":1,"cell":[45,74]}];m.cursor=0
	checks.corner_tail_exact=hs.movement._bed_goal_blocker(hw,hw.facts.actors.walker,m)=="bed"
	var allowed: Dictionary=m.duplicate();allowed.members=["walker","p"]
	checks.group_patient_permission=hs.movement._bed_goal_blocker(hw,hw.facts.actors.walker,allowed).is_empty()
	# Temporary detour contains no final approach: it must not create a
	# diagonal from the original goal to the current published tail.
	m.path=[{"kind":"floor","floor_id":1,"cell":[39,74]}]
	checks.temporary_route_no_guessed_tail=hs.movement._bed_goal_regions(hw,hw.facts.actors.walker,m).is_empty()
	var depart: Dictionary=walk(held,"p",[54,88])
	for i: int in 150:
		if not hw.facts.moves.has("walker"):break
		tick(held)
	checks.group_resumes_after_release=depart.arrived and hs.at(hw,"walker",1,[46,73]) and not hw.facts.moves.has("walker")

func local_rejoin() -> void:
	var x: Dictionary=fixture();var w: WorldState=x.w;var s: HospitalSpace=x.s
	w.facts.actors.walker.location.cell=[43,74];w.touch()
	s.request_move(w,"walker",1,x.fit.patient_cell)
	s.movement._dispatch_routes(w,w.present_actor_count())
	var m: Dictionary=w.facts.moves.walker
	# Explicit local-return boundary, before the target mutation in resume.
	# Its already reached safe corner is input, never claimed as tested motion.
	m.local_move={"origin":[43,74],"target":{"kind":"floor","floor_id":1,"cell":[43,74]},"rejoin":{"index":m.path.size()-1,"cell":x.fit.patient_cell.duplicate()}}
	var sequence: int=m.request_sequence
	tick(x)
	observations.local_rejoin={"location":w.facts.actors.walker.location.duplicate(true),"movement":m.duplicate(true)}
	checks.local_rejoin_cannot_enter=s.at(w,"walker",1,[43,74]) and ConvoyTrail.point(m.local_move.target.cell)==ConvoyTrail.point(x.fit.patient_cell) and m.request_sequence==sequence and not m.get("waiting_reason","").is_empty()
	var exit: Dictionary=walk(x,"p",[54,88])
	for i: int in 100:
		if not w.facts.moves.has("walker"):break
		tick(x)
	checks.local_rejoin_resumes=exit.arrived and s.at(w,"walker",1,x.fit.patient_cell) and not w.facts.moves.has("walker")

func detour_rejoin() -> void:
	var x: Dictionary=fixture();var w: WorldState=x.w;var s: HospitalSpace=x.s
	w.facts.actors.walker.location.cell=[43,73];w.touch()
	s.request_move(w,"walker",1,x.fit.patient_cell)
	s.movement._dispatch_routes(w,w.present_actor_count())
	var m: Dictionary=w.facts.moves.walker
	# Calculation handoff: an already reached aside stop and the untouched
	# original goal. Production continuation must publish and gate rejoin in
	# the same frame, before any portion of its first movement is accepted.
	m.detour={"phase":"aside","original_path":m.path.duplicate(true),"prefix_size":0,"resume_index":-1,"direction":[1,0]}
	m.path=[];m.cursor=0
	var sequence: int=m.request_sequence
	tick(x)
	checks.detour_rejoin_cannot_enter=s.at(w,"walker",1,[43,73]) and m.get("detour",{}).get("phase","")=="rejoin" and m.request_sequence==sequence and not m.get("waiting_reason","").is_empty()
	observations.detour_rejoin=m.duplicate(true)

# Both fixtures start before the real collision. Every movement tick runs;
# no local target, completion or actor step is supplied by the fixture.
func candidate_stops() -> void:
	for y: int in [71,72]:
		var x: Dictionary=fixture();var w: WorldState=x.w;var s: HospitalSpace=x.s
		w.facts.actors.walker.location.cell=[42,y]
		w.facts.actors.blocker=person("blocker","S49",[42,y-1])
		# World validation expects the untyped serialized actor map.
		var actors: Dictionary={}
		for id: Variant in w.facts.actors: actors[str(id)]=w.facts.actors[id]
		w.facts.actors=actors;w.touch()
		var initial: String=w.validate(content)
		var requested: String=s.request_move(w,"walker",1,[42,y-3])
		var sequence: int=w.facts.moves.walker.request_sequence
		var selected: Array=[];var safe: bool=true;var retained: bool=true;var steps: int=0
		for i: int in 200:
			var previous: Rect2=s.body_rectangle(w.facts.actors.walker)
			tick(x);steps+=1
			var current: Rect2=s.body_rectangle(w.facts.actors.walker)
			for other: Dictionary in w.facts.actors.values():
				if other.id=="walker": continue
				var body: Rect2=s.body_rectangle(other)
				safe=safe and not BodySweep.intersects(previous,current,body,body)
			safe=safe and not BodySweep.intersects(previous,current,Rect2(44,70,3,3),Rect2(44,70,3,3))
			if not w.facts.moves.has("walker"): break
			var m: Dictionary=w.facts.moves.walker
			retained=retained and m.request_sequence==sequence and m.target_cell==[42,y-3]
			if selected.is_empty() and m.has("local_move"): selected=m.local_move.target.cell.duplicate()
		var key: String="candidate_"+str(y)
		checks[key+"_legal_input_and_end"]=initial.is_empty() and w.validate(content).is_empty()
		checks[key+"_other_side_and_arrival"]=requested.is_empty() and not selected.is_empty() and float(selected[0])<42.0 and s.at(w,"walker",1,[42,y-3]) and not w.facts.moves.has("walker")
		checks[key+"_safe_original_intent"]=safe and retained and w.facts.adaptations.has("bed")
		observations[key]={"initial_validation":initial,"final_validation":w.validate(content),"selected":selected,"ticks":steps}

	# Explicit calculation boundary: choose between two orthogonal return
	# links. The first corner is held; the second is a real usable stop.
	var x: Dictionary=fixture();var w: WorldState=x.w;var s: HospitalSpace=x.s
	var actor: Dictionary=w.facts.actors.walker;actor.location.cell=[42,71.5];w.touch()
	var m: Dictionary={"actor_id":"walker","members":["walker"],"local_move":{"origin":[42,71.5]}}
	var query: RouteClearance=s.navigation.structural_clearance(w,actor,1)
	var returned: bool=s.movement._local_return(w,actor,m,query,0,Vector2(43,69))
	checks.return_chooses_unclaimed_corner=returned and m.local_move.target.cell==[42.0,69.0]
	checks.retreat_cannot_choose_claimed_stop=not s.movement._retreat_intention_clear(w,actor,m,[s.movement._floor_point(actor,Vector2(43,71.5))])
	observations.return_candidate=m.duplicate(true)

	# A production-created convoy, then an explicit aside-selection boundary.
	# No claim that this calculation input already executed a body collision.
	var group: Dictionary=fixture();var gw: WorldState=group.w;var gs: HospitalSpace=group.s
	gw.facts.actors.walker.location.cell=[42,71];gw.facts.actors.follower=person("follower","S49",[42,73]);gw.touch()
	var reason: String=gs.request_group_move(gw,"walker",["walker","follower"],{},1,[42,68])
	gs.movement._dispatch_routes(gw,gw.present_actor_count())
	var journey: Dictionary=gw.facts.moves.walker
	journey.detour={"phase":"aside","direction":[0,-1],"original_path":journey.path.duplicate(true),"prefix_size":0,"resume_index":-1,"backtrack":[],"back_cursor":-1}
	var selected_side: bool=gs.movement._detour_side_full(gw,gw.facts.actors.walker,journey)
	checks.convoy_chooses_unclaimed_side=reason.is_empty() and selected_side and journey.path[-1].cell==[41.0,71.0]
	# Head is clear at [45,74], but its two-cell rear crosses the patient
	# post. The synthetic candidate must not inherit the old route cursor.
	journey.cursor=99
	var path: Array=[]
	for point: Vector2 in [Vector2(43,71),Vector2(43,73),Vector2(45,73),Vector2(45,74)]:path.append(gs.movement._floor_point(gw.facts.actors.walker,point))
	var before: Dictionary=journey.duplicate(true)
	var blocked: String=gs.movement._bed_path_stop_blocker(gw,gw.facts.actors.walker,journey,path)
	checks.convoy_candidate_readonly=journey==before
	checks.convoy_candidate_tail_claim=blocked=="bed" and gs.bed_destination_blocker(gw,"walker",1,Rect2(45,74,1,1),journey.members).is_empty()
	observations.convoy_candidate={"chosen":before.path,"blocked":blocked}

func restoration() -> void:
	var x: Dictionary=fixture();x.s.request_floor_move(x.w,"walker",1,[49,73])
	for i: int in 8:tick(x)
	var frozen: Dictionary=x.w.freeze()
	var restored: Dictionary={"w":WorldState.new(frozen.duplicate(true)),"s":ObservedSpace.new(content)}
	checks.restore_exact_facts=restored.w.freeze()==frozen
	var post: Rect2=Rect2(44,73,1,1)
	checks.restore_soft_use_split=restored.s._dynamic_clear(restored.w,"walker",1,post,[],false,true) and not restored.s._dynamic_clear(restored.w,"walker",1,post)
	var moved: Dictionary=walk(restored,"walker",[49,73])
	var departed: Dictionary=walk(restored,"p",[54,88])
	checks.restore_actual_continuation=moved.arrived and moved.overlaps.is_empty() and departed.arrived and departed.overlaps.is_empty() and not restored.w.facts.adaptations.has("bed")
	observations.restore={"passage":moved,"release":departed}

func final_facing() -> void:
	var x: Dictionary=fixture();var s: HospitalSpace=x.s;var w: WorldState=x.w
	var found: bool=false;var measured: Dictionary={}
	# Calculation-only input selection from real content bodies. No actual
	# arrival is claimed by this geometry/permission assertion.
	for binding: Dictionary in content.catalog.treatment_bindings:
		var a: Dictionary=w.facts.actors.walker.duplicate(true)
		a.species_id=binding.species_id;a.body_binding_id=binding.id;a.facing=PI*0.5
		if s.clearance(a)>2:continue
		for ix: int in range(800,860):
			var goal: Vector2=Vector2(float(ix)/20.0,71)
			var current: Rect2=s._actor_rect(a,goal)
			var turned: Dictionary=a.duplicate();turned.facing=0.0
			var final: Rect2=s._actor_rect(turned,goal)
			if s.bed_destination_blocker(w,a.id,1,current).is_empty() or not s.bed_destination_blocker(w,a.id,1,final).is_empty():continue
			var m: Dictionary={"actor_id":a.id,"target_floor":1,"target_cell":[goal.x,goal.y],"cursor":0,"path":[{"kind":"floor","floor_id":1,"cell":[goal.x,goal.y-1]},{"kind":"floor","floor_id":1,"cell":[goal.x,goal.y]}]}
			var facts: Dictionary=w.freeze()
			checks.final_facing_not_current=s.movement._bed_goal_blocker(w,a,m).is_empty() and s.movement._bed_goal_regions(w,a,m)==[final] and w.freeze()==facts
			measured={"binding":binding.id,"goal":[goal.x,goal.y],"current_rect":str(current),"final_rect":str(final)};found=true;break
		if found:break
	checks.non_square_facing_witness=found
	observations.final_facing=measured

func run_cases(c: HospitalContent, selected: Array) -> Dictionary:
	content=c
	for name: String in selected:
		match name:
			"BED-PASS":passage()
			"BED-CLAIM":claims();late_goal()
			"BED-COLLISION":collision()
			"BED-EXPAND":expansion()
			"BED-RELEASE":release()
			"BED-GROUP":groups()
			"BED-LOCAL":local_rejoin();detour_rejoin()
			"BED-CANDIDATE":candidate_stops()
			"BED-RESTORE":restoration()
			"BED-FACING":final_facing()
			"BED-BLUEPRINT":
				var suite: RefCounted=load("res://tests/acceptance/space.gd").new();suite.content=content
				var result: Dictionary=suite._bed_blueprint_contract()
				checks.built_bed_blueprints=result.ok;observations.blueprints=result
			"BED-TRANSIT":
				var result: Dictionary=load("res://tests/acceptance/bed_transit.gd").new().run(content)
				checks.merge(result.checks);observations.transit=result.observations
			_:return {"ok":false,"error":"Unknown explicit case: "+name}
	var failed: Array=[];for key: String in checks:
		if not checks[key]:failed.append(key)
	return {"ok":failed.is_empty(),"checks":checks,"failed":failed,"observations":observations,"scope":"Explicit initial bedside inputs plus real production movement/reservation/release. Separate CLIN cases cover clinical arrival and service."}
