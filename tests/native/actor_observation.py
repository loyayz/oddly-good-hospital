#!/usr/bin/env python3
"""Compare real actor-observation code with explicit spatial input adapter.

Both full waiting_dependencies scripts and current BodyIndex run unchanged,
except script-local preloads replace global class registration. The spatial
adapter returns conservative broadphase candidates; actual BodyIndex filters
geometry. This is not Boost integration or full STAFF-69 validation.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default='godot')
    parser.add_argument('--baseline', default='35d656dc58c4f7afac8419218a12051d3617c47b')
    parser.add_argument('--iterations', type=int, default=2000)
    parser.add_argument('--rounds', type=int, default=4)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    if args.output.exists() or args.iterations < 1 or args.rounds < 1:
        parser.error('Choose a new output path and positive iterations/rounds')
    repo = Path(__file__).resolve().parents[2]
    relative = 'game/life/waiting_dependencies.gd'
    before = subprocess.check_output(['git','show',args.baseline+':'+relative],cwd=repo,text=True)
    after = (repo/relative).read_text()
    body = (repo/'game/building/body_index.gd').read_text()
    with tempfile.TemporaryDirectory(prefix='ogh-actor-observation-') as directory:
        p = Path(directory)
        (p/'project.godot').write_text('[application]\nconfig/name="wait-observation-isolation"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
        for name, source in [('before',before),('after',after)]:
            (p/(name+'.gd')).write_text(source.replace('extends RefCounted\n','extends RefCounted\nconst BodyIndex=preload("res://body.gd")\n',1))
        (p/'body.gd').write_text(body.replace('class_name BodyIndex\n','').replace('extends RefCounted\n','extends RefCounted\nconst PlatformSpatialIndex=preload("res://spatial.gd")\n',1))
        (p/'spatial.gd').write_text('''extends RefCounted
var records: Dictionary = {}
func clear() -> void: records.clear()
func update(id: String, floor: int, rect: Array) -> void: records[id] = {"floor":floor,"rect":rect}
func remove(id: String) -> void: records.erase(id)
func query(floor: int, _rect: Array) -> Dictionary:
	var ids: Array = []
	for id: String in records:
		if records[id].floor==floor: ids.append(id)
	return {"ids":ids}
func query_many(floor: int, _rects: Array) -> Dictionary: return query(floor,[])
''')
        driver = Path(__file__).with_suffix('.gd').read_text()
        (p/'run.gd').write_text(driver)
        env = dict(os.environ, XDG_DATA_HOME=str(p/'data'),XDG_CONFIG_HOME=str(p/'config'),XDG_CACHE_HOME=str(p/'cache'))
        command = [args.godot,'--headless','--path',str(p),'--script','run.gd','--',str(args.iterations),str(args.rounds)]
        run = subprocess.run(command,env=env,capture_output=True,text=True,timeout=180)
        result = next((json.loads(line.removeprefix('ACTOR_OBSERVATION_RESULT ')) for line in run.stdout.splitlines() if line.startswith('ACTOR_OBSERVATION_RESULT ')),None)
        evidence = {'command':command,'exit_code':run.returncode,'stdout':run.stdout,'stderr':run.stderr,'baseline':args.baseline,'sha256':{name:hashlib.sha256(source.encode()).hexdigest() for name,source in [('before',before),('after',after),('body',body),('driver',driver)]},'result':result}
        args.output.parent.mkdir(parents=True,exist_ok=True)
        args.output.write_text(json.dumps(evidence,indent=2))
        print(json.dumps(result,indent=2))
        if run.returncode or not result or not result['passed'] or 'SCRIPT ERROR' in run.stderr:
            raise SystemExit(1)


if __name__ == '__main__':
    main()
