import pathlib,json,shutil,hashlib
R=pathlib.Path(__file__).resolve().parent; D=R/'diagnostic-root-v1';D.mkdir(exist_ok=False);S=D/'source';S.mkdir();m=json.loads((R/'exporter-integration-r2/source-after-integration.json').read_text())
for f in m['files']:
 p=S/f['path'];p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(R/'source'/f['path'],p);assert hashlib.sha256(p.read_bytes()).hexdigest()==f['sha256']
# Import metadata is generated cache, copied only to resolve unchanged global class names.
shutil.copytree(R/'source/.godot',S/'.godot')
shutil.copy2(R/'run_engine.py',D/'run_engine.py');(D/'evidence').mkdir()
p=S/'tools/performance/current/diagnostic_v1.gd';t=(S/'tools/performance/current/plain_v4.gd').read_text();t=t.replace('var output: String','const Profile = preload("res://tools/performance/step_profile.gd")\nvar output: String')
t=t.replace('var prefix_steps: int = 0','var prefix_steps: int = 0\n\tvar profile_enabled: bool = false\n\tvar soft_seconds: float = 360.0')
t=t.replace('for arg: String in OS.get_cmdline_user_args():','for arg: String in OS.get_cmdline_user_args():\n\t\tif arg=="--profile": profile_enabled=true\n\t\tif arg.begins_with("--soft-seconds="): soft_seconds=arg.trim_prefix("--soft-seconds=").to_float()')
needle='\tvar init_us: int = Time.get_ticks_usec()-init_start'
attach='''
	var observer: RefCounted = null
	var attach_report: Dictionary = {"enabled":profile_enabled}
	if profile_enabled:
		observer=Profile.new();observer.source_directory=output+".generated"
		var before_bytes: PackedByteArray = var_to_bytes(world.freeze())
		var old: HospitalSimulation = sim
		var attach_start: int = Time.get_ticks_usec()
		var attached: HospitalSimulation = observer.attach(old,false)
		attach_report.elapsed_us=Time.get_ticks_usec()-attach_start
		attach_report.facts_rng_bytes_unchanged=before_bytes==var_to_bytes(world.freeze())
		attach_report.errors=observer.errors.duplicate()
		attach_report.returned_instance=attached!=null
		var references_ok: bool = attached!=null
		if attached!=null:
			for key: String in ["world","content","space","clinic","services","_commands","_command_boundary","_save_commands","_command_events","_business_handlers"]:
				var same: bool = is_same(old.get(key),attached.get(key))
				attach_report[key+"_same_reference"]=same;references_ok=references_ok and same
		attach_report.references_ok=references_ok
		write_json(output+".attach.json",attach_report)
		if attached==null or not references_ok or not attach_report.facts_rng_bytes_unchanged or not observer.errors.is_empty():
			write_json(output,{"complete":false,"reason":"attach gate failed; no continuation","attach":attach_report});quit(2);return
		sim=attached;old=null
'''
t=t.replace(needle,attach+needle)
t=t.replace('\tfor index: int in prefix_steps+steps:','\tfor index: int in prefix_steps+steps:\n\t\tif Time.get_ticks_usec()-wall_start>=soft_seconds*1000000.0: errors.append("soft deadline at complete boundary");break')
t=t.replace('\t\tvar started: int = Time.get_ticks_usec()','\t\tif observer!=null: observer.begin_step()\n\t\tvar started: int = Time.get_ticks_usec()')
t=t.replace('\t\tif result==null:', '\t\tif observer!=null:\n\t\t\tobserver.end_step(result,elapsed)\n\t\t\tif not observer.errors.is_empty(): errors.append("observer error");break\n\t\tif result==null:')
t=t.replace('\tvar final: Dictionary = snapshot(world)','\tif observer!=null: write_json(output+".profile.json",observer.report())\n\tvar final: Dictionary = snapshot(world)')
t=t.replace('"mode":"plain_cpu_full_step"','"mode":"root_diagnostic" if profile_enabled else "paired_plain_diagnostic","attach":attach_report,"soft_seconds":soft_seconds')
p.write_text(t)
(D/'copy-proof.json').write_text(json.dumps({'copied_source_files':len(m['files']),'original_aggregate':m['source_aggregate_sha256'],'production_changes':0,'added_driver':str(p),'driver_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'cache_copy':'generated .godot metadata only, excluded from source identity'},indent=2))
state=json.loads((R/'phase-state.json').read_text());state.update(phase='post_A_attribution',baseline_runs=5,baseline_series_complete=True,baseline_remaining_planned=0,active_run=None,business_reconciliation='All five exact facts bytes and ordered events equal; frozen completed-audit',next='Qualify independent diagnostic driver, fixed800 paired plain/root diagnostic; no production changes');(R/'phase-state.json').write_text(json.dumps(state,indent=2))
print(D)
