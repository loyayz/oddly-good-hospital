extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
 var result:Dictionary=load("res://tests/acceptance/component_turn_root_edges.gd").new().run(HospitalContent.new())
 FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print(JSON.stringify(result));quit(0 if result.ok else 1)
