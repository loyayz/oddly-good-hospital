extends "res://tests/acceptance/ordinary_door_passage.gd"
func ids(rows: Array) -> Array:
	var result: Array=[]
	for row: Dictionary in rows:result.append(row.id)
	return result
func query_ids(content: HospitalContent, world: WorldState, actor: Dictionary, swept: Rect2, members: Array, warm: bool) -> Array:
	var fresh: HospitalSpace=HospitalSpace.new(content)
	if warm:fresh.movement_doors(world,actor,swept,members)
	return ids(fresh.movement_doors(world,actor,swept,members))
func run_reach(content: HospitalContent, output: String) -> Dictionary:
	suite.content=content
	var f: Dictionary=_setup(true)
	var sim: HospitalSimulation=f.sim
	var world: WorldState=sim.world
	var build: CommandResult=suite._command(sim,"build_room",suite._room("reach_second",[34,70],[8,8]))
	suite._add_actor(sim,"reach_big","S59",[56,84])
	suite._add_actor(sim,"reach_small","S49",[40,84])
	var actual: Dictionary=world.facts.actors.reach_big
	var small: Dictionary=world.facts.actors.reach_small
	var proxy: Dictionary=actual.duplicate(true)
	proxy._convoy_size=1
	var checks: Dictionary={"second_room_built":build.accepted,"larger_world_member":sim.space.clearance(actual)>sim.space.clearance(proxy),"proxy_same_id_different_dictionary":proxy.id==actual.id and not is_same(proxy,actual)}
	var before: Dictionary=world.freeze()
	var input_file: FileAccess=FileAccess.open(output+".input.bin",FileAccess.WRITE);input_file.store_var(before);input_file.close()
	var expected: Array=ids(world.facts.floors.overrides["1"].doors)
	checks.real_multiple_doors=expected.size()>=2
	var phases: Array=[]
	for phase: String in ["cold","warm"]:
		var space: HospitalSpace=HospitalSpace.new(content)
		if phase=="warm":space.movement_doors(world,actual,Rect2(0,0,96,96),[actual.id])
		var all: Rect2=Rect2(0,0,96,96)
		checks[phase+"_same_instance_order"]=query_ids(content,world,actual,all,[actual.id],phase=="warm")==expected
		checks[phase+"_empty_members_order"]=query_ids(content,world,actual,all,[],phase=="warm")==expected
		checks[phase+"_different_member_order"]=query_ids(content,world,small,all,[small.id,actual.id],phase=="warm")==expected
		checks[phase+"_proxy_order"]=query_ids(content,world,proxy,all,[actual.id],phase=="warm")==expected
		# Find a read-only query rectangle around a genuine indexed door where
		# the world member's larger reach is essential. No body is moved.
		var geometry: FloorStaticGeometry=space._navigation.floor_geometry(space,world,1)
		var found: bool=false
		var chosen: Rect2
		var door_id: String=str(f.door.id)
		for dx: int in range(-9,10):
			if found:break
			for dy: int in range(-9,10):
				var query: Rect2=Rect2(Vector2(float(f.door.cell[0])+dx,float(f.door.cell[1])+dy),Vector2(0.25,0.25))
				var narrow: Array=geometry.door_index.candidates(1,query.grow(float(space.clearance(proxy))+1.0))
				var broad: Array=geometry.door_index.candidates(1,query.grow(float(space.clearance(actual))+1.0))
				if not narrow.has(door_id) and broad.has(door_id):chosen=query;found=true;break
		checks[phase+"_actual_detection_boundary_exists"]=found
		if found:
			var proxy_only: Array=query_ids(content,world,proxy,chosen,[],phase=="warm")
			var with_real: Array=query_ids(content,world,proxy,chosen,[actual.id],phase=="warm")
			checks[phase+"_proxy_must_include_larger_real_member"]=not proxy_only.has(door_id) and with_real.has(door_id)
			var body_proxy: Dictionary=actual.duplicate(true)
			body_proxy._convoy_body={"width_m":0.8,"depth_m":0.8,"height_m":0.8}
			checks[phase+"_convoy_body_proxy_smaller"]=space.clearance(body_proxy)<space.clearance(actual)
			var body_only: Array=query_ids(content,world,body_proxy,chosen,[],phase=="warm")
			var body_member: Array=query_ids(content,world,body_proxy,chosen,[actual.id],phase=="warm")
			checks[phase+"_convoy_body_larger_real_member"]=not body_only.has(door_id) and body_member.has(door_id)
			var small_only: Array=query_ids(content,world,small,chosen,[small.id],phase=="warm")
			var mixed_forward: Array=query_ids(content,world,small,chosen,[small.id,actual.id],phase=="warm")
			var mixed_reverse: Array=query_ids(content,world,small,chosen,[actual.id,small.id],phase=="warm")
			checks[phase+"_member_maximum_not_first_only"]=not small_only.has(door_id) and mixed_forward.has(door_id) and mixed_forward==mixed_reverse
			phases.append({"phase":phase,"query":str(chosen),"target_door":door_id,"proxy_only":proxy_only,"with_real_member":with_real,"expected_all_door_order":expected})
		checks[phase+"_world_unchanged"]=world.freeze()==before
	var union: Dictionary=reservation_union(content)
	checks.live_reservation_union=union.ok
	var result: Dictionary={"reservation_union":union,"ok":checks.values().all(func(v:Variant)->bool:return v==true),"checks":checks,"phases":phases,"scope":"Candidate query boundaries only, not physical crossing; same-ID smaller proxy must not hide larger real member."}
	sim.dispose();return result

func reservation_union(content: HospitalContent) -> Dictionary:
	var f: Dictionary=_setup(false)
	var sim: HospitalSimulation=f.sim
	var world: WorldState=sim.world
	var door: Dictionary=f.door
	var pos: Vector2=Vector2(float(door.cell[0]),float(door.cell[1]))
	suite._add_actor(sim,"reach_owner","S01",[pos.x,pos.y+0.1])
	var actor: Dictionary=world.facts.actors.reach_owner
	var quote: Dictionary=sim.space.door_quote(world,actor,1,door)
	var motion: HospitalMovement.MotionResult=HospitalMovement.MotionResult.new()
	var acquired: bool=sim.space.movement._reserve_doors(world,actor,{"actor_id":actor.id,"members":[actor.id]},sim.space.body_rectangle(actor),[door],motion)
	var before: Dictionary=world.freeze()
	var checks: Dictionary={"production_acquired":acquired,"live_reservation":world.facts.adaptations.has(door.id),"expanded":int(quote.get("span",0))>int(door.span)}
	var expected: Array=ids(world.facts.floors.overrides["1"].doors)
	for phase: String in ["cold","warm"]:
		var space: HospitalSpace=HospitalSpace.new(content)
		var swept: Rect2=Rect2(0,0,96,96)
		if phase=="warm":space.movement_doors(world,actor,swept,[actor.id])
		var evidence_space: HospitalSpace=HospitalSpace.new(content)
		var geometry: FloorStaticGeometry=evidence_space._navigation.floor_geometry(evidence_space,world,1)
		var indexed: Array=geometry.door_index.candidates(1,swept.grow(float(evidence_space.clearance(actor))+1.0))
		var reserved: bool=false
		for region: Dictionary in evidence_space._reservation_regions(world,1,swept):
			if region.reservation.kind=="door" and region.reservation_id==door.id:reserved=true
		checks[phase+"_both_union_sources"]=indexed.has(door.id) and reserved
		var count_before: int=int(space.query_counts.door_candidates)
		var found: Array=ids(space.movement_doors(world,actor,swept,[actor.id]))
		checks[phase+"_order_and_dedup"]=found==expected and found.count(door.id)==1
		checks[phase+"_candidate_count"]=int(space.query_counts.door_candidates)-count_before==found.size()
		checks[phase+"_world_and_owner_unchanged"]=world.freeze()==before
	var result: Dictionary={"ok":checks.values().all(func(v:Variant)->bool:return v==true),"checks":checks,"quote":quote,"scope":"Production-acquired live door reservation union, ordering/dedup/count; physical release is covered by ordinary/convoy cases."}
	sim.dispose();return result
