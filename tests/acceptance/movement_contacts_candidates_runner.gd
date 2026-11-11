extends SceneTree

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=2 or FileAccess.file_exists(args[0]): quit(2);return
	var selected: Array=Array(args[1].split(","))
	var seen: Dictionary={}
	var related: Array[String]=["first_contact","regions_exact","regions_permissions"]
	for id: String in selected:
		if (not id in preload("res://tests/acceptance/movement_contacts_candidates.gd").CASES and not id in related) or seen.has(id): quit(2);return
		seen[id]=true
	var database:=HospitalContent.new()
	var rows: Array=[]
	for id: String in selected:
		var started: int=Time.get_ticks_usec()
		var row: Dictionary
		if id=="first_contact":
			var details: Dictionary=preload("res://tests/acceptance/detour_first_contact.gd").new().run(database)
			row={"id":id,"ok":details.passed,"details":details}
		elif id in ["regions_exact","regions_permissions"]:
			var details: Dictionary=preload("res://tests/acceptance/detour_contact_regions.gd").new().run(database,"exact_candidates" if id=="regions_exact" else "permissions")
			row={"id":id,"ok":details.passed,"details":details}
		else: row=preload("res://tests/acceptance/movement_contacts_candidates.gd").new().run(database,[id]).rows[0]
		row.elapsed_us=Time.get_ticks_usec()-started;rows.append(row)
	var result: Dictionary={"ok":rows.all(func(row: Dictionary)->bool:return row.ok),"rows":rows,"scope":"Selected contact candidate calculations and related existing first-contact/region contracts only."}
	FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify({"ok":result.ok,"rows":result.rows.map(func(row: Dictionary)->Dictionary:return {"id":row.id,"ok":row.ok,"elapsed_us":row.elapsed_us})}))
	quit(0 if result.ok else 1)
