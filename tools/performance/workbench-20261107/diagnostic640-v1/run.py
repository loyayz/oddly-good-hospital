from pathlib import Path
import sys,os,json,subprocess,time,signal,hashlib
D=Path(__file__).resolve().parent;P=Path(sys.argv[1]).resolve();O=Path(sys.argv[2]).resolve()
assert P.is_relative_to(D) and P!=D
assert O.is_relative_to(D) and not O.exists()
check=json.loads((D/'static-check.json').read_text());assert hashlib.sha256((P/'tools/performance/fixture.gd').read_bytes()).hexdigest()==check['diagnostic_sha256']
E=Path('/workspace/scratch/6962cc21ddf3/ogh-recovery-20261107/runtime/Godot_v4.7.2-stable_linux.x86_64')
O.mkdir();env=os.environ.copy()
for k,n in [('HOME','home'),('XDG_DATA_HOME','data'),('XDG_CONFIG_HOME','config'),('XDG_CACHE_HOME','cache')]:
 p=O/n;p.mkdir();env[k]=str(p)
cmd=[str(E),'--headless','--path',str(P),'--script','res://diagnostic640-driver.gd','--','--output='+str(O/'result.json')]
(O/'started.json').write_text(json.dumps({'argv':cmd,'engine_sha256':hashlib.sha256(E.read_bytes()).hexdigest(),'timeout_seconds':120,'diagnostic_only':True,'legal_input_qualified':False},indent=2)+'\n')
start=time.monotonic();timed=False
with (O/'raw.log').open('wb') as log:
 p=subprocess.Popen(cmd,stdout=log,stderr=subprocess.STDOUT,env=env,start_new_session=True)
 try:rc=p.wait(timeout=120)
 except subprocess.TimeoutExpired:
  timed=True;os.killpg(p.pid,signal.SIGTERM)
  try:rc=p.wait(timeout=10)
  except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);rc=p.wait()
(O/'status.json').write_text(json.dumps({'returncode':rc,'timed_out':timed,'wall_seconds':time.monotonic()-start,'finished':True,'diagnostic_only':True,'legal_input_qualified':False},indent=2)+'\n')
print(O,rc,timed)
