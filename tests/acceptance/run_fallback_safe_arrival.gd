extends "res://tests/acceptance/run_floor_wait_order.gd"

class SafetyFlow extends CurrentBoundary:
	func run_safe(directory: String) -> Dictionary:
		var rows: Array=[]
		for foreign: bool in [false,true]:
			var x: Dictionary=_areas()
			_facility(x,"toilet","FUR07",[39,68],"west")
			var visit: Dictionary=_visit(x,"safe_waypoint",[37,78])
			var actor: Dictionary=x.world.facts.actors[visit.actor_id]
			var blocker: Dictionary=actor.duplicate(true)
			blocker.id="waypoint_blocker";blocker.name="waypoint_blocker";blocker.location.cell=[42,90]
			x.world.facts.actors[blocker.id]=blocker;x.space.sync_actor(x.world,blocker.id);x.world.touch(false)
			x.l._begin_need(x.world,visit)
			var need: Dictionary=x.world.facts.waiting_life.needs[visit.id]
			var start: int=need.started_tick
			var ticket_id: String=visit.ticket_id
			var ticket_before: Dictionary=x.world.facts.tickets[ticket_id].duplicate(true)
			var anger: float=visit.anger
			x.world.facts.sim_tick=start+451
			x.l._dispatch_need(x.world,visit,need)
			var pending: bool=need.phase=="fallback_travel" and need.remaining_ticks==0
			var reason: String=x.l._request_need_move(x.world,need,actor.id,1,[42,90])
			if foreign:x.world.facts.moves[actor.id].waiting_need_id="another_task"
			var initial: String=x.world.validate(_content)
			var f:=FileAccess.open(directory+("/foreign" if foreign else "/owned")+"-preWorld.bin",FileAccess.WRITE)
			f.store_var(x.world.freeze(),false);f.close()
			var steps: int=0
			var zero_before: bool=true
			var restored: bool=false
			var reached: bool=false
			var shared_rejected: bool=false
			var owner_result: bool=false
			var saved_need_id: String=need.id
			for i: int in 100:
				x.world.facts.sim_tick+=1
				var safe: bool=x.space.public_areas.safe_wait(x.world,actor.id,1,actor.location.cell)
				if safe:
					reached=steps>0 and actor.location.cell!=[42,90] and x.space.public_areas.current_area(x.world,actor.id).is_empty()
					var frozen: Dictionary=x.world.freeze()
					shared_rejected=not x.space.public_areas.try_finish_arrival(x.world,actor.id,{},"waiting_need_id",need.id) and x.world.freeze()==frozen
					x.l._dispatch_need(x.world,visit,need)
					owner_result=(need.phase=="fallback_travel" and need.remaining_ticks==0 and x.world.freeze()==frozen) if foreign else (need.phase=="fallback" and need.remaining_ticks==80 and not x.world.facts.moves.has(actor.id))
					break
				x.l._dispatch_need(x.world,visit,need)
				zero_before=zero_before and need.phase=="fallback_travel" and need.remaining_ticks==0 and visit.anger==anger and need.started_tick==start
				x.space.advance(x.world);x.world.touch(false);steps+=1
				if steps==5:
					var snapshot: Dictionary=x.world.freeze()
					var save:=FileAccess.open(directory+("/foreign" if foreign else "/owned")+"-inflight.bin",FileAccess.WRITE);save.store_var(snapshot,false);save.close()
					x=_restore(x);visit=x.world.facts.visits[visit.id];need=x.world.facts.waiting_life.needs[visit.id];actor=x.world.facts.actors[visit.actor_id]
					restored=x.world.freeze()==snapshot and need.started_tick==start and need.id==saved_need_id
			var ticket_at_arrival: bool=x.world.facts.tickets[ticket_id]==ticket_before
			var at_arrival: Array=actor.location.cell.duplicate()
			var eighty: bool=foreign
			if not foreign and owner_result:
				_tick_waiting(x,79)
				var before_last: bool=need.phase=="fallback" and need.remaining_ticks==1 and visit.anger==anger
				_tick_waiting(x)
				eighty=before_last and need.phase=="returning" and is_equal_approx(float(visit.anger),anger+float(_content.balance.amenity_flow.fallback_anger))
			var ticket_after: Dictionary=x.world.facts.tickets[ticket_id].duplicate(true)
			var ticket_changes: Array=[]
			for key: String in ticket_before:
				if ticket_before[key]!=ticket_after.get(key):ticket_changes.append(key)
			var expected_pause: Dictionary=ticket_before.pause_reasons.duplicate(true)
			if not foreign:expected_pause.erase("need_service")
			var pause_exact: bool=ticket_after.pause_reasons==expected_pause
			ticket_before.erase("pause_reasons");ticket_after.erase("pause_reasons")
			var checks: Dictionary={"legal_preWorld":initial.is_empty(),"real_pending_owned_request":pending and reason.is_empty(),"no_early_work":zero_before,"safe_midway_without_area":reached,"shared_area_contract_unchanged":shared_rejected,"owner_correct":owner_result,"restored_exactly":restored,"real_80_ticks":eighty,"original_need_clock_ticket":need.started_tick==start and need.id==saved_need_id and visit.ticket_id==ticket_id and ticket_at_arrival and ticket_after==ticket_before,"only_own_pause_released":pause_exact,"valid_final":x.world.validate(_content).is_empty()}
			rows.append({"foreign":foreign,"ok":checks.values().all(func(v:Variant)->bool:return v==true),"checks":checks,"steps":steps,"arrival":at_arrival,"phase":need.phase,"remaining_ticks":need.remaining_ticks,"validation":initial,"completion_ticket_changed_fields":ticket_changes})
			x.a.dispose()
		return {"ok":rows.all(func(row:Dictionary)->bool:return row.ok),"rows":rows}

class SupportGuard extends "res://tests/acceptance/arrival_entry_ownership_edges.gd":
	var observations: Array=[]
	var output_dir: String
	func _edge_tick(x: Dictionary, ids: Array) -> String:
		for actor_id: String in ids:
			var movement: Dictionary=x.world.facts.moves.get(actor_id,{})
			if movement.is_empty():continue
			var actor: Dictionary=x.world.facts.actors[actor_id]
			var cursor: int=int(movement.cursor)
			var support: bool=cursor>=0 and cursor<movement.path.size() and movement.path[cursor].kind=="support_exit"
			if actor.get("posture","")!="lying" and not support:continue
			# Direct helper permission probe, not a fabricated life-service flow.
			# The real support journey is unchanged except this saved ownership tag.
			var had: bool=movement.has("waiting_need_id")
			var old: Variant=movement.get("waiting_need_id")
			movement.waiting_need_id="guard-probe"
			var validation: String=x.world.validate(_content)
			var before: Dictionary=x.world.freeze()
			var denied: bool=not x.l._try_finish_fallback_travel(x.world,actor_id,"guard-probe")
			if observations.is_empty():
				var f:=FileAccess.open(output_dir+"/support-preWorld.bin",FileAccess.WRITE);f.store_var(before,false);f.close()
			observations.append({"lying":actor.posture=="lying","support_exit":support,"denied":denied,"unchanged":before==x.world.freeze(),"validation":validation})
			if had:movement.waiting_need_id=old
			else:movement.erase("waiting_need_id")
		return super._edge_tick(x,ids)

	func support_guard_journey() -> Dictionary:
		var x: Dictionary=_fixture({"sleeper":"nurse"})
		var room: String=_room(x)
		_facility(x,"bed","SE04",[43,75],room)
		_position(x,"sleeper",[43,80])
		var actor: Dictionary=x.world.facts.actors.sleeper
		var staff: Dictionary=x.world.facts.staff.sleeper
		staff.awake_ticks=13500;staff.energy=50.0;staff.stress_milli=50000
		var initial: String=x.world.validate(_content)
		var reached: bool=false
		var errors: Array=[]
		var steps: int=0
		for tick: int in 100:
			x.w.dispatch(x.world)
			var sleeping: bool=staff.life_task.phase=="sleep"
			var previous: Dictionary={actor.id:actor.location.duplicate(true)}
			var error: String=_edge_tick(x,[actor.id]);steps+=1
			x.w.advance(x.world,{},previous)
			if not error.is_empty():errors.append(error);break
			if sleeping:reached=true;break
		var was_lying: bool=actor.posture=="lying" and actor.get("support_facility_id","")=="bed"
		var interrupted: CommandResult=x.w.execute(x.world,"interrupt_staff_rest",{"staff_id":actor.id,"reason":"remodel"})
		var departure: Dictionary=_edge_drive(x,actor.id,[43,80])
		var ok: bool=initial.is_empty() and reached and was_lying and errors.is_empty() and interrupted.accepted and departure.support_seen and _edge_journey_ok(departure) and actor.posture=="standing" and not actor.has("support_facility_id") and x.world.validate(_content).is_empty()
		x.a.dispose()
		return {"ok":ok,"initial_validation":initial,"sleep_steps":steps,"actual_lying":was_lying,"errors":errors,"departure":departure}

func _guard_cases(directory: String) -> Array:
	var support:=SupportGuard.new();support._content=content;support.output_dir=directory
	var support_result: Dictionary=support.support_guard_journey()
	check("REAL-SUPPORT-GUARD",support_result.ok and not support.observations.is_empty() and support.observations.any(func(row:Dictionary)->bool:return row.support_exit) and support.observations.all(func(row:Dictionary)->bool:return row.denied and row.unchanged and row.validation.is_empty()),{"journey":support_result,"probes":support.observations})
	var suite=preload("res://tests/acceptance/space.gd").new();suite.content=content
	var sim: HospitalSimulation=suite._fixture()
	suite._add_actor(sim,"leader","S49",[54,80]);suite._add_actor(sim,"follower","S49",[52,80])
	var form: Dictionary=ConvoyTrail.formation(sim.space,sim.world,"leader",["leader","follower"],Vector2.RIGHT)
	for id: String in ["leader","follower"]:
		sim.world.facts.actors[id].location.cell=form.targets[id];sim.space.sync_actor(sim.world,id)
	var reason: String=sim.space.request_group_move(sim.world,"leader",["leader","follower"],{},1,[58,80])
	var movement: Dictionary=sim.world.facts.moves.get("leader",{})
	movement.waiting_need_id="guard-probe"
	var before: Dictionary=sim.world.freeze()
	var validation: String=sim.world.validate(content)
	var life:=HospitalWaitingLife.new(content,sim.space)
	var refused: bool=not life._try_finish_fallback_travel(sim.world,"leader","guard-probe")
	var f:=FileAccess.open(directory+"/convoy-preWorld.bin",FileAccess.WRITE);f.store_var(before,false);f.close()
	check("OFFICIAL-CONVOY-MEMBERS-GUARD",reason.is_empty() and validation.is_empty() and movement.has("convoy") and movement.members.size()==2 and refused and sim.world.freeze()==before,{"validation":validation,"request":reason,"members":movement.get("members",[]),"convoy":movement.has("convoy"),"denied":refused,"unchanged":sim.world.freeze()==before})
	sim.dispose()
	return checks

func _run() -> void:
	var args:=OS.get_cmdline_user_args();content=HospitalContent.new()
	var mode: String=args[0];var rows: Array=[]
	if mode=="flow":
		var flow:=SafetyFlow.new();flow._content=content
		var result: Dictionary=flow.run_safe(args[1].get_base_dir());rows=result.rows;_expect(result.ok,"safe-midway")
	elif mode=="guards":rows=_guard_cases(args[1].get_base_dir())
	elif mode=="staff74":
		var phase:=CountPhase.new();phase._content=content;phase._case_74(self);rows=checks
	else:errors.append("unknown mode")
	var out:=FileAccess.open(args[1],FileAccess.WRITE);out.store_string(JSON.stringify({"ok":errors.is_empty(),"rows":rows,"errors":errors},"\t"));out.close()
	quit(0 if errors.is_empty() else 1)
