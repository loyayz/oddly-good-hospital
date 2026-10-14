class_name HospitalJsonStream
extends RefCounted

const CHUNK: int = 32768
const MAX_STRING: int = 65536
const MAX_DEPTH: int = 64

var error: String = ""
var bytes: int = 0
var digest: String = ""
var _file: FileAccess
var _buffer: PackedByteArray = PackedByteArray()
var _cursor: int = 0
var _hash: HashingContext
var _budget: Callable

func encode(path: String, value: Dictionary, budget: Callable) -> bool:
	_budget = budget
	_file = FileAccess.open(path,FileAccess.WRITE)
	if _file == null:
		error = "无法写入世界：%d" % FileAccess.get_open_error()
		return false
	_hash = HashingContext.new()
	_hash.start(HashingContext.HASH_SHA256)
	_write_value(value,0)
	_flush()
	_file.flush()
	if _file.get_error() != OK:
		error = "世界写入失败：%d" % _file.get_error()
	_file.close()
	digest = _hash.finish().hex_encode()
	return error.is_empty()

func decode(path: String, expected_bytes: int, expected_hash: String, budget: Callable) -> Dictionary:
	_budget = budget
	_file = FileAccess.open(path,FileAccess.READ)
	if _file == null:
		return {"ok":false,"error":"无法读取世界"}
	if _file.get_length() != expected_bytes:
		_file.close()
		return {"ok":false,"error":"世界字节数与清单不符"}
	_hash = HashingContext.new()
	_hash.start(HashingContext.HASH_SHA256)
	var value: Variant = _read_value(0)
	_whitespace()
	if _peek() != -1:
		error = "JSON末尾存在额外数据"
	_file.close()
	digest = _hash.finish().hex_encode()
	if error.is_empty() and digest != expected_hash:
		error = "世界SHA-256与清单不符"
	if not value is Dictionary and error.is_empty():
		error = "世界根对象无效"
	return {"ok":error.is_empty(),"error":error,"value":value if error.is_empty() else {}}

func _write_value(value: Variant, depth: int) -> void:
	if not error.is_empty():
		return
	if depth > MAX_DEPTH:
		error = "JSON嵌套深度超过64"
		return
	if value is Dictionary:
		_emit("{")
		var keys: Array = value.keys()
		keys.sort()
		for index: int in keys.size():
			if index > 0:
				_emit(",")
			_write_value(str(keys[index]),depth+1)
			_emit(":")
			_write_value(value[keys[index]],depth+1)
		_emit("}")
	elif value is Array:
		_emit("[")
		for index: int in value.size():
			if index > 0:
				_emit(",")
			_write_value(value[index],depth+1)
		_emit("]")
	else:
		if value is String and value.to_utf8_buffer().size() > MAX_STRING:
			error = "JSON字符串超过64KiB"
			return
		_emit(JSON.stringify(value,"",true,true))

func _emit(value: String) -> void:
	_buffer.append_array(value.to_utf8_buffer())
	if _buffer.size() >= CHUNK:
		_flush()

func _flush() -> void:
	if _buffer.is_empty() or not error.is_empty():
		return
	if not _budget.call(bytes+_buffer.size()):
		error = "保存资源不足，当前医院与旧提交保留"
		return
	_file.store_buffer(_buffer)
	_hash.update(_buffer)
	bytes += _buffer.size()
	_buffer.clear()

func _peek() -> int:
	if not error.is_empty():
		return -1
	if _cursor >= _buffer.size():
		if _file.get_position() >= _file.get_length():
			return -1
		if not _budget.call(bytes+CHUNK):
			error = "载入资源不足，保留当前医院"
			return -1
		_buffer = _file.get_buffer(CHUNK)
		_cursor = 0
		_hash.update(_buffer)
		bytes += _buffer.size()
		if _buffer.is_empty():
			return -1
	return _buffer[_cursor]

func _take() -> int:
	var value: int = _peek()
	if value >= 0:
		_cursor += 1
	return value

func _whitespace() -> void:
	while _peek() in [9,10,13,32]:
		_take()

func _read_value(depth: int) -> Variant:
	if depth > MAX_DEPTH:
		error = "JSON嵌套深度超过64"
		return null
	_whitespace()
	var first: int = _peek()
	if first == 123:
		_take()
		var map: Dictionary = {}
		_whitespace()
		if _peek() == 125:
			_take()
			return map
		while error.is_empty():
			_whitespace()
			if _peek() != 34:
				error = "JSON对象键缺失"
				return null
			var key: Variant = _read_scalar()
			_whitespace()
			if _take() != 58 or map.has(key):
				error = "JSON对象分隔符或重复键无效"
				return null
			map[key] = _read_value(depth+1)
			_whitespace()
			var delimiter: int = _take()
			if delimiter == 125:
				return map
			if delimiter != 44:
				error = "JSON对象未完整关闭"
				return null
	elif first == 91:
		_take()
		var array: Array = []
		_whitespace()
		if _peek() == 93:
			_take()
			return array
		while error.is_empty():
			array.append(_read_value(depth+1))
			_whitespace()
			var delimiter: int = _take()
			if delimiter == 93:
				return array
			if delimiter != 44:
				error = "JSON数组未完整关闭"
				return null
	return _read_scalar()

func _read_scalar() -> Variant:
	var raw: PackedByteArray = PackedByteArray()
	var first: int = _peek()
	if first == 34:
		raw.append(_take())
		var escaped: bool = false
		while error.is_empty():
			var byte: int = _take()
			if byte < 0:
				error = "JSON字符串未完整关闭"
				return null
			raw.append(byte)
			if raw.size() > MAX_STRING*6+2:
				error = "JSON字符串超过64KiB"
				return null
			if byte == 34 and not escaped:
				break
			escaped = byte == 92 and not escaped
	else:
		while not _peek() in [-1,9,10,13,32,44,93,125]:
			raw.append(_take())
			if raw.size() > 128:
				error = "JSON标量格式无效"
				return null
	var source: String = raw.get_string_from_utf8()
	var parser: JSON = JSON.new()
	if parser.parse(source) != OK:
		error = "JSON标量无效"
		return null
	var value: Variant = parser.data
	if value is String and value.to_utf8_buffer().size() > MAX_STRING:
		error = "JSON字符串超过64KiB"
		return null
	if value is float:
		if not ("." in source or "e" in source.to_lower()):
			var integer: int = source.to_int()
			if str(integer)!=source and source!="-0":
				error = "JSON整数超出64位范围或格式无效"
				return null
			return integer
		if not ClassDB.class_exists("PlatformJsonNumbers"):
			error = "缺少精确数值解码器"
			return null
		var decoded: Dictionary = ClassDB.class_call_static("PlatformJsonNumbers","decode_decimal",source)
		if not decoded.get("ok",false):
			error = "JSON数值解码失败："+str(decoded.get("error",""))
			return null
		return decoded.value
	return value
