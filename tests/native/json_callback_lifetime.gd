extends SceneTree

func _initialize() -> void:
	var results: Dictionary = {}
	for mode: String in ["encode_ok","encode_bad_key","encode_budget","encode_sink","decode_ok","decode_bad_json","decode_budget","decode_source","decode_invalid_declaration"]:
		results[mode] = _check(mode)
	var passed: bool = not false in results.values()
	print("JSON_CALLBACK_RESULT="+JSON.stringify({"ok":passed,"checks":results,"scope":"Synchronous JSON callback lifetime, not a successful product save budget."}))
	quit(0 if passed else 1)

func _check(mode: String) -> bool:
	var codec: HospitalJsonStream = HospitalJsonStream.new()
	var weak: WeakRef = weakref(codec)
	var owner: Dictionary = {"codec":codec,"calls":0}
	var raw: PackedByteArray = '{"x":1}'.to_utf8_buffer() if mode != "decode_bad_json" else '{"x":'.to_utf8_buffer()
	var hash: HashingContext = HashingContext.new()
	hash.start(HashingContext.HASH_SHA256); hash.update(raw)
	var checksum: String = hash.finish().hex_encode()
	var budget: Callable = func(_bytes: int) -> bool:
		owner.calls += 1
		return mode != "encode_budget" and mode != "decode_budget"
	var sink: Callable = func(_bytes: PackedByteArray) -> Dictionary:
		owner.calls += 1
		return {"ok":mode != "encode_sink","error":"sink-failure"}
	var delivered: Array[bool] = [false]
	var source: Callable = func() -> Dictionary:
		owner.calls += 1
		if mode == "decode_source": return {"ok":false,"error":"source-failure"}
		if delivered[0]: return {"ok":true,"data":PackedByteArray()}
		delivered[0] = true
		return {"ok":true,"data":raw}
	var operation_ok: bool
	if mode.begins_with("encode"):
		operation_ok = codec.encode_to({1:"bad"} if mode == "encode_bad_key" else {"x":1},budget,sink)
	else:
		operation_ok = codec.decode_from(-1 if mode == "decode_invalid_declaration" else raw.size(),checksum,budget,source).ok
	var expected_ok: bool = mode.ends_with("_ok")
	var released: bool = not codec._budget.is_valid() and not codec._sink.is_valid() and not codec._source.is_valid()
	budget = Callable(); sink = Callable(); source = Callable()
	owner = {}
	codec = null
	return operation_ok == expected_ok and released and weak.get_ref() == null
