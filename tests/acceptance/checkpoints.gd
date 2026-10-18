extends RefCounted

const FORMAT_VERSION: int = 2
const Identity = preload("res://tests/acceptance/checkpoint_identity.gd")

# Only frozen input facts and scalar observation metadata are stored. Services,
# Nodes and player profiles never enter this cache. Every read returns a clone.
var _directory: String = ""
var _rebuild: bool = false
var _content: HospitalContent
var _identity: String = ""
var _builder: String = ""
var _builder_hash: String = ""
var _source_identity: String = ""
var _source_basis: Dictionary = {}
var _base_directory: String = ""
var _builder_file_hash: String = ""
var _producer: WeakRef
var _contexts: Dictionary = {}
var _fallback_description: Dictionary = {}
var _states: Dictionary = {}
var _started: Dictionary = {}
var observations: Array = []

func _init(content: HospitalContent, builder: String, producer: WeakRef = null) -> void:
	_content = content
	_builder = builder
	_producer = producer
	_builder_file_hash = FileAccess.get_sha256(builder)
	if producer==null: _fallback_description = Identity.file_dependencies(builder)
	if not FileAccess.file_exists("res://fixture-config.json"): return
	var parser: JSON = JSON.new()
	if parser.parse(FileAccess.get_file_as_string("res://fixture-config.json"))!=OK: return
	var config: Variant = parser.data
	if not config is Dictionary: return
	_source_identity = str(config.get("identity",""))
	_source_basis = config.get("basis",{}).duplicate(true)
	_base_directory = str(config.get("directory",""))
	_rebuild = bool(config.get("rebuild",false))

func _select_key(key: String) -> bool:
	if not _contexts.has(key):
		var description: Dictionary = _fallback_description
		if _producer!=null:
			var producer: RefCounted = _producer.get_ref()
			if producer==null: return false
			description = producer.call("_checkpoint_dependencies",key)
			if description.has("error"):
				push_error("Checkpoint producer: "+str(description.error))
				return false
		var producer_json: String = JSON.stringify(description)
		var producer_hash: String = producer_json.sha256_text()
		var identity: String = (_source_identity+_content.content_fingerprint+producer_hash+"acceptance-facts-v"+str(FORMAT_VERSION)).sha256_text()
		_contexts[key] = {"identity":identity,"producer_sha256":producer_hash,"description":description,"producer_json":producer_json}
	_identity = _contexts[key].identity
	_builder_hash = _contexts[key].producer_sha256
	_directory = _base_directory.path_join(_identity).path_join(_builder.get_file().get_basename()) if not _base_directory.is_empty() else ""
	return true

func read(key: String) -> Dictionary:
	if not _select_key(key): return {}
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
	if envelope.get("source_identity","")!=_source_identity or envelope.get("producer_sha256","")!=_builder_hash: return {}
	if envelope.get("producer_json","")!=_contexts[key].producer_json or envelope.get("content_fingerprint","")!=_content.content_fingerprint: return {}
	if envelope.get("producer",{})!=JSON.parse_string(_contexts[key].producer_json): return {}
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
	if not _select_key(key): return false
	if not _valid(state): return false
	_states[key] = state.duplicate(true)
	if not _directory.is_empty():
		DirAccess.make_dir_recursive_absolute(_directory)
		var bytes: PackedByteArray = var_to_bytes(state)
		var hashing: HashingContext = HashingContext.new()
		hashing.start(HashingContext.HASH_SHA256)
		hashing.update(bytes)
		var encoded: String = Marshalls.raw_to_base64(bytes)
		var envelope: Dictionary = {"version":FORMAT_VERSION,"identity":_identity,"source_identity":_source_identity,"source_basis":_source_basis,"builder":_builder,"builder_file_sha256":_builder_file_hash,
			"producer_sha256":_builder_hash,"producer":_contexts[key].description,"producer_json":_contexts[key].producer_json,"content_fingerprint":_content.content_fingerprint,
			"writer_sha256":FileAccess.get_sha256(get_script().resource_path),"key":key,"created_utc":Time.get_datetime_string_from_system(true),"sha256":hashing.finish().hex_encode(),"data_sha256":encoded.sha256_text(),"data":encoded}
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
