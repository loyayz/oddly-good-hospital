extends SceneTree
func _initialize() -> void:call_deferred("_run")
func _run() -> void:
	var args:=OS.get_cmdline_user_args();var out: String=args[1]
	var input: Dictionary=FileAccess.open(args[2],FileAccess.READ).get_var(false);var content:=HospitalContent.new();var rows: Array=[]
	for kind: String in ["valid","stale_request","stale_target","cancel_waiter","retarget_root","noncontact_body_unit","no_retreat_unit"]:
		var sim:=HospitalSimulation.new(WorldState.new(input.duplicate(true)),content);var w: WorldState=sim.world;var m: Dictionary=w.facts.moves.leader;var wp: Dictionary=m.route_waypoint;var root: Dictionary=w.facts.moves.zz_retreat
		var original: Dictionary=m.duplicate(true)
		var checks: Dictionary={"cold_exact":w.freeze()==input,"initial_valid":w.validate(content).is_empty()}
		match kind:
			"stale_request":wp.binding.retreat_request+=1
			"stale_target":wp.binding.retreat_target=[34.0,76.0]
			"cancel_waiter":HospitalTransit.cancel_waiting(w,m)
			"retarget_root":checks.formal_request=sim.space.request_move(w,"zz_retreat",2,[34,76]).is_empty()
			"noncontact_body_unit":
				# Separate declared legal current-body unit boundary, not a claim
				# that this actor physically travelled here in the saved history.
				w.facts.actors.zz_retreat.location.cell=[34.0,76.0]
				sim.space.sync_actor(w,"zz_retreat")
			"no_retreat_unit":root.local_move.erase("retreat")
		checks.shape_valid=w.validate(content).is_empty()
		FileAccess.open(out+"/"+kind+"-pre.bin",FileAccess.WRITE).store_var(w.freeze())
		var actor_before: Dictionary=w.facts.actors.leader.duplicate(true)
		sim.space.movement._dispatch_routes(w,w.present_actor_count())
		checks.pending_consumed=not m.has("route_waypoint") and not m.get("route_pending",false)
		checks.no_teleport=w.facts.actors.leader==actor_before
		checks.task_kept=m.request_sequence==original.request_sequence and m.target_floor==original.target_floor and m.target_cell==original.target_cell
		if kind=="valid":
			checks.published=m.path.slice(0,wp.prefix.size())==wp.prefix and m.path.slice(wp.prefix.size())==wp.continuation and m.transit_wait.cell==wp.cell and m.transit_ticket==original.transit_ticket
		else:
			checks.route_untouched=m.path==original.path and m.cursor==original.cursor
			if kind!="cancel_waiter":checks.ticket_marker_untouched=m.transit_ticket==original.transit_ticket and m.transit_wait==original.transit_wait
		checks.final_valid=w.validate(content).is_empty()
		FileAccess.open(out+"/"+kind+"-final.bin",FileAccess.WRITE).store_var(w.freeze())
		rows.append({"case":kind,"ok":checks.values().all(func(v: Variant)->bool:return bool(v)),"checks":checks,"validation":w.validate(content)})
		sim.dispose()
	var ok: bool=rows.all(func(row: Dictionary)->bool:return row.ok)
	FileAccess.open(out+"/result.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":ok,"rows":rows},"  "));quit(0 if ok else 1)
