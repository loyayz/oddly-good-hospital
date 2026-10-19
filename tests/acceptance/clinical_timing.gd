extends RefCounted

# Root stages are disjoint. Call totals are inclusive and can be nested.
var stages: Dictionary = {}
var calls: Dictionary = {}
var profile_sources: Dictionary = {}
var profile_errors: Array = []
var snapshot_path: String = ""
var _snapshot_written: int = 0

func finish(stage: String, started: int) -> void:
	var elapsed: int = Time.get_ticks_usec()-started
	stages[stage] = elapsed
	print("CASE_STAGE "+JSON.stringify({"stage":stage,"elapsed_us":elapsed}))
	_snapshot()

func count(operation: String, started: int) -> void:
	var elapsed: int = Time.get_ticks_usec()-started
	var entry: Dictionary = calls.get(operation,{"calls":0,"total_us":0,"max_us":0})
	entry.calls += 1
	entry.total_us += elapsed
	entry.max_us = maxi(entry.max_us,elapsed)
	calls[operation] = entry
	if not snapshot_path.is_empty() and operation=="clinical.dispatch" and Time.get_ticks_usec()-_snapshot_written>=2000000:
		_snapshot()

func _snapshot() -> void:
	if snapshot_path.is_empty(): return
	var file: FileAccess = FileAccess.open(snapshot_path,FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(report(),"\t"))
	_snapshot_written = Time.get_ticks_usec()

func report() -> Dictionary:
	return {"stages_us":stages.duplicate(true),"inclusive_calls":calls.duplicate(true),"profile_sources":profile_sources.duplicate(),"profile_errors":profile_errors.duplicate()}

func attach(simulation: HospitalSimulation) -> bool:
	# Install before dispatch. Keep the same simulation, services and facts.
	# Every timed override delegates once to its production implementation.
	var before: Dictionary = simulation.world.freeze()
	var old_space: HospitalSpace = simulation.space
	var old_clinic: HospitalClinic = simulation.clinic
	var geometry: HospitalSpace = TimedSpace.new(simulation.content,self)
	var clinic: HospitalClinic = TimedClinic.new(simulation.content,geometry,self)
	for property: Dictionary in old_clinic.get_property_list():
		if (int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE)!=0:
			clinic.set(property.name,old_clinic.get(property.name))
	simulation.space = geometry
	simulation.clinic = clinic
	_redirect(clinic,old_space,geometry,old_clinic,clinic)
	_redirect(clinic.visitors,old_space,geometry,old_clinic,clinic)
	for service: RefCounted in simulation.services.values():
		_redirect(service,old_space,geometry,old_clinic,clinic)
	for kind: String in simulation._business_handlers:
		if simulation._business_handlers[kind]==old_clinic:
			simulation._business_handlers[kind] = clinic
	for key: String in simulation.services.keys():
		_profile_service(simulation,key)
	return profile_errors.is_empty() and simulation.world.freeze()==before

func _profile_service(simulation: HospitalSimulation, key: String) -> void:
	var original: RefCounted = simulation.services[key]
	var base: GDScript = original.get_script()
	var source: String = "extends \""+base.resource_path+"\"\nvar _acceptance_timing: RefCounted\n"
	var wrapped: int = 0
	for method: Dictionary in base.get_script_method_list():
		var name: String = str(method.name)
		if not name in ["boundaries","arrivals","dispatch","advance","advance_wait","needs","sample","settle"] and not (key=="environment" and name in ["environment_at","_coverage","_coverage_edges","_edge_open","_wall_between","_water_usable"]): continue
		var expression: RegEx = RegEx.new()
		expression.compile("(?m)^func "+name+"\\([^\\r\\n]*\\)[^\\r\\n]*:[ \\t]*$")
		var header: RegExMatch = expression.search(base.source_code)
		if header==null: continue
		var arguments: PackedStringArray = []
		for argument: Dictionary in method.args: arguments.append(str(argument.name))
		var returns_value: bool = int(method["return"].type)!=TYPE_NIL
		var assignment: String = "var result: "+type_string(int(method["return"].type))+" = " if returns_value else ""
		source += header.get_string()+"\n\tvar started: int = Time.get_ticks_usec()\n\t"+assignment+"super."+name+"("+",".join(arguments)+")\n\t_acceptance_timing.count(\"service."+key+"."+name+"\",started)\n"
		if returns_value: source += "\treturn result\n"
		wrapped += 1
	if wrapped==0: return
	var script: GDScript = GDScript.new()
	script.source_code = source
	if script.reload()!=OK:
		profile_errors.append({"service":key,"error":"timing wrapper did not compile"})
		return
	var replacement: RefCounted = script.new(simulation.content,simulation.space)
	for property: Dictionary in original.get_property_list():
		if (int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE)!=0: replacement.set(property.name,original.get(property.name))
	if key=="wellbeing": replacement.personal_beds._owner = weakref(replacement)
	replacement.set("_acceptance_timing",self)
	simulation.services[key] = replacement
	var objects: Array = [simulation.clinic,simulation.clinic.visitors]+simulation.services.values()
	for object: Object in objects:
		for property: Dictionary in object.get_property_list():
			if int(property.type)==TYPE_OBJECT and (int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE)!=0 and object.get(property.name)==original:
				object.set(property.name,replacement)
	for kind: String in simulation._business_handlers:
		if simulation._business_handlers[kind]==original: simulation._business_handlers[kind] = replacement
	profile_sources[key] = source.sha256_text()
	var file: FileAccess = FileAccess.open("res://clinical-profile-"+key+".gd",FileAccess.WRITE)
	if file!=null: file.store_string(source)

func _redirect(object: Object, old_space: HospitalSpace, geometry: HospitalSpace, old_clinic: HospitalClinic, clinic: HospitalClinic) -> void:
	for property: Dictionary in object.get_property_list():
		if int(property.type)!=TYPE_OBJECT or (int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE)==0: continue
		var value: Variant = object.get(property.name)
		if value==old_space: object.set(property.name,geometry)
		elif value==old_clinic: object.set(property.name,clinic)

class TimedClinic extends HospitalClinic:
	var timing: RefCounted
	func _init(database: HospitalContent, geometry: HospitalSpace, observer: RefCounted) -> void:
		super(database,geometry)
		timing = observer
	func dispatch(world: WorldState) -> void:
		var started: int = Time.get_ticks_usec()
		super.dispatch(world)
		timing.count("clinical.dispatch",started)
	func advance(world: WorldState) -> void:
		var started: int = Time.get_ticks_usec()
		super.advance(world)
		timing.count("clinical.advance",started)
	func _ward_covering(world: WorldState, stay: Dictionary, nurse_coverage: Dictionary = {}) -> bool:
		var started: int = Time.get_ticks_usec()
		var result: bool = super._ward_covering(world,stay,nurse_coverage)
		timing.count("clinical.ward_covering",started)
		return result
	func _surgery_quote(world: WorldState, visit: Dictionary, requested_team: Array = [], options: Dictionary = {}) -> Dictionary:
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = super._surgery_quote(world,visit,requested_team,options)
		timing.count("clinical.surgery_quote",started)
		return result
	func _surgery_bundle_quote(world: WorldState, visit: Dictionary, team: Array, facility_id: String, options: Dictionary, bed_quotes: Dictionary) -> Dictionary:
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = super._surgery_bundle_quote(world,visit,team,facility_id,options,bed_quotes)
		timing.count("clinical.bundle_quote",started)
		return result
	func _compatible_bed(world: WorldState, visit: Dictionary, floor_id: int, excluded: Array, structural_only: bool = false, preferred_bed: String = "", reference_schedule: bool = false, alternatives: Variant = null) -> Dictionary:
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = super._compatible_bed(world,visit,floor_id,excluded,structural_only,preferred_bed,reference_schedule,alternatives)
		timing.count("clinical.compatible_bed",started)
		return result
	func _reserve_bundle(world: WorldState, visit: Dictionary, quote: Dictionary, owner_id: String) -> String:
		var started: int = Time.get_ticks_usec()
		var result: String = super._reserve_bundle(world,visit,quote,owner_id)
		timing.count("clinical.reserve_bundle",started)
		return result

class TimedSpace extends HospitalSpace:
	var timing: RefCounted
	var _facility_depth: int = 0
	func _init(database: HospitalContent, observer: RefCounted) -> void:
		super(database)
		timing = observer
		_navigation = TimedNavigation.new(observer)
	func advance(world: WorldState, present_at_start: int = -1) -> void:
		var started: int = Time.get_ticks_usec()
		super.advance(world,present_at_start)
		timing.count("space.advance",started)
	func _reserve_doors(world: WorldState, actor: Dictionary, movement: Dictionary, swept: Rect2) -> bool:
		var started: int = Time.get_ticks_usec()
		var result: bool = super._reserve_doors(world,actor,movement,swept)
		timing.count("space.reserve_doors",started)
		return result
	func _active_route_clear(world: WorldState, actor: Dictionary, movement: Dictionary, versions: Dictionary) -> bool:
		var started: int = Time.get_ticks_usec()
		var result: bool = super._active_route_clear(world,actor,movement,versions)
		timing.count("space.active_route_clear",started)
		return result
	func _dispatch_routes(world: WorldState, present_at_start: int) -> void:
		var started: int = Time.get_ticks_usec()
		super._dispatch_routes(world,present_at_start)
		timing.count("space.dispatch_routes",started)
	func route(world: WorldState, actor_id: String, floor_id: int, target: Array, members: Array = [], offsets: Dictionary = {}, ignore_people: bool = false) -> Dictionary:
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = super.route(world,actor_id,floor_id,target,members,offsets,ignore_people)
		timing.count("space.route",started)
		return result
	func facility_quote(world: WorldState, facility_id: String, actor_id: String, staff_ids: Array = []) -> Dictionary:
		var started: int = Time.get_ticks_usec()
		_facility_depth += 1
		var result: Dictionary = super.facility_quote(world,facility_id,actor_id,staff_ids)
		_facility_depth -= 1
		timing.count("space.facility_quote",started)
		return result
	func _floor_route(world: WorldState, actor: Dictionary, floor_id: int, start: Vector2i, goal: Vector2i, members: Array = [], offsets: Dictionary = {}, ignore_people: bool = false, navigation: Dictionary = {}) -> Dictionary:
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = super._floor_route(world,actor,floor_id,start,goal,members,offsets,ignore_people,navigation)
		timing.count("space.facility_exit_route" if _facility_depth>0 else "space.floor_route",started)
		return result
	func _exit_witness(world: WorldState, actor: Dictionary, floor_id: int, start: Vector2i, exit: Vector2i) -> Dictionary:
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = super._exit_witness(world,actor,floor_id,start,exit)
		timing.count("space.exit_witness",started)
		return result

class TimedNavigation extends NavigationCache:
	var timing: RefCounted
	var _seen_graphs: Dictionary = {}
	func _init(observer: RefCounted) -> void:
		timing = observer
	func graph(space: HospitalSpace, world: WorldState, floor_id: int, actor: Dictionary, members: Array, offsets: Dictionary) -> FloorNavigation:
		var started: int = Time.get_ticks_usec()
		var result: FloorNavigation = super.graph(space,world,floor_id,actor,members,offsets)
		var id: int = result.get_instance_id()
		timing.count("navigation.graph_new" if not _seen_graphs.has(id) else "navigation.graph_reuse_or_refresh",started)
		_seen_graphs[id] = true
		timing.count("navigation.graph",started)
		return result
	func _trim(target: int) -> void:
		var started: int = Time.get_ticks_usec()
		super._trim(target)
		timing.count("navigation.trim",started)
	func _distance_field(graph: FloorNavigation, query: RouteClearance, goal: Vector2i) -> Dictionary:
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = super._distance_field(graph,query,goal)
		timing.count("navigation.distance_field",started)
		return result
