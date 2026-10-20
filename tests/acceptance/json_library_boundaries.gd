extends RefCounted

class CapturedCheck extends RefCounted:
	var passed: bool = false
	var details: Variant = null
	func check(case_id: String, accepted: bool, observation: Variant = null) -> void:
		passed = case_id=="CORE-49" and accepted
		details = observation

func run(t, content: HospitalContent) -> void:
	# Keep the existing stream/ZIP assertions under one acceptance result.
	var prior: CapturedCheck = CapturedCheck.new()
	preload("res://tests/acceptance/stream_boundaries.gd").new().run(prior,content)
	var checks: Dictionary = {}
	_numbers(checks)
	_depth(checks)
	_strings(checks)
	_chunks(checks)
	_failures(checks)
	var accepted: bool = prior.passed
	for value: bool in checks.values():
		accepted = accepted and value
	t.check("CORE-49",accepted,{"existing_stream_and_zip":prior.details,"json_library_boundaries":checks})

func _numbers(checks: Dictionary) -> void:
	var raw: PackedByteArray = '{"zero":0e999,"negative_zero":-0.0,"maximum":9223372036854775807,"minimum":-9223372036854775808,"subnormal":4.9406564584124654e-324,"tie":1.00000000000000011102230246251565404236316680908203125,"above_tie":1.00000000000000011102230246251565404236316680908203126}'.to_utf8_buffer()
	var read: Dictionary = _decode(raw)
	var value: Dictionary = read.get("value",{})
	checks.finite_zero_large_exponent = read.ok and typeof(value.get("zero"))==TYPE_FLOAT and _float_bits(value.get("zero"))==PackedByteArray([0,0,0,0,0,0,0,0])
	var signed_zero: Dictionary = _decode('{"x":-0e999}'.to_utf8_buffer())
	checks.negative_zero_large_exponent = signed_zero.ok and _float_bits(signed_zero.value.x)==PackedByteArray([0,0,0,0,0,0,0,128])
	checks.int64_limits = read.ok and typeof(value.get("maximum"))==TYPE_INT and typeof(value.get("minimum"))==TYPE_INT and value.maximum==9223372036854775807 and value.minimum==-9223372036854775807-1
	checks.negative_zero = read.ok and _float_bits(value.get("negative_zero"))==PackedByteArray([0,0,0,0,0,0,0,128])
	checks.subnormal = read.ok and _float_bits(value.get("subnormal"))==PackedByteArray([1,0,0,0,0,0,0,0])
	checks.binary64_rounding = read.ok and _float_bits(value.get("tie"))==PackedByteArray([0,0,0,0,0,0,240,63]) and _float_bits(value.get("above_tie"))==PackedByteArray([1,0,0,0,0,0,240,63])
	var negative_zero: float = PackedByteArray([0,0,0,0,0,0,0,128]).decode_double(0)
	var numeric_roundtrip: Dictionary = _encode({"maximum":9223372036854775807,"minimum":-9223372036854775807-1,"negative_zero":negative_zero,"positive_zero":0.0})
	var restored: Dictionary = _decode(numeric_roundtrip.data)
	checks.numeric_roundtrip = numeric_roundtrip.ok and restored.ok and restored.value.maximum==9223372036854775807 and restored.value.minimum==-9223372036854775807-1 and _float_bits(restored.value.negative_zero)==PackedByteArray([0,0,0,0,0,0,0,128]) and _float_bits(restored.value.positive_zero)==PackedByteArray([0,0,0,0,0,0,0,0])
	checks.signed_zero_output = numeric_roundtrip.ok and numeric_roundtrip.data.get_string_from_utf8().contains('"negative_zero":-0.0') and numeric_roundtrip.data.get_string_from_utf8().contains('"positive_zero":0.0')
	var token: String = "0."+"0".repeat(125)+"1"
	checks.number_token_128 = token.length()==128 and _decode(('{"x":'+token+'}').to_utf8_buffer()).ok
	checks.number_token_129 = _rejected(_decode(('{"x":0.'+"0".repeat(126)+'1}').to_utf8_buffer()))
	for invalid: String in ["9223372036854775808","-9223372036854775809","NaN","Infinity","-Infinity","1e309","+1","01","0x1","1.",".1","1e","1e+"]:
		checks["reject_number_"+invalid] = _rejected(_decode(('{"x":'+invalid+'}').to_utf8_buffer()))
	checks.reject_duplicate_key = _rejected(_decode('{"x":1,"x":2}'.to_utf8_buffer()))
	checks.reject_escaped_duplicate_key = _rejected(_decode('{"a":1,"\\u0061":2}'.to_utf8_buffer()))
	checks.same_key_separate_objects = _decode('{"a":{"x":1},"b":{"x":2}}'.to_utf8_buffer()).ok

func _depth(checks: Dictionary) -> void:
	var at_limit: PackedByteArray = ('{"x":'+"[".repeat(63)+"0"+"]".repeat(63)+'}').to_utf8_buffer()
	var beyond: PackedByteArray = ('{"x":'+"[".repeat(64)+"0"+"]".repeat(64)+'}').to_utf8_buffer()
	var empty_at_limit: PackedByteArray = ('{"x":'+"[".repeat(64)+"]".repeat(64)+'}').to_utf8_buffer()
	checks.decode_depth_64 = _decode(at_limit).ok and _decode(empty_at_limit).ok
	checks.decode_depth_65 = _rejected(_decode(beyond))
	checks.encode_depth_64 = _encode(_nested_arrays(63,0)).ok and _encode(_nested_arrays(63,[])).ok
	checks.encode_depth_65 = not _encode(_nested_arrays(64,0)).ok

func _strings(checks: Dictionary) -> void:
	var ascii: String = "a".repeat(65536)
	var unicode: String = "中".repeat(21845)+"a"
	for label: String in ["ascii","unicode"]:
		var text: String = ascii if label=="ascii" else unicode
		var encoded: Dictionary = _encode({"x":text})
		var read: Dictionary = _decode(encoded.data)
		checks[label+"_65536_bytes"] = text.to_utf8_buffer().size()==65536 and encoded.ok and read.ok and read.value.x==text
		checks[label+"_65537_encode_rejected"] = not _encode({"x":text+"b"}).ok
		checks[label+"_65537_decode_rejected"] = _rejected(_decode(('{"x":"'+text+'b"}').to_utf8_buffer()))
	# Decoded UTF-8 is 64KiB, while its legal escaped JSON text is 384KiB.
	# This must not inherit an incidental 128KiB token-buffer ceiling.
	var escaped: PackedByteArray = ('{"x":"'+"\\u0001".repeat(65536)+'"}').to_utf8_buffer()
	var control: String = String.chr(1).repeat(65536)
	var escaped_read: Dictionary = _decode(escaped)
	var escaped_written: Dictionary = _encode({"x":control})
	checks.escaped_384k_decode = escaped.size()>393216 and escaped_read.ok and escaped_read.value.x==control
	checks.escaped_384k_encode = escaped_written.ok and escaped_written.data==escaped and escaped_written.sizes.size()>4
	checks.escaped_65537_decode_rejected = _rejected(_decode(('{"x":"'+"\\u0001".repeat(65537)+'"}').to_utf8_buffer()))
	checks.escaped_65537_encode_rejected = not _encode({"x":control+String.chr(1)}).ok
	var key: Dictionary = {ascii:1}
	var key_encoded: Dictionary = _encode(key)
	var key_read: Dictionary = _decode(key_encoded.data)
	checks.key_65536 = key_encoded.ok and key_read.ok and key_read.value.get(ascii)==1
	checks.key_65537_rejected = not _encode({ascii+"b":1}).ok and _rejected(_decode(('{"'+ascii+'b":1}').to_utf8_buffer()))
	checks.reject_invalid_utf8 = _rejected(_decode(PackedByteArray([123,34,120,34,58,34,255,34,125])))
	checks.reject_unpaired_surrogate = _rejected(_decode('{"x":"\\uD800"}'.to_utf8_buffer()))
	var vertical_tab: Dictionary = _encode({"x":String.chr(11)})
	checks.standard_control_escape = vertical_tab.ok and vertical_tab.data=='{"x":"\\u000B"}'.to_utf8_buffer() and _decode(vertical_tab.data).ok

func _chunks(checks: Dictionary) -> void:
	var prefix: String = '{"padding":"'
	var text: String = "a".repeat(32768-prefix.to_utf8_buffer().size()-1)+"😀中文"
	var unicode_raw: PackedByteArray = (prefix+text+'"}').to_utf8_buffer()
	var unicode_read: Dictionary = _decode(unicode_raw)
	checks.unicode_crosses_32k = unicode_raw[32767]==240 and unicode_read.ok and unicode_read.value.padding==text and unicode_read.source_calls>=3
	var number_prefix_bytes: int = (prefix+'","value":').to_utf8_buffer().size()
	var padding: String = "a".repeat(32768-5-number_prefix_bytes)
	var number_raw: PackedByteArray = (prefix+padding+'","value":9223372036854775807}').to_utf8_buffer()
	var number_read: Dictionary = _decode(number_raw)
	checks.number_crosses_32k = number_raw[32763]==57 and number_read.ok and number_read.value.value==9223372036854775807 and number_read.value.padding==padding
	var written: Dictionary = _encode({"padding":text})
	checks.writer_chunks = written.ok and written.data==unicode_raw and written.sizes==[32768,unicode_raw.size()-32768]
	var small_chunks: Dictionary = _decode(unicode_raw,{"chunk_size":7})
	checks.small_chunks_same_result = small_chunks.ok and small_chunks.value==unicode_read.get("value",{})
	checks.source_oversize_rejected = _rejected(_decode(unicode_raw,{"chunk_size":32769}))

func _failures(checks: Dictionary) -> void:
	var value: Dictionary = {"x":"a".repeat(65536)}
	var frozen: PackedByteArray = var_to_bytes(value)
	var raw: PackedByteArray = ('{"x":"'+value.x+'"}').to_utf8_buffer()
	var original: PackedByteArray = raw.duplicate()
	var denied: Callable = func(_bytes: int) -> bool: return false
	var one_chunk: Callable = func(requested: int) -> bool: return requested<=32768
	var read: Dictionary = _decode(raw,{"budget":denied})
	checks.decode_budget_before_source = _rejected(read) and read.source_calls==0 and read.bytes==0
	read = _decode(raw,{"budget":one_chunk})
	checks.decode_cancel_midway_no_candidate = _rejected(read) and read.source_calls==1 and read.bytes==32768
	read = _decode(raw,{"fail_after_bytes":32768})
	checks.source_failure_no_candidate = _rejected(read) and read.source_calls==2 and read.bytes==32768 and read.error=="boundary-source-failure"
	read = _decode(raw,{"expected_hash":"0".repeat(64)})
	checks.sha_failure_no_candidate = _rejected(read) and read.bytes==raw.size() and read.error.contains("SHA-256")
	checks.truncated_no_candidate = _rejected(_decode('{"x":1'.to_utf8_buffer()))
	checks.extra_root_no_candidate = _rejected(_decode('{"x":1} {}'.to_utf8_buffer()))
	checks.empty_document_no_candidate = _rejected(_decode(PackedByteArray()))
	var encoded: Dictionary = _encode(value,{"budget":denied})
	checks.encode_budget_before_sink = not encoded.ok and encoded.sink_calls==0 and encoded.bytes==0 and encoded.data.is_empty()
	encoded = _encode(value,{"budget":one_chunk})
	checks.encode_cancel_boundary = not encoded.ok and encoded.sink_calls==1 and encoded.bytes==32768 and encoded.data.size()==32768
	encoded = _encode(value,{"fail_after_chunks":1})
	checks.encode_sink_failure = not encoded.ok and encoded.sink_calls==2 and encoded.bytes==32768 and encoded.error=="boundary-sink-failure"
	checks.input_unchanged_on_failure = var_to_bytes(value)==frozen and raw==original
	var reused: HospitalJsonStream = HospitalJsonStream.new()
	var first: Dictionary = _decode('{"x":1}'.to_utf8_buffer(),{"codec":reused})
	var failed: Dictionary = _decode('{"x":2}'.to_utf8_buffer(),{"codec":reused,"expected_hash":"0".repeat(64)})
	var recovered: Dictionary = _decode('{"x":3}'.to_utf8_buffer(),{"codec":reused})
	checks.decoder_reuse_after_failure = first.ok and first.value=={"x":1} and _rejected(failed) and recovered.ok and recovered.value=={"x":3}
	var writer: HospitalJsonStream = HospitalJsonStream.new()
	var rejected_write: Dictionary = _encode(value,{"codec":writer,"budget":denied})
	var accepted_write: Dictionary = _encode({"x":4},{"codec":writer})
	checks.encoder_reuse_after_failure = not rejected_write.ok and accepted_write.ok and accepted_write.data=='{"x":4}'.to_utf8_buffer() and accepted_write.sha256==_sha(accepted_write.data)

func _nested_arrays(count: int, leaf: Variant) -> Dictionary:
	var value: Variant = leaf
	for _index: int in count:
		value = [value]
	return {"x":value}

func _float_bits(value: Variant) -> PackedByteArray:
	if typeof(value)!=TYPE_FLOAT:
		return PackedByteArray()
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0,value)
	return bytes

func _rejected(result: Dictionary) -> bool:
	return not result.get("ok",false) and result.get("value",null) is Dictionary and result.value.is_empty()

func _decode(raw: PackedByteArray, options: Dictionary = {}) -> Dictionary:
	var state: Dictionary = {"position":0,"calls":0}
	var source: Callable = func() -> Dictionary:
		state.calls += 1
		if options.has("fail_after_bytes") and state.position>=int(options.fail_after_bytes):
			return {"ok":false,"error":"boundary-source-failure"}
		var begin: int = int(state.position)
		state.position = mini(raw.size(),begin+int(options.get("chunk_size",32768)))
		return {"ok":true,"data":raw.slice(begin,int(state.position))}
	var codec: HospitalJsonStream = options.get("codec",HospitalJsonStream.new())
	var budget: Callable = options.get("budget",func(_bytes: int) -> bool: return true)
	var result: Dictionary = codec.decode_from(raw.size(),str(options.get("expected_hash",_sha(raw))),budget,source)
	result.bytes = codec.bytes
	result.source_calls = state.calls
	return result

func _encode(value: Dictionary, options: Dictionary = {}) -> Dictionary:
	var state: Dictionary = {"data":PackedByteArray(),"sizes":[],"calls":0}
	var sink: Callable = func(chunk: PackedByteArray) -> Dictionary:
		state.calls += 1
		if options.has("fail_after_chunks") and state.sizes.size()>=int(options.fail_after_chunks):
			return {"ok":false,"error":"boundary-sink-failure"}
		state.data.append_array(chunk)
		state.sizes.append(chunk.size())
		return {"ok":true}
	var codec: HospitalJsonStream = options.get("codec",HospitalJsonStream.new())
	var budget: Callable = options.get("budget",func(_bytes: int) -> bool: return true)
	var accepted: bool = codec.encode_to(value,budget,sink)
	return {"ok":accepted,"error":codec.error,"data":state.data,"sizes":state.sizes,"sink_calls":state.calls,"bytes":codec.bytes,"sha256":codec.digest}

func _sha(raw: PackedByteArray) -> String:
	var hash: HashingContext = HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	if not raw.is_empty():
		hash.update(raw)
	return hash.finish().hex_encode()
