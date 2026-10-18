@tool
extends EditorPlugin

# FileAccess checks the published GLB identity, while ResourceLoader follows the
# original import remap. The exporter's normal imported-resource pass keeps the
# scene and its dependencies; this adds only the manifest's exact source bytes.
class SourceAssetsExport extends EditorExportPlugin:

	const MANIFEST: String = "res://assets/models/stage01-production.json"
	var _assets: Dictionary = {}

	func _get_name() -> String:
		return "ProductionSourceAssets"

	func _export_begin(_features: PackedStringArray, _debug: bool, _path: String, _flags: int) -> void:
		_assets.clear()
		var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if not manifest is Dictionary or not manifest.get("assets") is Array:
			push_error(MANIFEST+": published asset manifest is invalid")
			return
		for record: Dictionary in manifest.assets:
			_assets["res://"+str(record.asset_path)] = record

	func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
		if not _assets.has(path):
			return
		var record: Dictionary = _assets[path]
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
		var digest: HashingContext = HashingContext.new()
		digest.start(HashingContext.HASH_SHA256)
		digest.update(bytes)
		if bytes.size()!=int(record.bytes) or digest.finish().hex_encode()!=str(record.asset_sha256):
			push_error(path+": published source bytes do not match the asset manifest")
			return
		add_file(path,bytes,false)

var _exporter: EditorExportPlugin = SourceAssetsExport.new()

func _enter_tree() -> void:
	add_export_plugin(_exporter)

func _exit_tree() -> void:
	remove_export_plugin(_exporter)
