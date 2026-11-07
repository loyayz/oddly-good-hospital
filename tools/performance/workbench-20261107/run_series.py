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
 name='baseline160-A%02d-v1'%i
 assert not (R/'evidence'/name).exists(), 'Existing run: review and resume explicitly, never overwrite'
 env={}
 for path in ['/proc/loadavg','/proc/meminfo','/sys/fs/cgroup/cpu.max','/sys/fs/cgroup/memory.max','/sys/fs/cgroup/cpu.stat']:
  p=Path(path);env[path]=p.read_text() if p.exists() else None
 (R/'evidence'/(name+'-environment-before.json')).write_text(json.dumps(env,indent=2))
 cmd=[sys.executable,'-B',str(R/'run_engine.py'),name,str(spec['max_process_seconds']),'--script','res://'+str(Path(spec['tool']).relative_to('source')),'--','--input='+str(R/spec['input']),'--output='+str(R/'evidence'/name/'result.json'),'--steps='+str(spec['steps_per_repeat'])]
 subprocess.run(cmd,cwd=R,check=True)
 status=json.loads((R/'evidence'/name/'status.json').read_text());record={'run':name,'status':status};records.append(record)
 if status['returncode']!=0 or status['timed_out']:break
 report=json.loads((R/'evidence'/name/'result.json').read_text());record.update({'complete':report['complete'],'metrics':report['metrics'],'business':report['business'],'initial_population':report['initial']['population'],'final_population':report['final']['population']})
 if not report['complete'] or report['errors']:break
 (R/'evidence'/'baseline160-series-v1-progress.json').write_text(json.dumps({'protocol_sha256':hashlib.sha256(protocol.read_bytes()).hexdigest(),'completed_records':records,'speedup_claim':False},indent=2))
(R/'evidence'/'baseline160-series-v1-result.json').write_text(json.dumps({'protocol_sha256':hashlib.sha256(protocol.read_bytes()).hexdigest(),'records':records,'all_repeats_complete':len(records)==spec['repeats'] and all(x.get('complete',False) for x in records),'formal_performance_pass':None,'speedup_claim':False},indent=2))
