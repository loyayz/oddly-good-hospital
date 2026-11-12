extends "res://tests/acceptance/run_floor_wait_order.gd"

func _save_world(world: WorldState, path: String) -> void:
	var f:=FileAccess.open(path,FileAccess.WRITE)
	f.store_var(world.freeze(),false);f.close()

func _derived_queries(directory: String) -> Array:
	var fixture:=CountPhase.new();fixture._content=content
	var x: Dictionary=fixture._fixture({"idle_doctor":"doctor"})
	var visit: Dictionary=fixture._visit(x,"derived_public",[38,90])
	var world: WorldState=x.world
	world.facts.floors.completed_top_floor={"1:2":2}
	world.facts.actors[visit.actor_id].location.floor_id=2
	world.facts.actors.idle_doctor.location.floor_id=2
	world.invalidate_geometry()
	var validation: String=world.validate(content)
	_save_world(world,directory+"/derived-preWorld.bin")
	var frozen: Dictionary=world.freeze()
	var service:=HospitalRoomUse.new(content)
	var count: int=0
	for y: int in range(64,96):
		for xcell: int in range(32,64):
			if service.public_point(world,2,Vector2i(xcell,y)):count+=1
	check("DERIVED-1024",validation.is_empty() and count==1024 and not world.facts.floors.overrides.has("2"),{"validation":validation,"count":count,"owned_plots":HospitalSpace.floor_plots(world,2)})
	check("DENY-BOUNDARIES",not service.public_point(world,3,Vector2i(38,90)) and not service.public_point(world,0,Vector2i(38,90)) and not service.public_point(world,2,Vector2i(31,90)) and not service.public_point(world,2,Vector2i(64,90)) and not service.public_point(world,2,Vector2i(-1,90)) and not service.public_point(world,2,Vector2i(38,96)))
	var actual:=TraceSpace.new(content);actual.public_areas=TraceAreas.new(actual)
	var reference:=TraceSpace.new(content);reference.public_areas=ReferenceAreas.new(reference)
	var query: Dictionary=_query("derived-live-safe-reach",world,visit.actor_id,actual,reference)
	check("DERIVED-REAL-QUERY",query.ok and query.count==1024 and not query.returned.is_empty() and actual.events.any(func(event:Dictionary)->bool:return event.kind=="reach" and event.result),query)
	var consumer: Dictionary=x.d._public_idle_point(world,"idle_doctor")
	check("DIRECT-IDLE-PERMISSION",consumer=={"here":true} and world.freeze()==frozen,{"result":consumer,"world_rng_unchanged":world.freeze()==frozen})
	# Same service: a negative cached layer must be invalidated by the completion
	# boundary's real geometry invalidation. This is a legal query fixture,
	# not a claim that a construction order was physically worked here.
	world.facts.floors.completed_top_floor["1:2"]=3
	world.invalidate_geometry()
	check("HEIGHT-INVALIDATION",service.public_point(world,3,Vector2i(38,90)) and service._plots.keys()==[3])
	var replacement: Dictionary=world.freeze();replacement.floors.completed_top_floor["1:2"]=2
	world.facts=replacement
	check("FACTS-INSTANCE-INVALIDATION",not service.public_point(world,3,Vector2i(38,90)))
	var restored:=WorldState.new(frozen.duplicate(true))
	check("RESTORED-WORLD-INVALIDATION",service.public_point(restored,2,Vector2i(38,90)) and service._world.get_ref()==restored and service._plots.keys()==[2] and restored.freeze()==frozen)
	# The model uses unbounded continuous height, not one object per floor.
	var high:=WorldState.new(frozen.duplicate(true))
	high.facts.floors.completed_top_floor["1:2"]=1000000
	high.invalidate_geometry()
	var high_before: Dictionary=high.freeze()
	var high_validation: String=high.validate(content)
	check("HIGH-ONLY-QUERIED-LAYER",high_validation.is_empty() and service.public_point(high,1000000,Vector2i(38,90)) and service._plots.keys()==[1000000] and high.freeze()==high_before and not high.facts.floors.overrides.has("1000000"),{"validation":high_validation,"indexed_floors":service._plots.keys()})
	x.a.dispose()
	return checks.duplicate(true)

func _permission_boundary() -> Array:
	var fixture:=CountPhase.new();fixture._content=content
	var x: Dictionary=fixture._fixture()
	var visit: Dictionary=fixture._visit(x,"permission",[38,90])
	x.world.facts.floors.completed_top_floor={"1:2":2}
	x.world.facts.actors[visit.actor_id].location.floor_id=2
	x.world.invalidate_geometry()
	var before: Dictionary=x.world.freeze()
	var guidance:=HospitalFloorGuidance.new(content,x.space)
	var allowed: bool=guidance.return_target_valid(x.world,visit,2,[38,90],{})
	var denied_adjacent: bool=not guidance.return_target_valid(x.world,visit,2,[64,90],{})
	var denied_floor: bool=not guidance.return_target_valid(x.world,visit,3,[38,90],{})
	var denied_bounds: bool=not guidance.return_target_valid(x.world,visit,2,[-1,90],{})
	check("DIRECT-GUIDANCE-PERMISSION",allowed and denied_adjacent and denied_floor and denied_bounds and x.world.freeze()==before and x.world.validate(content).is_empty(),{"allowed":allowed,"denied_adjacent":denied_adjacent,"denied_floor":denied_floor,"denied_bounds":denied_bounds,"world_unchanged":x.world.freeze()==before})
	x.a.dispose()
	return checks

func _run() -> void:
	var args:=OS.get_cmdline_user_args();content=HospitalContent.new()
	var mode: String=args[0];var rows: Array=[]
	if mode=="query":rows=_derived_queries(args[1].get_base_dir())
	elif mode=="rooms":rows=_fixture_queries()
	elif mode=="permission":rows=_permission_boundary()
	elif mode=="flow":
		var phase:=CountPhase.new();phase._content=content;phase._case_74(self)
		check("STAFF-74-floor-fallback-hit",CountAreas.calls>0,{"calls":CountAreas.calls})
		rows=checks
	else:errors.append("unknown mode")
	var out:=FileAccess.open(args[1],FileAccess.WRITE)
	out.store_string(JSON.stringify({"ok":errors.is_empty(),"mode":mode,"rows":rows,"errors":errors},"\t"));out.close()
	print("DERIVED_PUBLIC_POINT "+mode+" "+str(errors.is_empty()))
	quit(0 if errors.is_empty() else 1)
