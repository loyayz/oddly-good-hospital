from pathlib import Path
import subprocess,sys,json,hashlib,math

def validate_spec(spec):
 for key in ['repeats','steps_per_repeat']:
  if type(spec.get(key)) is not int or spec[key]<=0:raise ValueError(key+' must be positive integer')
 if type(spec.get('prefix_steps')) is not int or spec['prefix_steps']<0:raise ValueError('prefix_steps must be nonnegative integer')
 if not isinstance(spec.get('max_process_seconds'),(int,float)) or isinstance(spec['max_process_seconds'],bool) or not math.isfinite(spec['max_process_seconds']) or spec['max_process_seconds']<=0:raise ValueError('positive timeout required')
 if spec.get('variant')!='A_current_accepted_production':raise ValueError('A-only tool')
 if not spec.get('run_prefix') or '/' in spec['run_prefix'] or '..' in spec['run_prefix']:raise ValueError('safe run_prefix required')

def qualify(status,report,raw,spec):
 reasons=[]
 if status.get('returncode')!=0:reasons.append('nonzero or missing engine exit')
 if status.get('timed_out') is not False:reasons.append('timeout or missing timeout status')
 if status.get('finished') is not True:reasons.append('unfinished process')
 if 'SCRIPT ERROR:' in raw or 'ERROR:' in raw:reasons.append('engine or script error in raw log')
 if not isinstance(report,dict):return reasons+['missing result']
 if report.get('complete') is not True:reasons.append('incomplete result')
 if report.get('errors')!=[]:reasons.append('result errors or missing error list')
 if report.get('source_input_sha256')!=spec['input_sha256']:reasons.append('input identity mismatch')
 if report.get('all_completed_steps')!=spec['prefix_steps']+spec['steps_per_repeat']:reasons.append('wrong total step count')
 if report.get('requested_prefix_steps')!=spec['prefix_steps']:reasons.append('wrong prefix count')
 if report.get('requested_sample_steps')!=spec['steps_per_repeat']:reasons.append('wrong requested sample count')
 if report.get('metrics',{}).get('count')!=spec['steps_per_repeat']:reasons.append('wrong measured sample count')
 work=report.get('sample_business',{}).get('clinical_work_ticks_observed_lower_bound',{})
 if not isinstance(work,dict) or sum(v for k,v in work.items() if k!='reception' and isinstance(v,(int,float)))<=0:reasons.append('no non-reception clinical work in predefined sample window')
 return reasons

def all_qualified(records,count):
 return type(count) is int and count>0 and len(records)==count and all(r.get('qualified') is True and not r.get('failure_reasons') for r in records)

def load_record(path):
 try:
  value=json.loads(path.read_text())
  return (value,[]) if isinstance(value,dict) else (None,['non-object JSON: '+str(path)])
 except (OSError,ValueError) as error:return None,['missing/unreadable/malformed JSON: '+str(path)+': '+str(error)]

def main():
 R=Path(__file__).resolve().parent;protocol=R/sys.argv[1];spec=json.loads(protocol.read_text());validate_spec(spec)
 for key,pathkey in [('input_sha256','input'),('tool_sha256','tool')]:
  if hashlib.sha256((R/spec[pathkey]).read_bytes()).hexdigest()!=spec[key]:raise ValueError(pathkey+' identity mismatch')
 base=json.loads((R/'evidence/source-copy-proof.json').read_text())
 for row in base['files']:
  if hashlib.sha256((R/'source'/row['path']).read_bytes()).hexdigest()!=row['sha256']:raise ValueError('accepted production/source changed: '+row['path'])
 summary=R/'evidence'/(spec['run_prefix']+'-series-result.json')
 if summary.exists():raise FileExistsError(summary)
 records=[];protocol_hash=hashlib.sha256(protocol.read_bytes()).hexdigest()
 for i in range(1,spec['repeats']+1):
  name=spec['run_prefix']+'-A%02d'%i;run=R/'evidence'/name
  if run.exists():raise FileExistsError('Review existing run before explicit resume: '+str(run))
  environment={}
  for n in ['/proc/loadavg','/proc/meminfo','/sys/fs/cgroup/cpu.max','/sys/fs/cgroup/memory.max','/sys/fs/cgroup/cpu.stat']:
   p=Path(n);environment[n]=p.read_text() if p.exists() else None
  envpath=R/'evidence'/(name+'-environment-before.json')
  if envpath.exists():raise FileExistsError(envpath)
  envpath.write_text(json.dumps(environment,indent=2))
  cmd=[sys.executable,'-B',str(R/'run_engine.py'),name,str(spec['max_process_seconds']),'--script','res://'+str(Path(spec['tool']).relative_to('source')),'--','--input='+str(R/spec['input']),'--output='+str(run/'result.json'),'--steps='+str(spec['steps_per_repeat']),'--prefix-steps='+str(spec['prefix_steps'])]
  controller=subprocess.run(cmd,cwd=R)
  status,status_errors=load_record(run/'status.json');status=status or {}
  report,report_errors=load_record(run/'result.json')
  raw=(run/'raw.log').read_text(errors='replace') if (run/'raw.log').exists() else 'ERROR: missing raw log'
  reasons=status_errors+report_errors+qualify(status,report,raw,spec)
  if controller.returncode!=0:reasons.append('controller nonzero exit')
  record={'run':name,'argv':cmd,'status':status,'qualified':not reasons,'failure_reasons':reasons,'report':report};records.append(record)
  progress={'protocol_sha256':protocol_hash,'records':records,'all_repeats_complete':all_qualified(records,spec['repeats']),'formal_performance_pass':None,'speedup_claim':False}
  (R/'evidence'/(spec['run_prefix']+'-series-progress.json')).write_text(json.dumps(progress,indent=2))
  if reasons:break
 summary.write_text(json.dumps(progress,indent=2));return 0 if progress['all_repeats_complete'] else 1
if __name__=='__main__':sys.exit(main())
