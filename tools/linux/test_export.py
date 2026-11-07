#!/usr/bin/env python3
"""Exporter contracts using small synthetic sources; never run Godot/export."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('exporter',Path(__file__).parents[1]/'build-game-linux.py')
e=importlib.util.module_from_spec(spec);spec.loader.exec_module(e)

class ExportContracts(unittest.TestCase):
    def test_public_payload_rejects_local_path_across_chunk_boundary(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);binary=root/'library.so';binary.write_bytes(b'x'*(1048576-5)+b'/workspace/private/source.c')
            with self.assertRaisesRegex(ValueError,'leaked'):e.audit_public_paths([binary],['/workspace/'])
            binary.write_bytes(b'dependencies/scip/source.c');e.audit_public_paths([binary],['/workspace/'])
    def test_default_state_is_isolated_sibling(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);paths=e.state_paths(None,root/'source',root/'release',root/'data')
            self.assertEqual(paths['root'],str(root/'release.state'))
            self.assertEqual(paths['XDG_DATA_HOME'],str(root/'data'))
            self.assertFalse((root/'release.state').exists())
    def test_custom_state_path(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);paths=e.state_paths(root/'custom',root/'source',root/'release',root/'data')
            self.assertEqual(paths['HOME'],str(root/'custom/home'))
    def test_state_overlap_and_reuse_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            for bad in [root/'source/state',root/'source',root/'release/state',root/'data/state',root]:
                with self.assertRaises(ValueError):e.state_paths(bad,root/'source',root/'release',root/'data')
            (root/'used').mkdir()
            with self.assertRaisesRegex(ValueError,'must be new'):e.state_paths(root/'used',root/'source',root/'release',root/'data')
    def test_system_lgpl_needs_requirement_not_source_archive(self):
        e.validate_distribution_component('gmp',{'distribution':'system','requirement':'verified distribution GMP ABI'})
        with self.assertRaises(ValueError): e.validate_distribution_component('gmp',{'distribution':'system'})
    def test_bundled_lgpl_needs_corresponding_sources(self):
        with self.assertRaisesRegex(ValueError,'source/build'): e.validate_distribution_component('mpfr',{'distribution':'bundled'})
        e.validate_distribution_component('mpfr',{'distribution':'bundled','sources':[{'path':'checked separately'}]})
    def test_runtime_exception_requires_explicit_basis(self):
        with self.assertRaises(ValueError): e.validate_distribution_component('compiler-runtime',{'distribution':'bundled','source_obligation':'runtime-library-exception'})
        e.validate_distribution_component('compiler-runtime',{'distribution':'bundled','source_obligation':'runtime-library-exception','license_basis':'Supplied GCC Runtime Library Exception reviewed for this binary'})
    def test_empty_template_uses_standard(self):
        root=Path('/project');template=Path('/data/template')
        preset='[preset.0]\nname="Linux x86_64 Release"\nplatform="Linux"\n[preset.0.options]\ncustom_template/release=""\n'
        self.assertEqual(e.select_template(preset,template,root),template)
    def test_conflicting_template_rejected(self):
        preset='[preset.0]\nname="Linux x86_64 Release"\nplatform="Linux"\n[preset.0.options]\ncustom_template/release="wrong"\n'
        with self.assertRaisesRegex(ValueError,'overrides'): e.select_template(preset,Path('/standard'),Path('/source'))
    def test_matching_relative_template(self):
        preset='[preset.0]\nname="Linux x86_64 Release"\nplatform="Linux"\n[preset.0.options]\ncustom_template/release="template"\n'
        self.assertEqual(e.select_template(preset,Path('/source/template'),Path('/source')),Path('/source/template'))
    def test_dry_plan_has_complete_order_no_execution(self):
        with patch.object(e.subprocess,'run',side_effect=AssertionError('must not execute')):
            commands=e.build_commands(Path('/godot'),Path('/source'),Path('/release'))
        self.assertEqual([c[0] for c in commands],['content-check','import','export'])
        self.assertIn('--check',commands[0][1])
        self.assertEqual(commands[1][1][-3:],['--editor','--import','--quit'])
    def test_import_sidecars_and_resources(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);(root/'image.png').write_bytes(b'image');(root/'script.gd').write_text('extends Node')
            (root/'image.png.import').write_text('[remap]\nimporter="texture"\npath="old"\n[params]\ncompress/mode=0\n')
            before=e.source_identity(root)
            (root/'image.png.import').write_text('[remap]\nimporter="texture"\npath="new"\n[params]\ncompress/mode=0\n')
            (root/'script.gd.uid').write_text('uid://abc')
            (root/'.godot').mkdir();(root/'.godot/cache').write_text('ignored')
            after=e.source_identity(root)
            self.assertEqual(e.verify_sources(before,after,True),['image.png.import','script.gd.uid'])
            with self.assertRaises(ValueError): e.verify_sources(before,after)
            (root/'image.png').write_bytes(b'changed resource')
            with self.assertRaisesRegex(ValueError,'image.png'):e.verify_sources(before,e.source_identity(root),True)
    def test_import_settings_are_not_hidden(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);(root/'image.png').write_bytes(b'image')
            sidecar=root/'image.png.import';sidecar.write_text('[params]\ncompress/mode=0\n')
            before=e.source_identity(root);sidecar.write_text('[params]\ncompress/mode=1\n')
            with self.assertRaisesRegex(ValueError,'image.png.import'):e.verify_sources(before,e.source_identity(root),True)
    def test_existing_uid_cannot_change(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);(root/'script.gd').write_text('extends Node');uid=root/'script.gd.uid';uid.write_text('old')
            before=e.source_identity(root);uid.write_text('new')
            with self.assertRaises(ValueError):e.verify_sources(before,e.source_identity(root),True)
    def test_zero_exit_error_log_fails_and_is_retained(self):
        with tempfile.TemporaryDirectory() as temp:
            output=Path(temp)
            def fake_run(command,**kwargs):
                kwargs['stdout'].write('ERROR: test failure\n')
                return type('Result',(),{'returncode':0})()
            plan={'status':'planned'}
            with patch.object(e.subprocess,'run',side_effect=fake_run):
                with self.assertRaises(ValueError): e.run_stage('import',['fake'],output,{},plan)
            self.assertTrue((output/'import.log').exists())
            self.assertFalse(plan['stages'][0]['passed'])
            self.assertTrue((output/'package-manifest.json').exists())

if __name__=='__main__':unittest.main()
