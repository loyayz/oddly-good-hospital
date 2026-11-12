# Cloud profiling interruption and recovery boundary

This note records an execution-environment failure, not a gameplay or performance fix. Gameplay sources remain those of `e232c42389e614cf13d305c4376d59892c4aa0c3`; the published starting checkout was `75e63992525435834813aaa99f2e18298d1cd5f2`.

## What was actually observed before the interruption

The root-stage diagnostic used the original mixed input SHA256 `75f5e1d922f39f12382c0ceb74806bda0293251189f68a1ac158842f65fa78ca`, the qualified Linux Godot 4.7.2/native runtime, 0.1s steps, four environment tasks and `OMP_NUM_THREADS=1`. It requested `app` policy; Linux reported `applied=false`, `reason=platform_default`. This is not evidence of equivalent Windows thread priority.

The initial 0+2 ordinary/root-only qualification pair passed complete World/RNG/ordered-event equality, complete business-observer equality, unchanged errors/status, exact original method-body preservation, complete stage records, zero partition error and no nested timing. The complete state hash read from that result was `21aff2546935022312333b67605680c491292575aaa845b07733db993a415a51`.

One ordinary full window then executed all 1000 prefix + 6000 measured steps. Its result and process record were read before the environment failure:

- 7000 completed production steps; all 6000 measured samples in the >=144-present dense interval, ticks1634-7633. Present population minimum/median/maximum: 164/165/170.
- P50 91.225ms; P95 171.332ms; P99 284.836ms; maximum 5914.215ms. The large maximum is retained, not discarded as an outlier.
- Sum of measured step durations 607465142us; sample wall time 682490648us; simulated/wall speed 0.8791329255x. Whole process wall time 801.41464683s.
- Business coverage 29/31. Upgrade and effective ward visit remained uncovered. The measured upgrade command was rejected at tick1633 with `maintenance_unavailable` / `缺少真实合法维修操作位`.
- `all_completed_steps=7000`, but `complete=false` and process exit1 because the business coverage contract failed. Execution completion is not acceptance success. The latency and speed gates also failed.
- The reported final binary SHA256 was `41928476a199dbf3e35b3ff74cd54a52fd0801feb92c5b1d1a5d6fe035258a68`.

These are retained readings from tool results, NOT a reconstructed original result file. The original files and final binary are currently unavailable, so this note is not a replacement evidence archive or a qualified repeat. No cloud-versus-Windows performance gain is inferred.

## What failed and what is unknown

The single root-stage full window ran only after the ordinary process exited. Its last confirmed progress was index4500 / tick5134 with no reported engine/script error. During the wait, the tool reported `executor key changed during session recovery`.

Reattachment to the same listed cloud environment succeeded, but the filesystem had reverted to an older base tree. Independent checks found the new checkout, runtime-build directory and both full-window result directories absent. The new environment contained no Godot process. The full-stage window's final outcome, full stage totals, final state and end-of-run restoration check therefore cannot be verified. No dominant CPU stage or completed plain/profile equivalence is claimed. The missing run was not silently repeated or represented as successful.

## Recovery and remaining work

At the 2026-11-12 07:52 UTC recovery check, the GitHub branch still pointed to `75e63992525435834813aaa99f2e18298d1cd5f2`. A fresh cloud-only checkout of that exact commit succeeded. The three previously published cloud evidence archives were rechecked against their recorded SHA256 and ZIP CRC: preparation34 members, one-step29 members and six-step27 members. Thus the already-published fixes, source, dependency recipes and bounded transport evidence remain recoverable. There was no unpublished gameplay change in this interrupted profiling batch.

The native binary, engine/dependency workspace, generated caches and this profiling batch's unpublished raw results were not recovered. Runtime binaries must be rebuilt or restored from a verified copy and requalified before another measurement. No Windows execution is used for recovery.

Recovery proceeds in new directories without overwriting the retained base tree. A subsequent measurement is a separately identified run, not continuation of a missing process. Completed raw results must be durably checkpointed before starting the next expensive measurement. Known business failures and acceptance gates remain unchanged; no workload, random stream, actor, command timing or rule is relaxed to obtain coverage.
