extends RefCounted

# Enter through legal pre-work boundaries, then use the production 0.1-second
# dispatch/movement/work phases. Never set a completion, arrival or contribution.
class ObservedSpace extends HospitalSpace:
	var calls: int = 0
	var moving_calls: int = 0
	func route_cost(world: WorldState, actor_id: String, floor_id: int, target: Array, members: Array = [], offsets: Dictionary = {}, ignore_people: bool = false) -> Dictionary:
		calls += 1
		var move: Dictionary = world.facts.moves.get(actor_id,{})
		if move.get("target_floor",-1)==floor_id and move.get("target_cell",[])==target: moving_calls += 1
		return super.route_cost(world,actor_id,floor_id,target,members,offsets,ignore_people)

func maintenance(suite) -> Dictionary:
	var normal: Dictionary = _maintenance_trip(suite,false)
	var blocked: Dictionary = _maintenance_trip(suite,true)
	return {"ok":normal.ok and blocked.ok,"details":{"normal":normal,"blocked_then_reopened":blocked}}

func _maintenance_trip(suite, interrupt_route: bool) -> Dictionary:
	var f: Dictionary = suite._machine("Maintenance journey owns route checks")
	var space: ObservedSpace = ObservedSpace.new(suite._content)
	f.s.space = space
	f.s.services.maintenance.space = space
	f.w.facts.facilities.ops_machine.condition = 18.0
	f.w.facts.facilities.ops_machine.failed = true
	f.s.services.maintenance.boundaries(f.w)
	var job: Dictionary = f.w.facts.maintenance.jobs[f.w.facts.facilities.ops_machine.maintenance_order_id]
	var input_validation: String = f.w.validate(suite._content)
	var cash: int = HospitalLedger.balance(f.w)
	suite._work_tick(f,"maintenance")
	var worker: String = job.worker_id
	var sent: bool = not worker.is_empty() and f.w.facts.moves.has(worker) and not job.started and HospitalLedger.balance(f.w)==cash
	var retained: bool = true
	if interrupt_route and sent:
		# A legal unoccupied destination becomes blocked after departure. The
		# existing movement must stop and recover without charging/working early.
		f.w.facts.floors.overrides["1"].blocked.append(job.work_cell.duplicate())
		f.w.touch()
		for tick: int in 120: suite._work_tick(f,"maintenance")
		retained = not job.started and job.completed_milli==0 and HospitalLedger.balance(f.w)==cash and f.w.facts.actors[worker].location.kind=="floor" and not space.at(f.w,worker,int(job.work_floor),job.work_cell)
		f.w.facts.floors.overrides["1"].blocked.erase(job.work_cell)
		f.w.touch()
	for tick: int in 650:
		suite._work_tick(f,"maintenance")
		if job.phase=="completed": break
	var validation: String = f.w.validate(suite._content)
	var receipt: Dictionary = f.w.facts.maintenance.receipts.get(str(job.id)+":repair_completed",{})
	var ok: bool = input_validation.is_empty() and validation.is_empty() and f.errors.is_empty() and sent and retained and job.phase=="completed" and job.completed_milli==30000 and job.paid_parts==40 and cash-HospitalLedger.balance(f.w)==40 and receipt.get("standard_work_milli")==30000 and f.w.facts.maintenance.receipts.size()==1 and space.moving_calls==0
	return {"ok":ok,"input_validation":input_validation,"final_validation":validation,"sent_before_work_or_payment":sent,"blocked_trip_preserved":retained,"route_cost_calls":space.calls,"route_cost_calls_during_same_move":space.moving_calls,"job":job.duplicate(true),"paid":cash-HospitalLedger.balance(f.w),"receipt":receipt,"errors":f.errors}

func tools(suite) -> Dictionary:
	var f: Dictionary = suite._new("Each decorator chooses a reachable tool")
	suite._place(f,"a_unreachable_tool","SE02",[36,74])
	suite._place(f,"z_reachable_tool","SE02",[46,80])
	for x: int in range(34,40):
		f.w.facts.floors.overrides["1"].blocked.append([x,72])
		f.w.facts.floors.overrides["1"].blocked.append([x,77])
	for y: int in range(73,77):
		f.w.facts.floors.overrides["1"].blocked.append([34,y])
		f.w.facts.floors.overrides["1"].blocked.append([39,y])
	f.w.touch()
	var cash: int = HospitalLedger.balance(f.w)
	var ordered: CommandResult = suite._command(f,"renovation_order",{"material_id":"MAT01","floor_id":1,"units":[{"cell":[43,83]}],"allow_waiting":true})
	if not ordered.accepted: return {"ok":false,"details":{"reason":ordered.reason,"errors":f.errors}}
	var unit: Dictionary = f.w.facts.environment.orders[ordered.changed_ids[0]].units[0]
	suite._work_tick(f,"environment")
	var worker_id: String = str(unit.worker_id)
	if worker_id.is_empty(): return {"ok":false,"details":"contractor not admitted"}
	var input_validation: String = f.w.validate(suite._content)
	var first: Dictionary = f.s.services.environment._work_position(f.w,worker_id,1,[36,74],true)
	var second: Dictionary = f.s.services.environment._work_position(f.w,worker_id,1,[46,80],true)
	var observed: Dictionary = {"pickup":false,"only_at_work":true,"before_work":-1}
	var observe: Callable = func(stage: String) -> void:
		if stage=="before" and unit.tool_collected and not unit.started:
			observed.pickup = observed.pickup or f.s.space.at(f.w,worker_id,1,unit.tool_cell)
		if stage=="before" and not str(unit.worker_id).is_empty() and not f.s.space.at(f.w,worker_id,1,unit.work_cell):
			observed.before_work = int(unit.remaining_milli)
		elif stage=="after" and int(observed.before_work)>=0:
			observed.only_at_work = observed.only_at_work and int(unit.remaining_milli)==int(observed.before_work)
			observed.before_work = -1
	for tick: int in 350:
		suite._work_tick(f,"environment",observe)
		if unit.phase=="completed": break
	var receipt: Dictionary = f.w.facts.environment.receipts.get(str(unit.id)+":renovation_completed",{})
	var validation: String = f.w.validate(suite._content)
	var ok: bool = first.is_empty() and not second.is_empty() and input_validation.is_empty() and validation.is_empty() and f.errors.is_empty() and unit.tool_id=="z_reachable_tool" and observed.pickup and observed.only_at_work and unit.phase=="completed" and unit.remaining_milli==0 and unit.contributions.get(worker_id)==8000 and receipt.get("standard_work_milli")==8000 and f.w.facts.environment.receipts.size()==1 and cash-HospitalLedger.balance(f.w)==25
	return {"ok":ok,"details":{"first_tool_unreachable":first.is_empty(),"second_tool_reachable":not second.is_empty(),"actual_tool_pickup":observed.pickup,"work_only_at_destination":observed.only_at_work,"unit":unit.duplicate(true),"paid":cash-HospitalLedger.balance(f.w),"input_validation":input_validation,"final_validation":validation,"errors":f.errors}}

func remodel(suite) -> Dictionary:
	var f: Dictionary = suite._new("Only unfinished renovation cells block remodel")
	suite._construction_tools(f)
	var ordered: CommandResult = suite._command(f,"renovation_order",{"material_id":"MAT01","floor_id":1,"units":[{"cell":[42,80]},{"cell":[44,80]},{"cell":[46,80]}],"allow_waiting":true})
	if not ordered.accepted: return {"ok":false,"details":{"reason":ordered.reason,"errors":f.errors}}
	var id: String = ordered.changed_ids[0]
	var order: Dictionary = f.w.facts.environment.orders[id]
	var input_validation: String = f.w.validate(suite._content)
	for tick: int in 400:
		suite._work_tick(f,"environment")
		if order.units[0].phase=="completed": break
	var first_view: Array = f.s.services.remodel._waiting_view(f.w).units.get(1,[])
	var first_released: bool = order.phase not in ["completed","cancelled"] and order.units[0].phase=="completed" and not [42,80] in first_view and [44,80] in first_view and [46,80] in first_view
	var restored: Dictionary = suite._restore(f)
	var restore_view: Array = restored.s.services.remodel._waiting_view(restored.w).units.get(1,[])
	order = restored.w.facts.environment.orders[id]
	for tick: int in 400:
		suite._work_tick(restored,"environment")
		if order.units[1].started: break
	var cash: int = HospitalLedger.balance(restored.w)
	var cancelled: CommandResult = suite._command(restored,"renovation_cancel",{"order_id":id})
	var cancel_view: Array = restored.s.services.remodel._waiting_view(restored.w).units.get(1,[])
	var cancelled_released: bool = cancelled.accepted and order.units[1].started and order.units[1].phase=="working" and order.units[2].phase=="cancelled" and cancel_view==[[44,80]] and HospitalLedger.balance(restored.w)==cash+25
	for tick: int in 300:
		suite._work_tick(restored,"environment")
		if order.phase=="cancelled": break
	var final_view: Array = restored.s.services.remodel._waiting_view(restored.w).units.get(1,[])
	var validation: String = restored.w.validate(suite._content)
	var ok: bool = input_validation.is_empty() and validation.is_empty() and f.errors.is_empty() and restored.errors.is_empty() and first_released and first_view==restore_view and cancelled_released and order.phase=="cancelled" and order.units[1].phase=="completed" and final_view.is_empty() and restored.w.facts.environment.surfaces.size()==2 and restored.w.facts.environment.receipts.size()==2
	return {"ok":ok,"details":{"input_validation":input_validation,"final_validation":validation,"completed_cell_released":first_released,"first_blockers":first_view,"restored_blockers":restore_view,"cancelled_cell_released":cancelled_released,"cancel_blockers":cancel_view,"final_blockers":final_view,"order":order.duplicate(true),"errors":restored.errors}}

func cleanup(suite) -> Dictionary:
	var at_edge: Dictionary = _cleanup_trip(suite,[40,80],false)
	var approach: Dictionary = _cleanup_trip(suite,[36,80],false)
	var obstruction: Dictionary = _cleanup_trip(suite,[40,80],true)
	var corner: Dictionary = _cleanup_trip(suite,[40,80],false,true)
	var wall: Dictionary = _cleanup_closed_room(suite,[40,80],[43,80])
	var door: Dictionary = _cleanup_closed_room(suite,[43,82],[44,81])
	return {"ok":at_edge.ok and approach.ok and obstruction.ok and corner.ok and wall.ok and door.ok,"details":{"body_edge":at_edge,"actual_approach":approach,"contact_interrupted":obstruction,"unrelated_corner":corner,"wall":wall,"closed_door":door}}

func _cleanup_trip(suite, start: Array, interrupt_contact: bool, unrelated_corner: bool = false) -> Dictionary:
	var f: Dictionary = suite._new("Large cleaner reaches dirt with complete body")
	var target: Array = [43,80] if interrupt_contact or unrelated_corner else [42,80]
	for y: int in range(64,96): f.w.facts.floors.overrides["1"].blocked.append([44 if interrupt_contact or unrelated_corner else 43,y])
	if unrelated_corner: f.w.facts.floors.overrides["1"].blocked.append([43,82])
	f.w.touch()
	var id: String = f.s.services.environment.spawn_dirt(f.w,"CL01","body_edge_incident","body_edge_spill",1,target)
	suite._staff(f,"large_cleaner","cleaner",start)
	var actor: Dictionary = f.w.facts.actors.large_cleaner
	actor.species_id = "S53"
	f.w.touch()
	f.s.space.sync_actor(f.w,actor.id)
	var input_validation: String = f.w.validate(suite._content)
	var place: Dictionary = {}
	if id.is_empty(): return {"ok":false,"reason":"No legal dirt fixture","validation":input_validation}
	var patch: Dictionary = f.w.facts.environment.dirt[id]
	var observed: Dictionary = {"remaining":4000,"no_work_while_moving":true,"moved":false,"actual_work_ticks":0}
	var observe: Callable = func(stage: String) -> void:
		if stage=="before":
			observed.remaining = patch.remaining_milli
			observed.moving = f.w.facts.moves.has(actor.id)
			observed.moved = observed.moved or actor.location.cell!=start
		elif int(patch.remaining_milli)<int(observed.remaining):
			observed.actual_work_ticks += 1
			var body: Rect2 = f.s.space.body_rectangle(actor)
			var point: Vector2 = Vector2(float(target[0])+0.5,float(target[1])+0.5)
			observed.no_work_while_moving = observed.no_work_while_moving and not observed.moving and point.distance_to(point.clamp(body.position,body.end))<=1.0
	for tick: int in 250:
		suite._work_tick(f,"environment",observe)
		if not patch.work_cell.is_empty(): place = {"cell":patch.work_cell.duplicate()}
		if int(patch.remaining_milli)<4000: break
	var blocked: bool = true
	if interrupt_contact:
		# A new obstacle between the current body and target must stop the
		# already assigned work; position alone is not a valid work permission.
		f.w.facts.floors.overrides["1"].blocked.append(target.duplicate())
		f.w.touch()
		var remaining: int = int(patch.remaining_milli)
		for tick: int in 20: suite._work_tick(f,"environment",observe)
		blocked = int(patch.remaining_milli)==remaining and remaining>0 and str(patch.worker_id).is_empty()
		f.w.facts.floors.overrides["1"].blocked.erase(target)
		f.w.touch()
	for tick: int in 350:
		suite._work_tick(f,"environment",observe)
		if not f.w.facts.environment.dirt.has(id): break
	var receipt: Dictionary = f.w.facts.environment.receipts.get(id+":cleanup_completed",{})
	var validation: String = f.w.validate(suite._content)
	var ok: bool = input_validation.is_empty() and validation.is_empty() and f.errors.is_empty() and not place.is_empty() and not f.w.facts.environment.dirt.has(id) and receipt.get("standard_work_milli")==4000 and f.w.facts.environment.receipts.size()==1 and patch.contributions.get(actor.id)==4000 and observed.actual_work_ticks==40 and observed.no_work_while_moving and (start==[40,80] or observed.moved) and blocked and (not unrelated_corner or not observed.moved and place.get("cell")==start)
	return {"ok":ok,"input_validation":input_validation,"final_validation":validation,"work_position":place,"body":str(f.s.space.body_rectangle(actor)),"actual_work_ticks":observed.actual_work_ticks,"actual_movement":observed.moved,"work_only_at_contact":observed.no_work_while_moving,"blocked_contact_preserves_progress":blocked,"receipt":receipt,"remaining_milli":patch.remaining_milli,"errors":f.errors}

func _cleanup_closed_room(suite, start: Array, target: Array) -> Dictionary:
	var f: Dictionary = suite._new("Tools cannot clean through a wall or closed doorway")
	var built: CommandResult = suite._command(f,"build_room",{"id":"closed_room","room_type_id":"gp","floor_id":1,"origin":[43,78],"size":[4,4],"door":{"definition_id":"DR01","edge":"south","offset":2}})
	# The doorway is legal for its base body but cannot unfold to the three
	# cells this worker needs without crossing the room corner.
	var id: String = f.s.services.environment.spawn_dirt(f.w,"CL01","closed_room_incident","closed_room_spill",1,target)
	suite._staff(f,"large_cleaner","cleaner",start)
	var actor: Dictionary = f.w.facts.actors.large_cleaner
	actor.species_id = "S53"
	f.w.touch()
	f.s.space.sync_actor(f.w,actor.id)
	var validation: String = f.w.validate(suite._content)
	if id.is_empty(): return {"ok":false,"reason":"No legal blocked-contact fixture","built":built.reason,"validation":validation}
	var body: Rect2 = f.s.space.body_rectangle(actor)
	var point: Vector2 = Vector2(float(target[0])+0.5,float(target[1])+0.5)
	var in_reach: bool = point.distance_to(point.clamp(body.position,body.end))<=1.0
	for tick: int in 100: suite._work_tick(f,"environment")
	var patch: Dictionary = f.w.facts.environment.dirt.get(id,{})
	var final_validation: String = f.w.validate(suite._content)
	return {"ok":built.accepted and in_reach and validation.is_empty() and final_validation.is_empty() and f.errors.is_empty() and patch.get("remaining_milli")==4000 and patch.get("worker_id")=="" and f.w.facts.environment.receipts.is_empty(),"within_body_reach":in_reach,"input_validation":validation,"final_validation":final_validation,"remaining_milli":patch.get("remaining_milli"),"errors":f.errors}
