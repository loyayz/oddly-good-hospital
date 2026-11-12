extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
 var args:PackedStringArray=OS.get_cmdline_user_args();var selected:String=args[0];var content:HospitalContent=HospitalContent.new();var suite:RefCounted=preload("res://tests/acceptance/space.gd").new();suite.content=content
 var result:Dictionary
 match selected:
  "body":result=preload("res://tests/acceptance/structural_body_resident.gd").new().run(suite)
  "source":result=preload("res://tests/acceptance/navigation_source_lifecycle.gd").new().run_case(suite)
  "floor":result=preload("res://tests/acceptance/floor_static_loading.gd").new().run_case(suite)
  "perf08":
   result=preload("res://tests/acceptance/performance_contracts.gd").new()._case_08(content);result.ok=not result.checks.values().has(false)
  "detour":result=preload("res://tests/acceptance/detour_geometry_reuse.gd").new().run(suite)
  "local":result=preload("res://tests/acceptance/local_return_geometry.gd").new().run(content)
  _:result={"ok":false,"unknown":selected}
 FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));quit(0 if result.ok else 1)
