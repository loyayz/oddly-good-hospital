# Cloud runtime recovery for CPU profiling

The cloud runtime lost during the interrupted root-stage profile was rebuilt from the published repository and pinned official sources. This is a new preparation run; it does not recover the missing ordinary/profile raw results described in [the interruption report](2026-11-12-cloud-profile-interruption.md).

The build started from `75e63992525435834813aaa99f2e18298d1cd5f2` and finished at `3d8eda0752ccd1e2a9ca74eedbf5d64aac97c75b`. The only intervening change was the interruption document. Gameplay remains `e232c42389e614cf13d305c4376d59892c4aa0c3`. No Windows execution was used.

## Newly verified preparation

- Official Godot `4.7.2.stable.official.ed1daf0bf`: SHA256 `8d106cbe6144c2dc7e881d61d2429c1a8a76e6b22ef48bd5e48dcf934953f71e`.
- Freshly compiled Linux production native: SHA256 `3e97c961acf01e178046efc14b5dff786a83b4e91f09638528ccf531b248d379`. Its bytes match the previous build, but this result came from a new compilation, not reuse of an unavailable binary.
- All eight source archive pins verified. Compiler/tool identities, generated extension API/interface/guard files and host GMP bytes match the prior evidence. New runtime dependency identities and provenance are retained.
- Actual native load: exit0, four expected classes registered, 0.350526s.
- Actual headless import: exit0, no engine/script errors, 9.215084s. The 234 generated UID sidecars remain untracked and are not gameplay changes.
- SoPlex/SCIP dependency build: 273.268894s. Native build: 136.263034s. All downloads, extraction, MPFR, Boost, cache capture, load and import have separately recorded UTC and monotonic timings.

The earlier missing Boost CMake metadata issue was avoided by installing the upstream header metadata before configuring the dependencies, without changing versions or repository build logic. The original host GMP package-database provenance limitation is not erased by matching its bytes.

## Durable evidence and next boundary

[Preparation archive](evidence/2026-11-12-cloud-profile-recovery/preparation.zip) is 6621353 bytes, SHA256 `f34f996455cc0bba03b68d436d7d235c6f578bb6c4ecd6332fde9a1e61793186`. Its [manifest](evidence/2026-11-12-cloud-profile-recovery/preparation-manifest.json) covers all 32 members; ZIP CRC and each member's size/SHA256 were independently rechecked. The archive contains the recovery script, source/dependency/build identities, generated ABI files, commands, timing records and load/import logs. It does not include engine/native binaries, build caches, account credentials or home directories.

Build/load/import qualification does not establish gameplay, snapshot restore, profiling, release, GUI/audio or complete performance acceptance. Those were not run in this preparation batch. The next measurement must use a newly qualified ordinary/root-only pair and retain all existing workload and acceptance rules. Each complete raw result package must be durably published and read back before the following long measurement starts; a missing run's summary is never used as its raw evidence.

## Recovered-runtime diagnostic qualification

The new 0+2 plain/root-only pair completed and passed full World/RNG/ordered-event and business/failure-state equality. Both final binaries have SHA256 `21aff2546935022312333b67605680c491292575aaa845b07733db993a415a51`. Root-only instrumentation preserved the method body, every recorded tick/elapsed matched the measured driver row, counts and timing partitions passed, and locked source/cache/native/dependency identities remained unchanged. Process wall times were 4.217/4.523s including startup; they are qualification timings, not performance gains. Coverage=false and performance=null remain explicit.

The Linux owned-process guard was separately checked with a harmless Python sleep: timeout in 0.304s, exit-15, process reaped. Controller v2.1 SHA256 is `10b82734a87069043ddf292f2f905aa673392b0ec6d55ff83abff94a7a6e0677`. Its three independent phase entries bind qualification identity to subsequent runs and require a durable plain-result receipt before the full-stage entry. Three pure-Python synthetic test groups cover identity changes, missing/wrong stage records and non-acceptance status labels.

[Qualification archive](evidence/2026-11-12-cloud-profile-recovery/qualification.zip), 553479 bytes, SHA256 `b43118611326c986d9eae63845f6e66f2193ff64ee5ecbecd7ff529ae01704a4`, retains 30 raw members plus its manifest. [Support archive](evidence/2026-11-12-cloud-profile-recovery/qualification-support.zip), 2358 bytes, SHA256 `d87dbd58d940a105531a029beb10fe24b1cb728ac1719ded3fc8b1b353f9f2eb`, retains the guard proof, phase release and synthetic test source. Both ZIP CRC and all member sizes/SHA256 were independently verified. This is only instrumentation qualification, not a full workload or three-repeat acceptance result.
