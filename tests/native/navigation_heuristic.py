"""Run production A* Manhattan callbacks in a real Godot AStar2D graph.

Only _estimate_cost and its _cell dependency are extracted unchanged. Graph
setup is explicit test input; Godot owns all actual searches. This does not
exercise HospitalNavigation, native graph assembly, permissions or full steps.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--godot', default='godot')
p.add_argument('--baseline', default='35d656dc58c4f7afac8419218a12051d3617c47b')
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
repo = Path(__file__).resolve().parents[2]
output = a.output.resolve()
output.mkdir(parents=True, exist_ok=False)
project = output / 'project'
project.mkdir()
source_path = 'game/building/floor_navigation.gd'
current = (repo / source_path).read_bytes()
baseline = subprocess.run(['git', 'show', f'{a.baseline}:{source_path}'], cwd=repo, check=True, capture_output=True).stdout

def function(source, name):
    lines = source.decode().splitlines(keepends=True)
    start = next(i for i, line in enumerate(lines) if re.match(r'^(?:static )?func ' + re.escape(name) + r'\(', line))
    end = start + 1
    while end < len(lines) and (not lines[end].strip() or lines[end].startswith('\t')):
        end += 1
    return ''.join(lines[start:end]).rstrip() + '\n'

for name, source in [('baseline', baseline), ('current', current)]:
    side = re.search(rb'^const SIDE: int = (\d+)\s*$', source, re.M).group(1).decode()
    assert side == '96'
    body = 'extends AStar2D\nconst SIDE: int = ' + side + '\n'
    body += function(source, '_estimate_cost') + function(source, '_cell')
    (project / (name + '.gd')).write_text(body)
harness = Path(__file__).with_suffix('.gd')
shutil.copyfile(harness, project / 'run.gd')
(project / 'project.godot').write_text('config_version=5\n')
env = os.environ.copy()
for key in ['XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']:
    path = output / key.lower()
    path.mkdir()
    env[key] = str(path)
command = [a.godot, '--headless', '--path', str(project), '--script', 'res://run.gd']
run = subprocess.run(command, text=True, capture_output=True, env=env, timeout=120)
(output / 'run.log').write_text(run.stdout + run.stderr)
run.check_returncode()
if 'ERROR' in run.stderr:
    raise RuntimeError('Godot reported error; inspect run.log')
result = json.loads(next(line for line in reversed(run.stdout.splitlines()) if line.startswith('{')))
for field in ['windows', 'search_windows']:
    before = [w['us'] for w in result[field] if w['old']]
    after = [w['us'] for w in result[field] if not w['old']]
    assert len(before) == len(after) == 6
    assert len({w['checksum'] for w in result[field]}) == 1
    result[field + '_means'] = {'baseline_us': sum(before)/len(before), 'current_us': sum(after)/len(after), 'local_reduction_percent': (1-sum(after)/sum(before))*100}
result.update({'engine': subprocess.run([a.godot, '--version'], text=True, capture_output=True, env=env, check=True).stdout.strip(), 'baseline': a.baseline, 'baseline_sha256': hashlib.sha256(baseline).hexdigest(), 'source_sha256': hashlib.sha256(current).hexdigest(), 'harness_sha256': hashlib.sha256(harness.read_bytes()).hexdigest(), 'runner_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), 'command': command, 'scope': 'Production Manhattan helper and real Godot AStar2D on explicit synthetic graph; not full hospital navigation', 'formal_pass': False})
(output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
