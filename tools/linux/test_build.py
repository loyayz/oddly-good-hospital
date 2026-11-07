#!/usr/bin/env python3
"""Small build-contract checks, never compiles or exports."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
spec=importlib.util.spec_from_file_location('build',Path(__file__).with_name('build.py'))
b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)

class Contracts(unittest.TestCase):
    def test_hash_change_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'a';p.write_text('old');item=b.record(p);b.checked(item)
            p.write_text('new')
            with self.assertRaisesRegex(ValueError,'Input changed'): b.checked(item)
    def test_system_gmp_headers_resolve(self):
        import shlex
        import shutil
        if not shutil.which('g++'): self.skipTest('g++ not installed')
        result=b.run(['g++','-M','-MT','headers','-x','c++','-'],input_text='#include <gmpxx.h>\n')
        paths=shlex.split(result.replace('\\\n',' ').split(':',1)[1])
        self.assertTrue(any(Path(p).name=='gmp.h' for p in paths))
        self.assertTrue(any(Path(p).name=='gmpxx.h' for p in paths))

    def test_pins_are_complete(self):
        lock=json.loads(Path(__file__).with_name('dependencies.lock.json').read_text())
        self.assertEqual(len(lock),8)
        for item in lock.values(): self.assertRegex(item['sha256'],r'^[0-9a-f]{64}$')
    def test_missing_arguments_fail(self):
        for script in ['tools/build-platform-linux.py','tools/build-game-linux.py']:
            r=subprocess.run([sys.executable,str(b.ROOT/script)],capture_output=True)
            self.assertEqual(r.returncode,2)
    def test_wrong_precision_rejected(self):
        with self.assertRaisesRegex(ValueError,'precision'): b.abi({'header':{'precision':'double'}},'/unused')
    def test_abi_matches_supplied_engine(self):
        # Optional external verified API fixture; no dependency on a particular machine.
        import os
        fixture=os.environ.get('OGH_TEST_EXTENSION_API')
        if not fixture: self.skipTest('Set OGH_TEST_EXTENSION_API for pinned-engine ABI check')
        with tempfile.TemporaryDirectory() as tmp:
            out=Path(tmp)/'abi.h';b.abi(json.loads(Path(fixture).read_text()),out)
            self.assertIn('#define OGH_USER_DIR_HASH 201670096',out.read_text())
            self.assertIn('#define OGH_PACKED_INT64_ARRAY_SIZE 16',out.read_text())

if __name__=='__main__': unittest.main()
