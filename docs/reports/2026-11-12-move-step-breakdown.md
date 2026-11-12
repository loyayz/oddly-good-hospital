# Bounded move-step breakdown after exact-state restore

This diagnostic asks where frequent `_move_step` calls spend time in eight actual steps from the archived full terminal state. It does not replay the historical tick 6240 dispatch tail or reattribute the full 6000-step profile. Source commit is `a8f1a09f44163a35c875b74e2f75f69d210fed16`, including the separately validated same-instance door-reach guard.

## Fixed scope and validity

New plain and observed runs each execute exactly eight 0.1 s steps, starting from complete archived World/RNG/event state SHA256 `41928476a199dbf3e35b3ff74cd54a52fd0801feb92c5b1d1a5d6fe035258a68`. No requests, budgets, retry timing, tickets, workload or completion rule changed. The old pre-optimization plain8 control was not substituted. The first restored step and following seven are reported separately. No extra steps, complete window or microbenchmark was run.

Only selected same-signature wrappers inside owner-thread, active-step `_move_step` calls are measured. Initialization, other service calls and after-step calls pass through without reading timers. The two original structural-check statements (acquire structural clearance, then sweep reason) remain unchanged inside removable span markers. Original method bodies and driver recover byte-for-byte after inverse transform. Nested inclusive time is not added twice; exclusive contributions partition the parent, while measured handler cost is reported separately. Dispatch/timer overhead is not fully removed.

Both processes exit 0 and complete all eight steps. Complete final World/RNG/ordered-event bytes and business results agree, SHA256 `6ecee78b194a7925938549383dc9fb87f222a3843d901d790fe83ac7aeaeb93d`. All eight tick/elapsed/stack/scope/partition checks pass, with nonnegative exclusive spans. Process walls are plain 5.316617 s and observed 5.323327 s; their difference is not a calibrated overhead or optimization measurement. The isolated sources were restored; production files were unchanged.

## Observed decomposition

Times below are microseconds. Child columns use **exclusive** contributions; structural inclusive time also contains nested `movement_doors` calls.

| Component | First restored step calls | First exclusive us | Following 7 calls | Following 7 exclusive us |
|---|---:|---:|---:|---:|
| structural-check | 124 | 91287 | 868 | 443616 |
| movement_doors | 1002 | 9655 | 5190 | 61207 |
| _movement_contacts | 138 | 1948 | 966 | 17751 |
| _unit_sweeps | 138 | 1342 | 966 | 10329 |
| _reserve_doors | 138 | 379 | 966 | 2857 |
| _mark_door_use | 93 | 120 | 683 | 696 |
| Parent uncovered remainder | 138 | 5496 | 966 | 39403 |

Parent `_move_step` inclusive totals are 110227 us for 138 calls, then 575859 us for 966 calls. Structural-check inclusive totals are 99079 us, then 490437 us. Measured handler totals are 5497 and 37343 us; outside-parent plus gaps totals are 191354 and 545719 us. The cold step has 45 blocked and 93 unblocked parent outcomes; the following seven have 283 blocked and 683 unblocked. No `_move_convoy` call was observed, so no convoy cost conclusion follows.

The principal covered cost **in this sample** is structural checking, not contact handling. Parent uncovered remainder includes inline calculations, index updates, notifications, control flow and unremoved observer overhead; it is not all commit work.

## Limits and next question

A restored World does not restore runtime navigation caches. The following seven steps are not evidence that every cache is warm. Parent time averages about 82.3 ms per step here, versus about 11.3 ms in the earlier full narrow window; these different workload moments and cache histories cannot identify a causal performance change.

Source inspection shows `structural_clearance` borrows existing cached graph geometry, or constructs a new `RouteClearance` when unavailable. That construction resolves body-specific door fits, which can call `movement_doors` under this span. The current timer combines clearance acquisition and sweep predicates, so it cannot separate their costs, prove the number of cache misses/builds, or establish which behavior dominated the full original window. No new cache optimization is justified yet.

Separately, offline decoding of the eight previously archived door-call Worlds (ticks 7633-7640) found one pending route request, `patient_00000316`, sequence 3860. Existing counters show one actual failed dispatch by tick 7637, with scans and dispatches both 1, plus one route and connector-topology build increment. This is not evidence of excessive ready-queue scans. Those snapshots occur before a door call, not uniformly before step dispatch; runtime heaps were not serialized. The proposed blind terminal route-dispatch continuation was therefore canceled. It cannot explain the historical tick 6240 tail.

## Raw retention

[Raw paired diagnostic](evidence/2026-11-12-move-step-breakdown/batch.zip): 1356780 bytes, SHA256 `6971eb5321715c079487b9cc26ffe6856018c8027656de24885e7d2e6f2de047`, 35 raw members plus [manifest](evidence/2026-11-12-move-step-breakdown/batch.members.json). It includes exact input/final states, per-step data, source transforms, observer/controller versions, runtime identities, before/after host snapshots, logs and comparison/restoration checks. Independent CRC and every member size/hash pass.

All earlier raw files remain retained. This bounded observation does not replace any of the three recent complete diagnostic windows or count toward fixed-workload performance acceptance. No original latency or coverage gate is newly passed.
