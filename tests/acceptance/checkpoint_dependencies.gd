extends RefCounted

const Identity = preload("res://tests/acceptance/checkpoint_identity.gd")
const Store = preload("res://tests/acceptance/checkpoints.gd")

class Producer extends RefCounted:
	var description: Dictionary
	func _checkpoint_dependencies(_key: String) -> Dictionary:
		return description.duplicate(true)

func run(t, content: HospitalContent) -> void:
	var source: String = "extends RefCounted\nvar shared: int = 1\nfunc _root():\n\treturn _shared()\nfunc _shared():\n\treturn 1\nfunc _leaf():\n\treturn 2\nfunc _unrelated():\n\treturn 99\n"
	var recipes: Dictionary = {"root":{"methods":["_root"]},"leaf":{"parent":"root","methods":["_leaf"],"ticks":2},"other":{"methods":["_unrelated"],"ticks":5}}
	var path: String = "res://tests/acceptance/clinical_fixtures.gd"
	var first: Dictionary = Identity.describe(path,recipes,"leaf",source)
	var unrelated: Dictionary = Identity.describe(path,recipes,"leaf",source.replace("return 99","return 100"))
	var changed_recipes: Dictionary = recipes.duplicate(true)
	changed_recipes.other.ticks = 900
	var other_recipe: Dictionary = Identity.describe(path,changed_recipes,"leaf",source)
	changed_recipes.leaf.ticks = 3
	var own_recipe: Dictionary = Identity.describe(path,changed_recipes,"leaf",source)
	var ancestor: Dictionary = Identity.describe(path,recipes,"leaf",source.replace("return 1\n","return 3\n"))
	var declarations: Dictionary = Identity.describe(path,recipes,"leaf",source.replace("shared: int = 1","shared: int = 2"))
	var cyclic: Dictionary = {"root":{"parent":"leaf","methods":["_root"]},"leaf":{"parent":"root","methods":["_leaf"]}}
	var cycle_rejected: bool = Identity.describe(path,cyclic,"leaf",source).has("error")
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"独立命名前提",false,content)
	var state: Dictionary = {"facts":world.freeze(),"marker":1}
	var producer: RefCounted = Producer.new()
	producer.description = first
	var store: RefCounted = Store.new(content,path,weakref(producer))
	var directory: String = "user://checkpoint-dependencies-"+HospitalSnapshots.uuid()
	store._base_directory = directory
	store._rebuild = false
	var published: bool = store.publish("leaf",state)
	var reader: RefCounted = _reader(content,path,producer,directory)
	var restored: Dictionary = reader.read("leaf")
	var disk_hit: bool = restored==state and reader.observations.back().source=="disk" if not restored.is_empty() else false
	if not restored.is_empty():
		restored.marker = 99
		restored.facts.rng.arrival.state_decimal = "0"
	var independent: bool = reader.read("leaf")==state and world.freeze()==state.facts
	var changed_producer: RefCounted = Producer.new()
	changed_producer.description = own_recipe
	var own_rebuild: bool = _reader(content,path,changed_producer,directory).read("leaf").is_empty()
	var environment: RefCounted = _reader(content,path,producer,directory)
	environment._source_identity += "changed-runtime"
	var environment_rebuild: bool = environment.read("leaf").is_empty()
	var forced: RefCounted = _reader(content,path,producer,directory)
	forced._rebuild = true
	var force_rebuild: bool = forced.read("leaf").is_empty()
	var stored_path: String = store._directory.path_join("leaf.json")
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(stored_path))
	var original: Dictionary = envelope.duplicate(true)
	envelope.data_sha256 = "bad"
	_write(stored_path,envelope)
	var corrupt_rejected: bool = _reader(content,path,producer,directory).read("leaf").is_empty()
	envelope = original.duplicate(true)
	var invalid: Dictionary = state.duplicate(true)
	invalid.facts.inventory.units = -1
	var bytes: PackedByteArray = var_to_bytes(invalid)
	var hashing: HashingContext = HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	envelope.data = Marshalls.raw_to_base64(bytes)
	envelope.sha256 = hashing.finish().hex_encode()
	envelope.data_sha256 = str(envelope.data).sha256_text()
	_write(stored_path,envelope)
	var invalid_world_rejected: bool = _reader(content,path,producer,directory).read("leaf").is_empty()
	_write(stored_path,original)
	var details: Dictionary = {"unrelated_method_reused":first==unrelated,"unrelated_recipe_reused":first==other_recipe,
		"own_recipe_invalidated":first!=own_recipe,"ancestor_invalidated":first!=ancestor,"shared_declarations_invalidated":first!=declarations,
		"cycle_rejected":cycle_rejected,"published_legal_facts":published,"disk_hit":disk_hit,"independent_full_facts_rng":independent,
		"changed_recipe_misses":own_rebuild,"changed_environment_misses":environment_rebuild,"force_rebuild":force_rebuild,
		"corruption_rejected":corrupt_rejected,"valid_hash_invalid_world_rejected":invalid_world_rejected}
	var passed: bool = true
	for value: bool in details.values(): passed = passed and value
	t.check("CORE-50",passed,details)

func _reader(content: HospitalContent, path: String, producer: RefCounted, directory: String) -> RefCounted:
	var result: RefCounted = Store.new(content,path,weakref(producer))
	result._base_directory = directory
	result._rebuild = false
	return result

func _write(path: String, value: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()
