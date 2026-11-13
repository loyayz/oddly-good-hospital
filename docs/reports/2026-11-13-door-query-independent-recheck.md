# Independent door-query whole-workload recheck

## Purpose and identity

This is a fresh six-round ABABAB comparison of control3ffb9c83b77588cf5944dbae8cd5e285bcdf4fdb versus candidateee71f136caccd8b5aee5af493ebd61bd00b0c8db. Only the door-query local-reference change separates production sources. It does not mix previous door measurements, continuation0f56fda1 results, or instrumentation.

Every round ran the same complete128patient+32staff input,1000prefix+6000measured steps and fixed5439 dense samples with population>=144. Business coverage passed, final World/RNG/ordered-events hash8baf906509e5d0bfd5266adcfe5a3455fb274cc3aae00e786a6996b46d15dbbb matched in every run. Controller postflight source/engine/native/input identities held.

## Quiet protocol

One shared cross-exec lock covered each engine lifecycle. No coordinated second engine, compiler or diagnostic ran. Static contacts preparation finished and stopped IO. Each round's archive compression and actual Library member-by-member readback finished before starting the next engine. This removes the known overlap with our backup work; it does not prove a globally quiet host. Historical unguarded engine terminal states remain unknown because a complete host process inventory is unavailable. The user authorized reruns under this disclosed limitation.

## New results only

|Round|Dense P95 ms|Dense P99 ms|Dense max ms|6000step sum s|
|---|---:|---:|---:|---:|
|O1|121.919|151.345|538.618|379.689158|
|C1|121.854|146.185|464.774|386.800966|
|O2|121.094|145.002|446.479|374.243125|
|C2|119.342|150.374|443.997|374.427783|
|O3|116.729|141.718|454.169|373.679164|
|C3|116.913|138.764|426.826|367.762354|

Adjacent candidate-control measured-step sum changes: +7.111808s(+1.8731%),+0.184658s(+0.0493%),−5.916810s(−1.5834%). Direction is mixed. Group median changes: P95−1.4468%, P99+0.8159%, max−2.2397%, dense mean−0.0393%,6000step sum+0.0493%. The sum excludes1000prefix and observation/logging wall time. Absolute latency targets remain unmet.

## Interpretation

The earlier three adjacent pairs all had higher candidate cumulative time, which justified this independent recheck. The new test does not reproduce that consistent direction: the second pair is almost level and the third reverses. Do not pool the campaigns or treat these values as evidence of certain overall acceleration, nor use a near-zero median as proof of identical performance. ABABAB is interleaved but not randomized; environment variation and unknown historical processes remain confounders.

Given the previously independently validated local query reduction and functional equivalence, the new evidence does not establish a reason to revert the simple change under the user's explicit local-reduction/no-large-overall-degradation policy. This is a qualified retention recommendation, not an overall performance milestone. Any later decision to revert must use a new selective commit and preserve subsequent continuation changes and all historical evidence; never reset or force-push history.
