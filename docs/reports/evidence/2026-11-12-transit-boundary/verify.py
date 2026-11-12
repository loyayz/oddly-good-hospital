"""Offline verification of archived observations, not a gameplay oracle."""
from pathlib import Path
import hashlib,json,zipfile
root=Path(__file__).resolve().parent
manifest=json.loads((root/'manifest.json').read_text(encoding='utf-8'))
archive=root/'evidence.zip'
assert hashlib.sha256(archive.read_bytes()).hexdigest()==manifest['evidence_zip_sha256']
with zipfile.ZipFile(archive) as z:
 assert z.testzip() is None
 for row in manifest['members']:
  data=z.read(row['path']);assert len(data)==row['bytes'] and hashlib.sha256(data).hexdigest()==row['sha256'],row['path']
 def read(name):return json.loads(z.read(name).decode('utf-8-sig'))
 for name,steps in [('plain',1),('traced',1),('detailed',1),('plain8',8),('detailed8',8)]:
  d=read(name+'/result.json')
  assert d['complete'] and d['errors']==[] and d['requested_prefix_steps']==0
  assert d['requested_sample_steps']==d['all_completed_steps']==steps
  assert d['initial']['tick']==7633 and d['final']['tick']==7633+steps
  assert d['source_input_sha256']==manifest['input_sha256']
  assert read(name+'/process.json')['returncode']==0
  assert read(name+'/result.json.execution.json')['main_thread_policy']['applied']
 assert read('plain/result.json')['final_sha256']==read('traced/result.json')['final_sha256']==read('detailed/result.json')['final_sha256']
 assert read('plain8/result.json')['final_sha256']==read('detailed8/result.json')['final_sha256']
 trace=read('detailed8/result.json.transport.json')
 assert trace['errors']==[] and trace['movement_steps']==8
 for tick in range(7633,7641):
  events=[e for e in trace['events'] if e['tick']==tick]
  kinds=[e['kind'] for e in events]
  for kind in ['alight_attempt','actual_dynamic_reject','alight_rejected','actual_patient13_move']:assert kinds.count(kind)==1,(tick,kind)
  assert kinds.index('alight_attempt')<kinds.index('actual_dynamic_reject')<kinds.index('alight_rejected')<kinds.index('actual_patient13_move')
  find=lambda kind:next(e['details'] for e in events if e['kind']==kind)
  attempt=find('alight_attempt');assert attempt['body_blocker_ids']==['bench_patient_0013'] and attempt['connection']['trip_sequence']==37
  reject=find('actual_dynamic_reject');assert reject['actor_id']=='bench_patient_0018' and reject['branch']=='current_body_index'
  motion=find('actual_patient13_move');assert motion['actual']==[0.0,0.0] and motion['reservation_ids']==[] and motion['static_reason']==motion['door_id']==''
  expected=['bench_staff_0025','maintenance_contractor_00000239'] if tick%2 else ['bench_staff_0028']
  assert motion['body_ids']==expected
  requested=motion['requested'];assert abs(requested[0]+.2)<.00001 and requested[1]==0 if tick%2 else requested[0]==0 and abs(requested[1]-.2)<.00001
  assert motion['before']['move']['request_sequence']==motion['after']['move']['request_sequence']==16413
  assert motion['before']['move']['cursor']==motion['after']['move']['cursor']==1
  assert motion['before']['location']==motion['after']['location']
 actors=trace['actors']
 assert actors['bench_staff_0025']['staff_role']=='nurse' and actors['bench_staff_0028']['staff_role']=='cleaner'
 for id in ['bench_patient_0013','maintenance_contractor_00000238','maintenance_contractor_00000239']:
  assert actors[id]['motion']['floor_displacement_steps']==0
 assert trace['open_phases']['benchmark_lift']['connection']['phase']=='alighting'
 assert trace['open_phases']['benchmark_lift']['connection']['trip_sequence']==37
 assert read('restoration-check.json')['isolated_production_restored']
print(json.dumps({'ok':True,'verified_members':len(manifest['members']),'bounded_runs':5,'total_reexecuted_steps':19,'per_tick_actual_rejection_and_motion_checked':8,'scope':'Observation consistency and source-restoration proof only, not business/performance acceptance.'}))
