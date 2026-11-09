extends RefCounted
class Observe extends HospitalMovement:
	var chosen:bool=false
	func _local_choose(_w:WorldState,_a:Dictionary,_m:Dictionary,_v:Vector2)->bool:
		chosen=true
		return false
func run(content:HospitalContent)->Dictionary:
	var suite:RefCounted=load("res://tests/acceptance/space.gd").new();suite.content=content
	var rows:Array=[]
	for mode:String in ["same_floor","cross_floor_completed","cross_floor_rejoin"]:
		var sim:HospitalSimulation=suite._fixture()
		suite._add_actor(sim,"a","S49",[40,70]);suite._add_actor(sim,"b","S49",[40.6,70])
		sim.space.request_move(sim.world,"a",1,[45,70]);sim.space.request_move(sim.world,"b",1,[46,70])
		var a:Dictionary=sim.world.facts.moves.a;var b:Dictionary=sim.world.facts.moves.b
		# Authored completed-local boundary, not a simulated arrival claim.
		a.route_pending=false;a.cursor=0;a.path=[{"kind":"floor","floor_id":1,"cell":[45,70]}]
		b.route_pending=false;b.cursor=0;b.path=[{"kind":"floor","floor_id":1,"cell":[46,70]}]
		b.local_move={"origin":[40.6,69],"target":{"kind":"floor","floor_id":1,"cell":[40.6,70]}}
		if mode!="same_floor":b.target_floor=2
		if mode=="cross_floor_rejoin":b.local_move.rejoin={"index":0,"cell":[46,70]}
		var observer:HospitalMovement=Observe.new(sim.space)
		var contact:HospitalMovement.MotionResult=observer._move_step(sim.world,sim.world.facts.actors.a,a,a.path[0])
		observer._local_collision(sim.world,sim.world.facts.actors.a,a,contact)
		var expected:bool=false
		rows.append({"case":mode,"ok":contact.blocked and "b" in contact.blocker_actor_ids and observer.chosen==expected,"actual_contact":contact.blocker_actor_ids,"new_bypass_attempted":observer.chosen})
		sim.dispose()
	return {"ok":rows.all(func(r:Dictionary)->bool:return r.ok),"cases":rows,"scope":"Real next-step contact at authored completed-local boundary; selector observation only, not full journey."}
