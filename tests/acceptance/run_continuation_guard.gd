extends SceneTree
const Reference=preload("res://tests/acceptance/continuation_original.gd")
var output: String
var report: Dictionary={"passed":true,"cases":[],"timings":[],"inputs":[],"coverage":{},"missing":[]}
var sink: bool=false
func _initialize() -> void: call_deferred("_run")
func _finish(reason: String="") -> void:
	if not reason.is_empty(): report.passed=false;report.reason=reason
	var file: FileAccess=FileAccess.open(output,FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(report,"\t"));file.close()
	quit(0 if report.passed else 2)
func _check(source_name: String, id: String, movement: Dictionary, connector: String, unit: bool, measure: bool, queue_owner: bool) -> void:
	var before: PackedByteArray=var_to_bytes(movement)
	var path_ref: Array=movement.get("path",[])
	var waypoint_ref: Dictionary=movement.get("route_waypoint",{})
	var continuation_ref: Array=waypoint_ref.get("continuation",[])
	var expected: bool=not Reference._continuation(movement,connector).is_empty()
	var actual: bool=LiftLandingQueue._has_continuation(movement,connector)
	var same: bool=expected==actual and before==var_to_bytes(movement)
	var label: String=("hit" if expected else "miss")+("/waypoint" if waypoint_ref.has("continuation") else "/path")
	if not unit: report.coverage[label]=int(report.coverage.get(label,0))+1
	report.passed=report.passed and same
	report.cases.append({"input":source_name,"actor":id,"connector":connector,"synthetic_unit":unit,"same":same,"queue_owner":queue_owner,"stratum":label,"path_length":path_ref.size(),"cursor":movement.get("cursor",0),"continuation_length":continuation_ref.size(),"measured":measure})
	if measure:
		for batch: int in 8:
			var order: Array=[true,false] if batch%2==0 else [false,true]
			for reference: bool in order:
				var started: int=Time.get_ticks_usec()
				if reference:
					for i: int in 1000: sink=not Reference._continuation(movement,connector).is_empty()
				else:
					for i: int in 1000: sink=LiftLandingQueue._has_continuation(movement,connector)
				var elapsed: int=Time.get_ticks_usec()-started
				report.passed=report.passed and sink==expected
				report.timings.append({"input":source_name,"actor":id,"connector":connector,"stratum":label,"queue_owner":queue_owner,"batch":batch,"reference":reference,"calls":1000,"elapsed_us":elapsed,"same_last_result":sink==expected})
	var identities: bool=(not movement.has("path") or is_same(path_ref,movement.path)) and (not movement.has("route_waypoint") or is_same(waypoint_ref,movement.route_waypoint)) and (not waypoint_ref.has("continuation") or is_same(continuation_ref,waypoint_ref.continuation))
	report.passed=report.passed and identities and before==var_to_bytes(movement)
	report.cases[-1]["input_reference_identity_preserved"]=identities
func _run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()<2: quit(2);return
	output=args[0]
	var content: HospitalContent=HospitalContent.new()
	for index: int in range(1,args.size()):
		var file: FileAccess=FileAccess.open(args[index],FileAccess.READ)
		if file==null: _finish("Missing input");return
		var envelope: Variant=file.get_var(false);file.close()
		if not envelope is Dictionary: _finish("Invalid envelope");return
		var facts: Variant=envelope.get("facts",envelope)
		if not facts is Dictionary or not facts.has("moves") or not facts.has("connectors"): _finish("Missing facts");return
		var sim: HospitalSimulation=HospitalSimulation.new(WorldState.new(facts.duplicate(true)),content)
		var error: String=sim.world.validate(content)
		if not error.is_empty(): sim.dispose();_finish(error);return
		var before: Dictionary=sim.world.freeze()
		var sampled: Dictionary={}
		for connector_id: String in sim.world.ids("connectors"):
			var connector: Dictionary=sim.world.facts.connectors[connector_id]
			if content.definition("vertical_connectors",connector.definition_id).kind!="lift": continue
			var registered: Dictionary={}
			for line: Array in connector.get("landing_queues",{}).values():
				for entry: Dictionary in line:
					for owner: String in entry.get("leader_ids",[entry.actor_id]): registered[owner]=true
			# Actual queue owners first; remaining actual movements are separate strata.
			var owners: Array=registered.keys()
			for id: String in sim.world.ids("moves"):
				if not registered.has(id): owners.append(id)
			for id: String in owners:
				if not sim.world.facts.moves.has(id): continue
				var movement: Dictionary=sim.world.facts.moves[id]
				var expected: bool=not Reference._continuation(movement,connector_id).is_empty()
				var label: String=("queued/" if registered.has(id) else "other/")+("hit" if expected else "miss")+("/waypoint" if movement.get("route_waypoint",{}).has("continuation") else "/path")
				var measure: bool=int(sampled.get(label,0))<4
				if measure: sampled[label]=int(sampled.get(label,0))+1
				_check(args[index],id,movement,connector_id,false,measure,registered.has(id))
		var unchanged: bool=before==sim.world.freeze()
		report.passed=report.passed and unchanged
		report.inputs.append({"input":args[index],"sha256":FileAccess.get_sha256(args[index]),"world_unchanged":unchanged,"sampled":sampled})
		sim.dispose()
	# Synthetic semantic checks are untimed and never actual workload coverage.
	var path: Array=[{"kind":"floor"},{"kind":"connector","connector_id":"other"},{"kind":"floor"},{"kind":"connector","connector_id":"wanted"},{"kind":"connector","connector_id":"wanted"}]
	for cursor: int in [-20,-5,-4,-2,-1,0,1,3,4,5,20]:
		_check("unit:cursor",str(cursor),{"path":path,"cursor":cursor},"wanted",true,false,false)
		_check("unit:waypoint_priority",str(cursor),{"path":path,"cursor":cursor,"route_waypoint":{"continuation":path}},"wanted",true,false,false)
	_check("unit:empty_waypoint","",{"path":path,"route_waypoint":{"continuation":[]}},"wanted",true,false,false)
	_check("unit:empty_move","",{},"wanted",true,false,false)
	_check("unit:no_match","",{"path":path},"absent",true,false,false)
	for label: String in ["hit/path","hit/waypoint","miss/path","miss/waypoint"]:
		if not report.coverage.has(label): report.missing.append(label)
	report.scope="Exact original continuation+is_empty versus existence-only guard. Actual snapshot movement/connector inputs, queue membership marked; not proof release was invoked there. Warm alternating local batches, result/bytes/reference identities outside clock; synthetic semantic checks untimed. Publication function remains byte-identical; no full-scene savings claim."
	_finish()
