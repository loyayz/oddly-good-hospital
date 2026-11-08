extends RefCounted

# Production commands and real fixed steps; never write arrival/work progress.
func run(suite) -> Dictionary:
	var f: Dictionary = suite._new("Renovation pickup follows the current physical tool")
	if not suite._place(f,"tool","SE02",[46,80]): return {"ok":false,"details":f.errors}
	var cash: int = HospitalLedger.balance(f.w)
	var ordered: CommandResult = suite._command(f,"renovation_order",{"material_id":"MAT01","floor_id":1,"units":[{"cell":[43,83]}],"allow_waiting":true})
	if not ordered.accepted: return {"ok":false,"details":ordered.reason}
	var id: String = ordered.changed_ids[0]
	suite._work_tick(f,"environment")
	var unit: Dictionary = f.w.facts.environment.orders[id].units[0]
	var worker_id: String = str(unit.worker_id)
	var checks: Dictionary = {"assigned_before_pickup":not worker_id.is_empty() and not f.w.facts.staff.has(worker_id) and not unit.tool_collected and not unit.started and unit.remaining_milli==8000 and f.w.facts.moves.has(worker_id)}
	var before: Dictionary = f.w.freeze().duplicate(true)
	var moved: CommandResult = suite._command(f,"build_move",{"target_id":"tool","floor_id":1,"cell":[50,86]})
	# Commands replace facts. Reread all current aliases after the command.
	unit = f.w.facts.environment.orders[id].units[0]
	checks.moved_without_work = moved.accepted and f.w.facts.actors==before.actors and f.w.facts.moves==before.moves and unit.remaining_milli==8000 and not unit.tool_collected and not unit.started
	checks.input_valid = f.w.validate(suite._content).is_empty()
	if not checks.values().all(func(value): return value): return {"ok":false,"details":checks}
	var observed: Dictionary = {"pickup":false,"pickup_contact":true,"actual_work":true,"work_ticks":0,"remaining":8000,"collected":false}
	var observe: Callable = func(stage: String) -> void:
		var current: Dictionary = f.w.facts.environment.orders[id].units[0]
		if stage=="before":
			observed.remaining = int(current.remaining_milli)
			observed.collected = bool(current.tool_collected)
			return
		if current.tool_collected and not observed.collected:
			var actor: Dictionary = f.w.facts.actors[worker_id]
			var tool: Dictionary = f.w.facts.facilities[current.tool_id]
			var dx: float = absf(float(actor.location.cell[0])-float(tool.cell[0]))
			var dy: float = absf(float(actor.location.cell[1])-float(tool.cell[1]))
			observed.pickup = true
			observed.pickup_contact = observed.pickup_contact and actor.location.kind=="floor" and actor.location.floor_id==tool.floor_id and is_equal_approx(dx+dy,1.0) and (is_zero_approx(dx) or is_zero_approx(dy)) and not f.w.facts.moves.has(worker_id)
		if int(current.remaining_milli)<int(observed.remaining):
			observed.work_ticks += 1
			observed.actual_work = observed.actual_work and int(observed.remaining)-int(current.remaining_milli)==100 and f.s.space.at(f.w,worker_id,1,current.work_cell) and not f.w.facts.moves.has(worker_id)
	for tick: int in 450:
		suite._work_tick(f,"environment",observe)
		if unit.phase=="completed": break
	checks.current_tool_pickup = observed.pickup and observed.pickup_contact
	checks.real_full_work = observed.actual_work and observed.work_ticks==80 and unit.phase=="completed" and unit.remaining_milli==0 and unit.contributions.get(worker_id,0)==8000
	checks.once = cash-HospitalLedger.balance(f.w)==25 and f.w.facts.environment.surfaces.size()==1 and f.w.facts.environment.receipts.size()==1 and f.w.facts.environment.receipts.get(str(unit.id)+":renovation_completed",{}).get("standard_work_milli",0)==8000
	var terminal: Dictionary = f.w.facts.environment.duplicate(true)
	var ledger: Dictionary = f.w.facts.ledger.duplicate(true)
	for tick: int in 3: suite._work_tick(f,"environment")
	checks.idempotent = terminal==f.w.facts.environment and ledger==f.w.facts.ledger
	checks.final_valid = f.w.validate(suite._content).is_empty() and f.errors.is_empty()
	return {"ok":checks.values().all(func(value): return value),"details":{"checks":checks,"observed":observed,"unit":unit.duplicate(true),"errors":f.errors}}
