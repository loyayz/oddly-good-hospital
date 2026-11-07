#!/usr/bin/env python3
"""Real Linux native API and process-crash checks; no production budget override."""
import argparse, json, os, pathlib, subprocess, time
p=argparse.ArgumentParser();p.add_argument('--godot',required=True);p.add_argument('--output',required=True);a=p.parse_args()
project=pathlib.Path(__file__).resolve().parents[2];out=pathlib.Path(a.output).resolve();out.mkdir(parents=True,exist_ok=True)
env=os.environ.copy()
for key,name in [('HOME','home'),('XDG_DATA_HOME','data'),('XDG_CONFIG_HOME','config'),('XDG_CACHE_HOME','cache')]:
 d=out/name;d.mkdir(exist_ok=True);env[key]=str(d)
base=[str(pathlib.Path(a.godot).resolve()),'--headless','--path',str(project),'--script','res://tests/native/linux_platform.gd','--']
rows=[]
def run(mode):
 start=time.monotonic();r=subprocess.run(base+[mode],env=env,capture_output=True,text=True,timeout=90);log=r.stdout+r.stderr;(out/(mode+'.log')).write_text(log)
 data=[json.loads(line.split('=',1)[1]) for line in log.splitlines() if line.startswith('PLATFORM_RESULT=')]
 ok=r.returncode==0 and len(data)==1 and data[0]['ok'] and 'ERROR:' not in log
 rows.append({'mode':mode,'exit_code':r.returncode,'ok':ok,'seconds':time.monotonic()-start,'result':data});assert ok,log
 return data[0]
def hold(mode):
 logpath=out/(mode+'.log');log=logpath.open('w');child=subprocess.Popen(base+[mode],env=env,stdout=log,stderr=subprocess.STDOUT,text=True)
 try:
  limit=time.monotonic()+60
  while time.monotonic()<limit:
   if 'PLATFORM_READY='+mode in logpath.read_text():return child,log
   if child.poll() is not None:raise RuntimeError(logpath.read_text())
   time.sleep(.05)
  raise TimeoutError('no readiness '+mode)
 except BaseException:
  child.kill();child.wait();log.close();raise
result=run('all')
child,log=hold('hold')
try:run('contend')
finally:child.kill();child.wait(timeout=10);log.close()
run('all')
child,log=hold('transaction')
child.kill();child.wait(timeout=10);log.close()
run('recovery')
# A symlink guard may alias another file or defeat stable ownership. Refuse it.
user=pathlib.Path(result['user_directory']);guard=user/'.session.guard';saved=user/'.session.guard.saved';guard.rename(saved);guard.symlink_to(saved)
try:run('guard_denied')
finally:guard.unlink();saved.rename(guard)
(out/'result.json').write_text(json.dumps({'ok':all(r['ok'] for r in rows),'runs':rows,'scope':'Real native lock/SQLite/process tests, not full game save or product export.'},indent=2)+'\n')
print(json.dumps({'ok':True,'runs':len(rows),'evidence':str(out/'result.json')}))
