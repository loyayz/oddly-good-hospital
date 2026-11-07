#!/usr/bin/env bash
# Offline build from separately supplied, verified/extracted inputs. No installs.
set -euo pipefail
if [[ $# != 4 ]]; then
  echo 'Usage: build-dependencies.sh CACHE_ROOT CMAKE_EXECUTABLE NINJA_EXECUTABLE JOBS' >&2
  exit 2
fi
R=$(realpath "$1"); CMAKE=$(realpath "$2"); NINJA=$(realpath "$3"); JOBS=$4
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || { echo 'JOBS must be positive' >&2; exit 2; }
HERE=$(cd "$(dirname "$0")" && pwd)
python3 - "$R" "$HERE/dependencies.lock.json" <<'PY'
import hashlib,json,pathlib,sys
r=pathlib.Path(sys.argv[1])
for name,item in json.loads(pathlib.Path(sys.argv[2]).read_text()).items():
 h=hashlib.sha256()
 with (r/'downloads'/name).open('rb') as f:
  for b in iter(lambda:f.read(1048576),b''): h.update(b)
 if h.hexdigest()!=item['sha256']: raise SystemExit('Source archive mismatch: '+name)
for name in ['prefix/include/mpfr.h','prefix/lib/libmpfr.so']:
 if not (r/name).exists(): raise SystemExit('Supply separately built PIC MPFR 4.2.2 and GMP development inputs: '+name)
PY
mkdir -p "$R/build"
# Apply path normalization while compiling every dependency C/C++ translation unit.
# Resolve shared cache symlinks as well as the selected build/cache root.
PREFIX_MAP_FLAGS=$(python3 - "$R" <<'PYMAP'
import pathlib,shlex,sys
r=pathlib.Path(sys.argv[1])
maps=[(str(r),'dependencies'),(str((r/'deps').resolve()),'dependencies/deps'),(str((r/'prefix').resolve()),'dependencies/prefix')]
print(' '.join(shlex.quote('-ffile-prefix-map='+old+'='+new) for old,new in maps))
PYMAP
)
COMMON=(-G Ninja "-DCMAKE_MAKE_PROGRAM=$NINJA" -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON "-DCMAKE_C_FLAGS=$PREFIX_MAP_FLAGS" "-DCMAKE_CXX_FLAGS=$PREFIX_MAP_FLAGS" -DFETCHCONTENT_FULLY_DISCONNECTED=ON "-DGMP_DIR=$R/prefix" "-DMPFR_DIR=$R/prefix" "-DMPFR_LIBRARY=$R/prefix/lib/libmpfr.so" "-DBOOST_ROOT=$R/deps/boost_1_92_0" "-DBoost_INCLUDE_DIR=$R/deps/boost_1_92_0" "-DBoost_DIR=$R/prefix/lib/cmake/Boost-1.92.0" -DCMAKE_POLICY_DEFAULT_CMP0167=OLD -DPAPILO=OFF -DZLIB=OFF)
"$CMAKE" -S "$R/deps/soplex-a00610534e044f35aa298059eb963312336c4c9c" -B "$R/build/soplex" "${COMMON[@]}" -DGMP=ON -DBOOST=ON -DMPFR=ON > "$R/soplex-configure.log" 2>&1
for feature in GMP BOOST MPFR; do grep "^#define SOPLEX_WITH_$feature" "$R/build/soplex/soplex/config.h"; done
"$CMAKE" --build "$R/build/soplex" --target libsoplex --parallel "$JOBS"
"$CMAKE" -S "$R/deps/scip-10.1.0" -B "$R/build/scip" "${COMMON[@]}" "-DSOPLEX_DIR=$R/build/soplex" -DSHARED=OFF -DGMP=ON -DMPFR=ON -DEXACTSOLVE=ON -DREADLINE=OFF -DZIMPL=OFF -DAMPL=OFF -DIPOPT=OFF -DEXPRINT=none -DSYM=none -DTPI=none -DLPS=spx -DLPSEXACT=spx > "$R/scip-configure.log" 2>&1
"$CMAKE" --build "$R/build/scip" --target libscip --parallel "$JOBS"
printf 'Build complete. Capture inputs with tools/build-platform-linux.py capture-cache before native compilation.\n'
