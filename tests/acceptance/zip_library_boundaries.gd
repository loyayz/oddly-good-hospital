extends RefCounted

# Independent Python zipfile/zlib vectors. The database payload is bytes 0..255
# repeated 256 times, followed by zero. Invalid vectors keep ZIP metadata
# consistent while changing CRC or the raw DEFLATE stream boundary.
const VECTORS: Dictionary = {
	"DEFLATED":"UEsDBBQAAAAIAAAAIVBDv6ajBAAAAAIAAAANAAAAbWFuaWZlc3QuanNvbquuBQBQSwMEFAAAAAgAAAAhUBVhYnNDAgAAAQABABAAAABob3NwaXRhbC5zcWxpdGUz7c9DAhgGAACw2rZt27bN1bZt27a51Vpt27Ztu4d+I/lBAgQMFDhI0GDBQ4QMFTpM2HDhI0SMFDlK1GjRY8SMFTtO3HjxEyRMlDhJ0mTJU6RMlTpN2nTpM2TMlDlL1mzZc+TMlTtP3nz5CxQsVLhI0WLFS5QsVbpM2XLlK1SsVLlK1WrVa9T8p1btOnXr1W/QsFHjJk2bNW/RslXrNm3bte/QsVPnLl27de/Rs1fvPn379R8wcNDgIUOHDR8xctToMWPHjZ8wcdLkKVOnTZ8xc9bsOXPnzV+wcNHiJUuXLf/3vxUrV61es3bd+g0bN/2/ecvWbdt37Ny1e8/effsPHDx0+MjRY8dPnDx1+szZc+cvXLx0+crVa9dv3Lx1+87de/cfPHz0+MnTZ89fvHz1+s3bd+8/fPz0+cvXb99//Pz1O4C/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7//3/8fUEsBAhQAFAAAAAgAAAAhUEO/pqMEAAAAAgAAAA0AAAAAAAAAAAAAAIABAAAAAG1hbmlmZXN0Lmpzb25QSwECFAAUAAAACAAAACFQFWFic0MCAAABAAEAEAAAAAAAAAAAAAAAgAEvAAAAaG9zcGl0YWwuc3FsaXRlM1BLBQYAAAAAAgACAHkAAACgAgAAAAA=",
	"BAD_CRC":"UEsDBBQAAAAIAAAAIVBDv6ajBAAAAAIAAAANAAAAbWFuaWZlc3QuanNvbquuBQBQSwMEFAAAAAgAAAAhUBRhYnNDAgAAAQABABAAAABob3NwaXRhbC5zcWxpdGUz7c9DAhgGAACw2rZt27bN1bZt27a51Vpt27Ztu4d+I/lBAgQMFDhI0GDBQ4QMFTpM2HDhI0SMFDlK1GjRY8SMFTtO3HjxEyRMlDhJ0mTJU6RMlTpN2nTpM2TMlDlL1mzZc+TMlTtP3nz5CxQsVLhI0WLFS5QsVbpM2XLlK1SsVLlK1WrVa9T8p1btOnXr1W/QsFHjJk2bNW/RslXrNm3bte/QsVPnLl27de/Rs1fvPn379R8wcNDgIUOHDR8xctToMWPHjZ8wcdLkKVOnTZ8xc9bsOXPnzV+wcNHiJUuXLf/3vxUrV61es3bd+g0bN/2/ecvWbdt37Ny1e8/effsPHDx0+MjRY8dPnDx1+szZc+cvXLx0+crVa9dv3Lx1+87de/cfPHz0+MnTZ89fvHz1+s3bd+8/fPz0+cvXb99//Pz1O4C/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7//3/8fUEsBAhQAFAAAAAgAAAAhUEO/pqMEAAAAAgAAAA0AAAAAAAAAAAAAAIABAAAAAG1hbmlmZXN0Lmpzb25QSwECFAAUAAAACAAAACFQFGFic0MCAAABAAEAEAAAAAAAAAAAAAAAgAEvAAAAaG9zcGl0YWwuc3FsaXRlM1BLBQYAAAAAAgACAHkAAACgAgAAAAA=",
	"TRUNCATED_STREAM":"UEsDBBQAAAAIAAAAIVBDv6ajBAAAAAIAAAANAAAAbWFuaWZlc3QuanNvbquuBQBQSwMEFAAAAAgAAAAhUBVhYnNCAgAAAQABABAAAABob3NwaXRhbC5zcWxpdGUz7c9DAhgGAACw2rZt27bN1bZt27a51Vpt27Ztu4d+I/lBAgQMFDhI0GDBQ4QMFTpM2HDhI0SMFDlK1GjRY8SMFTtO3HjxEyRMlDhJ0mTJU6RMlTpN2nTpM2TMlDlL1mzZc+TMlTtP3nz5CxQsVLhI0WLFS5QsVbpM2XLlK1SsVLlK1WrVa9T8p1btOnXr1W/QsFHjJk2bNW/RslXrNm3bte/QsVPnLl27de/Rs1fvPn379R8wcNDgIUOHDR8xctToMWPHjZ8wcdLkKVOnTZ8xc9bsOXPnzV+wcNHiJUuXLf/3vxUrV61es3bd+g0bN/2/ecvWbdt37Ny1e8/effsPHDx0+MjRY8dPnDx1+szZc+cvXLx0+crVa9dv3Lx1+87de/cfPHz0+MnTZ89fvHz1+s3bd+8/fPz0+cvXb99//Pz1O4C/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7//3/9QSwECFAAUAAAACAAAACFQQ7+mowQAAAACAAAADQAAAAAAAAAAAAAAgAEAAAAAbWFuaWZlc3QuanNvblBLAQIUABQAAAAIAAAAIVAVYWJzQgIAAAEAAQAQAAAAAAAAAAAAAACAAS8AAABob3NwaXRhbC5zcWxpdGUzUEsFBgAAAAACAAIAeQAAAJ8CAAAAAA==",
	"TRAILING_STREAM":"UEsDBBQAAAAIAAAAIVBDv6ajBAAAAAIAAAANAAAAbWFuaWZlc3QuanNvbquuBQBQSwMEFAAAAAgAAAAhUBVhYnNEAgAAAQABABAAAABob3NwaXRhbC5zcWxpdGUz7c9DAhgGAACw2rZt27bN1bZt27a51Vpt27Ztu4d+I/lBAgQMFDhI0GDBQ4QMFTpM2HDhI0SMFDlK1GjRY8SMFTtO3HjxEyRMlDhJ0mTJU6RMlTpN2nTpM2TMlDlL1mzZc+TMlTtP3nz5CxQsVLhI0WLFS5QsVbpM2XLlK1SsVLlK1WrVa9T8p1btOnXr1W/QsFHjJk2bNW/RslXrNm3bte/QsVPnLl27de/Rs1fvPn379R8wcNDgIUOHDR8xctToMWPHjZ8wcdLkKVOnTZ8xc9bsOXPnzV+wcNHiJUuXLf/3vxUrV61es3bd+g0bN/2/ecvWbdt37Ny1e8/effsPHDx0+MjRY8dPnDx1+szZc+cvXLx0+crVa9dv3Lx1+87de/cfPHz0+MnTZ89fvHz1+s3bd+8/fPz0+cvXb99//Pz1O4C/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7//3/8fAFBLAQIUABQAAAAIAAAAIVBDv6ajBAAAAAIAAAANAAAAAAAAAAAAAACAAQAAAABtYW5pZmVzdC5qc29uUEsBAhQAFAAAAAgAAAAhUBVhYnNEAgAAAQABABAAAAAAAAAAAAAAAIABLwAAAGhvc3BpdGFsLnNxbGl0ZTNQSwUGAAAAAAIAAgB5AAAAoQIAAAAA",
	"COMMENT_SIGNATURE":"UEsDBBQAAAAIAAAAIVBDv6ajBAAAAAIAAAANAAAAbWFuaWZlc3QuanNvbquuBQBQSwMEFAAAAAgAAAAhUBVhYnNDAgAAAQABABAAAABob3NwaXRhbC5zcWxpdGUz7c9DAhgGAACw2rZt27bN1bZt27a51Vpt27Ztu4d+I/lBAgQMFDhI0GDBQ4QMFTpM2HDhI0SMFDlK1GjRY8SMFTtO3HjxEyRMlDhJ0mTJU6RMlTpN2nTpM2TMlDlL1mzZc+TMlTtP3nz5CxQsVLhI0WLFS5QsVbpM2XLlK1SsVLlK1WrVa9T8p1btOnXr1W/QsFHjJk2bNW/RslXrNm3bte/QsVPnLl27de/Rs1fvPn379R8wcNDgIUOHDR8xctToMWPHjZ8wcdLkKVOnTZ8xc9bsOXPnzV+wcNHiJUuXLf/3vxUrV61es3bd+g0bN/2/ecvWbdt37Ny1e8/effsPHDx0+MjRY8dPnDx1+szZc+cvXLx0+crVa9dv3Lx1+87de/cfPHz0+MnTZ89fvHz1+s3bd+8/fPz0+cvXb99//Pz1O4C/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7//3/8fUEsBAhQAFAAAAAgAAAAhUEO/pqMEAAAAAgAAAA0AAAAAAAAAAAAAAIABAAAAAG1hbmlmZXN0Lmpzb25QSwECFAAUAAAACAAAACFQFWFic0MCAAABAAEAEAAAAAAAAAAAAAAAgAEvAAAAaG9zcGl0YWwuc3FsaXRlM1BLBQYAAAAAAgACAHkAAACgAgAAKgB2YWxpZCBjb21tZW50IFBLBQYAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
}
const PAYLOAD_SHA: String = "2deb0bd2129a9d3aed91e3cff58b3993752be549642890a3e853ec1065f9b617"
const PAYLOAD_CRC: int = 1935827221

func run() -> Dictionary:
	var root: String = "user://zip-boundaries-"+HospitalSnapshots.uuid()
	if DirAccess.make_dir_recursive_absolute(root)!=OK:
		return {"ok":false,"error":"无法创建ZIP边界验证目录"}
	var zip: HospitalBackupZip = HospitalBackupZip.new()
	var budget: Callable = func(_bytes: int) -> bool: return true
	var payload: PackedByteArray = PackedByteArray()
	payload.resize(65537)
	for index: int in payload.size():
		payload[index] = index%256
	var database: String = _file(root,"database.bin",payload)
	var info: Dictionary = zip.file_info(database,budget)
	if not info.ok:
		_cleanup(root)
		return {"ok":false,"error":info.get("error","无法读取ZIP边界验证输入")}
	var checks: Dictionary = {"source_crc_sha":info.ok and info.bytes==65537 and info.crc==PAYLOAD_CRC and info.sha256==PAYLOAD_SHA}
	var errors: Dictionary = {}
	var stored: String = root.path_join("stored.oghbackup")
	var written: Dictionary = zip.write(stored,"{}".to_utf8_buffer(),database,info,budget)
	var archive: Dictionary = zip.inspect(stored) if written.ok else written
	var read: Dictionary = _read(zip,archive,budget)
	for stage: String in ["write","inspect","extract"]:
		var operation: Dictionary = {"write":written,"inspect":archive,"extract":read}[stage]
		if not operation.ok:
			errors["stored_"+stage] = operation.get("error","")
	checks.stored_chunks = read.ok and read.payload==payload and read.sizes==[32768,32768,1] and read.sha256==PAYLOAD_SHA
	var independent: ZIPReader = ZIPReader.new()
	checks.stored_independent_reader = independent.open(stored)==OK and independent.read_file("hospital.sqlite3")==payload
	independent.close()
	var deflated_path: String = _file(root,"deflated.oghbackup",Marshalls.base64_to_raw(VECTORS.DEFLATED))
	var deflated: Dictionary = zip.inspect(deflated_path)
	read = _read(zip,deflated,budget)
	if not read.ok:
		errors.deflated = read.get("error","")
	checks.deflated_chunks = read.ok and read.payload==payload and read.sizes==[32768,32768,1] and read.sha256==PAYLOAD_SHA
	var manifest: Dictionary = zip.read_manifest(deflated,budget)
	checks.manifest = manifest.ok and manifest.manifest=={}
	var comment: Dictionary = zip.inspect(_file(root,"comment.oghbackup",Marshalls.base64_to_raw(VECTORS.COMMENT_SIGNATURE)))
	read = _read(zip,comment,budget)
	if not read.ok:
		errors.comment = read.get("error","")
	checks.comment_signature = read.ok and read.payload==payload
	for label: String in ["BAD_CRC","TRUNCATED_STREAM","TRAILING_STREAM"]:
		var rejected: Dictionary = zip.inspect(_file(root,label+".oghbackup",Marshalls.base64_to_raw(VECTORS[label])))
		read = _read(zip,rejected,budget)
		checks[label.to_lower()] = rejected.ok and not read.ok
	var truncated: PackedByteArray = Marshalls.base64_to_raw(VECTORS.DEFLATED)
	truncated.resize(truncated.size()-1)
	checks.truncated_archive = not zip.inspect(_file(root,"truncated.oghbackup",truncated)).ok
	var emitted: Array[int] = [0]
	var sink: Callable = func(_chunk: PackedByteArray) -> Dictionary: emitted[0] += 1; return {"ok":true}
	var denied: Callable = func(_bytes: int) -> bool: return false
	var cancelled: Callable = func() -> bool: return true
	checks.read_budget = not zip.extract(deflated,"hospital.sqlite3",sink,denied).ok and emitted[0]==0
	checks.read_cancel = not zip.extract(deflated,"hospital.sqlite3",sink,budget,cancelled).ok and emitted[0]==0
	var stop: Array[bool] = [false]
	var bytes_before_cancel: Array[int] = [0]
	var partial: Callable = func(chunk: PackedByteArray) -> Dictionary:
		bytes_before_cancel[0] += chunk.size()
		stop[0] = true
		return {"ok":true}
	var cancelled_midway: Dictionary = zip.extract(deflated,"hospital.sqlite3",partial,budget,func() -> bool: return stop[0])
	checks.read_cancel_boundary = not cancelled_midway.ok and bytes_before_cancel[0]==32768
	var rejected_sink: Dictionary = zip.extract(deflated,"hospital.sqlite3",func(_chunk: PackedByteArray) -> Dictionary: return {"ok":false,"error":"sink-rejected"},budget)
	checks.read_sink_failure = not rejected_sink.ok and rejected_sink.error=="sink-rejected" and zip.inspect(deflated_path).ok
	for mode: String in ["budget","cancel","crc"]:
		var target: String = root.path_join(mode+".oghbackup")
		var source_info: Dictionary = info.duplicate()
		if mode=="crc":
			source_info.crc = int(source_info.crc)^1
		var failed: Dictionary = zip.write(target,"{}".to_utf8_buffer(),database,source_info,denied if mode=="budget" else budget,cancelled if mode=="cancel" else Callable())
		checks["write_"+mode+"_atomic"] = not failed.ok and not FileAccess.file_exists(target) and _no_pending(root,mode+".oghbackup.pending-")
	var existing: String = _file(root,"existing.oghbackup","preserved".to_utf8_buffer())
	checks.existing_preserved = not zip.write(existing,"{}".to_utf8_buffer(),database,info,budget).ok and FileAccess.get_file_as_string(existing)=="preserved"
	# Retain the former full/partial/high-byte vectors at the public CRC boundary;
	# raw ZIP DEFLATE no longer needs a synthetic Adler wrapper.
	var crc_vectors: Dictionary = {0:0,1:4278190080,32767:1294317196,32768:457435837}
	for size: int in crc_vectors:
		var high: PackedByteArray = PackedByteArray()
		high.resize(size)
		high.fill(255)
		var vector: Dictionary = zip.file_info(_file(root,"crc-"+str(size)+".bin",high),budget)
		checks["crc_"+str(size)] = vector.ok and vector.bytes==size and vector.crc==crc_vectors[size]
	var empty_path: String = _file(root,"empty.bin",PackedByteArray())
	var empty_info: Dictionary = zip.file_info(empty_path,budget)
	var empty_zip: String = root.path_join("empty.oghbackup")
	var empty_write: Dictionary = zip.write(empty_zip,"{}".to_utf8_buffer(),empty_path,empty_info,budget)
	var empty_read: Dictionary = _read(zip,zip.inspect(empty_zip),budget) if empty_write.ok else empty_write
	if not empty_read.ok:
		errors.empty = empty_read.get("error","")
	checks.empty_stored = empty_read.ok and empty_read.payload.is_empty() and empty_read.sizes.is_empty()
	var ok: bool = true
	for key: String in checks:
		ok = ok and checks[key]
	_cleanup(root)
	return {"ok":ok,"checks":checks,"errors":errors,"payload_bytes":payload.size(),"chunk_limit":32768,"sha256":PAYLOAD_SHA,"crc_vectors":crc_vectors.size()}

func _read(zip: HospitalBackupZip, archive: Dictionary, budget: Callable) -> Dictionary:
	if not archive.get("ok",false):
		return archive
	var chunks: Array[PackedByteArray] = []
	var sizes: Array[int] = []
	var result: Dictionary = zip.extract(archive,"hospital.sqlite3",func(chunk: PackedByteArray) -> Dictionary: chunks.append(chunk); sizes.append(chunk.size()); return {"ok":true},budget)
	var payload: PackedByteArray = PackedByteArray()
	for chunk: PackedByteArray in chunks:
		payload.append_array(chunk)
	result.payload = payload
	result.sizes = sizes
	return result

func _file(root: String, name: String, bytes: PackedByteArray) -> String:
	var path: String = root.path_join(name)
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	if file!=null:
		file.store_buffer(bytes)
		file.close()
	return path

func _no_pending(root: String, prefix: String) -> bool:
	for name: String in DirAccess.get_files_at(root):
		if name.begins_with(prefix):
			return false
	return true

func _cleanup(root: String) -> void:
	for name: String in DirAccess.get_files_at(root):
		DirAccess.remove_absolute(root.path_join(name))
	DirAccess.remove_absolute(root)
