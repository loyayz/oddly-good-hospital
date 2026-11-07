import json,hashlib,math,statistics
from pathlib import Path
from read_variant import decode
R=Path(__file__).resolve().parent;E=R/'evidence'; O=E/'baseline160-GP-v4-completed-audit';O.mkdir(exist_ok=False)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def save(n,v):(O/n).write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
m=json.loads((R/'exporter-integration-r2/source-after-integration.json').read_text()); changes=[]
for f in m['files']:
 p=R/'source'/f['path']
 if not p.exists() or sha(p)!=f['sha256'] or p.stat().st_mode&0o777!=f['mode']:changes.append(f['path'])
assert not changes,changes
save('source-no-diff.json',{'source_manifest_sha256':sha(R/'exporter-integration-r2/source-after-integration.json'),'verified_file_count':len(m['files']),'changed_missing_or_mode_changed':changes,'source_aggregate_sha256':m['source_aggregate_sha256']})
s=json.loads((E/'baseline160-GP-v4-series-result.json').read_text());assert s['all_repeats_complete'] and len(s['records'])==5
base=None;rows=[]
for record in s['records']:
 name=record['run'];d=E/name;r=json.loads((d/'result.json').read_text());v,dec=decode(d/'result.json.final.bin');a,b=dec.spans['facts'];facts=dec.data[a:b]
 if base is None:base=(facts,v['events'])
 assert facts==base[0] and v['events']==base[1],name+' deterministic mismatch'
 samples=[x['sample'] for x in map(json.loads,(d/'result.json.steps.ndjson').read_text().splitlines()) if x['kind']=='complete'];assert len(samples)==3000
 assert [x['tick'] for x in samples]==list(range(22,3022));sample=samples[1000:];times=sorted(x['elapsed_us'] for x in sample);met=r['metrics']
 calc={'count':len(times),'sum_step_us':sum(times),'mean_step_us':statistics.mean(times),'p50_us':times[math.ceil(.5*len(times))-1],'p95_us':times[math.ceil(.95*len(times))-1],'p99_us':times[math.ceil(.99*len(times))-1],'max_us':max(times)}
 for k,val in calc.items():assert abs(val-met[k])<1e-7,(name,k,val,met[k])
 assert r['sample_business']['clinical_work_ticks_observed_lower_bound']=={'gp':120,'reception':290};assert r['sample_business']['guidance_work_ticks']==177
 save(name+'-facts.json',v['facts'])
 row={'run':name,'qualified':record['qualified'],'status':record['status'],'final_bin_sha256':sha(d/'result.json.final.bin'),'facts_encoded_sha256':hashlib.sha256(facts).hexdigest(),'facts_byte_identical_to_A01':facts==base[0],'ordered_events_equal_A01':v['events']==base[1],'raw_steps_recomputed':calc,'metrics':met,'prefix_wall_us':r['prefix_wall_us'],'initial_population':r['initial']['population'],'sample_start_population':r['sample_start_population'],'final_population':r['final']['population'],'sample_business':r['sample_business'],'slowest_sample_steps':sorted(sample,key=lambda x:x['elapsed_us'],reverse=True)[:10]};rows.append(row)
summary={'scope':'Five independent same-machine plain CPU runs, initial160 dynamic legal population; fixed1000 prefix +2000 sample. Limited GP/guidance/reception/maintenance. No treatment/full-game/GPU/FPS claim.','all_complete':True,'exact_facts_and_ordered_events_identical_all_five':True,'business_oracle_reference':'../baseline160-GP-v4-A01-business-byte-audit.json','runs':rows,'independent_run_statistics':{k:{'median':statistics.median(x['metrics'][k] for x in rows),'min':min(x['metrics'][k] for x in rows),'max':max(x['metrics'][k] for x in rows)} for k in ['mean_step_us','p95_us','p99_us','max_us','simulation_seconds_per_wall_second']},'formal_performance_pass':None,'speedup_claim':False}
save('audit.json',summary)
files=[R/'audit_A_series_v1.py',R/'read_variant.py',E/'baseline160-GP-v4-series-result.json',E/'baseline160-GP-v4-series-progress.json',E/'baseline160-GP-v4-controller.log',E/'baseline160-GP-v4-protocol.json']+list(O.iterdir())
for row in rows:files += [p for p in (E/row['run']).iterdir() if p.is_file()]
save('manifest.json',{'frozen':True,'files':[{'path':str(p.relative_to(R)),'bytes':p.stat().st_size,'sha256':sha(p)} for p in sorted(set(files))]})
print(json.dumps(summary['independent_run_statistics'],indent=2));print('frozen',O)
