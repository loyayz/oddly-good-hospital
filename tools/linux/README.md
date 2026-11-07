# Offline Linux x86_64 product build

This workflow compiles the repository's production platform sources, including their
Linux branches. It does not use or transform the temporary POSIX performance-test
adapter. Windows PowerShell entry points are unchanged.

## Build contract and prerequisites

- Linux x86_64, Python 3.9+, GCC/G++, binutils, and adequate free disk/RAM.
- Godot **4.7.2.stable.official.ed1daf0bf**, standard single-precision Linux
  x86_64. The native build verifies its pinned binary SHA-256, actual version,
  generated extension API version, primitive sizes, and method hashes.
- Separately supplied upstream archives matching `dependencies.lock.json` and
  their extracted sources. These tools do not download, install or obtain login
  credentials. Archive provenance URLs are reference metadata, not network calls.
- A dependency cache with `downloads/`, `deps/`, `prefix/` and `build/` laid out
  below. GMP development headers/shared libraries and PIC MPFR 4.2.2 in `prefix/`
  must be supplied. System GMP is resolved using the installed G++ search path.
- A fresh product export additionally needs verified Godot 4.7.2 Linux release
  export templates, complete license/source inputs and runtime-library mapping.

These scripts change build/packaging behavior, not hospital business rules. The
selected checks are input-integrity rejection, ABI validation, command planning,
argument validation and fail-closed release prerequisites. A native build is not
functional regression, target-host graphics validation or a performance result.

## Dependency cache layout and clean dependency build

`deps/` contains these extracted upstream roots:

- `soplex-a00610534e044f35aa298059eb963312336c4c9c`
- `scip-10.1.0`
- `boost_1_92_0`
- `rapidjson-24b5e7a8b27f42fa16b96fc70aade9106cf7102f`
- `sqlite-amalgamation-3540000`
- `minizip-ng-4.2.2`
- `zlib-1.3.2`

The MPFR source archive is also pinned; supply its built `prefix/include/mpfr.h`
and `prefix/lib/libmpfr.so`. Supply a GMP development package and its provenance.
MPFR/GMP bootstrap and operating-system provisioning are explicit external
prerequisites, not hidden network/install steps. For a clean dependency build
from reviewed extracted inputs, with a supplied CMake and Ninja:

```sh
bash tools/linux/build-dependencies.sh "$CACHE" "$CMAKE" "$NINJA" 1
```

This compiles static PIC SoPlex and SCIP using GMP/MPFR and exact solving, with
unneeded integrations disabled. It deliberately does not build MPFR/GMP or
extract unreviewed archives. Resulting archives are
`build/soplex/lib/libsoplex.a` and `build/scip/lib/libscip.a`. CMake-generated
headers, CMake caches and configure logs remain alongside them. The script
verifies all source archive pins first and disables CMake FetchContent network
population. Run in an offline environment to enforce the no-network contract
for all third-party CMake code as well.

A previously built cache may instead be explicitly captured:

```sh
python tools/build-platform-linux.py capture-cache \
  --cache "$CACHE" --output "$WORK/linux-dependency-inputs.json"
```

Capture records streaming SHA-256 hashes of all pinned archives, dependency
source/header inputs, generated headers, static/shared library artifacts,
CMake configuration files, available historical build records, and current
compiler/binutils executables and versions, plus GMP C/C++ headers and their
actual transitive system includes. It is a local inventory, **not**
proof that historical static archives were produced by the current compiler or
that extracted source trees exactly correspond to their archives. Audit the
supplied build records or rebuild in a clean, controlled environment when that
stronger guarantee is needed. Subsequent builds reject changed captured inputs.
No copied static libraries or source trees are required.

## Native build and dry-run

```sh
python tools/build-platform-linux.py build \
  --inputs "$WORK/linux-dependency-inputs.json" \
  --godot "$GODOT" --build-dir "$WORK/native-build" --dry-run

# Remove --dry-run to compile sequentially and link the production extension.
python tools/build-platform-linux.py build \
  --inputs "$WORK/linux-dependency-inputs.json" \
  --godot "$GODOT" --build-dir "$WORK/native-build"
```

Dry-run validates real inputs and produces `build-manifest.json`, without
compiling or generating ABI dumps. Actual compilation dumps the API/interface
from pinned Godot, generates `platform_guard_abi.h`, compiles SQLite, the zip
backend and repository platform sources, and links with undefined-symbol
checking. The output is
`game/platform/linux/bin/oddly_good_platform.linux.x86_64.so`. An alternative
`--output` is supported for controlled validation, but the project's extension
registration expects the default production location for export.

The built manifest contains exact commands, source hashes, dependency inventory,
ABI-file hashes, output hash, builder/lock hashes, and ELF DT_NEEDED/RPATH
inspection. Before publishing the output, all recorded candidate source and
builder files are rehashed; changed-during-build inputs reject publication. Dynamic MPFR,
GMP and compiler runtimes are not silently installed or bundled. RPATH is
`$ORIGIN`, allowing explicitly bundled, replaceable LGPL shared libraries.
Source paths are prefix-mapped in the native compile commands. This is a
repeatable, source-identified procedure; byte-identical cross-toolchain builds
are not claimed. Do not share a build directory between concurrent invocations.
A failed build does not replace the last successful `.so`; consumers must require
`status: built` and a matching artifact hash from the manifest.

## Release export and license/source manifest

The project must define the export preset **Linux x86_64 Release**. Supply
`$DATA_HOME/godot/export_templates/4.7.2.stable/linux_release.x86_64` and its
independently verified SHA-256. Export does not download templates.

```sh
python tools/build-game-linux.py \
  --godot "$GODOT" --native-manifest "$WORK/native-build/build-manifest.json" \
  --distribution-inputs "$WORK/distribution-inputs.json" \
  --data-home "$DATA_HOME" --template-sha256 "$VERIFIED_TEMPLATE_SHA256" \
  --output "$WORK/release-linux" --dry-run
```

Remove `--dry-run` to export to a **new** directory. Template files, license files
and source artifacts are not present merely because native compilation works.
Missing inputs fail explicitly; an incomplete directory is not a release.

The distribution JSON has two maps:

1. `components`: exactly `project`, `godot`, `sqlite`, `rapidjson`, `boost`,
   `scip`, `soplex`, `minizip-ng`, `zlib`, `gmp`, `mpfr`, `compiler-runtime`,
   `glibc`. Each entry has a nonempty `licenses` list and an optional `sources`
   list. Each file record contains an absolute `path` and its `sha256`.
   For GMP, MPFR, compiler runtime and glibc, an explicit `distribution` of
   `bundled` or `system` is mandatory. Bundled components require corresponding
   `sources` and applicable build materials. System-only components instead
   require a documented `requirement`; their source archives are not required.
   A bundled compiler runtime covered by an applicable Runtime Library Exception
   may instead set `source_obligation: runtime-library-exception` and a nonempty
   `license_basis` explaining that assessment. Its actual notices/exception text
   are still mandatory. This declaration needs legal review; the tool cannot
   establish the exception applies. Supply all applicable notices, license texts (including LGPL and
   GCC Runtime Library Exception when applicable), corresponding upstream and
   distribution patches/build materials, rather than just a URL or placeholder.
2. `elf_dependencies`: each required/transitive SONAME maps to a file record
   with `mode: bundle` or `mode: system`. System entries also require a human
   readable `requirement` identifying supported runtime distribution/version.
   Every ELF entry has a `component` key referring to its component entry;
   bundling a library declared as system-only is rejected.
   Include dependencies of both the extension and Godot export template. Do not
   bundle glibc/loader casually; normally declare the supported system runtime.

A shortened structural example (not a valid complete manifest):

```json
{
  "components": {
    "gmp": {
      "distribution": "bundled",
      "licenses": [{"path": "/inputs/gmp/COPYING.LESSER", "sha256": "..."}],
      "sources": [{"path": "/inputs/gmp-corresponding-source.tar.gz", "sha256": "..."}]
    }
  },
  "elf_dependencies": {
    "libgmp.so.10": {"path": "/inputs/libgmp.so.10", "sha256": "...", "mode": "bundle", "component": "gmp"},
    "libc.so.6": {"path": "/inputs/libc.so.6", "sha256": "...", "mode": "system", "component": "glibc", "requirement": "Supported glibc baseline and distribution"}
  }
}
```

Empty custom-template values select the standard verified template location.
A nonempty custom path must resolve to that same verified template.

The exporter verifies source and native identities, template hash, component
completeness, license/source files, library SONAMEs and transitive resolutions.
It rejects stale native export artifacts, copies only explicitly selected
runtime libraries alongside the exported extension, and copies supplied
licenses/source artifacts into the release. `package-manifest.json` inventories
all output files and ELF dependency/version requirements. Failed stages preserve their logs, error details, source inventory and
`failed` status; only fully checked exports become `exported`. These checks
support a compliance review but cannot establish the legal completeness of
supplier-provided notices or corresponding-source packages.

## Focused verification

```sh
python tools/linux/test_build.py
python tools/linux/test_export.py
# Add an independently generated API fixture to exercise ABI generation:
OGH_TEST_EXTENSION_API=/verified/extension_api.json python tools/linux/test_build.py
python -m py_compile tools/linux/*.py tools/build-platform-linux.py tools/build-game-linux.py
bash -n tools/linux/build-dependencies.sh
```

The initial Linux product preparation validated the existing offline cache,
passed six native build checks with the pinned API fixture, eleven synthetic
export contract checks, and generated a
native dry-run plan. Clean dependency compilation and release export must be
reported separately. A subsequent actual export completed content/import/export and isolated
headless startup. Its payload audit discovered historical reports, so that
first successful executable remains rejected for player distribution. The
Linux exclusions and actual-PCK checks were then tightened. Consult the final
package manifest and independent audit for the eventual candidate; do not infer
a final release pass from the earlier smoke test. Verified templates, runtime
mappings and required notices remain mandatory.

### Export stage and source-integrity checks

After preflight, export runs `tools/compile-content.py --check`, then Godot
`--headless --path ... --editor --import --quit`, and finally the release export.
Each stage has its own retained log and exit/error status. A nonzero exit or
Godot ERROR/SCRIPT ERROR/Parse Error fails the build even if no export process
error is returned. Dry-run only reports the commands and verifies supplied
inputs; it never runs content compilation, import or export.

All regular source files, gameplay scripts, assets, content and build settings
are hashed before these stages. Generated cache directories (`.godot`, `.cache`,
`.build`, `__pycache__`) and Python bytecode are excluded; intentional ordinary
resources are not. Content checking must not mutate the source inventory.
During import only, a sidecar change is allowed when paired with an unchanged
existing resource: generated `.import` remap/cache paths may change, but existing
importer/type/UID and `[params]` settings must remain unchanged; new script UID
sidecars may appear, but existing UID values cannot change. Locale translation
outputs are accepted only when paired with an unchanged existing locale CSV.
All such generated changes are inventoried. After import, the entire inventory
including these sidecars is frozen and checked after export and packaging.
Added/deleted/modified ordinary files or changed import settings fail the build.
Release output must be outside the source tree, preventing output files from
contaminating or escaping these checks.

### Isolated editor state and desktop target

The exporter creates fresh workspace-local HOME, XDG_CONFIG_HOME and
XDG_CACHE_HOME directories. Use `--state-dir` to choose their new parent; the
default is `<output-name>.state` beside the release output. The state directory
must be new and must not contain, equal or sit inside the source, release output
or template data-home. Actual paths are recorded in `build_environment`. No
configuration is copied from the user's real home and no system permissions
are changed. XDG_DATA_HOME remains the supplied verified template data-home.
This isolates editor preferences/cache while retaining the pinned templates.

ELF DT_NEEDED validation is only one part of deployment. This project's
`gl_compatibility` renderer requires a working OpenGL 3.3 driver and compatible
hardware. A graphical target needs an X11 or Wayland desktop and appropriate
client/GLX/EGL runtime libraries. Audio requires a PulseAudio-compatible service
or ALSA and device access. Godot can dynamically load further feature-dependent
libraries for D-Bus/portals, fontconfig, udev, Wayland decorations and
speech/accessibility. These are not exhaustively represented by ELF DT_NEEDED.
Headless/Dummy-audio tests do not validate display, input or audio. See the
[official system requirements](https://docs.godotengine.org/en/stable/about/system_requirements.html),
[driver options](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html),
and [pinned Linux build configuration](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/platform/linuxbsd/detect.py).

The current native build's versioned symbols require GLIBC_2.38,
GLIBCXX_3.4.32 and CXXABI_1.3.15. The current host reports Debian 13 with
glibc 2.41, GMP 6.3.0 and MPFR 4.2.2. These are audited host facts, not a promise
that the game works on every distribution satisfying these symbols. Declare
system runtime requirements and validate the intended desktop separately.

### Package-content and player-delivery boundary

The exporter reads the actual standalone Godot 4.7.2 PCK v4 directory and checks
all entry bounds, canonical paths, duplicate paths, overlapping contents, MD5
integrity and per-entry SHA-256. Unknown/encrypted/sparse formats are rejected.
`pck-resources.json` records the actual payload, not only exporter log claims.
Reports, tests, tools, art sources, native C/C++ headers/source, Windows binaries
and build objects are forbidden. Linux-specific exclusion changes leave the
Windows export preset unchanged. Four explicitly required docs/data JSON inputs
are permitted; unrelated feasibility/history data is excluded.

The full release output is an internal build directory: logs, package-manifest
and PCK audit files can contain machine-local paths. **Do not distribute the
whole directory.** `public-release-files.json` is a portable relative-path,
SHA-256 and size allowlist for player delivery: executable, PCK, native library,
licenses, public runtime requirements, and explicitly bundled runtime/source
artifacts where applicable. Archive only these listed payload files. Source and
full evidence backups are separate deliverables, not part of the game install.
The runtime requirements identify the current Linux candidate limitations,
including unverified GUI/audio and successful saves, and the production refusal
to save when complete cgroup resource limits cannot be established.

Focused parser tests: `python tools/linux/test_pck.py`.

Dependency builds apply `-ffile-prefix-map` in both C and C++ compilation,
covering the selected cache root and resolved source/prefix symlink targets.
This is necessary because native linking or stripping cannot remove embedded
`__FILE__` strings from precompiled static dependencies. A focused command/cache
probe uses real small CMake caches without compiling solver code:
`OGH_TEST_DEPENDENCY_CACHE=/verified/cache python tools/linux/test_dependency_flags.py`.

PCK policy is a runtime-resource allowlist, not a general directory blacklist:
unknown roots/files such as `debug.log` or `private/report.json` fail. Selected
public payload bytes are additionally scanned for this build's local path
roots, including cross-buffer matches. Only an executable exactly matching the
verified official template is exempt from our local-build-path scan; upstream
vendor build paths are not rewritten. The native extension, PCK, runtime
requirements and copied notices remain checked.
