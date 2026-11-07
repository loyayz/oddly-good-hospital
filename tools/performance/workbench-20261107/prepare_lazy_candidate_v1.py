from pathlib import Path
import json,shutil,hashlib,difflib
R=Path(__file__).resolve().parent;D=R/'candidate-lazy-copy-v1';S=D/'source';S.mkdir();m=json.loads((R/'exporter-integration-r2/source-after-integration.json').read_text())
for f in m['files']:
 p=S/f['path'];p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(R/'source'/f['path'],p);assert hashlib.sha256(p.read_bytes()).hexdigest()==f['sha256']
shutil.copytree(R/'source/.godot',S/'.godot');shutil.copy2(R/'run_engine.py',D/'run_engine.py')
p=S/'game/building/hospital_movement.gd';original=p.read_text();start=original.index('func _detour_path_clear(');end=original.index('\nfunc ',start+1);body=original[start:end];assert body.count('var sample: Dictionary = actor.duplicate(true)')==1
body=body.replace('var sample: Dictionary = actor.duplicate(true)','var sample: Dictionary = {}').replace('space._actor_rect(sample,origin)','space._actor_rect(actor,origin)')
assert body.count('sample.facing = ')==2
body=body.replace('\t\t\t\tsample.facing = ', '\t\t\t\tif sample.is_empty(): sample = actor.duplicate(true)\n\t\t\t\tsample.facing = ',1)
body=body.replace('\t\t\t\t\tsample.facing = ', '\t\t\t\t\tif sample.is_empty(): sample = actor.duplicate(true)\n\t\t\t\t\tsample.facing = ',1)
t=original[:start]+body+original[end:];p.write_text(t);(D/'evidence/production.diff').write_text(''.join(difflib.unified_diff(original.splitlines(True),t.splitlines(True),fromfile='A/game/building/hospital_movement.gd',tofile='B/game/building/hospital_movement.gd')))
(D/'evidence/change.json').write_text(json.dumps({'only_production_path':'game/building/hospital_movement.gd','before_sha256':hashlib.sha256(original.encode()).hexdigest(),'after_sha256':hashlib.sha256(t.encode()).hexdigest(),'A_full_aggregate':m['source_aggregate_sha256'],'purpose':'Private lazy deepcopy only; initial rectangle call preserved'},indent=2))
runner='''extends SceneTree
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var output: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	if output.is_empty() or FileAccess.file_exists(output): quit(2);return
	var content: HospitalContent = HospitalContent.new()
	var results: Dictionary = {}
	var passed: bool = true
	for name: String in ["detour_step_proof","detour_segment_proof","movement_detour"]:
		print("SELECTED_BEGIN="+name)
		var started: int = Time.get_ticks_usec()
		var test: RefCounted = load("res://tests/acceptance/"+name+".gd").new()
		var result: Dictionary
		if name=="movement_detour":
			var suite: RefCounted = load("res://tests/acceptance/space.gd").new();suite.content=content
			result=test.run(suite)
		else: result=test.run(content)
		result.elapsed_us=Time.get_ticks_usec()-started
		results[name]=result;passed=passed and bool(result.get("passed",result.get("ok",false)))
		var f: FileAccess = FileAccess.open(output,FileAccess.WRITE);f.store_string(JSON.stringify({"complete":false,"results":results},"\\t"));f.close()
		print("SELECTED_END="+name+" "+str(passed))
	var f: FileAccess = FileAccess.open(output,FileAccess.WRITE);f.store_string(JSON.stringify({"complete":true,"passed":passed,"results":results},"\\t"));f.close()
	quit(0 if passed else 1)
'''
(S/'tools/performance/current/lazy_selected_tests.gd').write_text(runner)
# Diagnostic-only driver unchanged from qualified root driver; no profiling flag will be used.
shutil.copy2(R/'diagnostic-root-v1/source/tools/performance/current/diagnostic_v1.gd',S/'tools/performance/current/diagnostic_v1.gd')
print((D/'evidence/production.diff').read_text())
