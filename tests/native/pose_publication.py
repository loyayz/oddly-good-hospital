#!/usr/bin/env python3
"""Run a real-Godot isolated publication comparison, without the platform DLL.

The baseline is an explicit Git revision. Only its class name is changed so
both implementations can coexist. No game renderer/pose algorithm is mocked.
This headless CPU measurement is not a GPU, game-frame, or acceptance result.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path('game/view/skinned_pose_batch.gd')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default='godot')
    parser.add_argument('--baseline', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    project = output / 'project'
    (project / 'game/view').mkdir(parents=True)
    for relative in [SOURCE, Path('game/view/compatibility_skin_input.gd')]:
        shutil.copy2(ROOT / relative, project / relative)
    shutil.copytree(ROOT / 'game/view/shaders', project / 'game/view/shaders')
    baseline = subprocess.check_output(['git', 'show', f'{args.baseline}:{SOURCE.as_posix()}'], cwd=ROOT)
    baseline_text = baseline.decode('utf-8')
    assert baseline_text.count('class_name SkinnedPoseBatch') == 1
    (project / 'game/view/baseline_pose_batch.gd').write_text(
        baseline_text.replace('class_name SkinnedPoseBatch', 'class_name BaselinePoseBatch', 1), encoding='utf-8')
    shutil.copy2(ROOT / 'tests/native/pose_publication.gd', project / 'run.gd')
    (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="PosePublishCheck"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding='utf-8')
    env = dict(os.environ)
    for variable in ['HOME', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']:
        home = output / variable.lower()
        home.mkdir()
        env[variable] = str(home)
    godot = shutil.which(args.godot) or str(Path(args.godot).resolve())
    version = subprocess.check_output([godot, '--version'], env=env, text=True).strip()
    command = [godot, '--headless', '--path', str(project), '--script', 'res://run.gd']
    try:
        completed = subprocess.run(command, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90)
        log = completed.stdout
    except subprocess.TimeoutExpired as error:
        raw = error.stdout or b''
        log = raw.decode(errors='replace') if isinstance(raw, bytes) else raw
        (output / 'run.log').write_text(log, encoding='utf-8')
        raise
    (output / 'run.log').write_text(log, encoding='utf-8')
    records = [json.loads(line) for line in log.splitlines() if line.startswith('{')]
    passed = completed.returncode == 0 and 'SCRIPT ERROR:' not in log and 'ERROR:' not in log and len(records) == 2 and all(r.get('functional_ok') for r in records)
    result = {'passed': passed, 'engine': version, 'command': command, 'baseline_revision': args.baseline,
              'baseline_source_sha256': hashlib.sha256(baseline).hexdigest(),
              'current_source_sha256': hashlib.sha256((ROOT / SOURCE).read_bytes()).hexdigest(),
              'exit_code': completed.returncode, 'results': records}
    if passed:
        windows = records[-1]['windows']
        times = {name: sum(w['elapsed_us'] for w in windows if w['variant'] == name) for name in ['baseline', 'current']}
        result['aggregate_cpu_reduction_fraction'] = 1 - times['current'] / times['baseline']
    (output / 'result.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps(result, indent=2))
    return 0 if passed else 1


if __name__ == '__main__':
    sys.exit(main())
