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
var _sink: Callable
var _source: Callable
var _expected_bytes: int = 0
var _ended: bool = false

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
	_write_value(value,0)
	_flush(true)
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
		return {"ok":false,"error":"世界长度或哈希声明无效","value":{}}
	_budget = budget
	_source = source
	_expected_bytes = expected_bytes
	_hash = HashingContext.new()
	_hash.start(HashingContext.HASH_SHA256)
	var value: Variant = _read_value(0)
	_whitespace()
	if _peek() != -1:
		error = "JSON末尾存在额外数据"
	digest = _hash.finish().hex_encode()
	if error.is_empty() and bytes != expected_bytes:
		error = "世界字节数与清单不符"
	if error.is_empty() and digest != expected_hash:
		error = "世界SHA-256与清单不符"
	if not value is Dictionary and error.is_empty():
		error = "世界根对象无效"
	return {"ok":error.is_empty(),"error":error,"value":value if error.is_empty() else {}}

func _reset() -> void:
	error = ""
	bytes = 0
	digest = ""
	_buffer = PackedByteArray()
	_cursor = 0
	_ended = false

func _write_value(value: Variant, depth: int) -> void:
	if not error.is_empty():
		return
	if depth > MAX_DEPTH:
		error = "JSON嵌套深度超过64"
		return
	if value is Dictionary:
		var keys: PackedStringArray = PackedStringArray()
		for key: Variant in value:
			if not (key is String or key is StringName):
				error = "世界对象键必须是字符串"
				return
			keys.append(str(key))
		_emit("{")
		# Both accepted key types encode as JSON strings. Sort their text so
		# decoding StringName keys to String cannot change canonical byte order.
		keys.sort()
		for index: int in keys.size():
			if index > 0:
				_emit(",")
			_write_value(keys[index],depth+1)
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
		if value is StringName:
			value = str(value)
		if not typeof(value) in [TYPE_NIL,TYPE_BOOL,TYPE_INT,TYPE_FLOAT,TYPE_STRING] or (value is float and not is_finite(value)):
			error = "世界含有不能保存的值或平台句柄"
			return
		if value is String and value.to_utf8_buffer().size() > MAX_STRING:
			error = "JSON字符串超过64KiB"
			return
		_emit(JSON.stringify(value,"",true,true))

func _emit(value: String) -> void:
	_buffer.append_array(value.to_utf8_buffer())
	if _buffer.size() >= CHUNK:
		_flush()

func _flush(finish: bool = false) -> void:
	while not _buffer.is_empty() and (finish or _buffer.size()>=CHUNK) and error.is_empty():
		var chunk: PackedByteArray = _buffer.slice(0,mini(CHUNK,_buffer.size()))
		if not _budget.call(bytes+chunk.size()):
			error = "保存资源不足，当前医院与旧提交保留"
			return
		var result: Dictionary = _sink.call(chunk)
		if not result.get("ok",false):
			error = str(result.get("error","世界分段写入失败"))
			return
		_hash.update(chunk)
		bytes += chunk.size()
		_buffer = _buffer.slice(chunk.size())

func _peek() -> int:
	if not error.is_empty():
		return -1
	if _cursor >= _buffer.size():
		if _ended:
			return -1
		if not _budget.call(bytes+CHUNK):
			error = "载入资源不足，保留当前医院"
			return -1
		var result: Dictionary = _source.call()
		if not result.get("ok",false) or not result.get("data") is PackedByteArray:
			error = str(result.get("error","世界分段读取失败"))
			return -1
		_buffer = result.data
		if _buffer.size()>CHUNK or bytes+_buffer.size()>_expected_bytes:
			error = "世界分段超出声明字节数"
			return -1
		_cursor = 0
		if _buffer.is_empty():
			_ended = true
			return -1
		_hash.update(_buffer)
		bytes += _buffer.size()
	return _buffer[_cursor]

func _take() -> int:
	if error.is_empty() and _cursor<_buffer.size():
		var buffered: int = _buffer[_cursor]
		_cursor += 1
		return buffered
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
	if source.to_utf8_buffer()!=raw:
		error = "JSON包含无效UTF-8"
		return null
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
