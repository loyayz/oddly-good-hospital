"""Check the post-fix evidence package without starting the engine."""
from pathlib import Path
import hashlib,json,zipfile
root=Path(__file__).resolve().parent
manifest=json.loads((root/'manifest.json').read_text())
assert hashlib.sha256((root/'evidence.zip').read_bytes()).hexdigest()==manifest['evidence_zip_sha256']
with zipfile.ZipFile(root/'evidence.zip') as z:
 assert z.testzip() is None
 for row in manifest['members']:
  raw=z.read(row['path']);assert len(raw)==row['bytes'] and hashlib.sha256(raw).hexdigest()==row['sha256']
 def read(path):return json.loads(z.read(path).decode('utf-8-sig'))
 plain=read('plain8/result.json');traced=read('detailed8/result.json');trace=read('detailed8/result.json.transport.json')
 for name,d in [('plain8',plain),('detailed8',traced)]:
  assert d['complete'] and d['errors']==[] and d['all_completed_steps']==8 and d['requested_prefix_steps']==0
  assert d['source_input_sha256']==manifest['input_sha256'] and d['initial']['tick']==7633 and d['final']['tick']==7641
  assert d['initial']['population']['present']==d['final']['population']['present']==166
  assert read(name+'/process.json')['returncode']==0
 assert plain['final_sha256']==traced['final_sha256']==manifest['final_sha256']
 assert trace['errors']==[] and trace['movement_steps']==8
 success=[e for e in trace['events'] if e['kind']=='alight_succeeded']
 assert len(success)==1 and success[0]['tick']==7640 and success[0]['details']['connection']['trip_sequence']==37
 actor=trace['actors']['bench_patient_0013'];assert actor['motion']['floor_displacement_steps']==6 and actor['move']['request_sequence']==16413 and actor['move']['cursor']==1
 assert trace['actors']['bench_patient_0018']['location']['kind']=='floor'
 for id in ['maintenance_contractor_00000238','maintenance_contractor_00000239']:assert trace['actors'][id]['motion']['floor_displacement_steps']==0
 connection=trace['open_phases']['benchmark_lift']['connection']
 assert connection['phase']=='empty_riding' and connection['assigned_actor_id']=='bench_patient_0119' and connection['to']==4 and connection['riders']==[]
print(json.dumps({'ok':True,'verified_members':len(manifest['members']),'bounded_steps_per_run':8,'patient13_actual_steps':6,'trip37_alight_tick':7640,'scope':'Post-fix bounded observation proof, not full gameplay or performance acceptance.'}))
