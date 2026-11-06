extends SceneTree
const Before=preload("res://baseline.gd")
const After=preload("res://current.gd")
const World=preload("res://world.gd")
class SpaceInput:
	extends RefCounted
	var public_areas: RefCounted
	func changed(world): world.calls.append(["changed"])
	func exit_cell(_world,_actor): return [0,0]
	func at(world,id,_floor,_cell): return world.facts.actors[id].get("at_target",false)
	func sync_actor(world,id): world.calls.append(["sync",id])
	func request_move(world,id,floor,cell):
		world.calls.append(["move",id,floor,cell])
		world.facts.moves[id]={"floor":floor,"cell":cell}
class BeforeTrace:
	extends Before
	var lookups=0
	func _lookup(world: World, include_present: bool = true) -> Dictionary:
		lookups+=1
		return super._lookup(world,include_present)
class AfterTrace:
	extends After
	var lookups=0
	func _lookup(world: World, include_present: bool = true) -> Dictionary:
		lookups+=1
		return super._lookup(world,include_present)
func fixture(wards:int,visitors:int,pending:bool)->RefCounted:
	var w=World.new()
	w.facts={"ward_stays":{},"attempts":{},"visitors":{"stays":{}},"actors":{},"visits":{},"moves":{}}
	for i in wards:
		var id=str(i)
		w.facts.ward_stays[id]={"attempt_id":id,"phase":"recovery","bed_id":id}
		w.facts.attempts[id]={"visit_id":id}
	for i in visitors:
		var id=str(i)
		w.facts.actors[id]={"id":id}
		w.facts.visits[id]={"id":id,"phase":"waiting","visitor_consent":true,"visitor_windows":{"0:0":{"started":false}}}
		w.facts.visitors.stays[id]={"id":id,"visit_id":id,"actor_id":id,"phase":"waiting","purpose":"companion","pending_window":"0:0" if pending else "","public_use":{"phase":"local_wait"},"remaining_ticks":0,"waiting_floor":1,"waiting_cell":[0,0],"bedside_floor":1,"bedside_cell":[0,0]}
	return w
func configure(o,sp):
	o.space=sp
	o.content={"balance":{"schedule":{"shift_seconds":600},"hospital_situations":{"ward_visit_seconds":60}}}
func _initialize():
	var b=Before.new();var a=After.new();var sp=SpaceInput.new();sp.public_areas=sp
	for o in [b,a]:configure(o,sp)
	var checks=0
	for wards in [0,1,32,160]:
		for visitors in [0,1,8,32]:
			for pending in [false,true]:
				var x=fixture(wards,visitors,pending);var y=fixture(wards,visitors,pending)
				b._dispatch_waiting(x);a._dispatch_waiting(y)
				assert(x.facts==y.facts and x.calls==y.calls);checks+=1
	for phase in ["waiting","to_waiting","yielding","to_bed","visiting","leaving"]:
		for window in ["","0:0","old"]:
			for consent in [false,true]:
				for ready in [false,true]:
					for departed in [false,true]:
						var x=fixture(2,2,false);var y=fixture(2,2,false)
						for w in [x,y]:
							for id in ["0","1"]:
								var s=w.facts.visitors.stays[id]
								s.phase=phase;s.pending_window=window;s.ready=ready
								w.facts.visits[id].visitor_consent=consent
								w.facts.visits[id].phase="departed" if departed else "waiting"
								w.facts.actors[id].at_target=ready
								w.facts.ward_stays[id].bedside={"cell":[1,2],"floor_id":1} if ready else {}
						b._dispatch_waiting(x);a._dispatch_waiting(y)
						assert(x.facts==y.facts and x.calls==y.calls);checks+=1
	# Independently require no ward lookup for public waiting, exactly one
	# for multiple eligible visits, and the first ward per visit to win.
	var trace=AfterTrace.new();configure(trace,sp)
	var w=fixture(160,8,false);trace._dispatch_waiting(w);assert(trace.lookups==0);checks+=1
	w=fixture(3,3,true);trace._dispatch_waiting(w);assert(trace.lookups==1);checks+=1
	w=fixture(2,1,true);w.facts.attempts["1"].visit_id="0"
	w.facts.ward_stays["0"].bedside={"cell":[3,4],"floor_id":1}
	trace._dispatch_waiting(w)
	assert(w.facts.visitors.stays["0"].bed_id=="0")
	assert(w.facts.visitors.stays["0"].phase=="to_bed")
	assert(w.facts.moves["0"].cell==[3,4]);checks+=3
	# A later dispatch must rebuild rather than retain a previous mapping.
	w.facts.visitors.stays["0"].phase="waiting"
	w.facts.ward_stays.erase("0");w.facts.ward_stays["1"].bedside={"cell":[7,8],"floor_id":1}
	trace._dispatch_waiting(w)
	assert(w.facts.visitors.stays["0"].bed_id=="1")
	assert(w.facts.moves["0"].cell==[7,8]);checks+=2
	var windows=[]
	for wards in [0,32,160]:
		for pending in [false,true]:
			for c in 3:
				for old in [true,false,false,true]:
					var o=b if old else a;var input=fixture(wards,8,pending)
					for warm in 10:o._dispatch_waiting(input)
					input.calls.clear()
					var t=Time.get_ticks_usec()
					for i in 1000:
						o._dispatch_waiting(input)
						input.calls.clear()
					windows.append({"wards":wards,"pending":pending,"old":old,"us":Time.get_ticks_usec()-t})
	print(JSON.stringify({"checks":checks,"calls_per_window":1000,"windows":windows,"scope":"actual dispatch/ward lookup; explicit bedside, public waiting and movement action adapters; no complete visit integration claim"}))
	sp.public_areas=null
	quit()
