extends RefCounted
func run(content: HospitalContent) -> Dictionary:
	var suite: RefCounted=load("res://tests/acceptance/space.gd").new();suite.content=content
	var sim: HospitalSimulation=suite._fixture()
	suite._add_actor(sim,"walker","S49",[35,70]);suite._add_actor(sim,"owner","S49",[50,85])
	HospitalFactory._add_facility(sim.world,{"id":"composition_facility","definition_id":"M37","anchor":[44,76],"size":content.facility_definition("M37").footprint.duplicate(),"room_id":null},content)
	var reason: String=sim.space.reserve_facility(sim.world,"composition_facility","owner","owner")
	if not reason.is_empty():sim.dispose();return {"passed":false,"reason":reason}
	var raw: Array=sim.world.facts.adaptations.composition_facility.regions[0]
	var box: Rect2=Rect2(float(raw[0]),float(raw[1]),float(raw[2]),float(raw[3]))
	sim.space._ensure_actor_index(sim.world);sim.space._actor_index.clear()
	# Explicit collision-kernel inputs, not fabricated completed travel.
	sim.space._actor_index.update("alpha",1,box);sim.space._actor_index.update("beta",1,box)
	var sweep: BodyIndex.Record=BodyIndex.Record.new();sweep.sweep_from=box;sweep.sweep_to=box
	var sweeps: Array[BodyIndex.Record]=[sweep]
	var queries: Dictionary={"regions":{}}
	var first: HospitalMovement.MotionResult=HospitalMovement.MotionResult.new();first.first_contact_only=true
	var full: HospitalMovement.MotionResult=HospitalMovement.MotionResult.new()
	var uncached: HospitalMovement.MotionResult=HospitalMovement.MotionResult.new()
	var before: Dictionary=sim.world.freeze()
	sim.space.movement._movement_contacts(sim.world,"walker",1,box,sweeps,["walker"],first,queries)
	sim.space.movement._movement_contacts(sim.world,"walker",1,box,sweeps,["walker"],full,queries)
	sim.space.movement._movement_contacts(sim.world,"walker",1,box,sweeps,["walker"],uncached)
	var checks: Dictionary={"first_true_witness":first.blocked and first.blocker_actor_ids==["alpha"] and first.reservation_ids.is_empty(),"cache_not_truncated":full.blocker_actor_ids==["alpha","beta"] and full.reservation_ids==["composition_facility"],"full_same_uncached":full.blocked==uncached.blocked and full.blocker_actor_ids==uncached.blocker_actor_ids and full.reservation_ids==uncached.reservation_ids,"mode_default_and_owner":not full.first_contact_only and HospitalMovement.ReturnContactScratch.new().result.first_contact_only,"readonly":before==sim.world.freeze()}
	# Synthetic full cache occupancy: entries are deliberately outside this query.
	# Exercise insertion 4096, attempted insertion 4097, and overfull input fallback.
	for initial: int in [4095,4096,4097]:
		for permitted: bool in [false,true]:
			var capped: Dictionary={"regions":{}}
			for index: int in initial:
				capped.regions[Rect2(-10000-index*4,-10000,2,2)]={"bounds":Rect2(-10000-index*4,-10000,2,2),"actors":[],"accepted":[],"reservations":[]}
			var id: String="owner" if permitted else "walker"
			var result: HospitalMovement.MotionResult=HospitalMovement.MotionResult.new()
			var reference: HospitalMovement.MotionResult=HospitalMovement.MotionResult.new()
			sim.space.movement._movement_contacts(sim.world,id,1,box,sweeps,[id],result,capped)
			sim.space.movement._movement_contacts(sim.world,id,1,box,sweeps,[id],reference)
			checks["cap_%d_permission_%s"%[initial,permitted]]=result.blocker_actor_ids==reference.blocker_actor_ids and result.reservation_ids==reference.reservation_ids and result.blocked==reference.blocked and capped.regions.size()==maxi(initial,4096)
			if initial==4095:
				var retained: Dictionary=capped.last
				var hit: Dictionary=sim.space.movement._return_contact_region(sim.world,id,1,box,[id],capped)
				checks["last_hit_at_cap_%s"%permitted]=is_same(retained,hit)
				capped.erase("last")
				hit=sim.space.movement._return_contact_region(sim.world,id,1,box,[id],capped)
				checks["existing_region_at_cap_%s"%permitted]=is_same(retained,hit)
	checks.readonly_after_cap=before==sim.world.freeze()
	var ok: bool=true
	for value: bool in checks.values():ok=ok and value
	sim.dispose();return {"passed":ok,"checks":checks}
