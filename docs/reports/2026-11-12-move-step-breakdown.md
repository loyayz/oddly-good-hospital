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

## Follow-up: actual acquisition and sweep split

The next fixed observation reused the sealed current-code plain8 only after checking every gameplay/content/native, project and driver byte plus runtime identities. Documentation-only HEAD changes did not alter that implementation. Exactly one new observer8 ran, with no added steps. It splits the two original structural statements and counts only the actually taken cached-lookup return branch and fallback-constructor branch. Classification does not repeat any key, source or route query. Step/thread/active-parent/span gating, signatures and byte-exact inverse transforms passed.

| Metric | First restored step | Following seven |
|---|---:|---:|
| Parent calls | 138 | 966 |
| Parent inclusive ms | 142.655 | 563.958 |
| Acquisition calls | 124 | 868 |
| Acquisition inclusive ms | 125.707 | 477.031 |
| Sweep ms | 1.032 | 7.174 |
| Cache hit | 70 | 604 |
| Entry-absent miss | 54 | 264 |
| Static-source mismatch miss | 0 | 0 |
| Actual fallback constructors | 54 | 264 |
| Parent uncovered ms | 9.336 | 38.947 |
| Observer handler ms | 6.493 | 39.583 |

Hits plus misses equal acquisition calls in every step; actual fallback counts equal misses, and acquisition/sweep counts match. Complete World/RNG/ordered events, business results and all eight tick/partition checks match the plain control. The final SHA remains `6ecee78b194a7925938549383dc9fb87f222a3843d901d790fe83ac7aeaeb93d`. The observer exited 0 after 6.022614 s, was reaped, and all modified isolated sources were restored.

This sample now establishes that acquisition, not the sweep predicates, dominates this structural check, and that the following seven steps still execute 264 fallback constructors. It does **not** assign all acquisition time to those constructors: hit lookup and missing-graph construction costs are still combined. Nested door calls are already included in acquisition time. These restored-state observations do not reattribute the full original window and do not justify a new cache by themselves.

Read-only source review confirms the fallback result is not retained as a graph entry. Repeated construction is therefore possible when no matching graph is resident. Any later optimization must preserve the full traversal-envelope key (including proxy shapes and posture), weak World/source ownership and current static-source validation, as well as the shared 134217728-byte cache budget and eviction accounting. Current reservation permissions are separate from static fit and must remain live; a cache hit is not a passage authorization.

[Acquisition/sweep raw observation](evidence/2026-11-12-move-step-breakdown/structural-acquisition.zip): 1401033 bytes, SHA256 `2d97291181f0a772f44fa6100fd25629bf0a12a9ebbef72e474599ff0be2baee`, 38 raw members plus [manifest](evidence/2026-11-12-move-step-breakdown/structural-acquisition.members.json). It retains the reused plain evidence and durable receipt, exact tool/source transforms, all branch counts and timings, input/final states, host snapshots, process log, identity, comparison and restoration proofs. Independent CRC and every member size/hash pass. All prior archives remain unchanged; no production code or memory-budget change was made in this follow-up.


## Follow-up: actual fallback cost and repeated missing-key corpus

One further eight-step observer reused the sealed current-code plain8. Complete final World/RNG/ordered-event bytes, business results and all tick/partition checks match that control; final SHA256 remains `6ecee78b194a7925938549383dc9fb87f222a3843d901d790fe83ac7aeaeb93d`. Production gameplay remains `a8f1a09f44163a35c875b74e2f75f69d210fed16`; isolated observer changes were restored. No additional full window or optimization was run.

| Observed branch/span | First restored step calls / ms | Following seven calls / ms |
|---|---:|---:|
| Cache hit | 70 / 1.253 | 604 / 11.217 |
| Entry-absent lookup | 54 / 10.933 | 264 / 4.023 |
| Actual fallback expression | 54 / 103.932 | 264 / 478.290 |
| Sweep | 124 / 1.022 | 868 / 7.481 |

The fallback expression includes evaluation of its `floor_source` argument and nested door work; these are inclusive costs and must not be counted twice. Corpus collection consumed 609.700 ms on the first step only. Measured handler costs are deducted from the reported spans, but collection-induced cache perturbation is not removed. These observations are not whole-window optimization gains or a calibrated comparison against earlier observed runs.

Only three actual missing keys were encountered: unit-envelope keys on floors 2, 3 and 4, repeated 38, 112 and 168 times respectively. Each key's static-source version stayed unchanged. The first actual pre-call full World, actor alias, arguments, source identity and returned summary were sealed for each of these three keys. The capture limit was eight, but no extra calls or states were manufactured to fill it.

Repeated fallback construction is therefore real in this bounded sample. This establishes neither a safe cache design nor a whole-window benefit; no cache optimization or memory-budget change is made here.

[Structural fallback/corpus raw observation](evidence/2026-11-12-move-step-breakdown/structural-corpus.zip): 2324765 bytes, SHA256 `573b72a071de859b3ae20fea1bfe8d043bceaa365249f0846ee5d983637fbe3f`, 39 raw members plus `MEMBERS.json` and the external [member manifest](evidence/2026-11-12-move-step-breakdown/structural-corpus.members.json). Independent CRC, exact member set, all member sizes and SHA256 checks pass. Earlier raw archives and the three complete diagnostic windows remain retained; no latency or coverage gate is newly passed.
