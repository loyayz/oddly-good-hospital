#!/usr/bin/env python3
"""Exercise real shell command construction and tiny CMake caches, not dependencies.

OGH_TEST_DEPENDENCY_CACHE supplies already verified archives and installed CMake.
The fake build commands only create the feature header; no solver is compiled.
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

class DependencyFlags(unittest.TestCase):
    def test_shell_passes_prefix_maps_into_c_and_cpp_cmake_cache(self):
        supplied=os.environ.get('OGH_TEST_DEPENDENCY_CACHE')
        if not supplied:self.skipTest('Set OGH_TEST_DEPENDENCY_CACHE to supplied pinned cache')
        supplied=Path(supplied).resolve()
        with tempfile.TemporaryDirectory() as temp:
            temp=Path(temp);cache=temp/'cache';cache.mkdir()
            for name in ('downloads','deps','prefix'):(cache/name).symlink_to(supplied/name,target_is_directory=True)
            fixture=temp/'fixture';fixture.mkdir()
            (fixture/'CMakeLists.txt').write_text('cmake_minimum_required(VERSION 3.20)\nproject(flag_probe NONE)\nmessage(STATUS "C=${CMAKE_C_FLAGS};CXX=${CMAKE_CXX_FLAGS}")\n')
            wrapper=temp/'cmake-wrapper'
            wrapper.write_text('''#!/usr/bin/env python3
import json,os,pathlib,subprocess,sys
args=sys.argv[1:]
with open(os.environ['PROBE_COMMANDS'],'a') as out:out.write(json.dumps(args)+'\\n')
if '-S' in args:
 build=pathlib.Path(args[args.index('-B')+1]);build.mkdir(parents=True,exist_ok=True)
 flags=[arg for arg in args if arg.startswith(('-DCMAKE_C_FLAGS=','-DCMAKE_CXX_FLAGS='))]
 subprocess.run([os.environ['REAL_CMAKE'],'-S',os.environ['PROBE_FIXTURE'],'-B',str(build)]+flags,check=True,stdout=subprocess.DEVNULL)
 config=build/'soplex/config.h';config.parent.mkdir(exist_ok=True);config.write_text('#define SOPLEX_WITH_GMP\\n#define SOPLEX_WITH_BOOST\\n#define SOPLEX_WITH_MPFR\\n')
''')
            wrapper.chmod(0o755)
            env=os.environ.copy();env.update(PROBE_COMMANDS=str(temp/'commands.jsonl'),REAL_CMAKE=str(supplied/'python-tools/cmake/data/bin/cmake'),PROBE_FIXTURE=str(fixture))
            script=Path(__file__).with_name('build-dependencies.sh')
            subprocess.run(['bash',str(script),str(cache),str(wrapper),'/bin/true','1'],env=env,check=True,stdout=subprocess.DEVNULL)
            commands=[json.loads(line) for line in (temp/'commands.jsonl').read_text().splitlines()]
            configure=[cmd for cmd in commands if '-S' in cmd];self.assertEqual(len(configure),2)
            for cmd in configure:
                for flag in ('-DCMAKE_C_FLAGS=','-DCMAKE_CXX_FLAGS='):
                    value=next(x for x in cmd if x.startswith(flag))
                    self.assertIn('-ffile-prefix-map='+str(cache)+'=dependencies',value)
                    self.assertIn('-ffile-prefix-map='+str(supplied/'deps')+'=dependencies/deps',value)
            for dependency in ('scip','soplex'):
                data=(cache/'build'/dependency/'CMakeCache.txt').read_text()
                for key in ('CMAKE_C_FLAGS:','CMAKE_CXX_FLAGS:'):
                    line=next(line for line in data.splitlines() if line.startswith(key))
                    self.assertIn('-ffile-prefix-map='+str(cache)+'=dependencies',line)

if __name__=='__main__':unittest.main()
