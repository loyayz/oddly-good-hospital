from pathlib import Path
import json,hashlib
R=Path(__file__).resolve().parent
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
D=R/'tool-adaptation640-v2';F=D/'evidence/prepare640wide-candidate01';I=D/'evidence/input640wide-candidate01';status=json.loads((F/'status.json').read_text());report=json.loads((I/'base-preparation-640wide.json').read_text());assert status['finished'] and status['returncode']==1 and not status['timed_out'] and not report['ok']
proof=json.loads((D/'full-preparation-protocol.json').read_text());changed=[]
for f in proof['files']:
 p=D/'project'/f['path']
 if sha(p)!=f['sha256'] or p.stat().st_mode&0o777!=f['mode']:changed.append(f['path'])
assert not changed
write(D/'full-preparation-result-analysis.json',{'status':status,'complete_fixture_constructor':True,'fixture_construct_us':854290707,'simulation_constructor_us':912669407-854294887,'failed_stage':'initial public companion seat search','required':32,'available':4,'checked_candidates':39,'actual_steps':0,'valid_input_created':False,'no_frozen_final_world':'Originalprepare failure output has report/log only; no constructor/failure facts checkpoint exists. Do not claim resumable fullworld.','scope':'Only bounded original y90 candidates insufficient, not proof all legitimate layouts impossible. No rooms/props/headcount/safety checks removed.','source_projection_files_verified_unchanged':len(proof['files']),'projection_is_not_exhaustive_project':'Extra oracle/prefix scripts and generated metadata are not included in1389 execution projection.','next_not_executed':'After publication pause: broaden legal public-seat placement candidates using current rules without deleting facilities, save complete constructor boundary for resumption, then original32companion admission/SE01 and full input validation;320/640 clinical preflight still pending.'})
files=[D/'full-preparation-result-analysis.json',D/'full-preparation-protocol.json',D/'full-preparation-protocol-manifest.json',D/'full-preparation-readiness.json']+[p for x in [F,I] for p in x.iterdir() if p.is_file()]
write(D/'full-preparation-result-manifest.json',{'frozen':True,'files':[{'path':str(p.relative_to(D)),'bytes':p.stat().st_size,'sha256':sha(p)} for p in files]})
base=json.loads((R/'exporter-integration-r2/source-after-integration.json').read_text());index={f['path']:f for f in base['files']};projects={'diagnostic-root-v1':'source','diagnostic-fine-v1':'source','diagnostic-fine-v2':'source','diagnostic640-v1':'project','diagnostic640-v2':'project','candidate-lazy-copy-v1':'source','tool-adaptation640-v1':'project','tool-adaptation640-v2':'project'};overlays={}
for name,child in projects.items():
 P=R/name/child;rows=[]
 for f in base['files']:
  p=P/f['path']
  if not p.exists():rows.append({'path':f['path'],'missing':True});continue
  h=sha(p)
  if h!=f['sha256'] or p.stat().st_mode&0o777!=f['mode']:rows.append({'path':str(p.relative_to(R)),'base_path':f['path'],'sha256':h,'bytes':p.stat().st_size,'mode':p.stat().st_mode&0o777})
 for p in P.rglob('*'):
  rel=p.relative_to(P)
  if not p.is_file() or any(x in rel.parts for x in ['.godot','.cache','.git','__pycache__']):continue
  if str(rel) not in index:rows.append({'path':str(p.relative_to(R)),'new_relative_path':str(rel),'sha256':sha(p),'bytes':p.stat().st_size,'mode':p.stat().st_mode&0o777})
 overlays[name]=rows
H=R/'handoff-performance-publication-v1';H.mkdir(exist_ok=False);write(H/'project-overlays.json',{'base_manifest':'exporter-integration-r2/source-after-integration.json','base_manifest_sha256':sha(R/'exporter-integration-r2/source-after-integration.json'),'base_aggregate':base['source_aggregate_sha256'],'overlays':overlays,'excluded':'Generated .godot/.cache/.git/__pycache__, duplicated unchanged base files'})
status={'engine_active':False,'pause':'Parent/user publication pause: do not start another engine until resumed','accepted_measurement_and_evidence':['source/tools/performance/current (7 gd tools, v1-v3 historical/v4 active)','run_engine.py','run_series_v4.py','read_variant.py','audit_A_series_v1.py','evidence/baseline160-GP-v4-completed-audit','evidence/baseline160-GP-v4-business-throughput.json','review-measurement-v4','review-workload-contract'], 'qualified_tool_candidate_not_canonical_adoption':['tool-adaptation640-v1 fixture/helper +54queryoracle','tool-adaptation640-v2 supplemental alias/commit/exhaustion/reservation/original640prefix oracles','tool-adaptation640-v2 full640 preparation ended functional setup failure4/32seats; no legalinput'], 'diagnostic_only':['diagnostic-root-v1','diagnostic-fine-v1','diagnostic-fine-v2','diagnostic640-v1','diagnostic640-v2'], 'not_adopted_production_candidate':['candidate-lazy-copy-v1: functional tests and exact800facts pass; single diagnostic2.76%slower; no5B, no gain/adoption'], 'unexecuted_next_tool':['prepare_fine_diagnostic_v3.py only generator, no project/engine'], 'no_release_claim':['320 only prepared, no clinical baseline','640wide constructor complete but currentlegal input incomplete','wide160/tall640 unverified','GPU/FPS/nativeSQLite/Windows/fullrelease unsupported','11 inherited deferred scopes unchanged'], 'production_baseline_changes_adopted':0,'verified_performance_improvements':0,'full_A_source_aggregate':base['source_aggregate_sha256']}
write(H/'status.json',status)
# Deliver all small root tools, all raw/evidence products, and only source overlays rather than duplicate projects.
selected=set()
for p in R.iterdir():
 if p.is_file() and p.suffix=='.py':selected.add(p)
for root in [R/'evidence']+[R/n for n in projects]+[p for p in R.iterdir() if p.is_dir() and p.name.startswith('review-')]:
 for p in root.rglob('*'):
  rel=p.relative_to(root)
  if p.is_file() and not any(x in rel.parts for x in ['source','project','.godot','.cache','.git','__pycache__','home','data','config','cache']):selected.add(p)
for rows in overlays.values():
 for f in rows:
  if not f.get('missing'):selected.add(R/f['path'])
for p in (R/'source/tools/performance/current').iterdir():
 if p.is_file():selected.add(p)
selected.update([H/'status.json',H/'project-overlays.json'])
write(H/'artifact-manifest.json',{'frozen':True,'files':[{'path':str(p.relative_to(R)),'bytes':p.stat().st_size,'sha256':sha(p)} for p in sorted(selected)],'base_source_delivery':'Parent owns full canonical1388 source backup and latest design/doc overlays; this package is performance tools/evidence + reconstructable experimental deltas only','no_runtime_generated_profiles_or_duplicate_projects':True})
p=R/'phase-state.json';s=json.loads(p.read_text());s.update(active_run=None,phase='paused_for_user_publication',preparation640wide_candidate01='finished exit1,no timeout; constructor complete,4/32 bounded seats; no validinput',next='Parent publication pause, no newengine');write(p,s)
print('HANDOFF',H,'files',len(selected),'bytes',sum(p.stat().st_size for p in selected))
