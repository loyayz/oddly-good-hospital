extends RefCounted

const FORMAT_VERSION: int = 1

# Only frozen input facts and scalar observation metadata are stored. Services,
# Nodes and player profiles never enter this cache. Every read returns a clone.
var _directory: String = ""
var _rebuild: bool = false
var _content: HospitalContent
var _identity: String = ""
var _builder: String = ""
var _builder_hash: String = ""
var _source_identity: String = ""
var _states: Dictionary = {}
var _started: Dictionary = {}
var observations: Array = []

func _init(content: HospitalContent, builder: String) -> void:
	_content = content
	_builder = builder
	if not FileAccess.file_exists("res://fixture-config.json"): return
	var parser: JSON = JSON.new()
	if parser.parse(FileAccess.get_file_as_string("res://fixture-config.json"))!=OK: return
	var config: Variant = parser.data
	if not config is Dictionary: return
	_source_identity = str(config.get("identity",""))
	_builder_hash = FileAccess.get_sha256(builder)
	# The producer defines input facts; the format defines how they are stored.
	# Reader diagnostics do not change facts produced by the same game/builder.
	var identity: String = _source_identity+_builder_hash+"acceptance-facts-v"+str(FORMAT_VERSION)
	_identity = identity.sha256_text()
	_directory = str(config.get("directory","")).path_join(_identity).path_join(builder.get_file().get_basename())
	_rebuild = bool(config.get("rebuild",false))

func read(key: String) -> Dictionary:
	var started: int = Time.get_ticks_msec()
	_started[key] = started
	if _states.has(key):
		_note(key,"memory",started)
		return _states[key].duplicate(true)
	if _directory.is_empty() or _rebuild: return {}
	var path: String = _directory.path_join(key+".json")
	if not FileAccess.file_exists(path): return {}
	var parser: JSON = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path))!=OK: return {}
	var envelope: Variant = parser.data
	if not envelope is Dictionary or envelope.get("version",0)!=FORMAT_VERSION: return {}
	if envelope.get("identity","")!=_identity or envelope.get("builder","")!=_builder or envelope.get("key","")!=key: return {}
	if envelope.get("source_identity","")!=_source_identity or envelope.get("builder_sha256","")!=_builder_hash: return {}
	if not envelope.get("data") is String or str(envelope.data).sha256_text()!=envelope.get("data_sha256",""): return {}
	var bytes: PackedByteArray = Marshalls.base64_to_raw(envelope.data)
	var hashing: HashingContext = HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	if hashing.finish().hex_encode()!=envelope.get("sha256",""): return {}
	var state: Variant = bytes_to_var(bytes)
	if not state is Dictionary or not _valid(state): return {}
	_states[key] = state.duplicate(true)
	_note(key,"disk",started)
	return state.duplicate(true)

func publish(key: String, state: Dictionary) -> bool:
	if not _valid(state): return false
	_states[key] = state.duplicate(true)
	if not _directory.is_empty():
		DirAccess.make_dir_recursive_absolute(_directory)
		var bytes: PackedByteArray = var_to_bytes(state)
		var hashing: HashingContext = HashingContext.new()
		hashing.start(HashingContext.HASH_SHA256)
		hashing.update(bytes)
		var encoded: String = Marshalls.raw_to_base64(bytes)
		var envelope: Dictionary = {"version":FORMAT_VERSION,"identity":_identity,"source_identity":_source_identity,"builder":_builder,"builder_sha256":_builder_hash,"writer_sha256":FileAccess.get_sha256(get_script().resource_path),"key":key,"created_utc":Time.get_datetime_string_from_system(true),"sha256":hashing.finish().hex_encode(),"data_sha256":encoded.sha256_text(),"data":encoded}
		var path: String = _directory.path_join(key+".json")
		var temporary: String = path+"."+HospitalSnapshots.uuid()+".tmp"
		var file: FileAccess = FileAccess.open(temporary,FileAccess.WRITE)
		if file==null: return false
		file.store_string(JSON.stringify(envelope))
		file.close()
		if DirAccess.rename_absolute(temporary,path)!=OK: return false
	_note(key,"built",int(_started.get(key,Time.get_ticks_msec())))
	return true

func _valid(state: Dictionary) -> bool:
	if not state.get("facts") is Dictionary: return false
	return WorldState.new(state.facts.duplicate(true)).validate(_content).is_empty()

func _note(key: String, source: String, started: int) -> void:
	var observation: Dictionary = {"key":key,"builder":_builder,"identity":_identity,"source":source,"elapsed_ms":Time.get_ticks_msec()-started}
	observations.append(observation)
	print("FIXTURE "+JSON.stringify(observation))
