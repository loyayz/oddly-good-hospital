# Journey path scan: avoid unused slice allocation

Baseline: `ec8d4f315cdfa89c95b61ec4b0c87de7ebbaa044`, exact runtime source corresponding to the frozen 160-person benchmark. The sole runtime change is `HospitalTransit.journey`: scan the original array rather than eagerly creating a path slice inside a dictionary default expression. No cache, scheduling, collision, business-load or threshold changes.

## Correctness

Two independent read-only reviews found no valid-world semantic blocker. The dedicated runner passed 12,792 combinations covering continuation precedence (including empty), absent waypoint, negative and out-of-range cursor, unchanged input, and original returned segment dictionary identity.

Three full runs used the same `mixed160-clinical-ops-v1` input, 1,000 prefix and 6,000 sampled steps, 160 initial real actors, unchanged coverage gates, Godot 4.7.2 Linux, four worker tasks, platform-default threading. Each passed coverage and ended with identical complete world, RNG and ordered events SHA256:
`8baf906509e5d0bfd5266adcfe5a3455fb274cc3aae00e786a6996b46d15dbbb`.

Input SHA256: `6c10de8a81e9e4574512e5ebe9e0dc1a73649abf75437eec512a697aa63aa0d9`.
Runtime file SHA256: `f547e1f334fd4065134bfc4bba64718ea5a4ba74d92d19549789a956e40d7edc`.

## Results

| Run | P95 ms | P99 ms | Maximum ms | Total step seconds |
|---|---:|---:|---:|---:|
| Control 1 |118.871|145.804|1359.418|395.715|
| Control 2 |122.408|148.838|1445.729|390.939|
| Control 3 |125.368|153.499|1437.559|397.355|
| Candidate 1 |118.279|143.829|1477.406|380.365|
| Candidate 2 |122.878|155.497|1507.960|399.463|
| Candidate 3 |119.470|149.876|1406.580|383.706|

The implementation deterministically removes unnecessary path allocation. Whole-run measurements are mixed within cloud variability; do not claim a significant overall P95 improvement. Retained under the policy that demonstrably reduced local work without material overall regression is worthwhile. Absolute CPU targets remain **failed**. Management-operation spikes are a separate issue, not fixed by this change.

All three complete original candidate run directories were independently archived and read back, validating every member's bytes and SHA256. Existing control archives were retained untouched. This measures Simulation.step only, not renderer or application persistence lifecycle.
