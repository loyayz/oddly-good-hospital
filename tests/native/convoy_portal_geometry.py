#!/usr/bin/env python3
"""Run actual ConvoyPortal/ConvoyTrail geometry without the platform backend.

Only their external typed world/content/space context is a literal harness.
No production collision, navigation, persistence, or full-game pass is claimed.
"""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default='godot')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    project = output / 'project'
    project.mkdir()
    files = ['game/building/convoy_portal.gd', 'game/building/convoy_trail.gd', 'content/core/vertical_connectors.json', 'docs/data/balance.json']
    identity = {}
    space_source = (ROOT / 'game/building/hospital_space.gd').read_text()
    cell_meters = re.search(r'^const CELL_METERS: float = ([0-9.]+)$', space_source, re.M).group(1)
    identity['game/building/hospital_space.gd'] = hashlib.sha256(space_source.encode()).hexdigest()
    for relative in files:
        source = ROOT / relative
        shutil.copy2(source, project / source.name)
        identity[relative] = hashlib.sha256(source.read_bytes()).hexdigest()
    transit_source = (ROOT / 'game/building/hospital_transit.gd').read_text()
    identity['game/building/hospital_transit.gd'] = hashlib.sha256(transit_source.encode()).hexdigest()
    timer_functions = []
    for name in ['_boarding', '_alighting']:
        start = transit_source.index('static func ' + name + '(')
        end = transit_source.find('\nstatic func ', start + 1)
        timer_functions.append(transit_source[start:end if end >= 0 else None])
    (project / 'hospital_transit.gd').write_text('class_name HospitalTransit\nextends RefCounted\n\n' + '\n'.join(timer_functions))
    (project / 'world_state.gd').write_text('class_name WorldState\nextends RefCounted\nconst TICK_SECONDS: float = 0.1\nvar facts: Dictionary = {"actors":{},"moves":{},"connectors":{}}\n')
    (project / 'content.gd').write_text('''class_name LiteralContent
extends RefCounted
var connectors: Array = JSON.parse_string(FileAccess.get_file_as_string("res://vertical_connectors.json"))
var balance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://balance.json"))
func definition(_kind: String, id: String) -> Dictionary:
 for entry: Dictionary in connectors:
  if entry.id==id: return entry
 return {}
''')
    (project / 'space.gd').write_text('''class_name HospitalSpace
extends RefCounted
const CELL_METERS: float = CELL_METERS_VALUE
var content: LiteralContent = LiteralContent.new()
var query_counts: Dictionary = {}
func walking_speed(actor: Dictionary) -> float: return float(content.balance.movement_speeds[str(actor.clearance)])
func body(actor: Dictionary) -> Dictionary: return actor.body
func clearance(actor: Dictionary) -> int: return int(actor.clearance)
func at(world: WorldState, id: String, floor_id: int, cell: Array) -> bool:
 var actor: Dictionary=world.facts.actors[id]
 return actor.location.kind=="floor" and int(actor.location.floor_id)==floor_id and Vector2(actor.location.cell[0],actor.location.cell[1]).distance_to(Vector2(cell[0],cell[1]))<0.001
'''.replace('CELL_METERS_VALUE',cell_meters))
    shutil.copy2(ROOT / 'tests/native/convoy_portal_geometry.gd', project / 'run.gd')
    (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="ConvoyPortalGeometry"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
    env = dict(os.environ)
    for variable in ['HOME', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']:
        directory = output / variable.lower()
        directory.mkdir()
        env[variable] = str(directory)
    godot = shutil.which(args.godot) or str(Path(args.godot).resolve())
    version = subprocess.check_output([godot, '--version'], env=env, text=True).strip()
    logs = {}
    codes = {}
    for stage, command in [
        ('import', [godot, '--headless', '--path', str(project), '--editor', '--quit']),
        ('run', [godot, '--headless', '--path', str(project), '--script', 'res://run.gd']),
    ]:
        completed = subprocess.run(command, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90)
        logs[stage] = completed.stdout
        codes[stage] = completed.returncode
        (output / (stage + '.log')).write_text(completed.stdout)
    records = [json.loads(line) for line in logs['run'].splitlines() if line.startswith('{')]
    passed = all(code == 0 for code in codes.values()) and not any('SCRIPT ERROR:' in log or 'ERROR:' in log for log in logs.values()) and len(records)==1 and bool(records[0].get('ok'))
    result = {'passed': passed, 'engine': version, 'exit_codes': codes, 'source_sha256': identity, 'records': records, 'scope': 'Production pure portal geometry and tick-budget proposals with literal external context; not full-game, collision-index, or persistence verification.'}
    (output / 'result.json').write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))
    return 0 if passed else 1

if __name__ == '__main__':
    raise SystemExit(main())
