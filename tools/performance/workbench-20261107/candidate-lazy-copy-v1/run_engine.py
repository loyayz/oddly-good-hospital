from pathlib import Path
import os,sys,json,time,subprocess,signal,hashlib
root=Path(__file__).resolve().parent
run=root/'evidence'/sys.argv[1];run.mkdir(exist_ok=False)
args=sys.argv[3:];limit=float(sys.argv[2]);engine=Path('/workspace/scratch/6962cc21ddf3/ogh-recovery-20261107/runtime/Godot_v4.7.2-stable_linux.x86_64')
env=os.environ.copy()
for key,name in [('HOME','home'),('XDG_DATA_HOME','data'),('XDG_CONFIG_HOME','config'),('XDG_CACHE_HOME','cache')]:
 p=run/name;p.mkdir();env[key]=str(p)
cmd=[str(engine),'--headless','--path',str(root/'source')]+args
start=time.time();(run/'started.json').write_text(json.dumps({'argv':cmd,'timeout_seconds':limit,'started_unix':start,'engine_sha256':hashlib.sha256(engine.read_bytes()).hexdigest()},indent=2))
with (run/'raw.log').open('wb') as log:
 p=subprocess.Popen(cmd,env=env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True);timed=False
 try:rc=p.wait(timeout=limit)
 except subprocess.TimeoutExpired:
  timed=True;os.killpg(p.pid,signal.SIGTERM)
  try:rc=p.wait(timeout=10)
  except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);rc=p.wait()
(run/'status.json').write_text(json.dumps({'returncode':rc,'timed_out':timed,'wall_seconds':time.time()-start,'finished':True},indent=2));print(run,rc,timed)
