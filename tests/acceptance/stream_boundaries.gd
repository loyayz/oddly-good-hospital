extends RefCounted

func run(t, _content: HospitalContent) -> void:
	var value: Dictionary = {"text":"a".repeat(32760)+"中文😀"+"b".repeat(4096),"maximum":9223372036854775807,"items":[true,false,null,-0.25]}
	var encoded: Array[PackedByteArray] = []
	var writer: HospitalJsonStream = HospitalJsonStream.new()
	var budget: Callable = func(_bytes: int) -> bool: return true
	var sink: Callable = func(chunk: PackedByteArray) -> Dictionary:
		encoded.append(chunk)
		return {"ok":true}
	var correct: bool = writer.encode_to(value,budget,sink)
	var cursor: Array[int] = [0]
	var source: Callable = func() -> Dictionary:
		if cursor[0]==encoded.size(): return {"ok":true,"data":PackedByteArray()}
		var chunk: PackedByteArray = encoded[cursor[0]]
		cursor[0] += 1
		return {"ok":true,"data":chunk}
	var read: Dictionary = HospitalJsonStream.new().decode_from(writer.bytes,writer.digest,budget,source)
	correct = correct and read.ok and read.value==value
	for raw: PackedByteArray in ["{\"x\":1,\"x\":2}".to_utf8_buffer(),"{\"x\":9223372036854775808}".to_utf8_buffer(),PackedByteArray([123,34,120,34,58,34,255,34,125]),"{\"x\":1".to_utf8_buffer()]:
		var used: Array[bool] = [false]
		var invalid_source: Callable = func() -> Dictionary:
			if used[0]: return {"ok":true,"data":PackedByteArray()}
			used[0] = true
			return {"ok":true,"data":raw}
		var checksum: HashingContext = HashingContext.new()
		checksum.start(HashingContext.HASH_SHA256)
		checksum.update(raw)
		var invalid: Dictionary = HospitalJsonStream.new().decode_from(raw.size(),checksum.finish().hex_encode(),budget,invalid_source)
		correct = correct and not invalid.ok and invalid.value.is_empty()
	var zip_boundaries: Dictionary = load("res://tests/acceptance/zip_library_boundaries.gd").new().run()
	correct = correct and zip_boundaries.ok
	t.check("CORE-49",correct,{"chunk_crossing_and_utf8":read.ok,"unsafe_inputs_rejected":correct,"zip_boundaries":zip_boundaries})
