extends SceneTree

const Structure = preload("res://game/building/room_structure.gd")

func _initialize() -> void:
	call_deferred("_run")

func _hash(value: Variant) -> String:
	var digest: HashingContext=HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(var_to_bytes(value))
	return digest.finish().hex_encode()

func _run() -> void:
	var output: String=""
	var label: String=""
	var repeats: int=3
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output=argument.trim_prefix("--output=")
		if argument.begins_with("--variant="): label=argument.trim_prefix("--variant=")
		if argument.begins_with("--repeats="): repeats=argument.trim_prefix("--repeats=").to_int()
	var identity: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://build-prepare-identity.json"))
	if output.is_empty() or label.is_empty() or repeats<=0 or FileAccess.file_exists(output) or not identity is Dictionary or identity.get("instrumented",true):
		push_error("Use a plain frozen project, variant label and new output path.")
		quit(2)
		return
	var policy: Dictionary={"applied":false,"reason":"platform_default"}
	if OS.get_name()=="Windows" and ClassDB.class_exists("PlatformThreadPolicy"): policy=ClassDB.class_call_static("PlatformThreadPolicy","apply_main_thread")
	var plots: Dictionary={}
	for y: int in 3:
		for x: int in 3: plots[Vector2i(x,y)]=true
	var rows: Array=[]
	for repeat: int in repeats:
		for kind: String in ["85x95","96x95","auxiliary8x8"]:
			var auxiliary: bool=kind=="auxiliary8x8"
			var draft: Dictionary={"origin":[16,82] if auxiliary else [0,0],"size":[8,8] if auxiliary else [85 if kind=="85x95" else 96,95]}
			var before: PackedByteArray=var_to_bytes(draft)
			var started: int=Time.get_ticks_usec()
			var shape: Dictionary=BuildGeometry.shape(draft)
			var shape_elapsed: int=Time.get_ticks_usec()-started
			if not shape.get("ok",false) or before!=var_to_bytes(draft):
				push_error("Shape contract failed.")
				quit(2)
				return
			rows.append({"case":kind,"repeat":repeat+1,"operation":"shape","elapsed_usec":shape_elapsed,"complete_hash":_hash(shape),"cells":shape.cells.size(),"walls":shape.wall_edges.size()})
			var edges: Array=shape.wall_edges.duplicate(true)
			if auxiliary:
				for index: int in 16: edges.append_array(BuildGeometry.room_walls({"origin":[5+index%4*22,5+int(index/4)*22],"size":[8,8]}))
			var barriers: Dictionary=Structure.units(edges)
			var visited: Dictionary={}
			var starts: Array=[Vector2i(int(draft.origin[0]),int(draft.origin[1])),Vector2i(0,0) if auxiliary else (Vector2i(85,0) if kind=="85x95" else Vector2i(0,95))]
			for start: Vector2i in starts:
				started=Time.get_ticks_usec()
				var component: Dictionary=Structure._component(start,plots,barriers,visited)
				var component_elapsed: int=Time.get_ticks_usec()-started
				rows.append({"case":kind,"repeat":repeat+1,"operation":"closed_component" if component.closed else "open_component","elapsed_usec":component_elapsed,"complete_hash":_hash([component,visited]),"cells":component.cells.size(),"points":component.points.size(),"visited":visited.size(),"closed":component.closed})
	var result: Dictionary={"complete":true,"variant":label,"scope":"Plain complete geometry operations only. No world actors are advanced or removed; this is neither a 640-person preview nor a 160-person simulation acceptance.","main_thread_policy":policy,"geometry_reference":identity.get("geometry_reference"),"repeats":repeats,"samples":rows}
	var file: FileAccess=FileAccess.open(output,FileAccess.WRITE)
	if file==null:
		push_error("Cannot write local geometry result.")
		quit(2)
		return
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	print("BUILD_GEOMETRY_PROBE="+JSON.stringify({"variant":label,"samples":rows.size(),"output":output}))
	quit(0)
