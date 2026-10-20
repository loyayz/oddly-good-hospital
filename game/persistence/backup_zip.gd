class_name HospitalBackupZip
extends RefCounted

const BLOCK: int = 32768

func inspect(path: String) -> Dictionary:
	var native: RefCounted = _native()
	if native==null:
		return _failure("备份ZIP原生库不可用")
	var result: Dictionary = native.call("inspect",ProjectSettings.globalize_path(path))
	if result.ok:
		result.path = path
	return result

func extract(archive: Dictionary, name: String, sink: Callable, budget: Callable, cancelled: Callable = Callable()) -> Dictionary:
	if not archive.get("ok",false) or not archive.entries.has(name):
		return _failure("备份条目不存在")
	var native: RefCounted = _native()
	if native==null:
		return _failure("备份ZIP原生库不可用")
	var entry: Dictionary = archive.entries[name]
	var result: Dictionary = native.call("open_read",ProjectSettings.globalize_path(archive.path),name,int(archive.bytes),entry)
	if not result.ok:
		return result
	var bytes: int = 0
	var hash: HashingContext = HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	while true:
		if cancelled.is_valid() and cancelled.call():
			result = _failure("备份操作已取消")
			break
		if not budget.call(maxi(int(entry.unpacked),bytes)):
			result = _failure("备份读取所需内存或磁盘不足")
			break
		result = native.call("read_chunk")
		if not result.ok or result.done:
			break
		var raw: PackedByteArray = result.raw
		result = sink.call(raw)
		if not result.get("ok",false):
			break
		bytes += raw.size()
		hash.update(raw)
	native.call("close")
	if not result.ok:
		return result
	return {"ok":true,"bytes":bytes,"sha256":hash.finish().hex_encode()}

func read_manifest(archive: Dictionary, budget: Callable) -> Dictionary:
	var chunks: Array[PackedByteArray] = []
	var result: Dictionary = extract(archive,"manifest.json",func(raw:PackedByteArray) -> Dictionary: chunks.append(raw); return {"ok":true},budget)
	if not result.ok:
		return result
	var bytes: PackedByteArray = PackedByteArray()
	for chunk: PackedByteArray in chunks:
		bytes.append_array(chunk)
	var parser: JSON = JSON.new()
	if parser.parse(bytes.get_string_from_utf8())!=OK or not parser.data is Dictionary:
		return _failure("备份清单JSON无效")
	return {"ok":true,"manifest":parser.data}

func file_info(path: String, budget: Callable) -> Dictionary:
	var file: FileAccess = FileAccess.open(path,FileAccess.READ)
	if file==null:
		return _failure("无法读取备份数据库")
	var native: RefCounted = _native()
	if native==null:
		return _failure("备份ZIP原生库不可用")
	var length: int = file.get_length()
	var hash: HashingContext = HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	var crc: int = 0
	while file.get_position()<length:
		if not budget.call(length):
			return _failure("备份所需资源不足")
		var raw: PackedByteArray = file.get_buffer(mini(BLOCK,length-file.get_position()))
		if raw.is_empty():
			return _failure("备份数据库读取中断")
		hash.update(raw)
		var checked: Dictionary = native.call("crc32",raw,crc)
		if not checked.ok:
			return checked
		crc = checked.crc
	if file.get_length()!=length:
		return _failure("备份数据库实际长度已改变")
	file.close()
	return {"ok":true,"bytes":length,"sha256":hash.finish().hex_encode(),"crc":crc}

func write(destination: String, manifest: PackedByteArray, database_path: String, database_info: Dictionary, budget: Callable, cancelled: Callable = Callable()) -> Dictionary:
	if not destination.to_lower().ends_with(".oghbackup") or FileAccess.file_exists(destination):
		return _failure("请选择尚不存在的.oghbackup文件")
	if manifest.size()>65536:
		return _failure("备份清单超过64KiB")
	var native: RefCounted = _native()
	if native==null:
		return _failure("备份ZIP原生库不可用")
	var temporary: String = destination+".pending-"+HospitalSnapshots.uuid()
	var result: Dictionary = native.call("open_write",ProjectSettings.globalize_path(temporary))
	var manifest_crc: Dictionary = native.call("crc32",manifest,0)
	if not manifest_crc.ok:
		result = manifest_crc
	var entries: Array[Dictionary] = [{"name":"manifest.json","bytes":manifest.size(),"crc":manifest_crc.get("crc",0),"raw":manifest},
		{"name":"hospital.sqlite3","bytes":database_info.bytes,"crc":database_info.crc,"path":database_path}]
	for entry: Dictionary in entries:
		if not result.ok:
			break
		result = native.call("begin_entry",str(entry.name),int(entry.bytes))
		var input: FileAccess = null if entry.has("raw") else FileAccess.open(entry.path,FileAccess.READ)
		if not entry.has("raw") and (input==null or input.get_length()!=int(entry.bytes)):
			result = _failure("独立备份数据库无法读取或实际长度已改变")
		var offset: int = 0
		while result.ok and offset<int(entry.bytes):
			if not budget.call(entry.bytes) or (cancelled.is_valid() and cancelled.call()):
				result = _failure("备份取消或目标资源不足")
				break
			var amount: int = mini(BLOCK,int(entry.bytes)-offset)
			var raw: PackedByteArray = entry.raw.slice(offset,offset+amount) if entry.has("raw") else input.get_buffer(amount)
			if raw.size()!=amount:
				result = _failure("独立备份数据库读取中断")
				break
			result = native.call("write_chunk",raw)
			offset += raw.size()
		if input!=null:
			if input.get_length()!=int(entry.bytes):
				result = _failure("备份数据库实际长度已改变")
			input.close()
		if result.ok:
			result = native.call("end_entry",int(entry.crc))
	if result.ok:
		result = native.call("finish_write")
	native.call("close")
	if result.ok:
		result = inspect(temporary)
	if result.ok and not FileAccess.file_exists(destination) and DirAccess.rename_absolute(temporary,destination)==OK:
		return {"ok":true,"path":destination}
	DirAccess.remove_absolute(temporary)
	return _failure("备份无法完成："+str(result.get("error","无法发布备份文件")))

static func _native() -> RefCounted:
	return ClassDB.instantiate("PlatformBackupZip") as RefCounted if ClassDB.class_exists("PlatformBackupZip") else null

static func _failure(message: String) -> Dictionary:
	return {"ok":false,"error":message}
