extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var content: HospitalContent=HospitalContent.new()
	var rows: Dictionary={}
	var started: int=Time.get_ticks_usec()
	for name: String in ["local_return_geometry","local_only_movement","clinical_exit_local_move","floor_guidance"]:
		var begin: int=Time.get_ticks_usec()
		var suite: RefCounted=load("res://tests/acceptance/"+name+".gd").new()
		var result: Dictionary
		match name:
			"local_only_movement": result=suite.run_local(content)
			"clinical_exit_local_move": result=suite.run_exit_cases(content)
			"floor_guidance": result=suite.run_cases(content,["GUIDE-REAL-ARRIVAL","GUIDE-NURSE-RECOVERY","GUIDE-SAME-FLOOR-NEW-STAGE"])
			_: result=suite.run(content)
		rows[name]={"elapsed_us":Time.get_ticks_usec()-begin,"result":result}
		print("REGRESSION "+name+" "+str(result.ok))
	var ok: bool=true
	for row: Dictionary in rows.values(): ok=ok and row.result.ok
	var output: Dictionary={"ok":ok,"elapsed_us":Time.get_ticks_usec()-started,"groups":rows}
	FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(output,"\t"))
	quit(0 if ok else 1)
