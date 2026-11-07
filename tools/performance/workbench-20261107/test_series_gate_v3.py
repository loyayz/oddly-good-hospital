import json,tempfile
from pathlib import Path
import run_series_v3 as m
spec={'repeats':1,'steps_per_repeat':1,'prefix_steps':0,'max_process_seconds':10,'variant':'A_current_accepted_production','run_prefix':'test','input_sha256':'X'}
status={'returncode':0,'timed_out':False,'finished':True}
report={'complete':True,'errors':[],'source_input_sha256':'X','all_completed_steps':1,'requested_prefix_steps':0,'requested_sample_steps':1,'metrics':{'count':1},'sample_business':{'clinical_work_ticks_observed_lower_bound':{'gp':1}}}
rows=[]
def check(name,condition):
 assert condition,name
 rows.append({'case':name,'passed':True})
m.validate_spec(spec)
check('valid_record',not m.qualify(status,report,'',spec))
for text in ['SCRIPT ERROR: failure','ERROR: native failure']:
 reasons=m.qualify(status,report,text,spec)
 check(text,bool(reasons) and not m.all_qualified([{'qualified':not reasons,'failure_reasons':reasons}],1))
check('reception_only_rejected',bool(m.qualify(status,dict(report,sample_business={'clinical_work_ticks_observed_lower_bound':{'reception':10}}),'',spec)))
check('timeout_rejected',bool(m.qualify(dict(status,timed_out=True),report,'',spec)))
check('wrong_sample_count_rejected',bool(m.qualify(status,dict(report,metrics={'count':0}),'',spec)))
check('missing_result_rejected',bool(m.qualify(status,None,'',spec)))
check('empty_repeats_not_complete',not m.all_qualified([],0))
check('positive_aggregate',m.all_qualified([{'qualified':True,'failure_reasons':[]}],1))
for field,value in [('repeats',0),('steps_per_repeat',0),('prefix_steps',-1),('max_process_seconds',float('nan'))]:
 try:m.validate_spec(dict(spec,**{field:value}));raise AssertionError('accepted invalid '+field)
 except ValueError:rows.append({'case':'reject '+field,'passed':True})
with tempfile.TemporaryDirectory() as directory:
 p=Path(directory)/'bad.json';p.write_text('{broken');value,reasons=m.load_record(p)
 check('malformed_result_preserved_as_failure',value is None and bool(reasons))
print(json.dumps({'engine_runs':0,'cases':rows},indent=2))
