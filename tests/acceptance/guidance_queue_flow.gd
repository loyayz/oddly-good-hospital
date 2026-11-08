extends RefCounted

const Flow=preload("res://game/operations/guidance_queue_flow.gd")

# Pure geometric contract tests. This fake fixed query is NOT evidence of real
# building clearance, actor arrival or dynamic collision safety.
class Fixed extends RouteClearance:
	var denied: bool=false
	var calls: int=0
	var sweeps: Array=[]
	func _init(size: int=1) -> void:
		_size=size
	func sweep_reason(_from: Vector2,_to: Vector2) -> String:
		calls+=1
		sweeps.append([_from,_to])
		return "fixed obstacle" if denied else ""

func run_geometry() -> Dictionary:
	var checks: Dictionary={}
	for rotation: int in 4:
		var front: Vector2=[Vector2.DOWN,Vector2.LEFT,Vector2.UP,Vector2.RIGHT][rotation]
		var right: Vector2=Vector2(front.y,-front.x)
		for span: int in [1,2,3]:
			var head: Vector2=Vector2(40,40)
			var slots: Array=[]
			for i: int in 3:
				var point: Vector2=head+front*i*span
				slots.append([point.x,point.y])
			var saved: Array=slots.duplicate(true)
			var fixed: Fixed=Fixed.new(span)
			var service: Vector2=head-right*span
			var tail: Vector2=head+front*3*span
			var target: Vector2=head+front*span
			var entry: Array=Flow.hints(slots,span,rotation,Vector2.ZERO,target,service,true,fixed)
			var entry_sweeps: Array=fixed.sweeps.duplicate(true)
			var leave: Array=Flow.hints(slots,span,rotation,target,Vector2.ZERO,service,false,fixed)
			var prefix: String=str(rotation)+"_"+str(span)
			checks[prefix+"_entry"]=entry==[target+right*span]
			checks[prefix+"_entry_keeps_static_side_proofs"]=entry_sweeps.has([head+right*span,tail+right*span]) and entry_sweeps.has([head-right*span,tail-right*span]) and entry_sweeps.has([tail-right*span,tail+right*span]) and entry_sweeps.has([target+right*span,target])
			checks[prefix+"_exit"]=leave==[target-right*span,tail-right*span]
			checks[prefix+"_service"]=Flow.hints(slots,span,rotation,service,Vector2.ZERO,service,false,fixed)==[tail-right*span]
			checks[prefix+"_readonly"]=slots==saved
			var between: Vector2=head+front*(float(span)+0.25)
			var fractional: Array=Flow.hints(slots,span,rotation,between,Vector2.ZERO,service,false,fixed)
			checks[prefix+"_fractional_inside_exit"]=fractional==[between-right*span,tail-right*span]
			var outside: Vector2=between+right*0.25
			checks[prefix+"_fractional_outside_fallback"]=Flow.hints(slots,span,rotation,outside,Vector2.ZERO,service,false,fixed).is_empty()
			fixed.denied=true
			checks[prefix+"_fractional_static_block_fallback"]=Flow.hints(slots,span,rotation,between,Vector2.ZERO,service,false,fixed).is_empty()
			fixed.denied=false

			var box: Rect2=Flow.bounds(slots,span)
			checks[prefix+"_bounds"]=box==Rect2(head,Vector2.ONE*span).merge(Rect2(head+front*2*span,Vector2.ONE*span))
			checks[prefix+"_service_direct"]=Flow.service_approach(slots,span,rotation,head,service,fixed).mode=="direct"
			var local: Dictionary=Flow.service_approach(slots,span,rotation,target,service,fixed)
			checks[prefix+"_service_local"]=local.mode=="local" and local.points==[target-right*span,service]
			var remote: Dictionary=Flow.service_approach(slots,span,rotation,head+right*span,service,fixed)
			checks[prefix+"_service_remote"]=remote.mode=="remote" and remote.points==[tail-right*span,service]
			checks[prefix+"_service_no_cross"]=Flow.service_approach(slots,span,rotation,head+right*span,head+right*span*2,fixed).mode=="none"

			fixed.denied=true
			checks[prefix+"_blocked_fallback"]=Flow.hints(slots,span,rotation,Vector2.ZERO,target,service,true,fixed).is_empty()
			checks[prefix+"_service_blocked"]=Flow.service_approach(slots,span,rotation,target,service,fixed).mode=="none"
	var fixed: Fixed=Fixed.new()
	checks.multicolumn_fallback=Flow.hints([[40,40],[40,41],[42,40]],1,0,Vector2.ZERO,Vector2(40,40),Vector2(39,40),true,fixed).is_empty()
	checks.filtered_gap_fallback=Flow.hints([[40,40],[40,42]],1,0,Vector2.ZERO,Vector2(40,40),Vector2(39,40),true,fixed).is_empty()
	checks.foreign_origin_fallback=Flow.hints([[40,40]],1,0,Vector2(35,35),Vector2.ZERO,Vector2(39,40),false,fixed).is_empty()
	checks.foreign_goal_fallback=Flow.hints([[40,40]],1,0,Vector2.ZERO,Vector2(41,40),Vector2(39,40),true,fixed).is_empty()
	checks.large_query_fallback=Flow.hints([[40,40]],1,0,Vector2.ZERO,Vector2(40,40),Vector2(39,40),true,Fixed.new(2)).is_empty()
	checks.empty_bounds=Flow.bounds([],1)==Rect2()
	checks.service_multicolumn=Flow.service_approach([[40,40],[42,40]],1,0,Vector2.ZERO,Vector2(39,40),fixed).mode=="none"
	checks.service_large_body=Flow.service_approach([[40,40]],1,0,Vector2.ZERO,Vector2(39,40),Fixed.new(2)).mode=="none"

	# Static integration contract only, not a fake claim to have run quote() or
	# moved a patient. The existing service_local cases prove helper output;
	# this guards the previously observed wrapper early-return that hid it.
	var route_source: String=FileAccess.get_file_as_string("res://game/operations/guidance_queue_routes.gd")
	checks.wrapper_local_branch_static_contract=not route_source.is_empty() and route_source.find("if already_in_column and target.distance_to")<0 and route_source.find("Flow.service_approach(slots,span,int(desk.rotation),start,target,fixed)")>=0 and route_source.find('remote_first=approach.mode=="remote"')>=0 and route_source.find("hints=approach.points")>=0
	var passed: bool=true
	for value: bool in checks.values(): passed=passed and value
	return {"passed":passed,"checks":checks,"scope":"pure geometry only; real routing and collision require integration tests"}
