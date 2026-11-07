#!/usr/bin/env python3
"""Synthetic PCK boundary tests plus optional real-package inspection."""
import hashlib
import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest
spec=importlib.util.spec_from_file_location('pck',Path(__file__).with_name('pck.py'));pck=importlib.util.module_from_spec(spec);spec.loader.exec_module(pck)

def fixture(names=('game/main.gdc',),flags=2,file_flags=0,bad_offset=False,bad_md5=False):
    payload=b'content';base=112;directory=base+len(payload)
    data=struct.pack('<6I2Q',0x43504447,4,4,7,2,flags,base,directory)+bytes(base-40)+payload+struct.pack('<I',len(names))
    for name in names:
        raw=name.encode();raw+=bytes((-len(raw))%4)
        data+=struct.pack('<I',len(raw))+raw+struct.pack('<QQ',999999 if bad_offset else 0,len(payload))+(bytes(16) if bad_md5 else hashlib.md5(payload).digest())+struct.pack('<I',file_flags)
    return data

class PckContracts(unittest.TestCase):
    def parse(self,data):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'test.pck';path.write_bytes(data);return pck.read_pck(path)
    def test_valid_content_sha(self):
        result=self.parse(fixture());self.assertEqual(result['resource_count'],1);self.assertEqual(result['forbidden_resources'],[])
        self.assertEqual(result['files'][0]['sha256'],hashlib.sha256(b'content').hexdigest())
    def test_forbidden_paths_are_reported(self):
        for name in ['docs/reports/secret.json','docs/data/stage01-feasibility.json','tests/x.gdc','tools/x.json','art-source/x.res','game/platform/windows/bin/x.dll','game/platform/windows/x.cpp','game/platform/linux/x.h','other/x.lib','debug.log','private/report.json','content/core/private.log','assets/models/report.json']:
            self.assertEqual(self.parse(fixture((name,)))['forbidden_resources'],[name])
    def test_unknown_encrypted_flags_rejected(self):
        for flags in (0,1,3,4,8):
            with self.assertRaises(ValueError):self.parse(fixture(flags=flags))
        with self.assertRaises(ValueError):self.parse(fixture(file_flags=1))
    def test_duplicate_path_rejected(self):
        with self.assertRaisesRegex(ValueError,'Duplicate'):self.parse(fixture(('game/main.gdc','game/main.gdc')))
    def test_overlap_rejected(self):
        with self.assertRaisesRegex(ValueError,'Overlapping'):self.parse(fixture(('a.res','b.res')))
    def test_traversal_and_noncanonical_paths_rejected(self):
        for name in ('../secret','/absolute','game/../secret','game//file','game\\file','game/./file','bad\x00name'):
            with self.assertRaises(ValueError):self.parse(fixture((name,)))
    def test_bounds_and_truncation_rejected(self):
        with self.assertRaisesRegex(ValueError,'outside'):self.parse(fixture(bad_offset=True))
        with self.assertRaises(ValueError):self.parse(fixture()[:-4])
        with self.assertRaises(ValueError):self.parse(fixture()+b'hidden')
    def test_bad_content_hash_rejected(self):
        with self.assertRaisesRegex(ValueError,'checksum'):self.parse(fixture(bad_md5=True))

if __name__=='__main__':unittest.main()
