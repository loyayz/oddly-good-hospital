# Isolated structural-body cache candidate: fixed real-corpus API comparison

This is an isolated candidate, not a production change. Production remains `a8f1a09f44163a35c875b74e2f75f69d210fed16`. The three inputs are the actual missing-envelope calls captured in the [previous diagnostic](2026-11-12-move-step-breakdown.md), not synthetic optimization-friendly replacements. Their raw corpus backup was downloaded and verified from commit `07ebd1daa18d307168c3e6a0445ed64103684d04` before this batch.

## Candidate and fixed plan

The candidate preserves existing graph hits and only retains no-member/no-offset fallback `RouteClearance` bodies. It does not build a navigation graph. The key includes the full body dictionary, `_convoy_size` presence and value, posture and floor. Every acquisition still validates the weak World/source record and complete canonical static source. Dynamic occupancy is deliberately absent from retained static geometry, as with existing resident graph geometry; current permissions are not cached.

Body records share the original 134217728-byte allowance and recency clock with graphs. Both trim paths account for them, and graph/body eviction uses joint LRU order. A conservative charge covers all held containers, including repeated counts of borrowed floor/source arrays; floor eviction must not turn retained bodies into uncharged ownership. This is an eviction allowance, not measured RAM. Oversized results remain complete for the synchronous caller but are not retained.

Before timing, the plan was fixed to three actual inputs, six AB/BA alternating pairs each, one fresh cold call and 500 warm calls per arm: 18 pairs, 36 cold calls, 18000 total warm calls. No pairs were added after results. Both arms call the complete structural-clearance API and perform the same lightweight warm-return checks. Baseline fallback and candidate build/hit counters are retained; reported timings include those small diagnostic counters, not a claim of zero observer cost.

Godot parsing and three preliminary equivalence checks passed. They compare complete canonical static fields, all 9216 integer positions per input, door fit and five explicitly labeled fractional position/sweep probes. The probes are verification inputs, not claimed as captured live sweeps. World state is unchanged, no graph is built and retained accounting stays within budget. Preparation attempt 01 failed before engine launch because the Python process-output directory already existed; its error/controller are preserved. Only that setup path was corrected, and attempt 02 passed with the candidate unchanged.

## Result and tradeoff

| Fixed API work | Baseline | Candidate |
|---|---:|---:|
| 9000 warm calls per arm, total | 13.739686 s | 0.141903 s |
| 18 independent cold calls per arm, total | 251.191 ms | 429.887 ms |

The candidate is faster in all 18 warm pairs, but first construction/accounting/retention is more expensive. Each baseline arm performs 501 fallback constructions; each candidate arm performs one construction and 500 resident hits. No eviction occurs in these three independently prepared cases. Body allowance is approximately 6.21-6.23 MB per case and total allowance approximately 8.51-8.54 MB; neither number is a measured process allocation.

All paired canonical-return, World-invariance and budget checks pass. The candidate is not yet validated for proxy/cross-World invalidation, mixed graph/body LRU pressure, live permissions or actual movement handoffs. This result only covers repeated calls for these three missing envelopes; it cannot be converted to full-step or whole-window gains, nor does it clear any original performance/coverage gate. No production cache, workload or budget was changed.

## Raw evidence and next boundary

[Raw fixed batch](evidence/2026-11-12-structural-cache-micro/micro.zip): 1699759 bytes, SHA256 `dfd0e23ec68fed2955f3e360eda58ba6976dca60040c4b92a54c5fb61dabdf6c`, 44 raw members plus [manifest](evidence/2026-11-12-structural-cache-micro/micro.members.json). [Derived per-pair summary](evidence/2026-11-12-structural-cache-micro/summary.json) retains cold and warm values separately. Independent CRC, exact member set, every size and SHA pass. The package preserves the failed setup attempt, successful precheck, all original pair timings, source identities and candidate files, input corpus, process logs and host information. All prior raw files remain retained.

Before any production use, selected tests must cover body/proxy/posture keys, static-source and same-revision cross-World changes, dead-World lifetime, separate source/floor/body/graph eviction, budget pressure and complete over-budget returns, live reservation permission, plus representative actual local movement. Total-charge reporters/assertions must include the new category. An old test requiring a fresh geometry object for every call is not a gameplay rule; its dynamic revalidation and actual movement outcomes must remain tested instead.
