extends RefCounted

func run(t, content: HospitalContent) -> void:
	var guard: RefCounted = ClassDB.instantiate("PlatformSessionGuard")
	var acquired: Dictionary = guard.call("acquire")
	if not acquired.ok:
		t.check("CORE-46",false,acquired)
		return
	var store: HospitalSnapshots = HospitalSnapshots.new(content,guard)
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"旧保存点校验",false,content)
	var receipts: Array = []
	var correct: bool = true
	for index: int in 5:
		var begun: Dictionary = store.begin(world,"cleanup-proof","manual","1")
		var receipt: Dictionary = store.wait_for_idle() if begun.ok else begun
		correct = correct and receipt.ok
		receipts.append(receipt)
		if not receipt.ok: break
	if correct:
		var retained: Array = store.list_commits(world.hospital_id)
		correct = retained.size()==3
		var bad_id: String = receipts[3].snapshot_id
		var opened: Dictionary = store._connect(world.hospital_id)
		correct = correct and opened.ok
		if opened.ok:
			var database: RefCounted = opened.database
			var corrupted: Dictionary = database.call("execute","UPDATE world_chunks SET data=? WHERE snapshot_id=? AND chunk_index=0",[PackedByteArray([123,125]),bad_id])
			database.call("close")
			correct = correct and corrupted.ok and not store.load_commit(world.hospital_id,bad_id).ok
		var begun: Dictionary = store.begin(world,"cleanup-proof","manual","1")
		var last: Dictionary = store.wait_for_idle() if begun.ok else begun
		correct = correct and last.ok
		# Bad old data is neither counted as a fallback nor removed as if it
		# were a verified obsolete commit. The older valid fallback survives.
		correct = correct and store.load_commit(world.hospital_id,receipts[2].snapshot_id).ok
		correct = correct and store.load_commit(world.hospital_id,receipts[4].snapshot_id).ok
		correct = correct and not store.load_commit(world.hospital_id,bad_id).ok
		var listed: Array = store.list_commits(world.hospital_id)
		var bad_preserved: bool = false
		for record: Dictionary in listed:
			if record.snapshot_id==bad_id: bad_preserved = true
		correct = correct and bad_preserved and listed.size()==4
	guard.call("release")
	t.check("CORE-46",correct,{"real_commits":receipts.size()+1,"valid_fallback_preserved":correct,"bad_old_commit_not_trusted":correct})
