# Same-instance door reach optimization: implementation and selected validation

## Rule and handoff before implementation

No gameplay rule changes. `movement_doors` must conservatively include the complete actor and every member's required door reach. Same actor ID does not imply the same dictionary or proxy body. Live static-door and reservation candidate queries, original floor-door ordering, exact permissions and full physical release remain unchanged.

The only intended production change skips recalculating the member clearance when `is_same(world.facts.actors[id], actor)` proves the initial actor reach already covers that exact dictionary. The handoff is candidate-door discovery, before existing acquisition/ownership checks.

Evidence: the fixed 48-pair real empty-door/same-instance API microbenchmark showed a local gain; it does not establish whole-step gain or nonempty/proxy correctness. Rules: `docs/specs/26-11/2026-11-05-convoy-following.md` and `tests/acceptance/convoy_door_lifecycle.md`.

## Selected validation and reasons

- New door reach query boundary: same-instance, empty members, different member, same-ID different dictionary with a larger real world member, genuine nonempty ordered doors, cold/warm query agreement and unchanged World. Query boundaries do not claim physical crossing.
- `ordinary_door_passage`: its four actual passage/body/remodel/expanded-owner cases.
- `door_passage_static_fit`: existing cold/warm, exact proxy, live ownership and cross-world/static-change checks.
- `convoy_door_lifecycle`: only `mixed_large_reverse`, `permissions`, `authorized_regroup_tail`, covering mixed bodies, outsider exclusion and real trailing ownership.

No full performance window, microbenchmark repeat or full movement suite is included. Runtime/native/imported assets are reused by identity. The selected results follow.

## Implemented result

Production diff: `hospital_space.gd` adds only the exact-instance member guard (3 insertions / 1 replaced line). Final SHA256: `97aea6add01864da51d73db7853c7a242b3ceb61505ac1bd8620f26c9fb9e69b`.

All selected executions exited 0:

| Selection | Process wall seconds | Result |
|---|---:|---|
| New query boundary, final body-cache correction | 4.013783 | passed |
| Ordinary passage, four cases | 3.717094 | passed |
| Static fit | 3.216992 | passed |
| Convoy: mixed_large_reverse, permissions, authorized_regroup_tail | 4.319503 | passed |

The new query test constructs two real doors using production commands. Exact candidate order is `door_00000001`, `door_00000003`. A real indexed boundary query at `(42,74)` size `(0.25,0.25)` has no door for the small proxy alone, but includes `door_00000001` when the larger same-ID world member participates. Both `_convoy_size` and `_convoy_body` proxies, mixed-member maximum in both orders, empty members, exact-instance members, independently cold and warm calls, and unchanged World are checked. A production-acquired expanded reservation is present in both index and live reservation sources; its candidate appears once, in original order, with exact `door_candidates` increment and unchanged owner/world. Independent proof queries use a separate space so they do not warm the cold subject.

The initial query-only revision passed in 4.213453 s; explicitly requested extra boundaries passed in 4.113622 s; the first cold-evidence isolation revision reran only this affected query in 4.215947 s. A remaining body-cache warmup was then corrected as documented below. All three raw runs are retained, not silently replaced. Unchanged ordinary/static-fit/convoy selections ran once.

`git diff --check` passed. Existing UID files are byte-preserved. No native rebuild/import, new full performance window, repeated microbenchmark, full regression, commit or push was performed. Local API microbenchmark gain is not a full-step gain or performance acceptance result.

Raw evidence below preserves original process commands/exits/times, test inputs/results/trace, exact test sources, identities and member hashes. The initial archive is retained unchanged alongside the final correction.

## Final independent-review correction

At 2026-11-12T09:47:18.638517+00:00, independent review identified one remaining proof-side `space.clearance(actor)` that warmed the subject body cache. It now uses `evidence_space.clearance(actor)`. Only the new query test reran; it passed (exit 0) in 4.0137827819999075 process seconds. Previous `selected.zip` and all prior outputs remain immutable. This supersedes the earlier cold-isolation claim for the reservation-union subcase. The reservation test proves **both-source union ordering/dedup/count**, not reservation-only inclusion. Production source and other passed selections are unchanged.

## Durable evidence and limits

- [Selected execution archive](evidence/2026-11-12-door-clearance-optimization/selected.zip): 247359 bytes, 42 raw members plus [manifest](evidence/2026-11-12-door-clearance-optimization/selected.members.json), SHA256 `ea805f13a1e867bca9bdf64ff27f6b4512bb3f23a2f471bdd2692456a57f02b2`.
- [Final cold-body-cache correction](evidence/2026-11-12-door-clearance-optimization/cold-correction.zip): 11881 bytes, 7 raw members plus [manifest](evidence/2026-11-12-door-clearance-optimization/cold-correction.members.json), SHA256 `afbf5b3fbfe3e63d5a593481af3013a7f07ce363a1cedee1855af278b6ffcb3e`.

Independent CRC and all member lengths/hashes pass for both archives. The correction archive's final test source exactly matches the committed test. Independent source review found no changed body, query, ownership or ordering contract: `clearance` is read-only except its body-cache fill, already performed by the initial same-instance calculation. 663 pre-existing UID files retain their bytes; generated untracked sidecars are not part of the commit.

The earlier microbenchmark's raw backup was independently downloaded from commit `73051a845d21cc86ccd428c95287ed6197b1dd2c` and all 18 raw members verified. All three recent full diagnostic windows and older raw runs remain retained. This commit is not a new performance acceptance attempt; the known full-window latency and two missing coverage gates remain unresolved. No GUI/GPU/audio or release acceptance is claimed.
