from pathlib import Path
import json,hashlib,time,datetime
start=time.time();P=Path(__file__).resolve().parent.parent;p=P/'diagnostic-fine-v1';o=Path(__file__).parent;J=lambda x:json.loads(x.read_text());H=lambda x:hashlib.sha256(x.read_bytes()).hexdigest();c=J(p/'changes.json');checks={'reverse_body':{},'hash_mismatches':[]};inputs=[]
for f in c['files']:
 x=p/'source'/f['path'];a=(P/'diagnostic-root-v1/source'/f['path']).read_text();b=x.read_text();prefix=b.split('\nfunc '+f['methods'][0]+'(',1)[0];prefix=prefix.replace('const _FineTimer = preload("res://tools/performance/current/fine_timer_v1.gd")\n','')
 for name in f['methods']:prefix=prefix.replace('func _fine_original_'+name+'(','func '+name+'(')
 checks['reverse_body'][f['path']]=prefix.rstrip('\n')==a.rstrip('\n') and H(x)==f['diagnostic_sha256'];inputs.append(x)
for name,base in [('qualification-manifest.json',P),('completed-manifest.json',p)]:
 for f in J(p/'evidence'/name)['files']:
  if H(base/f['path'])!=f['sha256']:checks['hash_mismatches'].append(f['path'])
 inputs.append(p/'evidence'/name)
d=p/'evidence/fine800';r=J(d/'result.json');fine=J(d/'result.json.fine.json')['steps'];logs=[json.loads(x) for x in (d/'result.json.steps.ndjson').read_text().splitlines()];rows=[x['sample'] for x in logs if x['kind']=='complete'];agg={}
for step in fine:
 for name,v in step['rows'].items():
  z=agg.setdefault(name,{'calls':0,'inclusive_us':0,'exclusive_us':0,'max_us':0})
  for k in ['calls','inclusive_us','exclusive_us']:z[k]+=v[k]
  z['max_us']=max(z['max_us'],v['max_us'])
comp=J(p/'evidence/completed-comparison.json');checks.update({'status':J(d/'status.json'),'complete':r['complete'],'errors':r['errors'],'raw_error':'ERROR' in (d/'raw.log').read_text(),'fine_800_continuous':len(fine)==800 and all(x['tick']==1022+i and not x['errors'] for i,x in enumerate(fine)),'step_800_continuous':len(rows)==800 and all(x['tick']==1022+i and x['index']==i for i,x in enumerate(rows)),'step_elapsed_sum_matches':sum(x['elapsed_us'] for x in rows)==r['metrics']['sum_step_us'],'whole_final_equal':(d/'result.json.final.bin').read_bytes()==(P/'diagnostic-root-v1/evidence/plain800/result.json.final.bin').read_bytes(),'all_aggregate_rows_match':all(agg[x['name']]=={k:v for k,v in x.items() if k!='name'} for x in comp['methods']) and len(agg)==len(comp['methods']),'valid_durations':all(0<=v['exclusive_us']<=v['inclusive_us'] and 0<=v['max_us']<=v['inclusive_us'] for x in fine for v in x['rows'].values()),'selected_exclusive_sum_within_outer_each_step':all(sum(v['exclusive_us'] for v in x['rows'].values())<=y['elapsed_us'] for x,y in zip(fine,rows)),'methods':agg,'argv':J(d/'started.json')['argv']});end=time.time();checks['execution']={'start_utc':datetime.datetime.fromtimestamp(start,datetime.timezone.utc).isoformat(),'end_utc':datetime.datetime.fromtimestamp(end,datetime.timezone.utc).isoformat(),'elapsed_seconds':end-start};(o/'checks.json').write_text(json.dumps(checks,indent=2));inputs += [p/'changes.json',p/'evidence/protocol-v1.json',p/'source/tools/performance/current/fine_timer_v1.gd',p/'source/tools/performance/current/fine_driver_v1.gd'];(o/'input-manifest.json').write_text(json.dumps([{'path':str(x),'sha256':H(x)} for x in inputs],indent=2));print(json.dumps({k:v for k,v in checks.items() if k not in ['methods','argv']},indent=2))
