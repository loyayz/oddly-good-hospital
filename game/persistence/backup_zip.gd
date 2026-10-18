class_name HospitalBackupZip
extends RefCounted

const ALLOWED: Array[String] = ["manifest.json","hospital.sqlite3","thumbnail.png"]
const BLOCK: int = 32768
const U32: int = 4294967295
var _crc_table: PackedInt64Array = PackedInt64Array()

func inspect(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path,FileAccess.READ)
	if file==null:
		return _failure("无法读取备份文件")
	var total: int = file.get_length()
	if total<22:
		return _failure("备份ZIP未完整写入")
	file.seek(maxi(0,total-65557))
	var tail: PackedByteArray = file.get_buffer(mini(total,65557))
	var end: int = -1
	for offset: int in range(tail.size()-22,-1,-1):
		if tail.decode_u32(offset)==0x06054b50 and offset+22+tail.decode_u16(offset+20)==tail.size():
			end = total-tail.size()+offset
			break
	if end<0:
		return _failure("备份ZIP目录缺失")
	file.seek(end+4)
	var disk: int = file.get_16()
	var directory_disk: int = file.get_16()
	var disk_count: int = file.get_16()
	var count: int = file.get_16()
	var directory_bytes: int = file.get_32()
	var directory_offset: int = file.get_32()
	var directory_end: int = end
	if disk!=0 or directory_disk!=0 or disk_count!=count:
		return _failure("备份不支持分卷ZIP")
	if count==65535 or directory_bytes==U32 or directory_offset==U32:
		if end<20:
			return _failure("备份ZIP64定位缺失")
		file.seek(end-20)
		if file.get_32()!=0x07064b50 or file.get_32()!=0:
			return _failure("备份ZIP64定位无效")
		var zip64_offset: int = file.get_64()
		if file.get_32()!=1 or zip64_offset<0 or zip64_offset+56>end-20:
			return _failure("备份ZIP64位置越界")
		file.seek(zip64_offset)
		if file.get_32()!=0x06064b50:
			return _failure("备份ZIP64目录无效")
		var record_size: int = file.get_64()
		if record_size<44 or zip64_offset+12+record_size!=end-20:
			return _failure("备份ZIP64目录大小不符")
		file.get_16()
		file.get_16()
		if file.get_32()!=0 or file.get_32()!=0:
			return _failure("备份不支持分卷ZIP64")
		disk_count = file.get_64()
		count = file.get_64()
		directory_bytes = file.get_64()
		directory_offset = file.get_64()
		directory_end = zip64_offset
	if count<2 or count>3 or disk_count!=count or directory_offset<0 or directory_bytes<0 or directory_offset+directory_bytes!=directory_end:
		return _failure("备份条目数量或目录范围无效")
	var entries: Dictionary = {}
	file.seek(directory_offset)
	for index: int in count:
		if file.get_position()+46>directory_end or file.get_32()!=0x02014b50:
			return _failure("备份ZIP条目目录无效")
		file.get_16()
		file.get_16()
		var flags: int = file.get_16()
		var method: int = file.get_16()
		file.get_16()
		file.get_16()
		var crc: int = file.get_32()
		var compressed: int = file.get_32()
		var unpacked: int = file.get_32()
		var name_bytes: int = file.get_16()
		var extra_bytes: int = file.get_16()
		var comment_bytes: int = file.get_16()
		var start_disk: int = file.get_16()
		file.get_16()
		var attributes: int = file.get_32()
		var local_offset: int = file.get_32()
		if name_bytes<1 or name_bytes>64 or file.get_position()+name_bytes+extra_bytes+comment_bytes>directory_end:
			return _failure("备份条目名称或附加信息越界")
		var raw_name: PackedByteArray = file.get_buffer(name_bytes)
		var name: String = raw_name.get_string_from_utf8()
		var extra: PackedByteArray = file.get_buffer(extra_bytes)
		file.seek(file.get_position()+comment_bytes)
		if not name in ALLOWED or name.to_utf8_buffer()!=raw_name or entries.has(name) or start_disk!=0 or flags & ~0x080e or not method in [0,8] or ((attributes>>16)&61440)==40960:
			return _failure("备份包含未知、重复、加密、符号链接或不安全条目")
		var extended: Dictionary = _zip64(extra,unpacked,compressed,local_offset)
		if not extended.ok:
			return extended
		unpacked = extended.unpacked
		compressed = extended.compressed
		local_offset = extended.offset
		if unpacked<0 or compressed<0 or local_offset<0 or local_offset>=directory_offset or (unpacked>0 and (compressed==0 or unpacked/float(compressed)>200.0)) or (method==0 and compressed!=unpacked):
			return _failure("备份条目字节数、压缩比例或位置无效")
		if (name=="manifest.json" and unpacked>65536) or (name=="thumbnail.png" and unpacked>262144):
			return _failure("备份清单或缩略图超过限额")
		entries[name] = {"name":name,"flags":flags,"method":method,"crc":crc,"compressed":compressed,"unpacked":unpacked,"offset":local_offset}
	if file.get_position()!=directory_end or not entries.has("manifest.json") or not entries.has("hospital.sqlite3"):
		return _failure("备份必需条目缺失或目录大小不符")
	var ordered: Array = entries.values()
	ordered.sort_custom(func(a:Dictionary,b:Dictionary) -> bool: return int(a.offset)<int(b.offset))
	var previous_end: int = 0
	for entry: Dictionary in ordered:
		if entry.offset!=previous_end:
			return _failure("备份包含未登记条目、重复区域或前置数据")
		file.seek(entry.offset)
		if file.get_32()!=0x04034b50:
			return _failure("备份本地条目头无效")
		file.get_16()
		if file.get_16()!=entry.flags or file.get_16()!=entry.method:
			return _failure("备份本地条目类型与目录不符")
		file.get_16()
		file.get_16()
		var local_crc: int = file.get_32()
		var local_compressed: int = file.get_32()
		var local_unpacked: int = file.get_32()
		var name_bytes: int = file.get_16()
		var extra_bytes: int = file.get_16()
		if name_bytes!=str(entry.name).length() or file.get_position()+name_bytes+extra_bytes>directory_offset:
			return _failure("备份本地条目名称越界")
		if file.get_buffer(name_bytes)!=str(entry.name).to_utf8_buffer():
			return _failure("备份本地条目路径与目录不符")
		var local_extra: PackedByteArray = file.get_buffer(extra_bytes)
		var extended: Dictionary = _zip64(local_extra,local_unpacked,local_compressed,0)
		if not extended.ok:
			return extended
		if not entry.flags & 8 and (local_crc!=entry.crc or extended.compressed!=entry.compressed or extended.unpacked!=entry.unpacked):
			return _failure("备份本地条目长度或CRC与目录不符")
		entry.data_offset = file.get_position()
		if int(entry.compressed)>directory_offset-int(entry.data_offset):
			return _failure("备份条目数据越界")
		previous_end = int(entry.data_offset)+int(entry.compressed)
		if entry.flags & 8:
			file.seek(previous_end)
			var descriptor_crc: int = file.get_32()
			if descriptor_crc==0x08074b50:
				descriptor_crc = file.get_32()
			var descriptor_compressed: int = file.get_64() if entry.compressed>=U32 or entry.unpacked>=U32 else file.get_32()
			var descriptor_unpacked: int = file.get_64() if entry.compressed>=U32 or entry.unpacked>=U32 else file.get_32()
			if descriptor_crc!=entry.crc or descriptor_compressed!=entry.compressed or descriptor_unpacked!=entry.unpacked:
				return _failure("备份流式条目描述不符")
			previous_end = file.get_position()
	if previous_end!=directory_offset:
		return _failure("备份目录前存在未登记数据")
	file.close()
	return {"ok":true,"entries":entries,"bytes":total,"path":path}

func _zip64(extra: PackedByteArray, unpacked: int, compressed: int, offset: int) -> Dictionary:
	var cursor: int = 0
	var found: bool = false
	while cursor+4<=extra.size():
		var kind: int = extra.decode_u16(cursor)
		var size: int = extra.decode_u16(cursor+2)
		cursor += 4
		if cursor+size>extra.size():
			return _failure("备份ZIP附加字段未完整写入")
		if kind==1:
			if found:
				return _failure("备份ZIP64字段重复")
			found = true
			var values: Array[int] = [unpacked,compressed,offset]
			var position: int = cursor
			for index: int in values.size():
				if values[index]==U32:
					if position+8>cursor+size:
						return _failure("备份ZIP64长度缺失")
					values[index] = extra.decode_u64(position)
					position += 8
			unpacked = values[0]
			compressed = values[1]
			offset = values[2]
		cursor += size
	if cursor!=extra.size() or ((unpacked==U32 or compressed==U32 or offset==U32) and not found):
		return _failure("备份ZIP附加字段格式无效")
	return {"ok":true,"unpacked":unpacked,"compressed":compressed,"offset":offset}

func extract(archive: Dictionary, name: String, sink: Callable, budget: Callable, cancelled: Callable = Callable()) -> Dictionary:
	if not archive.get("ok",false) or not archive.entries.has(name):
		return _failure("备份条目不存在")
	var entry: Dictionary = archive.entries[name]
	var file: FileAccess = FileAccess.open(archive.path,FileAccess.READ)
	if file==null or file.get_length()!=int(archive.bytes):
		return _failure("备份在读取前已改变")
	file.seek(entry.data_offset)
	var decoder: StreamPeerGZIP = StreamPeerGZIP.new()
	if entry.method==8 and decoder.start_decompression(true,262144)!=OK:
		return _failure("无法创建ZIP解压器")
	# StreamPeerGZIP's deflate mode expects an RFC1950 wrapper. ZIP stores
	# RFC1951 bytes, so supply the bounded wrapper and verify its stream end.
	if entry.method==8 and decoder.put_data(PackedByteArray([0x78,0x01]))!=OK:
		return _failure("无法初始化ZIP解压流")
	var state: Dictionary = {"bytes":0,"crc":U32,"adler_a":1,"adler_b":0}
	var hash: HashingContext = HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	var remaining: int = entry.compressed
	while remaining>0:
		if cancelled.is_valid() and cancelled.call():
			return _failure("备份操作已取消")
		if not budget.call(maxi(int(entry.unpacked),int(state.bytes))):
			return _failure("备份读取所需内存或磁盘不足")
		var raw: PackedByteArray = file.get_buffer(mini(BLOCK,remaining))
		if raw.is_empty():
			return _failure("备份条目未完整写入")
		remaining -= raw.size()
		if entry.method==0:
			var emitted: Dictionary = _emit(raw,entry,state,hash,sink)
			if not emitted.ok:
				return emitted
		else:
			var cursor: int = 0
			while cursor<raw.size():
				var put: Array = decoder.put_partial_data(raw.slice(cursor))
				if put[0]!=OK:
					return _failure("备份DEFLATE数据损坏")
				cursor += int(put[1])
				var drained: Dictionary = _drain(decoder,entry,state,hash,sink)
				if not drained.ok:
					return drained
				if int(put[1])==0 and int(drained.bytes)==0:
					return _failure("备份解压没有进展")
	if entry.method==8:
		var drained: Dictionary = _drain(decoder,entry,state,hash,sink)
		if not drained.ok:
			return drained
		var adler: int = (int(state.adler_b)<<16)|int(state.adler_a)
		var trailer: PackedByteArray = PackedByteArray([(adler>>24)&255,(adler>>16)&255,(adler>>8)&255,adler&255])
		var ended: Array = decoder.put_partial_data(trailer)
		if ended[0]!=OK or int(ended[1])!=4:
			return _failure("备份DEFLATE流包含额外数据或未完整结束")
		var sentinel: Array = decoder.put_partial_data(PackedByteArray([0]))
		if sentinel[0]!=OK or int(sentinel[1])!=0 or decoder.get_available_bytes()!=0:
			return _failure("备份DEFLATE流未完整结束")
	file.close()
	if state.bytes!=entry.unpacked or (int(state.crc)^U32)!=int(entry.crc):
		return _failure("备份条目实际长度或CRC不符")
	return {"ok":true,"bytes":state.bytes,"sha256":hash.finish().hex_encode()}

func _drain(decoder: StreamPeerGZIP, entry: Dictionary, state: Dictionary, hash: HashingContext, sink: Callable) -> Dictionary:
	var bytes: int = 0
	while decoder.get_available_bytes()>0:
		var decoded: Array = decoder.get_data(mini(BLOCK,decoder.get_available_bytes()))
		if decoded[0]!=OK:
			return _failure("备份解压数据读取失败")
		var emitted: Dictionary = _emit(decoded[1],entry,state,hash,sink)
		if not emitted.ok:
			return emitted
		bytes += decoded[1].size()
	return {"ok":true,"bytes":bytes}

func _emit(raw: PackedByteArray, entry: Dictionary, state: Dictionary, hash: HashingContext, sink: Callable) -> Dictionary:
	if raw.size()+int(state.bytes)>int(entry.unpacked):
		return _failure("备份解压超过声明长度")
	var result: Dictionary = sink.call(raw)
	if not result.get("ok",false):
		return result
	state.bytes += raw.size()
	state.crc = _crc(raw,state.crc)
	if entry.method==8:
		var a: int = state.adler_a
		var b: int = state.adler_b
		# Extract/drain feeds at most BLOCK bytes. Even a full block's sums
		# fit int64, so reducing once preserves the exact Adler remainder.
		for byte: int in raw:
			a += byte
			b += a
		state.adler_a = a%65521
		state.adler_b = b%65521
	hash.update(raw)
	return {"ok":true}

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
	var length: int = file.get_length()
	var hash: HashingContext = HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	var crc: int = U32
	while file.get_position()<length:
		if not budget.call(length):
			return _failure("备份所需资源不足")
		var raw: PackedByteArray = file.get_buffer(BLOCK)
		if raw.is_empty():
			return _failure("备份数据库读取中断")
		hash.update(raw)
		crc = _crc(raw,crc)
	file.close()
	return {"ok":true,"bytes":length,"sha256":hash.finish().hex_encode(),"crc":crc^U32}

func write(destination: String, manifest: PackedByteArray, database_path: String, database_info: Dictionary, budget: Callable, cancelled: Callable = Callable()) -> Dictionary:
	if not destination.to_lower().ends_with(".oghbackup") or FileAccess.file_exists(destination):
		return _failure("请选择尚不存在的.oghbackup文件")
	var temporary: String = destination+".pending-"+HospitalSnapshots.uuid()
	var output: FileAccess = FileAccess.open(temporary,FileAccess.WRITE)
	if output==null:
		return _failure("无法在目标目录创建备份，请检查权限和空间")
	var entries: Array[Dictionary] = [{"name":"manifest.json","bytes":manifest.size(),"crc":_crc(manifest,U32)^U32,"raw":manifest},
		{"name":"hospital.sqlite3","bytes":database_info.bytes,"crc":database_info.crc,"path":database_path}]
	var failed: String = ""
	for entry: Dictionary in entries:
		entry.offset = output.get_position()
		var large: bool = int(entry.bytes)>=U32
		output.store_32(0x04034b50)
		output.store_16(45 if large else 20)
		output.store_16(0)
		output.store_16(0) # Stored mode cannot create a decompression bomb.
		output.store_16(0)
		output.store_16(33)
		output.store_32(entry.crc)
		output.store_32(U32 if large else int(entry.bytes))
		output.store_32(U32 if large else int(entry.bytes))
		output.store_16(str(entry.name).length())
		output.store_16(20 if large else 0)
		output.store_buffer(str(entry.name).to_utf8_buffer())
		if large:
			output.store_16(1)
			output.store_16(16)
			output.store_64(entry.bytes)
			output.store_64(entry.bytes)
		if entry.has("raw"):
			output.store_buffer(entry.raw)
		else:
			var input: FileAccess = FileAccess.open(entry.path,FileAccess.READ)
			if input==null:
				failed = "独立备份数据库无法读取"
				break
			while input.get_position()<int(entry.bytes):
				if not budget.call(entry.bytes) or (cancelled.is_valid() and cancelled.call()):
					failed = "备份取消或目标资源不足"
					break
				var raw: PackedByteArray = input.get_buffer(BLOCK)
				if raw.is_empty():
					failed = "独立备份数据库读取中断"
					break
				output.store_buffer(raw)
			input.close()
		if not failed.is_empty() or output.get_error()!=OK:
			failed = "备份写入失败，旧文件保留" if failed.is_empty() else failed
			break
	var central_offset: int = output.get_position()
	if failed.is_empty():
		for entry: Dictionary in entries:
			var large: bool = int(entry.bytes)>=U32
			var far: bool = int(entry.offset)>=U32
			output.store_32(0x02014b50)
			output.store_16(45)
			output.store_16(45 if large or far else 20)
			output.store_16(0)
			output.store_16(0)
			output.store_16(0)
			output.store_16(33)
			output.store_32(entry.crc)
			output.store_32(U32 if large else int(entry.bytes))
			output.store_32(U32 if large else int(entry.bytes))
			output.store_16(str(entry.name).length())
			output.store_16((4 if large or far else 0)+(16 if large else 0)+(8 if far else 0))
			output.store_16(0)
			output.store_16(0)
			output.store_16(0)
			output.store_32(0)
			output.store_32(U32 if far else int(entry.offset))
			output.store_buffer(str(entry.name).to_utf8_buffer())
			if large or far:
				output.store_16(1)
				output.store_16((16 if large else 0)+(8 if far else 0))
				if large:
					output.store_64(entry.bytes)
					output.store_64(entry.bytes)
				if far:
					output.store_64(entry.offset)
		var central_bytes: int = output.get_position()-central_offset
		var large_directory: bool = central_offset>=U32 or central_bytes>=U32
		if large_directory:
			var zip64_offset: int = output.get_position()
			output.store_32(0x06064b50)
			output.store_64(44)
			output.store_16(45)
			output.store_16(45)
			output.store_32(0)
			output.store_32(0)
			output.store_64(entries.size())
			output.store_64(entries.size())
			output.store_64(central_bytes)
			output.store_64(central_offset)
			output.store_32(0x07064b50)
			output.store_32(0)
			output.store_64(zip64_offset)
			output.store_32(1)
		output.store_32(0x06054b50)
		output.store_16(0)
		output.store_16(0)
		output.store_16(entries.size())
		output.store_16(entries.size())
		output.store_32(U32 if large_directory else central_bytes)
		output.store_32(U32 if large_directory else central_offset)
		output.store_16(0)
		output.flush()
		if output.get_error()!=OK:
			failed = "备份目标磁盘写入失败"
	output.close()
	if failed.is_empty():
		var checked: Dictionary = inspect(temporary)
		if not checked.ok:
			failed = checked.error
	if failed.is_empty() and DirAccess.rename_absolute(temporary,destination)==OK:
		return {"ok":true,"path":destination}
	DirAccess.remove_absolute(temporary)
	return _failure("备份无法完成："+failed)

func _crc(raw: PackedByteArray, current: int) -> int:
	if _crc_table.is_empty():
		for byte: int in 256:
			var crc: int = byte
			for bit: int in 8:
				crc = (crc>>1)^0xedb88320 if crc&1 else crc>>1
			_crc_table.append(crc)
	var crc: int = current
	for byte: int in raw:
		crc = _crc_table[(crc^byte)&255]^(crc>>8)
	return crc

static func _failure(message: String) -> Dictionary:
	return {"ok":false,"error":message}
