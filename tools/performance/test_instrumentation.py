"""Diagnostic wrapper contracts, independent of the Windows game runtime.

Run: python3 -B tools/performance/test_instrumentation.py
The optional Godot smoke test checks wrapper behavior, not hospital performance.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

import instrument_all_instances as instrumenter

ROOT = Path(__file__).resolve().parents[2]


class InstrumentationTests(unittest.TestCase):
    def test_current_source_coverage_and_preservation(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            (project / 'source-identity.json').write_text('{}\n')
            profile = project / 'tools/performance/step_profile.gd'
            profile.parent.mkdir(parents=True)
            shutil.copyfile(ROOT / 'tools/performance/step_profile.gd', profile)
            for path in (ROOT / 'game').rglob('*.gd'):
                destination = project / path.relative_to(ROOT)
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, destination)
            result = instrumenter.instrument(project)
            operations = {row['operation'] for item in result['files'] for row in item['methods']}
            expected = {
                'waiting_dependencies.refresh', 'waiting_dependencies.dirty',
                'waiting_dependencies.observe_actors', 'waiting_dependencies.observe_reservations',
                'public_areas._capture_wait_signature', 'public_areas._observe_wait_dependencies',
                'public_areas._wait_dependency_value', 'point_navigation.waiting_travel_ticks',
                'point_navigation._waiting_cost_basis', 'point_navigation.ready_waiting_cost_field',
                'visitors._public_seat_quote', 'visitors._supported_facilities', 'public_areas.turn',
            }
            self.assertLessEqual(expected, operations)
            for item in result['files']:
                original = (project / '.cache/tail-profile-originals' / item['path']).read_bytes()
                self.assertEqual(hashlib.sha256(original).hexdigest(), item['original_sha256'])
                self.assertEqual(original, (ROOT / item['path']).read_bytes())
            with self.assertRaises(FileExistsError):
                instrumenter.instrument(project)

    def test_visitor_seat_observation_is_read_only(self):
        godot = shutil.which('godot') or shutil.which('godot4')
        if godot is None:
            self.skipTest('Godot executable is not installed')
        runner = '''extends SceneTree
class Scope:
	extends RefCounted
	var _route_queries: Array = []
func _initialize() -> void:
	var probe = load("res://visitor_seat_observation.gd")
	var space = Scope.new()
	var world = RefCounted.new()
	var other = RefCounted.new()
	var no_scope: Dictionary = {"same_world_scope":false,"supported_view_ready":false,"known_supported":false}
	var cold: Dictionary = {"same_world_scope":true,"supported_view_ready":false,"known_supported":false}
	assert(probe.capture(space,world,"a","seat")==no_scope)
	var views: Dictionary = {}
	space._route_queries.append({"world":other,"views":views})
	assert(probe.capture(space,world,"a","seat")==no_scope)
	space._route_queries.back().world = world
	assert(probe.capture(space,world,"a","seat")==cold and views.is_empty())
	views["visitor_supported:b"] = {"seat":true}
	assert(probe.capture(space,world,"a","seat")==cold)
	views["visitor_supported:a"] = {}
	assert(probe.capture(space,world,"a","seat")=={"same_world_scope":true,"supported_view_ready":true,"known_supported":false})
	views["visitor_supported:a"]["seat"] = true
	var before: Dictionary = views.duplicate(true)
	var observed: Dictionary = probe.capture(space,world,"a","seat")
	assert(observed=={"same_world_scope":true,"supported_view_ready":true,"known_supported":true})
	assert(views==before)
	# A child with inherited views sees the same existing proof; another world
	# and a new post-commit scope must not borrow it.
	space._route_queries.append({"world":world,"views":views})
	assert(probe.capture(space,world,"a","seat")==observed)
	space._route_queries.back().world = other
	assert(probe.capture(space,world,"a","seat")==no_scope)
	space._route_queries.clear()
	space._route_queries.append({"world":world,"views":{}})
	assert(probe.capture(space,world,"a","seat")==cold)
	views["visitor_supported:a"].clear()
	assert(observed.known_supported) # Observation owns scalar values, no aliases.
	space._route_queries.clear()
	print("VISITOR_SEAT_OBSERVATION_OK")
	quit()
'''
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            (project / 'project.godot').write_text('config_version=5\n')
            shutil.copyfile(ROOT / 'tools/performance/visitor_seat_observation.gd', project / 'visitor_seat_observation.gd')
            (project / 'run.gd').write_text(runner)
            environment = dict(os.environ, HOME=directory, XDG_DATA_HOME=directory, XDG_CACHE_HOME=directory)
            result = subprocess.run([godot, '--headless', '--path', directory, '--script', 'res://run.gd'],
                                    capture_output=True, text=True, env=environment, timeout=30)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('VISITOR_SEAT_OBSERVATION_OK', output)
            self.assertNotIn('SCRIPT ERROR', output)
            self.assertNotIn('ERROR:', output)

    def test_defaults_and_void_wrapper(self):
        source = '''extends RefCounted
func capture(observed: Dictionary, collect: bool = true, options: Array = [1,2]) -> Array:
\tobserved["count"] = int(observed.get("count",0))+1
\treturn options.duplicate() if collect else []
func refresh(read: Callable) -> void:
\tread.call()
'''
        generated, records = instrumenter.transform(source, 'waiting_dependencies', {'capture', 'refresh'})
        self.assertEqual(records[0]['arguments'], ['observed', 'collect', 'options'])
        self.assertIn('func capture(observed: Dictionary, collect: bool = true, options: Array = [1,2]) -> Array:', generated)
        self.assertIn('_tail_profile_original_capture(observed,collect,options)', generated)
        self.assertIn('exit_instance("waiting_dependencies.refresh",null)', generated)
        with self.assertRaises(ValueError):
            instrumenter.transform(generated, 'waiting_dependencies', {'capture'})

    def test_godot_wrapper_semantics(self):
        godot = shutil.which('godot') or shutil.which('godot4')
        if godot is None:
            self.skipTest('Godot executable is not installed')
        source = '''extends RefCounted
var calls: int = 0
func capture(observed: Dictionary, collect: bool = true) -> Array:
\tcalls += 1
\tobserved["count"] = int(observed.get("count",0))+1
\treturn [calls] if collect else []
func refresh(read: Callable) -> void:
\tread.call()
'''
        generated, _ = instrumenter.transform(source, 'waiting_dependencies', {'capture', 'refresh'})
        # Both observer-present and observer-absent paths must preserve default
        # arguments, side effects, return values, and one execution per call.
        runner = '''extends SceneTree
var entered: Array = []
var exited: Array = []
var callback_count: int = 0
func enter_instance(operation: String, _id: int, _arguments: Dictionary) -> void:
\tentered.append(operation)
func exit_instance(operation: String, _result: Variant) -> void:
\texited.append(operation)
func _initialize() -> void:
\tvar target: RefCounted = load("res://wrapped.gd").new()
\tvar observed: Dictionary = {}
\tassert(target.capture(observed)==[1])
\tassert(target.capture(observed,false)==[])
\tassert(observed.count==2 and target.calls==2)
\tEngine.set_meta(&"oddly_good_tail_profile_observer_v1",self)
\tassert(target.capture(observed)==[3])
\tassert(target.capture(observed,false)==[])
\ttarget.refresh(func() -> void: callback_count += 1)
\tEngine.remove_meta(&"oddly_good_tail_profile_observer_v1")
\tassert(observed.count==4 and target.calls==4 and callback_count==1)
\tassert(entered==["waiting_dependencies.capture","waiting_dependencies.capture","waiting_dependencies.refresh"])
\tassert(entered==exited)
\tprint("DIAGNOSTIC_WRAPPER_SMOKE_OK")
\tquit()
'''
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            (project / 'project.godot').write_text('config_version=5\n')
            (project / 'wrapped.gd').write_text(generated)
            (project / 'run.gd').write_text(runner)
            environment = dict(os.environ, HOME=directory, XDG_DATA_HOME=directory, XDG_CACHE_HOME=directory)
            result = subprocess.run([godot, '--headless', '--path', directory, '--script', 'res://run.gd'],
                                    capture_output=True, text=True, env=environment, timeout=30)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('DIAGNOSTIC_WRAPPER_SMOKE_OK', output)
            self.assertNotIn('SCRIPT ERROR', output)
            self.assertNotIn('ERROR:', output)


if __name__ == '__main__':
    unittest.main()
