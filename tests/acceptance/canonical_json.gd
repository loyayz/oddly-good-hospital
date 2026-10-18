extends RefCounted

func run(t, _content: HospitalContent) -> void:
	var first: Dictionary = {"z":0}
	first[StringName("array")] = [{"z":4,StringName("a"):3}]
	first[StringName("a")] = {"z":2,StringName("a"):1}
	var reverse: Dictionary = {"a":{"a":1,"z":2},"array":[{"a":3,"z":4}],"z":0}
	var expected: PackedByteArray = '{"a":{"a":1,"z":2},"array":[{"a":3,"z":4}],"z":0}'.to_utf8_buffer()
	var original: PackedByteArray = var_to_bytes(first)
	# Real String lookup must find the original StringName entry. Neither the
	# production encoder nor this check rewrites the source dictionary's keys.
	var lookup: bool = first["a"]["a"]==1 and first[StringName("z")]==0 and first["array"][0]["a"]==3
	var encoder: HospitalJsonStream = HospitalJsonStream.new()
	var cold: Dictionary = _encode(first,encoder)
	var reversed: Dictionary = _encode(reverse,encoder)
	var warm: Dictionary = _encode(first,encoder)
	var independent: Dictionary = _encode(first,HospitalJsonStream.new())
	var cursor: Dictionary = {"position":0}
	var source: Callable = func() -> Dictionary:
		var data: PackedByteArray = cold.data
		var begin: int = int(cursor.position)
		cursor.position = mini(data.size(),begin+HospitalJsonStream.CHUNK)
		return {"ok":true,"data":data.slice(begin,int(cursor.position))}
	var decoder: HospitalJsonStream = HospitalJsonStream.new()
	var restored: Dictionary = decoder.decode_from(int(cold.bytes),str(cold.sha256),_budget,source)
	var roundtrip: Dictionary = _encode(restored.get("value",{}),encoder)
	var invalid: Dictionary = _encode({1:"not a text key"},encoder)
	var exact: bool = cold.ok and reversed.ok and warm.ok and independent.ok and restored.ok and roundtrip.ok \
		and cold.data==expected and reversed.data==expected and warm.data==expected and independent.data==expected and roundtrip.data==expected \
		and cold.sha256==reversed.sha256 and cold.sha256==warm.sha256 and cold.sha256==independent.sha256 and cold.sha256==roundtrip.sha256 \
		and restored.value==reverse and var_to_bytes(first)==original
	t.check("CORE-44",lookup and exact and not invalid.ok and str(invalid.error).contains("键必须是字符串"),{"string_lookup_preserves_stringname":lookup,"all_canonical_bytes_and_hashes_equal":exact,"expected":expected.get_string_from_utf8(),"mixed":cold.data.get_string_from_utf8(),"reversed":reversed.data.get_string_from_utf8(),"cold_sha256":cold.sha256,"roundtrip_sha256":roundtrip.sha256,"source_unchanged":var_to_bytes(first)==original,"invalid_key_rejected":not invalid.ok,"invalid_key_error":invalid.error})

func _encode(value: Dictionary, encoder: HospitalJsonStream) -> Dictionary:
	var captured: Dictionary = {"data":PackedByteArray()}
	var sink: Callable = func(chunk: PackedByteArray) -> Dictionary:
		captured.data.append_array(chunk)
		return {"ok":true}
	var accepted: bool = encoder.encode_to(value,_budget,sink)
	return {"ok":accepted,"data":captured.data,"bytes":encoder.bytes,"sha256":encoder.digest,"error":encoder.error}

func _budget(_bytes: int) -> bool:
	return true
