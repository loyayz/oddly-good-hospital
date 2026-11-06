extends SceneTree
const Waiting = preload("res://waiting.gd")
const Areas = preload("res://areas.gd")
const World = preload("res://world.gd")
const Departments = preload("res://departments.gd")
var checks: Array = []
func check(name: String, ok: bool) -> void:
	checks.append({"name":name,"passed":ok})
func intent(phase: String = "local_wait") -> Dictionary:
	return {"id":"seat_visit","actor_id":"patient","ticket_id":"ticket","area":{"room_id":"area"},"mode":"auto","phase":phase,"facility_id":"","arrived_tick":50,"public_purpose":"seat"}
func visit() -> Dictionary:
	return {"id":"visit","actor_id":"patient","ticket_id":"ticket","anger":50.0,"personality_id":"fixture"}
func fixture() -> Dictionary:
	var w = World.new()
	var l = Waiting.new()
	var i = intent()
	w.facts.waiting_life.seats.visit = i
	return {"w":w,"l":l,"i":i,"v":visit()}
func _initialize() -> void:
	var areas = Areas.new()
	areas.queue = [{"intent":{"id":"older","actor_id":"older","arrived_tick":1,"public_purpose":"seat","ticket_id":"older"}}]
	var w = World.new()
	var i = intent()
	check("old area arrival cannot block waiting chair",areas.turn(w,i,"chair") and areas.queries==0)
	i.public_purpose = "toilet"
	check("service FIFO remains",not areas.turn(w,i,"toilet") and areas.queries==1)
	var x = fixture()
	check("no remote claim",not x.l._claim_seat(x.w,x.v,x.i,"chair") and x.l.space.reserves==0)
	x.w.facts.actors.patient.location.cell = [2,2]
	x.w.facts.moves.patient = {}
	check("unfinished move cannot claim",not x.l._claim_seat(x.w,x.v,x.i,"chair") and x.l.space.reserves==0)
	x.w.facts.moves.clear()
	x.l.space.reserve_result = "body blocked"
	check("failed real reservation does not seat",not x.l._claim_seat(x.w,x.v,x.i,"chair") and x.i.phase=="local_wait")
	x.l.space.reserve_result = ""
	check("actual arrival claims empty chair",x.l._claim_seat(x.w,x.v,x.i,"chair") and Waiting.is_seated(x.w,"visit") and x.w.owner=="patient")
	x.w.owner = "other"
	check("actual occupant remains exclusive",not x.l._claim_seat(x.w,x.v,x.i,"chair"))
	x = fixture()
	x.l._dispatch_public_seat(x.w,x.v,x.i)
	check("failed search waits between five-second scans",x.l.searches==0 and x.l.safe_waits==1)
	x.w.sim_tick = 100
	x.l._dispatch_public_seat(x.w,x.v,x.i)
	check("failed search retries on existing scan",x.l.searches==1 and x.i.phase=="local_wait")
	x.w.sim_tick = 101
	x.i.phase = "area_travel"
	x.l._dispatch_public_seat(x.w,x.v,x.i)
	check("new actual area arrival searches immediately",x.l.searches==2)
	x.i.phase = "local_wait"
	x.i.arrived_tick = -1
	x.l._dispatch_public_seat(x.w,x.v,x.i)
	check("arrival after area reselection also searches immediately",x.l.searches==3)
	x = fixture()
	x.i.phase = "area_travel"
	x.l.candidates = [{"facility_id":"chair","floor_id":1,"patient_cell":[2,2]}]
	x.l.space.move_result = "blocked"
	x.l._dispatch_public_seat(x.w,x.v,x.i)
	check("failed departure returns to optional standing wait",x.i.phase=="local_wait" and x.i.facility_id=="" and x.l.space.requests==1)
	x.l._dispatch_public_seat(x.w,x.v,x.i)
	check("failed departure does not retry every tick",x.l.searches==1 and x.l.space.requests==1)
	x = fixture()
	x.i.phase = "local_travel"
	x.i.facility_id = "chair"
	x.w.facts.actors.patient.location.cell = [2,2]
	x.l._dispatch_public_seat(x.w,x.v,x.i)
	check("real target arrival claims without rescoring",Waiting.is_seated(x.w,"visit") and x.l.searches==0)
	x = fixture()
	var d = Departments.new()
	var observation = {"value":50.0,"clean":true,"noise":0.0}
	var data = {"anger_sources":{},"cause_clocks":{}}
	d._update_cause_clocks(x.w,x.v,data,observation)
	check("standing intent does not suppress no-seat clock",data.cause_clocks.get("no_compatible_seat",-1)==51)
	data.cause_clocks.no_compatible_seat = 0
	x.w.sim_tick = 149
	d._sample_anger(x.w,x.v,data,observation)
	check("no-seat grace excludes 14.9 seconds",float(data.anger_sources.get("no_compatible_seat",0.0))==0.0)
	x.w.sim_tick = 150
	d._sample_anger(x.w,x.v,data,observation)
	check("no-seat reaction starts at existing 15-second boundary",is_equal_approx(float(data.anger_sources.get("no_compatible_seat",0.0)),0.6))
	x.w.facts.actors.patient.location.cell = [2,2]
	x.l._claim_seat(x.w,x.v,x.i,"chair")
	d._update_cause_clocks(x.w,x.v,data,observation)
	check("actual sitting clears no-seat clock",not data.cause_clocks.has("no_compatible_seat"))
	x.w.facts.actors.patient.posture = "standing"
	check("stale seated intent cannot grant chair effect",not Waiting.is_seated(x.w,"visit"))
	x.w.facts.tickets.ticket.pause_reasons.need_service = "toilet"
	x.w.facts.waiting_life.needs.visit = {"purpose":"toilet","phase":"using"}
	x.w.facts.waiting_life.seats.clear()
	data = {"anger_sources":{},"cause_clocks":{"no_compatible_seat":0}}
	d._update_cause_clocks(x.w,x.v,data,observation)
	d._sample_anger(x.w,x.v,data,observation)
	check("life-service absence does not add no-seat reaction",not data.cause_clocks.has("no_compatible_seat") and not data.anger_sources.has("no_compatible_seat"))
	var failed = checks.filter(func(row): return not row.passed).size()
	print(JSON.stringify({"checks":checks,"failed":failed}))
	quit(0 if failed==0 else 1)
