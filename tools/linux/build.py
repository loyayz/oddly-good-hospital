#!/usr/bin/env python3
"""Offline Linux x86_64 build. No download, installation or source rewriting."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import shlex
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
ENGINE_VERSION = '4.7.2.stable.official.ed1daf0bf'
ENGINE_SHA = '8d106cbe6144c2dc7e881d61d2429c1a8a76e6b22ef48bd5e48dcf934953f71e'
DIRS = dict(soplex='soplex-a00610534e044f35aa298059eb963312336c4c9c', scip='scip-10.1.0', boost='boost_1_92_0', rapidjson='rapidjson-24b5e7a8b27f42fa16b96fc70aade9106cf7102f', sqlite='sqlite-amalgamation-3540000', zip='minizip-ng-4.2.2', zlib='zlib-1.3.2')

def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()

def record(path):
    path = Path(path).resolve(strict=True)
    return {'path': str(path), 'sha256': digest(path), 'bytes': path.stat().st_size}

def write_json(path, obj):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(json.dumps(obj, indent=2, sort_keys=True) + '\n')

def run(cmd, cwd=None, input_text=None):
    return subprocess.check_output([str(x) for x in cmd], cwd=cwd, input=input_text, text=True, stderr=subprocess.PIPE).strip()

def checked(item):
    if digest(item['path']) != item['sha256']:
        raise ValueError('Input changed since cache capture: ' + item['path'])
    return Path(item['path'])

def tool(name):
    path = shutil.which(name)
    if not path:
        raise ValueError('Required installed tool unavailable: ' + name)
    return record(path) | {'version': run([path, '--version']).splitlines()[0]}

def capture(cache, output):
    cache = cache.resolve(strict=True)
    locks = json.loads((Path(__file__).parent / 'dependencies.lock.json').read_text())
    archives = {}
    for name, lock in locks.items():
        item = record(cache / 'downloads' / name)
        if item['sha256'] != lock['sha256']:
            raise ValueError('Pinned source archive mismatch: ' + name)
        archives[name] = item | {'url': lock['url']}
    # Capture the actual inputs, not an assertion that historical cache builds are reproducible.
    files = set()
    for folder in [cache/'deps'/v for v in DIRS.values()] + [cache/'prefix/include', cache/'build/scip/scip', cache/'build/soplex/soplex']:
        if not folder.is_dir():
            raise ValueError('Required dependency tree missing: ' + str(folder))
        files.update(p for p in folder.rglob('*') if p.is_file() and p.suffix in ('.h', '.hpp', '.ipp', '.tcc', '.inc', '.c', '.cpp', '.hh', '.hxx'))
    # Capture GMP C/C++ headers and their actual transitive system includes.
    header_deps = run(['g++', '-M', '-MT', 'headers', '-x', 'c++', '-'], input_text='#include <gmpxx.h>\n')
    dependency_paths = shlex.split(header_deps.replace('\\\n', ' ').split(':', 1)[1])
    files.update(Path(p) for p in dependency_paths if Path(p).is_file())
    files.update(cache/'build'/name/'CMakeCache.txt' for name in ('scip', 'soplex'))
    artifacts = {name: record(path) for name, path in {
        'scip':cache/'build/scip/lib/libscip.a', 'soplex':cache/'build/soplex/lib/libsoplex.a',
        'mpfr':cache/'prefix/lib/libmpfr.so',
        'gmp':Path(run(['g++','-print-file-name=libgmp.so'])),
        'gmpxx':Path(run(['g++','-print-file-name=libgmpxx.so']))}.items()}
    for name in ('gmp', 'gmpxx'):
        if not Path(artifacts[name]['path']).is_absolute():
            raise ValueError('GMP development package required')
    obj = {'schema':1, 'cache':str(cache), 'archives':archives, 'inputs':[record(p) for p in sorted(files)],
           'artifacts':artifacts, 'tools':{n:tool(n) for n in ('cc','g++','ar','readelf')},
           'provenance_note':'Locally captured prebuilt cache, not independently reproduced. Static archive identity and current headers/configuration recorded; historical compiler identity must be audited using supplied build records.',
           'build_records':[record(cache/n) for n in ('build_dependencies.sh','soplex-configure.log','scip-configure.log') if (cache/n).is_file()]}
    write_json(output, obj)
    print('Captured cache manifest:', output)

def abi(api, destination):
    if api['header']['precision'] != 'single' or any(api['header'].get('version_'+k) != v for k,v in [('major',4),('minor',7),('patch',2)]):
        raise ValueError('Wrong engine extension API version/precision')
    sizes = {s['name']:s['size'] for row in api['builtin_class_sizes'] if row['build_configuration']=='float_64' for s in row['sizes']}
    expected = {'Variant':24,'String':8,'StringName':8,'Dictionary':8,'Array':8,'PackedByteArray':16,'PackedInt32Array':16,'PackedInt64Array':16,'Vector2':8,'Rect2':16}
    if any(sizes.get(k)!=v for k,v in expected.items()):
        raise ValueError('Unexpected engine ABI sizes')
    macros = {'VARIANT':24,'STRING':8,'STRING_NAME':8,'DICTIONARY':8,'ARRAY':8,'PACKED_BYTE_ARRAY':16,'PACKED_INT32_ARRAY':16,'PACKED_INT64_ARRAY':16}
    lines = [f'#define OGH_{k}_SIZE {v}' for k,v in macros.items()]
    methods = [('USER_DIR','OS','get_user_data_dir'),('NOTIFICATION','Object','notification'),('ASTAR_RESERVE','AStar2D','reserve_space'),('ASTAR_ADD','AStar2D','add_point'),('ASTAR_DISABLE','AStar2D','set_point_disabled'),('ASTAR_CONNECT','AStar2D','connect_points'),('ASTAR_COUNT','AStar2D','get_point_count'),('ARRAY_SIZE','Array','size'),('ARRAY_APPEND','Array','append'),('BYTES_RESIZE','PackedByteArray','resize'),('DICTIONARY_KEYS','Dictionary','keys'),('DICTIONARY_GET','Dictionary','get')]
    classes = {c['name']:c for c in api['classes']+api['builtin_classes']}
    for macro, cls, method in methods:
        matches=[m['hash'] for m in classes[cls]['methods'] if m['name']==method]
        if len(matches)!=1 or not matches[0]:
            raise ValueError('Missing/ambiguous ABI method '+cls+'.'+method)
        lines.append(f'#define OGH_{macro}_HASH {matches[0]}')
    Path(destination).write_text('\n'.join(lines)+'\n')

def native(a):
    if platform.system()!='Linux' or platform.machine() not in ('x86_64','AMD64'):
        raise ValueError('Build host must be Linux x86_64')
    config=json.loads(a.inputs.read_text())
    for item in list(config['archives'].values())+config['inputs']+list(config['artifacts'].values())+list(config['tools'].values())+config['build_records']:
        checked(item)
    # A locally edited manifest cannot silently change upstream archive pins.
    locks=json.loads((Path(__file__).parent/'dependencies.lock.json').read_text())
    if any(config['archives'][k]['sha256']!=v['sha256'] for k,v in locks.items()):
        raise ValueError('Cache manifest does not match dependency lock')
    if digest(a.godot)!=ENGINE_SHA or run([a.godot,'--version'])!=ENGINE_VERSION:
        raise ValueError('Requires pinned Godot 4.7.2 standard Linux x86_64 binary')
    r=Path(config['cache']); b=a.build_dir.resolve(); b.mkdir(parents=True,exist_ok=True)
    src=ROOT/'game/platform/windows'; deps={k:r/'deps'/v for k,v in DIRS.items()}
    cc=config['tools']['cc']['path']; cxx=config['tools']['g++']['path']
    commands=[]; objects=[]
    includes=['-I',str(b),'-I',str(deps['sqlite'])]
    def compile_one(source, flags, compiler=cc):
        obj=b/(Path(source).stem+'.o'); objects.append(str(obj)); commands.append([compiler]+flags+['-c',str(source),'-o',str(obj)])
    base=['-O2','-fPIC','-ffile-prefix-map='+str(ROOT)+'=.','-ffile-prefix-map='+str(r)+'=dependencies']
    compile_one(deps['sqlite']/'sqlite3.c',base+['-std=c11','-DSQLITE_THREADSAFE=1','-DSQLITE_OMIT_LOAD_EXTENSION=1','-DSQLITE_DQS=0'])
    compile_one(src/'platform_session_guard.c',base+['-std=c11','-Wall','-Wextra','-Werror']+includes)
    zflags=base+['-std=c11','-D_GNU_SOURCE','-DNDEBUG','-DHAVE_ZLIB','-DZLIB_COMPAT','-DMZ_ZIP_NO_ENCRYPTION','-DMZ_ZIP_NO_CRYPTO','-DHAVE_UNISTD_H','-I',str(b),'-I',str(deps['zip']),'-I',str(deps['zlib'])]
    for name in 'mz_crypt mz_os mz_os_posix mz_strm mz_strm_mem mz_strm_os_posix mz_strm_zlib'.split():
        compile_one(deps['zip']/(name+'.c'),zflags)
    for name in 'adler32 crc32 deflate infback inffast inflate inftrees trees zutil compress uncompr'.split():
        compile_one(deps['zlib']/(name+'.c'),zflags)
    compile_one(src/'platform_backup_zip.c',zflags)
    cflags=base+['-std=c++17','-DNDEBUG','-DSCIP_STATIC_DEFINE','-Wall','-Wextra','-Werror','-I',str(b)]
    for p in (deps['soplex']/'src',r/'build/soplex',r/'build/scip',deps['scip']/'src',r/'prefix/include',deps['boost'],deps['rapidjson']/'include',deps['zip'],deps['zlib']):
        cflags+=['-isystem',str(p)]
    compile_one(src/'platform_arrivals.cpp',cflags,cxx)
    target=a.output.resolve(); tmp=target.with_suffix('.so.partial')
    commands.append([cxx,'-shared','-Wl,-z,defs','-Wl,-rpath,$ORIGIN','-o',str(tmp)]+objects+[config['artifacts'][k]['path'] for k in ('scip','soplex','mpfr','gmpxx','gmp')]+['-pthread','-ldl'])
    source_files=[record(p) for p in sorted(src.rglob('*')) if p.is_file() and p.suffix in ('.c','.h','.cpp','.inc')]
    linux=ROOT/'game/platform/linux'
    if linux.exists():
        source_files += [record(p) for p in sorted(linux.rglob('*')) if p.is_file() and p.suffix in ('.c','.h','.cpp','.inc')]
    builder_files=[record(Path(__file__).resolve()), record(ROOT/'tools/build-platform-linux.py'), record(Path(__file__).with_name('dependencies.lock.json')), record(Path(__file__).with_name('build-dependencies.sh'))]
    manifest={'builder_files':builder_files,'schema':1,'status':'planned' if a.dry_run else 'building','engine':record(a.godot),'engine_version':ENGINE_VERSION,'cache_manifest':record(a.inputs),'dependency_provenance':config,'sources':source_files,'commands':commands,'output':str(target)}
    write_json(b/'build-manifest.json',manifest)
    if a.dry_run:
        print('Validated offline build plan:',b/'build-manifest.json'); return
    target.parent.mkdir(parents=True,exist_ok=True)
    run([a.godot,'--headless','--dump-gdextension-interface'],cwd=b)
    run([a.godot,'--headless','--dump-extension-api'],cwd=b)
    abi(json.loads((b/'extension_api.json').read_text()),b/'platform_guard_abi.h')
    (b/'mz_config.h').write_text('#pragma once\n'+''.join('#define '+s+' 1\n' for s in 'HAVE_DIRENT_H HAVE_SYS_DIRENT_H HAVE_INTTYPES_H HAVE_STDINT_H HAVE_PDIR HAVE_FSEEKO HAVE_SYMLINK HAVE_READLINK'.split()))
    for command in commands:
        print(' '.join(command),flush=True)
        subprocess.run(command,check=True)
    elf=run([config['tools']['readelf']['path'],'-d',tmp])
    if 'Machine:                           Advanced Micro Devices X86-64' not in run(['readelf','-h',tmp]):
        raise ValueError('Unexpected output ELF architecture')
    # Refuse publication if a source or builder changed while compiling.
    for item in source_files + builder_files:
        checked(item)
    tmp.replace(target)
    manifest.update(status='built',artifact=record(target),elf_dynamic=elf,needed=re.findall(r'\(NEEDED\).*\[(.*?)\]',elf),abi_files=[record(b/n) for n in ('gdextension_interface.h','extension_api.json','platform_guard_abi.h')])
    write_json(b/'build-manifest.json',manifest)
    print('Native build complete:',target)

def main():
    p=argparse.ArgumentParser(description=__doc__)
    sub=p.add_subparsers(dest='command',required=True)
    c=sub.add_parser('capture-cache',help='Hash supplied dependency sources/artifacts; never builds or downloads')
    c.add_argument('--cache',type=Path,required=True); c.add_argument('--output',type=Path,required=True)
    n=sub.add_parser('build',help='Compile repository sources, never the test adapter')
    n.add_argument('--inputs',type=Path,required=True);n.add_argument('--godot',type=Path,required=True)
    n.add_argument('--build-dir',type=Path,default=ROOT/'.build/linux-native')
    n.add_argument('--output',type=Path,default=ROOT/'game/platform/linux/bin/oddly_good_platform.linux.x86_64.so')
    n.add_argument('--dry-run',action='store_true')
    a=p.parse_args()
    try:
        capture(a.cache,a.output) if a.command=='capture-cache' else native(a)
    except (OSError,ValueError,KeyError,subprocess.CalledProcessError) as e:
        p.exit(1,'Linux build failed: '+str(e)+'\n')

if __name__=='__main__':
    main()
