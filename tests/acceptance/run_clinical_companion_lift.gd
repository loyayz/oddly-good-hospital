extends SceneTree

class LiftFamily extends "res://tests/acceptance/inpatient_family.gd":
	var output: String
	var declarations: Array=[]

	func _upstairs_input(t) -> Dictionary:
		# Generate the ordinary legitimate admitted state, then declare a separate
		# built-hospital initial condition BEFORE any independent visitor is drawn.
		var source: Dictionary=await _source(t)
		if source.is_empty(): return {}
		var c: Dictionary=_copy_facts(source.facts,source.visit_id)
		_exact_input(c.world,"arrival",0)
		_tick(c)
		if not _stay(c).has("admitted_tick"): return _failed_input(c,"admission","ordinary legal fixture failed")
		var closed: CommandResult=_command(c,"build_room_open",{"target_id":"clin_or","open_intent":false})
		if not closed.accepted: return _failed_input(c,"hold_surgery",closed.reason)
		if not _role(c,"ward_visit").is_empty() or _stay(c).get("visitor_day",-1)==c.world.sim_tick/WorldState.TICKS_PER_DAY:
			return _failed_input(c,"pre_daily_draw","visitor already drawn; no redraw permitted")
		_save("declared-input-before",c.world.freeze())
		var world:=WorldState.new(c.world.freeze().duplicate(true))
		var room: Dictionary=world.facts.rooms.clin_ward
		var old_room: Dictionary=room.duplicate(true)
		old_room.id="clin_ward_empty_ground"
		world.facts.rooms[old_room.id]=old_room
		room.floor_id=2
		var doors: Array=[]
		for door: Dictionary in world.facts.floors.overrides["1"].doors:
			if door.room_id!="clin_ward":continue
			var upper: Dictionary=door.duplicate(true)
			upper.id=str(door.id)+"_upper"
			doors.append(upper)
			door.room_id=old_room.id
		world.facts.floors.height_intervals=[{"first":1,"last":2,"height_m":float(_content.balance.floors.clear_height_m)}]
		world.facts.floors.completed_top_floor={HospitalSpace.plot_key([1,2]):2}
		world.facts.floors.overrides["2"]={"plots":[[1,2]],"blocked":[],"wall_edges":BuildGeometry.room_walls(room).duplicate(true),"doors":doors,"paths":[]}
		world.facts.connectors["clin_lift"]={"id":"clin_lift","definition_id":"VC03","first_floor":1,"last_floor":2,"cell":[56,65],"footprint":[7,7],"rotation":0,"anchor":[56,72],"repair_cell":[63,65],"floor_id":1,"phase":"idle","riders":[],"remaining_ticks":0,"condition":100.0,"failed":false,"pending_failure":false,"use_receipts":{},"paid_cost":3200,"used":false}
		var actors: Array=[]
		for actor: Dictionary in world.facts.actors.values():
			if actor.location.kind!="floor" or int(actor.location.floor_id)!=1:continue
			if not c.sim.space.room_contains(old_room,c.sim.space.body_rectangle(actor)):continue
			if not world.facts.moves.get(actor.id,{}).is_empty():
				return _failed_input(c,"declared_input","ward occupant still moving: "+str(actor.id))
			actor.location.floor_id=2
			actors.append(actor.id)
		for facility: Dictionary in world.facts.facilities.values():
			if facility.get("room_id","")=="clin_ward":facility.floor_id=2
		declarations.append({"scope":"Independent initial admitted upstairs ward, not runtime teleport or original dense workload","preserved":"ward/bed IDs, occupancy, claims, treatment facts and RNG; empty former ward remains downstairs","changed":"added upper floor/lift; ward facilities and initial occupants on 2F","initial_occupants":actors})
		if not str(_visit(c).actor_id) in actors:
			return _failed_input(c,"declared_input_patient","initial admitted patient was not carried with the declared upstairs ward")
		var error: String=world.validate(_content)
		_save("declared-input-after",world.freeze())
		if not error.is_empty():return _failed_input(c,"declared_input_validation",error)
		c=_copy_facts(world.freeze(),c.visit_id)
		_exact_input(c.world,"arrival",9999)
		return c

	func _exact_input(world: WorldState, stream: String, value: int) -> void:
		var before: Dictionary=world.facts.rng[stream].duplicate(true)
		super._exact_input(world,stream,value)
		declarations.append({"tick":world.sim_tick,"stream":stream,"requested_draw":value,"before":before,"after":world.facts.rng[stream].duplicate(true),"scope":"Declared independent functional boundary, not mixed160 input or probability change"})

	func _save(label: String, facts: Dictionary) -> void:
		var path: String=output.path_join(label+".bin")
		assert(not FileAccess.file_exists(path))
		var file: FileAccess=FileAccess.open(path,FileAccess.WRITE)
		file.store_var(facts,false);file.close()

	func run_lift(t, content: HospitalContent, directory: String) -> Dictionary:
		_content=content;output=directory
		var file: FileAccess=FileAccess.open("/workspace/scratch/6962cc21ddf3/clinical-lift-r1/clinical-start.bin",FileAccess.READ)
		var initial: Dictionary=file.get_var(false);file.close()
		initial.floors.overrides["1"].plots.append([2,2])
		initial.floors.completed_top_floor[HospitalSpace.plot_key([2,2])]=2
		initial.floors.overrides["2"].plots.append([2,2])
		var c: Dictionary=_copy_facts(initial,"visit_00000006")
		declarations.append({"initial_hospital_extension":"declare completed adjacent ground and 2F plot [2,2]; no actor/body/move changes","scope":"independent clinical coverage, not mixed160 performance"})
		if c.is_empty():return {"ok":false,"failures":_case_failures}
		var built:CommandResult=_command(c,"connector_build",{"definition_id":"VC03","floor_id":1,"cell":[68,68],"rotation":0})
		if not built.accepted:return {"ok":false,"built":built.to_record()}
		var lift_id:String=str(built.changed_ids[0])
		var extended:CommandResult=_command(c,"connector_extend",{"connection_id":lift_id,"floor_id":2})
		if not extended.accepted:return {"ok":false,"extended":extended.to_record()}
		var removed:CommandResult=_command(c,"connector_remove",{"connection_id":"clin_lift"})
		if not removed.accepted:return {"ok":false,"removed":removed.to_record()}
		declarations.append({"independent_fixture":"actual connector_remove/build/extend commands before this case runs","old_nursing_egress":"blocked by staff_bed_a in former fixture","new_connection":c.world.facts.connectors[lift_id].duplicate(true),"not_comparable_to_original_mixed_load":true})
		var reopened:CommandResult=_command(c,"build_room_open",{"target_id":"clin_or","open_intent":true})
		_save("clinical-start",c.world.freeze())
		var trace:Array=[];var saw_convoy:bool=false;var saw_joint:bool=false;var landed:bool=false;var joint_convoy:bool=false;var returned:bool=false;var error:String=c.world.validate(_content)
		for index:int in 6000:
			if not error.is_empty():break
			_tick(c)
			var companion:Dictionary=_role(c,"companion")
			var patient:String=str(_visit(c).actor_id)
			for m:Dictionary in c.world.facts.moves.values():
				if m.has("convoy") and patient in m.members:saw_convoy=true
			var lift:Dictionary=c.world.facts.connectors[lift_id]
			for g:Dictionary in lift.get("passenger_groups",[]):
				if patient in g.members and companion.get("actor_id","") in g.members:
					saw_joint=true
					for owner: String in g.leader_ids:
						if c.world.facts.moves.get(owner,{}).has("convoy"):joint_convoy=true
					if not FileAccess.file_exists(output.path_join("joint.bin")):_save("joint",c.world.freeze())
			if saw_joint and c.world.facts.actors[patient].location.kind=="floor" and int(c.world.facts.actors[patient].location.floor_id)==1:landed=true
			if joint_convoy and c.world.facts.actors[patient].location.kind=="floor" and int(c.world.facts.actors[patient].location.floor_id)==2:returned=true
			if index%25==0 or returned:trace.append({"tick":c.world.sim_tick,"ward":_stay(c).duplicate(true),"companion":companion.duplicate(true),"lift":lift.duplicate(true),"moves":c.world.facts.moves.duplicate(true)})
			error=c.world.validate(_content)
			if returned:break
			if index%100==99:
				print("CLINICAL_LIFT_PROGRESS ",c.world.sim_tick," ",_stay(c).get("phase",""))
				await t.process_frame
		_save("clinical-final",c.world.freeze())
		FileAccess.open(output.path_join("clinical-trace.json"),FileAccess.WRITE).store_string(JSON.stringify(trace))
		var result:Dictionary={"ok":reopened.accepted and saw_convoy and saw_joint and joint_convoy and returned and error.is_empty(),"convoy":saw_convoy,"joint":saw_joint,"landed":landed,"joint_convoy":joint_convoy,"returned":returned,"error":error,"tick":c.world.sim_tick,"declarations":declarations,"fixture_errors":c.errors}
		_dispose_simulations();return result

func _initialize() -> void:call_deferred("_run")
func preparation_elapsed(_started: int) -> void:pass
func _run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=1 or FileAccess.file_exists(args[0]):quit(2);return
	var directory: String=args[0].get_base_dir()
	DirAccess.make_dir_recursive_absolute(directory)
	var started: int=Time.get_ticks_usec()
	var result: Dictionary=await LiftFamily.new().run_lift(self,HospitalContent.new(),directory)
	result.elapsed_us=Time.get_ticks_usec()-started
	FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print(JSON.stringify(result));quit(0 if result.ok else 1)
