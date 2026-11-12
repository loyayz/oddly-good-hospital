# Cloud migration and bounded transport continuation

The previously validated local-waypoint fix and its complete evidence were committed and pushed as `e232c42389e614cf13d305c4376d59892c4aa0c3`. Its Windows working tree was clean after publication. Subsequent development and execution moved to a new Linux cloud checkout of that exact commit. No Windows development or simulation was performed during this migration.

The cloud copy reverified all 90 published archive members and source identities, including the complete tick7641 snapshot `59570f0a9f59bfb5bdf5f5f88531a461c226cef43268ae130cbea581e718d1ba` (5,543,896 bytes). No unpublished code or evidence was guessed or reconstructed. Gameplay sources remain unchanged from e232c42.

## Qualified Linux runtime

- Official Godot `4.7.2.stable.official.ed1daf0bf`, binary SHA256 `8d106cbe6144c2dc7e881d61d2429c1a8a76e6b22ef48bd5e48dcf934953f71e`. The preinstalled 4.6.3 was not substituted.
- Production native extension SHA256 `3e97c961acf01e178046efc14b5dff786a83b4e91f09638528ccf531b248d379`.
- All eight repository source-archive pins were verified. Clean builds used GCC 14.2.0, CMake 4.4.4, Ninja 1.13.2, Boost 1.92.0, MPFR 4.2.2, SoPlex 8.1.0 and SCIP 10.1.0. Host GMP 6.3.0 bytes and available provenance were recorded; its original package database was unavailable. That limitation is not hidden by the source archive checks.
- Actual native load and bounded headless project import both exited 0, without ERROR/SCRIPT ERROR/Parse Error. Import generated 234 UID sidecars, separately inventoried and not added to the gameplay commit, plus cache and the ignored native binary.
- Retained stage times: MPFR 41s; Boost bootstrap/install 149s; SoPlex/SCIP 451s; dependency capture/native build 262s; import 17s. Load finished within one timestamp second. Individual download durations were not instrumented.

The first dependency configure failed closed because upstream Boost CMake package metadata was missing. Installing that metadata resolved it without changing pins, build scripts or business rules. Build/load success does not establish complete Linux gameplay, save/restore, GUI/audio, release or performance acceptance.

## Actual one-step boundary

From tick7641, one full production step was executed separately in plain and observed cloud processes. Complete World/RNG/ordered-event binaries match at tick7642, SHA256 `fb4dce11b37978f555437a1abe896d5475efb21431aa38b74ed0f188a13af9a8`. This is cloud-versus-cloud qualification, not a claim of Windows output equality.

Worker288's existing return leg requests southward movement, but its actual MotionResult identifies cleaner0028 and zero displacement. There is no static, door or reservation blocker. Cleaner0028 had actually moved east earlier in that same step. Worker288 retains its original request4024, job287, current waypoint/rejoin [87,44], target [86,46] and corner [87,46]. It must not earn the outstanding waypoint merely because it stands on the lift landing. Patient0111's actual alight rejection remains body288.

This is different from the fixed worker313 completed-waypoint defect. No new rule violation was established.

## Bounded departure check

A six-step cap then tested the concrete question of whether cleaner0028's existing departure clears worker288. It was not a blind full-world waiting extension.

- At7642, cleaner0028 still blocks worker288.
- At7643 and7644, that departure clears: worker288 actually moves south twice, reaching [86,44.4000015258789].
- At7645 through7647, nurse0025 is the actual new body blocker. Nurse0025 also moves, including a westward move on7647; a stationary deadlock is not established.
- All six patient0111 alight attempts still reject against body288. No actual alight, target-worker arrival or service work is claimed.

Plain and observed complete binaries again match, now tick7648, SHA256 `477372219729a259f451b0db95968ff098a3d6c924ac8ca125b855f2b21b6306`. The cap was honored and no subsequent continuation was run. The known cleaner departure question resolved positively. Further diagnosis would need a separately selected concrete boundary, not a priority change or fabricated motion.

## Method and limits

Exactly 7 logical production steps were observed, 14 executions including plain/observer qualification. The original 0.1s step, app main-thread policy, four environmental tasks and OMP_NUM_THREADS=1 were retained. No body, ticket, job, goal, route, benchmark input or business rule was changed to force progress. Only isolated runtime copies received reversible hooks, with all 2047 inventoried files restored and verified afterward.

The Linux guard owns a new process group, uses bounded timeout/termination and reaps it; a harmless Python sleep proved that guard separately. Each actual run uses fresh HOME/XDG/TMPDIR. Native/dependency identities and loading paths are recorded. Windows-only process guards were not reused unchanged.

Process wall times including startup were 9.230/9.001s for the one-step plain/observer pair and 9.046/8.637s for the six-step pair. These are diagnostic timings, not CPU performance measurements. The previous full-window failures, missing upgrade/visitation coverage and 0/3 accepted repetitions are not changed by this work. No new full performance window, release, GUI/audio or two-hour test was run.

## Evidence and continuation

[Summary](evidence/2026-11-12-cloud-continuation/summary.json), [runtime preparation](evidence/2026-11-12-cloud-continuation/preparation.zip), [one-step evidence](evidence/2026-11-12-cloud-continuation/one-step.zip), and [six-step evidence](evidence/2026-11-12-cloud-continuation/departure-six.zip) retain original results, complete inputs/finals, actual branch traces, reversible overlays, source/runtime identities, commands, logs and hash manifests. These are engineering evidence, not a player release package.

Latest continuation is the `plain6/result.json.final.bin` member of the six-step archive, tick7648 with the SHA above. The expanded cloud workspace is `/workspace/scratch/6962cc21ddf3/worker288-departure-six-20261112`. Fixed runtime preparation remains in sibling `cloud-validation-20261112`; subsequent runs must preserve its qualified native/dependency identity or explicitly rebuild and requalify.
