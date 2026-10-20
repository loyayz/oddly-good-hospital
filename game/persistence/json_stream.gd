class_name HospitalJsonStream
extends RefCounted

const CHUNK: int = 32768
const MAX_STRING: int = 65536
const MAX_DEPTH: int = 64

var error: String = ""
var bytes: int = 0
var digest: String = ""
var _file: FileAccess
var _hash: HashingContext
var _budget: Callable
var _sink: Callable
var _source: Callable
var _expected_bytes: int = 0

func encode(path: String, value: Dictionary, budget: Callable) -> bool:
	_file = FileAccess.open(path,FileAccess.WRITE)
	if _file == null:
		error = "无法写入世界：%d" % FileAccess.get_open_error()
		return false
	encode_to(value,budget,_file_sink)
	_file.flush()
	if _file.get_error() != OK:
		error = "世界写入失败：%d" % _file.get_error()
	_file.close()
	return error.is_empty()

func encode_to(value: Dictionary, budget: Callable, sink: Callable) -> bool:
	_reset()
	_budget = budget
	_sink = sink
	_hash = HashingContext.new()
	_hash.start(HashingContext.HASH_SHA256)
	if not ClassDB.class_exists("PlatformJsonStream"):
		error = "缺少RapidJSON流式编解码器"
	else:
		var result: Dictionary = ClassDB.class_call_static("PlatformJsonStream","encode",value,_write_chunk,_float_token)
		if not result.get("ok",false) and error.is_empty():
			error = str(result.get("error","世界编码失败"))
	digest = _hash.finish().hex_encode()
	return error.is_empty()

func _file_sink(chunk: PackedByteArray) -> Dictionary:
	_file.store_buffer(chunk)
	return {"ok":_file.get_error()==OK,"error":"世界文件写入失败"}

func decode(path: String, expected_bytes: int, expected_hash: String, budget: Callable) -> Dictionary:
	_file = FileAccess.open(path,FileAccess.READ)
	if _file == null:
		return {"ok":false,"error":"无法读取世界"}
	if _file.get_length() != expected_bytes:
		_file.close()
		return {"ok":false,"error":"世界字节数与清单不符"}
	var result: Dictionary = decode_from(expected_bytes,expected_hash,budget,_file_source)
	_file.close()
	return result

func _file_source() -> Dictionary:
	return {"ok":true,"data":_file.get_buffer(CHUNK) if _file.get_position()<_file.get_length() else PackedByteArray()}

func decode_from(expected_bytes: int, expected_hash: String, budget: Callable, source: Callable) -> Dictionary:
	_reset()
	if expected_bytes<0 or not HospitalSnapshots._valid_sha(expected_hash):
		error = "世界长度或哈希声明无效"
		return {"ok":false,"error":error,"value":{}}
	_budget = budget
	_source = source
	_expected_bytes = expected_bytes
	_hash = HashingContext.new()
	_hash.start(HashingContext.HASH_SHA256)
	var result: Dictionary = {"ok":false,"value":{}}
	if not ClassDB.class_exists("PlatformJsonStream"):
		error = "缺少RapidJSON流式编解码器"
	else:
		result = ClassDB.class_call_static("PlatformJsonStream","decode",_read_chunk,_decimal_value)
		if not result.get("ok",false) and error.is_empty():
			error = str(result.get("error","世界解码失败"))
	digest = _hash.finish().hex_encode()
	if error.is_empty() and bytes != expected_bytes:
		error = "世界字节数与清单不符"
	if error.is_empty() and digest != expected_hash:
		error = "世界SHA-256与清单不符"
	return {"ok":error.is_empty(),"error":error,"value":result.get("value",{}) if error.is_empty() else {}}

func _reset() -> void:
	error = ""
	bytes = 0
	digest = ""

func _float_token(value: float) -> String:
	# Preserve the established full-precision spelling and float type marker.
	return JSON.stringify(value,"",true,true)

func _decimal_value(source: String) -> Dictionary:
	if not ClassDB.class_exists("PlatformJsonNumbers"):
		return {"ok":false,"error":"缺少精确数值解码器"}
	return ClassDB.class_call_static("PlatformJsonNumbers","decode_decimal",source)

func _write_chunk(chunk: PackedByteArray) -> Dictionary:
	if not _budget.call(bytes+chunk.size()):
		error = "保存资源不足，当前医院与旧提交保留"
		return {"ok":false,"error":error}
	var result: Dictionary = _sink.call(chunk)
	if not result.get("ok",false):
		error = str(result.get("error","世界分段写入失败"))
		return {"ok":false,"error":error}
	_hash.update(chunk)
	bytes += chunk.size()
	return {"ok":true}

func _read_chunk() -> Dictionary:
	if not _budget.call(bytes+CHUNK):
		error = "载入资源不足，保留当前医院"
		return {"ok":false,"error":error}
	var result: Dictionary = _source.call()
	if not result.get("ok",false) or not result.get("data") is PackedByteArray:
		error = str(result.get("error","世界分段读取失败"))
		return {"ok":false,"error":error}
	var chunk: PackedByteArray = result.data
	if chunk.size()>CHUNK or bytes+chunk.size()>_expected_bytes:
		error = "世界分段超出声明字节数"
		return {"ok":false,"error":error}
	# An empty source chunk is EOF, not a hash update. Godot rejects empty
	# HashingContext.update calls; the existing digest already covers the bytes.
	if not chunk.is_empty():
		_hash.update(chunk)
	bytes += chunk.size()
	return {"ok":true,"data":chunk}
