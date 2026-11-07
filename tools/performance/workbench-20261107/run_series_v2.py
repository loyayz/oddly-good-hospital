from pathlib import Path
import subprocess,sys,json,hashlib,time
R=Path(__file__).resolve().parent
protocol=R/sys.argv[1];spec=json.loads(protocol.read_text());assert spec['variant']=='A_current_accepted_production'
assert hashlib.sha256((R/spec['input']).read_bytes()).hexdigest()==spec['input_sha256']
assert hashlib.sha256((R/spec['tool']).read_bytes()).hexdigest()==spec['tool_sha256']
base=json.loads((R/'evidence/source-copy-proof.json').read_text())
for row in base['files']:assert hashlib.sha256((R/'source'/row['path']).read_bytes()).hexdigest()==row['sha256']
records=[]
for i in range(1,spec['repeats']+1):
 name=spec['run_prefix']+'-A%02d'%i
 assert not (R/'evidence'/name).exists(), 'Existing run: review and resume explicitly, never overwrite'
 env={}
 for path in ['/proc/loadavg','/proc/meminfo','/sys/fs/cgroup/cpu.max','/sys/fs/cgroup/memory.max','/sys/fs/cgroup/cpu.stat']:
  p=Path(path);env[path]=p.read_text() if p.exists() else None
 (R/'evidence'/(name+'-environment-before.json')).write_text(json.dumps(env,indent=2))
 cmd=[sys.executable,'-B',str(R/'run_engine.py'),name,str(spec['max_process_seconds']),'--script','res://'+str(Path(spec['tool']).relative_to('source')),'--','--input='+str(R/spec['input']),'--output='+str(R/'evidence'/name/'result.json'),'--steps='+str(spec['steps_per_repeat']),'--prefix-steps='+str(spec['prefix_steps'])]
 subprocess.run(cmd,cwd=R,check=True)
 status=json.loads((R/'evidence'/name/'status.json').read_text());record={'run':name,'status':status};records.append(record)
 if status['returncode']!=0 or status['timed_out']:break
 report=json.loads((R/'evidence'/name/'result.json').read_text());record.update({'complete':report['complete'],'metrics':report['metrics'],'business':report['sample_business'],'prefix_business':report['prefix_business'],'prefix_wall_us':report['prefix_wall_us'],'all_wall_us':report['all_wall_us'],'initial_population':report['initial']['population'],'sample_start_population':report['sample_start_population'],'final_population':report['final']['population']})
 clinical=sum(v for k,v in report['sample_business']['clinical_work_ticks_observed_lower_bound'].items() if k!='reception')
 record['non_reception_clinical_work_ticks_lower_bound']=clinical
 if clinical<=0:
  record['qualification_error']='No non-reception clinical work in predefined sample window';break
 if not report['complete'] or report['errors'] or 'SCRIPT ERROR:' in (R/'evidence'/name/'raw.log').read_text():break
 (R/'evidence'/(spec['run_prefix']+'-series-progress.json')).write_text(json.dumps({'protocol_sha256':hashlib.sha256(protocol.read_bytes()).hexdigest(),'completed_records':records,'speedup_claim':False},indent=2))
(R/'evidence'/(spec['run_prefix']+'-series-result.json')).write_text(json.dumps({'protocol_sha256':hashlib.sha256(protocol.read_bytes()).hexdigest(),'records':records,'all_repeats_complete':len(records)==spec['repeats'] and all(x.get('complete',False) and not x.get('qualification_error') for x in records),'formal_performance_pass':None,'speedup_claim':False},indent=2))
