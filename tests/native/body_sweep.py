"""Compare complete production BodySweep implementations in a real Godot process.

No spatial, physics or Godot-method mocks are used. This checks the mathematical
helper only; it is not a complete movement, native bridge or game benchmark.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--godot', default='godot')
parser.add_argument('--baseline', default='35d656dc58c4f7afac8419218a12051d3617c47b')
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=False)
project = output / 'project'
project.mkdir()
source_path = 'game/building/body_sweep.gd'
current = (repo / source_path).read_bytes()
baseline = subprocess.run(['git', 'show', f'{args.baseline}:{source_path}'], cwd=repo, capture_output=True, check=True).stdout
(project / 'current.gd').write_bytes(current)
# Rename only the baseline's global class so both exact implementations can load.
(project / 'baseline.gd').write_bytes(baseline.replace(b'class_name BodySweep', b'class_name BaselineSweep', 1))
harness = Path(__file__).with_suffix('.gd')
shutil.copyfile(harness, project / 'run.gd')
(project / 'project.godot').write_text('config_version=5\n')
env = os.environ.copy()
for key in ['XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']:
    location = output / key.lower()
    location.mkdir()
    env[key] = str(location)
command = [args.godot, '--headless', '--path', str(project), '--script', 'res://run.gd']
run = subprocess.run(command, text=True, capture_output=True, env=env, timeout=120)
(output / 'run.log').write_text(run.stdout + run.stderr)
run.check_returncode()
if 'SCRIPT ERROR' in run.stderr or 'ERROR:' in run.stderr:
    raise RuntimeError('Godot error; see run.log')
result = json.loads(next(line for line in reversed(run.stdout.splitlines()) if line.startswith('{')))
old = [window['elapsed_us'] for window in result['windows'] if window['old']]
new = [window['elapsed_us'] for window in result['windows'] if not window['old']]
assert len(old) == len(new) == 6
assert len({window['hits'] for window in result['windows']}) == 1
result.update({
    'engine': subprocess.run([args.godot, '--version'], text=True, capture_output=True, env=env, check=True).stdout.strip(),
    'baseline': args.baseline,
    'baseline_sha256': hashlib.sha256(baseline).hexdigest(),
    'source_sha256': hashlib.sha256(current).hexdigest(),
    'harness_sha256': hashlib.sha256(harness.read_bytes()).hexdigest(),
    'runner_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    'baseline_mean_us': sum(old) / len(old),
    'current_mean_us': sum(new) / len(new),
    'local_reduction_percent': (1.0 - sum(new) / sum(old)) * 100,
    'command': command,
    'formal_pass': False,
})
(output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
