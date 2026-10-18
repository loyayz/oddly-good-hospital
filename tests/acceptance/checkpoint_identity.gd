extends RefCounted

static func file_dependencies(builder: String) -> Dictionary:
	var dependencies: Dictionary = {}
	_collect_preloads(FileAccess.get_file_as_string(builder),dependencies,{builder:true})
	return {"builder_sha256":FileAccess.get_sha256(builder),"external_sources":dependencies}

# Describes the actual named recipe, its ancestor recipes, and reachable local
# producer methods. Assertions and other recipes are not generation inputs.
static func describe(builder: String, recipes: Dictionary, key: String, source: String = "") -> Dictionary:
	if source.is_empty(): source = FileAccess.get_file_as_string(builder)
	var lines: PackedStringArray = source.replace("\r\n","\n").split("\n")
	var methods: Dictionary = {}
	var name: String = ""
	var header: PackedStringArray = []
	for line: String in lines:
		if line.begins_with("func "):
			name = line.trim_prefix("func ").get_slice("(",0)
			methods[name] = ""
		if name.is_empty(): header.append(line)
		else: methods[name] += line+"\n"
	var selected: Dictionary = {}
	var entries: Array[String] = []
	var error: String = _recipes(recipes,key,selected,entries,{})
	if not error.is_empty(): return {"error":error}
	var calls: RegEx = RegEx.new()
	calls.compile("\\b(_[A-Za-z0-9_]+)\\s*\\(")
	var bodies: Dictionary = {}
	var dependencies: Dictionary = {}
	var seen: Dictionary = {builder:true}
	_collect_preloads("\n".join(header),dependencies,seen)
	while not entries.is_empty():
		var entry: String = entries.pop_back()
		if bodies.has(entry) or entry=="_checkpoint_recipes": continue
		if not methods.has(entry): return {"error":"Missing producer method: "+entry}
		bodies[entry] = str(methods[entry]).sha256_text()
		_collect_preloads(methods[entry],dependencies,seen)
		for found: RegExMatch in calls.search_all(methods[entry]):
			var called: String = found.get_string(1)
			if methods.has(called) and called!="_checkpoint_recipes": entries.append(called)
	return {"builder":builder,"key":key,"recipes":selected,"shared_declarations_sha256":"\n".join(header).sha256_text(),
		"methods":bodies,"external_sources":dependencies}

static func _recipes(recipes: Dictionary, key: String, selected: Dictionary, entries: Array[String], visiting: Dictionary) -> String:
	if not recipes.has(key) or visiting.has(key): return "Unknown or cyclic checkpoint recipe: "+key
	if selected.has(key): return ""
	visiting[key] = true
	var recipe: Dictionary = recipes[key]
	selected[key] = recipe.duplicate(true)
	for method: String in recipe.get("methods",[]): entries.append(method)
	if recipe.has("generator"): entries.append(recipe.generator)
	var ancestors: Array = recipe.get("requires",[]).duplicate()
	if recipe.has("parent"): ancestors.append(recipe.parent)
	for ancestor: String in ancestors:
		var error: String = _recipes(recipes,ancestor,selected,entries,visiting)
		if not error.is_empty(): return error
	visiting.erase(key)
	return ""

static func _collect_preloads(source: String, result: Dictionary, seen: Dictionary) -> void:
	var expression: RegEx = RegEx.new()
	expression.compile("(?:preload|load)\\(\"(res://[^\"]+\\.gd)\"\\)")
	for found: RegExMatch in expression.search_all(source):
		var path: String = found.get_string(1)
		if seen.has(path): continue
		seen[path] = true
		result[path] = FileAccess.get_sha256(path)
		_collect_preloads(FileAccess.get_file_as_string(path),result,seen)
