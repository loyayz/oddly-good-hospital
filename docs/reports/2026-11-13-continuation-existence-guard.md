# Release continuation existence guard

Base: ee71f136caccd8b5aee5af493ebd61bd00b0c8db. Candidate changes only the release eligibility check from building a copied continuation and testing emptiness to a read-only existence scan. Decision: limited retention under the user's explicit policy after independent final review; not an overall acceleration claim.

## Semantics

Every original owner check and actor-location short circuit remains in order. The helper finds the first occurrence of the requested connector, not the first arbitrary connector. Existing waypoint continuation wins even when empty. Otherwise the path cursor uses the original Array.slice negative-index/clamp semantics. No cross-owner, cross-call or cross-tick cache is introduced. All three publication callsites and the original _continuation deep-copy function remain byte-identical; publication re-queries current movement state, rather than reusing a guard result. The separate eager-default-slice behavior in publication is unchanged.

## Evidence

- Full original diagnostic: 1266 guard calls, 128611 outer tail elements copied then discarded, 238244 microseconds inside the original function over all 7000 steps. 1195 later boarding calls were unchanged, only71 published. Elements are not bytes or recursive-copy volume. Instrumented timing is not an uninstrumented saving prediction.
- Independent warm query micro: 243 actual snapshot queries and25 untimed synthetic cursor/waypoint/connector semantics cases passed, facts and input reference identities unchanged. Bounded queued hit/path median132.9065→0.8335us; other hit/path88.7635→0.979us; other miss/path4.6875→3.857us. These are reconstructed snapshot queries, not captured live release executions, and not population-weighted. Actual waypoint queries were absent.
- Real SPACE54 and SPACE55 _group subset capture: four fixtures passed, six independently restored original/candidate complete release results and worlds matched. Three cases actually published and checked outer-array and segment-Dictionary non-aliasing; three unchanged-call cases published nothing. Signals were empty on both sides. This is not a complete Simulation.step event-flow proof or recursive alias test. Deep nested-copy semantics additionally rely on the unchanged publication implementation. All cases single/path/success; waypoint and multi-owner failure remain explicit actual-coverage gaps. Captured hot-state outcome is not asserted equal to cold replay outcome.
- Six fresh uninstrumented rounds: O1,C1,C2,O2,O3,C3. Each full input has1000prefix+6000measured steps,128patients+32staff initially,5439 fixed dense samples at present>=144. Comprehensive business coverage passes, input/source/engine/native postflight unchanged, final World/RNG/ordered-events SHA256 is8baf906509e5d0bfd5266adcfe5a3455fb274cc3aae00e786a6996b46d15dbbb in every round.

## Full measurements

| Group/round | Dense P95 ms | Dense P99 ms | Dense max ms |6000 measured-step sum s|
|---|---:|---:|---:|---:|
|O1|119.389|152.038|429.364|378.970358|
|C1|121.824|144.583|457.456|378.827654|
|C2|124.247|150.604|428.217|381.817918|
|O2|119.032|144.706|442.751|373.496131|
|O3|122.577|148.134|461.375|381.545767|
|C3|120.778|144.667|422.620|374.072166|

Candidate relative to group medians: P95+2.040%, P99−2.340%, max−3.283%, dense mean+0.386%, measured6000-step sum−0.038%. The sum excludes1000prefix and logging/loop wall time. Adjacent-pair sum differences are mixed, not a consistent speedup. Absolute P95/P99/max performance targets remain unmet.

## Interpretation and limits

The local copying removal is measurable and functionally supported. Whole-workload results are mixed and the measured total change is negligible; do not claim overall acceleration. Under the user's explicit local-reduction/no-large-overall-degradation policy, this is retained after independent final review and actual member-by-member Library readback of all six raw rounds, not an overall performance-success milestone.

ABBAAB is not randomized. Historical unguarded engine terminal states remain unknown; new runs were serialized under the shared lock with unchanged conditions, per the user's authorization to rerun. Environment variation and instrumentation effects cannot be ruled out or causally assigned. This incremental comparison uses ee71 as control and does not resolve the earlier door-query/basis changes' own mixed overall measurements or their pending independent recheck.

Keep original and candidate three raw rounds separately, with identities and actual Library member-by-member readback. Preserve failed/partial earlier boundary records rather than overwriting them. Do not lower workload, collision semantics, coverage or thresholds to improve these numbers.
