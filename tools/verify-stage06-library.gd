extends SceneTree

var _checks: Dictionary = {}
var _guard: RefCounted

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not "Stage06 验收" in OS.get_user_data_dir():
		push_error("Library verification requires an isolated Stage06 验收 profile")
		quit(2)
		return
	_guard = ClassDB.instantiate("PlatformSessionGuard") as RefCounted
	_check("exclusive_guard",_guard.call("acquire").ok)
	var content: HospitalContent = HospitalContent.new()
	var snapshots: HospitalSnapshots = HospitalSnapshots.new(content,_guard)
	var library: HospitalLibrary = HospitalLibrary.new(content,snapshots)
	var hospital_id: String = HospitalSnapshots.uuid()
	var world: WorldState = FeasibilityHospitals.create(hospital_id,false,content)
	world.facts.display_name = hospital_id+":display-text"
	var original_actor: Dictionary = world.facts.actors.sample_S21
	world.facts.actors.erase("sample_S21")
	original_actor.id = hospital_id+":sample"
	original_actor.name = hospital_id+":sample"
	world.facts.actors[original_actor.id] = original_actor
	var created: Dictionary = library.create(world,"library-verification")
	var receipt: Dictionary = snapshots.wait_for_idle() if created.ok else created
	_check("new_hospital_initial_commit",receipt.ok)
	if not receipt.ok:
		print(receipt)
		_finish()
		return
	_check("create_never_overwrites_existing",not library.create(world,"another-session").ok)
	var page: Dictionary = library.scan_page({},1,hospital_id)
	var found: bool = false
	while page.ok:
		for card: Dictionary in page.records:
			if card.hospital_id==hospital_id:
				found = not card.world_verified and card.snapshot_id==receipt.snapshot_id
		if page.done:
			break
		page = library.scan_page(page.cursor,1,hospital_id)
	_check("paged_frozen_summaries",found)
	var old_cursor: Dictionary = page.cursor
	library.cancel_scan()
	_check("cancelled_scan_cannot_publish",not library.scan_page(old_cursor,1,hospital_id).ok)
	_check("continue_exact_world",library.continue_hospital(hospital_id).world.facts==world.facts)
	_check("last_valid_slot_protected",not library.delete_slot(hospital_id,receipt.snapshot_id).ok)
	var directory: String = "user://library-verification/"+HospitalSnapshots.uuid()
	DirAccess.make_dir_recursive_absolute(directory)
	var backup: String = directory.path_join("hospital.oghbackup")
	var exported: Dictionary = library.export_backup(hospital_id,receipt.snapshot_id,backup)
	_check("closed_database_export",exported.ok and FileAccess.file_exists(backup) and not library.busy())
	if not exported.ok:
		print(exported)
		_finish()
		return
	var zip: HospitalBackupZip = HospitalBackupZip.new()
	var inspected: Dictionary = zip.inspect(backup)
	_check("restricted_zip_directory",inspected.ok and inspected.entries.size()==2 and inspected.entries["hospital.sqlite3"].method==0)
	var imported: Dictionary = library.import_backup(backup)
	_check("import_commits_new_identity",imported.ok and imported.hospital_id!=hospital_id and snapshots.load_commit(hospital_id,receipt.snapshot_id).ok)
	if imported.ok:
		_check("typed_instance_ids_remapped",imported.world.facts.actors.has(imported.hospital_id+":sample") and not imported.world.facts.actors.has(hospital_id+":sample"))
		_check("text_and_definitions_preserved",imported.world.facts.display_name==world.facts.display_name and imported.world.facts.actors[imported.hospital_id+":sample"].name==original_actor.name and imported.world.facts.rng==world.facts.rng and imported.world.facts.ledger==world.facts.ledger)
	var reader: ZIPReader = ZIPReader.new()
	reader.open(backup)
	var manifest: PackedByteArray = reader.read_file("manifest.json")
	var database: PackedByteArray = reader.read_file("hospital.sqlite3")
	reader.close()
	var deflated: String = directory.path_join("deflated.oghbackup")
	_pack(deflated,[{"name":"manifest.json","raw":manifest},{"name":"hospital.sqlite3","raw":database}])
	var deflate_import: Dictionary = library.import_backup(deflated)
	_check("deflate_stream_import",deflate_import.ok)
	var unsafe: String = directory.path_join("unsafe.oghbackup")
	_pack(unsafe,[{"name":"manifest.json","raw":manifest},{"name":"hospital.sqlite3","raw":database},{"name":"../escape","raw":PackedByteArray([1])}])
	_check("rejects_path_escape",not library.import_backup(unsafe).ok)
	var duplicate: String = directory.path_join("duplicate.oghbackup")
	_pack(duplicate,[{"name":"manifest.json","raw":manifest},{"name":"hospital.sqlite3","raw":database},{"name":"manifest.json","raw":manifest}])
	_check("rejects_duplicate_entries",not library.import_backup(duplicate).ok)
	var tampered: String = directory.path_join("tampered.oghbackup")
	var raw: PackedByteArray = FileAccess.get_file_as_bytes(backup)
	raw[int(inspected.entries["hospital.sqlite3"].data_offset)+100] ^= 1
	HospitalSnapshots._store(tampered,raw)
	_check("rejects_actual_byte_corruption",not library.import_backup(tampered).ok and library.continue_hospital(hospital_id).ok)
	var central: int = -1
	var pristine: PackedByteArray = FileAccess.get_file_as_bytes(backup)
	for position: int in range(pristine.size()-46,-1,-1):
		if pristine.decode_u32(position)==0x02014b50:
			central = position
			break
	var encrypted: PackedByteArray = pristine.duplicate()
	encrypted.encode_u16(central+8,1)
	var encrypted_path: String = directory.path_join("encrypted.oghbackup")
	HospitalSnapshots._store(encrypted_path,encrypted)
	_check("rejects_encrypted_entries",not library.import_backup(encrypted_path).ok)
	var symlink: PackedByteArray = pristine.duplicate()
	symlink.encode_u32(central+38,40960<<16)
	var symlink_path: String = directory.path_join("symlink.oghbackup")
	HospitalSnapshots._store(symlink_path,symlink)
	_check("rejects_symlink_entries",not library.import_backup(symlink_path).ok)
	var changed: Dictionary = JSON.parse_string(manifest.get_string_from_utf8())
	changed.database_sha256 = "0".repeat(64)
	var mismatch: String = directory.path_join("hash-mismatch.oghbackup")
	_pack(mismatch,[{"name":"manifest.json","raw":JSON.stringify(changed).to_utf8_buffer()},{"name":"hospital.sqlite3","raw":database}])
	_check("rejects_database_sha_mismatch",not library.import_backup(mismatch).ok)
	changed = JSON.parse_string(manifest.get_string_from_utf8())
	changed.schema_version = 2
	var future: String = directory.path_join("future-format.oghbackup")
	_pack(future,[{"name":"manifest.json","raw":JSON.stringify(changed).to_utf8_buffer()},{"name":"hospital.sqlite3","raw":database}])
	_check("future_format_keeps_existing_world",not library.import_backup(future).ok and library.continue_hospital(hospital_id).world.facts==world.facts)
	var bomb: String = directory.path_join("ratio.oghbackup")
	var zeros: PackedByteArray = PackedByteArray()
	zeros.resize(65536)
	_pack(bomb,[{"name":"manifest.json","raw":manifest},{"name":"hospital.sqlite3","raw":zeros}])
	_check("rejects_over_200_to_one",not library.import_backup(bomb).ok)
	_check("active_hospital_delete_rejected",not library.trash_hospital(hospital_id,hospital_id).ok)
	var trashed: Dictionary = library.trash_hospital(hospital_id,"other")
	_check("delete_is_same_volume_recycle",trashed.ok and not hospital_id in snapshots.hospital_ids())
	var recycled: Dictionary = library.scan_page({},32,hospital_id,true)
	_check("recycle_list_has_original_identity",recycled.ok and recycled.records.size()==1 and recycled.records[0].hospital_id==hospital_id and not recycled.records[0].cleanup_due)
	var restored: Dictionary = library.restore_hospital(hospital_id)
	_check("recycle_restore_preserves_world",restored.ok and library.continue_hospital(hospital_id).world.facts==world.facts)
	world.touch()
	snapshots.begin(world,"library-verification","manual","2")
	var second: Dictionary = snapshots.wait_for_idle()
	_check("manual_slots_share_writer",second.ok and library.slots(hospital_id).records.size()==2)
	_check("delete_selected_slot_keeps_survivor",library.delete_slot(hospital_id,second.snapshot_id).ok and snapshots.load_commit(hospital_id,receipt.snapshot_id).ok)
	var image: Image = Image.create(8,8,false,Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	_check("thumbnail_checked_before_decode",HospitalLibrary.thumbnail_valid(image.save_png_to_buffer()) and not HospitalLibrary.thumbnail_valid(zeros))
	var new_identity: String = HospitalSnapshots.uuid()
	var instance: String = hospital_id+":typed"
	var remapped: Dictionary = library._remap_hospital({"hospital_id":hospital_id,"actors":{instance:{"id":instance,"name":instance,"species_id":instance}},"notes":{instance:"text"},"connector":{"riders":[instance]},"ledger":{"entries":{instance+":fee":{"owner_id":instance,"component":"fee"}}}},hospital_id,new_identity)
	_check("remap_only_typed_identity_fields",remapped.actors.has(new_identity+":typed") and remapped.actors[new_identity+":typed"].species_id==instance and remapped.notes.has(instance) and remapped.connector.riders==[new_identity+":typed"] and remapped.ledger.entries.has(new_identity+":typed:fee"))
	_finish()

func _pack(path: String,entries: Array) -> void:
	var writer: ZIPPacker = ZIPPacker.new()
	writer.open(path)
	for entry: Dictionary in entries:
		writer.start_file(entry.name)
		writer.write_file(entry.raw)
		writer.close_file()
	writer.close()

func _check(name: String,condition: bool) -> void:
	_checks[name] = condition
	if not condition:
		push_error(name)

func _finish() -> void:
	var ok: bool = not _checks.values().has(false)
	print(JSON.stringify({"stage":6,"ok":ok,"checks":_checks,"performance":"skipped"},"",true))
	_guard.call("release")
	quit(0 if ok else 1)
