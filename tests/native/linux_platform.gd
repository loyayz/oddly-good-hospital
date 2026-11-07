extends SceneTree

# Tests actual native APIs against an isolated profile selected by the runner.
# No memory/resource override or fake native object is provided.
const ID: String = "11111111-1111-4111-8111-111111111111"
var checks: Dictionary = {}
var guard: RefCounted

func _initialize() -> void:
	GDExtensionManager.load_extension("res://game/platform/windows/oddly_good_platform.gdextension")
	call_deferred("run")

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var mode: String = args[0] if not args.is_empty() else "all"
	for name: String in ["PlatformSessionGuard","PlatformSQLite","PlatformJsonNumbers","PlatformArrivalMath","PlatformArrivalCapacity","PlatformSpatialIndex","PlatformRouteQueue","PlatformJsonStream","PlatformBackupZip"]:
		checks["class:"+name] = ClassDB.class_exists(name)
	if false in checks.values(): finish(); return
	guard = ClassDB.instantiate("PlatformSessionGuard")
	var initial: Dictionary = guard.get_resource_status()
	checks.no_unowned_budget = not initial.ok and initial.available_physical_bytes == 0 and initial.available_disk_bytes == 0
	var unowned: RefCounted = ClassDB.instantiate("PlatformSQLite")
	checks.no_unowned_database = not unowned.open(ID,true).ok
	var acquired: Dictionary = guard.acquire()
	if mode == "contend":
		checks.busy = not acquired.ok and acquired.busy
		finish(); return
	if mode == "guard_denied":
		checks.non_regular_guard_refused = not acquired.ok and not acquired.busy
		finish(); return
	checks.acquire = acquired.ok
	if not acquired.ok: finish(); return
	checks.repeated_acquire = guard.acquire().ok
	if mode == "hold":
		print("PLATFORM_READY=hold")
		return
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir().path_join("hospitals").path_join(ID))
	var db: RefCounted = ClassDB.instantiate("PlatformSQLite")
	var opened: Dictionary = db.open(ID,true)
	checks.sqlite_open = opened.ok and opened.get("version","") == "3.54.0"
	if not opened.ok: finish(); return
	checks.sqlite_create = db.execute("CREATE TABLE IF NOT EXISTS linux_platform_probe (id INTEGER PRIMARY KEY, text TEXT, integer_value INTEGER, real_value REAL, blob BLOB)",[]).ok
	if mode == "transaction":
		checks.begin = db.execute("BEGIN IMMEDIATE",[]).ok
		checks.uncommitted = db.execute("INSERT INTO linux_platform_probe(id,text) VALUES(99,'not committed')",[]).ok
		if false in checks.values(): db.close(); finish(); return
		# Keep the actual SQLite connection alive until controller kills this process.
		set_meta("held_database",db)
		print("PLATFORM_READY=transaction")
		return
	if mode == "recovery":
		var recovered: Dictionary = db.execute("SELECT id FROM linux_platform_probe ORDER BY id",[])
		checks.crash_transaction_rolled_back = recovered.ok and recovered.rows.size() == 1 and recovered.rows[0].id == 1
		db.close(); finish(); return
	checks.sqlite_clear = db.execute("DELETE FROM linux_platform_probe",[]).ok
	var number: Dictionary = ClassDB.class_call_static("PlatformJsonNumbers","decode_decimal","99.52000000000027")
	var bytes: PackedByteArray = PackedByteArray([0,255,1,128])
	checks.sqlite_insert = db.execute("INSERT INTO linux_platform_probe VALUES(1,?,?,?,?)",["中文路径 空格",9223372036854775807,number.value,bytes]).ok
	var selected: Dictionary = db.execute("SELECT * FROM linux_platform_probe",[])
	checks.sqlite_types = selected.ok and selected.rows.size() == 1 and selected.rows[0].text == "中文路径 空格" and selected.rows[0].integer_value == 9223372036854775807 and selected.rows[0].blob == bytes and var_to_bytes(selected.rows[0].real_value) == var_to_bytes(number.value)
	checks.sqlite_transaction = db.execute("BEGIN",[]).ok and db.execute("INSERT INTO linux_platform_probe(id) VALUES(2)",[]).ok and db.execute("ROLLBACK",[]).ok
	var rolled: Dictionary = db.execute("SELECT count(*) AS count FROM linux_platform_probe",[])
	checks.sqlite_rollback = rolled.ok and rolled.rows[0].count == 1
	checks.invalid_sql_rejected = not db.execute("SELECT FROM invalid",[]).ok
	checks.after_error_usable = db.execute("SELECT id FROM linux_platform_probe",[]).ok
	db.close()
	checks.sqlite_reopen = db.open(ID,false).ok and db.execute("SELECT id FROM linux_platform_probe",[]).rows.size() == 1
	db.close()
	var other: RefCounted = ClassDB.instantiate("PlatformSessionGuard")
	var contested: Dictionary = other.acquire()
	checks.same_process_exclusivity = not contested.ok and contested.busy
	var resource: Dictionary = guard.get_resource_status()
	checks.resource_result_is_explicit = (resource.ok and resource.available_physical_bytes >= 0 and resource.available_disk_bytes >= 0) or (not resource.ok and resource.error != 0 and not resource.message.is_empty() and resource.available_physical_bytes == 0 and resource.available_disk_bytes == 0)
	print("RESOURCE_STATUS="+JSON.stringify(resource))
	var fraction: Dictionary = ClassDB.class_call_static("PlatformArrivalMath","fraction",1,{"n":"1","d":"2"},{"n":"1","d":"3"})
	checks.rational = fraction == {"n":"5","d":"6"}
	var decimal_bytes: PackedByteArray = PackedByteArray()
	decimal_bytes.resize(8); decimal_bytes.encode_double(0,number.value)
	checks.decimal = number.ok and decimal_bytes.hex_encode() == "f47a14ae47e15840"
	var cpu: Dictionary = ClassDB.class_call_static("PlatformArrivalMath","thread_cpu")
	var clock: Dictionary = ClassDB.class_call_static("PlatformArrivalMath","monotonic_clock")
	checks.clocks = cpu.get("cpu_us",-1) >= 0 and clock.get("qpc_ticks",0) > 0 and clock.get("qpc_frequency",0) == 1000000000
	guard.release()
	checks.release_recovery = other.acquire().ok
	other.release()
	finish()

func finish() -> void:
	if guard != null: guard.release()
	var passed: bool = not false in checks.values()
	print("PLATFORM_RESULT="+JSON.stringify({"ok":passed,"checks":checks,"user_directory":OS.get_user_data_dir()}))
	quit(0 if passed else 1)
