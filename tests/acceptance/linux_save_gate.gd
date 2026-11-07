extends SceneTree

# A real product guard controls the real snapshot admission gate. This test never
# invents an allowance. Successful full save/restore is explicitly skipped when
# the executor cannot prove its effective resource limit.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var content: HospitalContent = HospitalContent.new()
	var guard: RefCounted = ClassDB.instantiate("PlatformSessionGuard")
	var acquired: Dictionary = guard.acquire()
	if not content.error.is_empty() or not acquired.ok:
		print("SAVE_GATE_RESULT="+JSON.stringify({"ok":false,"error":content.error,"acquired":acquired}))
		quit(1); return
	var resource: Dictionary = guard.get_resource_status()
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"Linux存档预算边界",false,content)
	var store: HospitalSnapshots = HospitalSnapshots.new(content,guard)
	var original: Dictionary = world.freeze()
	if resource.ok:
		print("SAVE_GATE_RESULT="+JSON.stringify({"ok":true,"scope":"Resource budget available; run CORE-18 through CORE-29 and CORE-46 for full save acceptance.","rejection_test":"not_applicable","resource":resource}))
		guard.release(); quit(0); return
	var result: Dictionary = store.begin(world,"linux-resource-safety")
	var unchanged: bool = world.freeze() == original
	var no_database: bool = not FileAccess.file_exists(HospitalSnapshots.ROOT.path_join(world.hospital_id).path_join(HospitalSnapshots.DATABASE_NAME))
	var passed: bool = not result.ok and not store.busy() and unchanged and no_database
	print("SAVE_GATE_RESULT="+JSON.stringify({"ok":passed,"resource":resource,"save_result":result,"world_unchanged":unchanged,"no_database_created":no_database,"worker_not_started":not store.busy(),"scope":"Actual save safely refused; successful save/restore remains blocked by effective-memory visibility."}))
	guard.release()
	quit(0 if passed else 1)
