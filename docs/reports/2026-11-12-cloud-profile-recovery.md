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

## New complete ordinary window

After the new qualification and its durable checkpoint, exactly one new ordinary 1000+6000 window completed. All 7000 production steps are recorded; all 6000 measured steps qualify as the >=144-present dense interval (ticks1634-7633, population min/median/max 164/165/170). Source, native, imported-cache and dependency identities remained unchanged.

- P50 58.764ms; P95 96.160ms; P99 130.222ms; maximum 319.280 ms. The 10/15/30ms latency gates fail.
- Measured step sum 365368920 us; sample wall 411324936 us; speed 1.4587007679x. Process wall 487.309 s includes preparation/startup/prefix/output overhead.
- Coverage 29/31: upgrade and effective ward visit remain missing. The same fixed upgrade command rejects at tick 1633 with `maintenance_unavailable` / `缺少真实合法维修操作位`. Raw `complete=false`, exit 1 are preserved. This is not an accepted repeat.
- Complete final World/RNG/ordered-events SHA256: `41928476a199dbf3e35b3ff74cd54a52fd0801feb92c5b1d1a5d6fe035258a68`.

[Full ordinary raw archive](evidence/2026-11-12-cloud-profile-recovery/full-plain.zip) is 851352 bytes, SHA256 `0aaf766947d28dc8c5c7cade528b24e6ebc1241293c624245b71fbf7cb09b3ba`, with 21 raw members plus its internal manifest. The [external member manifest](evidence/2026-11-12-cloud-profile-recovery/full-plain.members.json) permits independent size/hash validation. The archive includes the complete input/final binaries, every step row, unmodified result/observer output, process/command/exit records, controller, source and runtime identities. It was locally CRC/member-verified before publication. The root-stage long window was not started while this checkpoint was pending.

This is a separately identified run, not recovery of the missing earlier raw files. No code changed between the timing observations, and neither the difference from the earlier interrupted batch nor a cross-machine comparison is claimed as an optimization gain. The causal stage attribution remains pending the paired root-stage window.

## Complete paired root-stage attribution

The root-stage window completed all 7000 production steps after the plain checkpoint had been downloaded and verified from GitHub. Its complete World/RNG/ordered-event binary, entire business observer and failure status match plain exactly. All 6000 measured steps are again the same dense interval. The profiler retained every stage record, matching its measured tick and elapsed value; source/cache identity, original method body and zero partition error all passed. Linux still reports requested=app, applied=false, reason=platform_default.

| Disjoint root stage | Measured total | Share of complete profiled step |
| --- | ---: | ---: |
| movement.space |130.506020s|35.45%|
| clinic.dispatch |48.988236s|13.31%|
| dispatch.waiting |37.636165s|10.22%|
| sample.experience |36.755726s|9.98%|
| dispatch.environment |31.434434s|8.54%|

Complete profiled step time is 368.175157 s: disjoint stages 366.866874 s, measured observer handlers 0.837732 s (0.228%) and residual 0.470551 s (0.128%). Whole measured and dense-stage statistics are identical because all 6000 samples meet density. Never add nested/inclusive times to these disjoint spans.

Movement is the largest stage in 4786/6000 steps and 28 of the slowest 60, but tail latency is not exclusively movement. The maximum step, tick 1634 at 308.111 ms, is principally environment/waiting dispatch; tick 2884 takes 289.788 ms, including 256.752 ms waiting dispatch. Several 240–274 ms slow steps are movement-led. These observations support investigating `Simulation.step_nonblocking -> HospitalSpace.advance -> HospitalMovement.advance` next; they do not prove collision or any particular movement submethod is responsible.

Profile P95/P99/max are 92.355/124.496/308.111 ms, sample wall 412.130669 s, speed 1.4558489458x, process wall 492.845 s. Paired total step time differs from plain by about +0.77%. This single-pair difference is not a pure observer-overhead estimate or an optimization gain. The 31 coverage gates, upgrade rejection, missing effective visit and failed 10/15/30 ms latency gates remain unchanged. No three-repeat acceptance is established.

[Full-stage raw archive](evidence/2026-11-12-cloud-profile-recovery/full-stages.zip) is 6664255 bytes, SHA256 `1c83d3d5284dd7fc26b04fb88e1bdab8f99a4ae8ece7e605666e7ab77843285d`, retaining 23 raw members plus its manifest. [Member manifest](evidence/2026-11-12-cloud-profile-recovery/full-stages.members.json) and [derived root attribution](evidence/2026-11-12-cloud-profile-recovery/root-attribution.json) accompany the original complete files. ZIP CRC, each member size/SHA and final-state identity were independently checked before publication. No further profile or gameplay edit was made in this batch.
