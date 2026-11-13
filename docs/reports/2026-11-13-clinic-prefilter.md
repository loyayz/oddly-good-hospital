# Suspended outpatient candidate prefilter

Single runtime change: apply existing actual eligibility predicates before expensive structural reachability enumeration in `_dispatch_suspended`. Keep structural enumeration, candidate order, and all final commit-time checks. No cross-tick cache, workload reduction, collision changes, renderer changes, or relaxed acceptance limits.

Base for isolated comparison: ec8d4f315cdfa89c95b61ec4b0c87de7ebbaa044. Integration retains the separately reviewed journey change in parent 2fed5b429ad6d92bf2c215831d0818290dc17173. The isolated candidate runs are not a measured combined-build benchmark.

## Correctness and review
Independent source and evidence review found no substantive adoption blocker. Complete final World/RNG/ordered events match the original full-load reference in all three new rounds (SHA256 8baf906509e5d0bfd5266adcfe5a3455fb274cc3aae00e786a6996b46d15dbbb). Each has 6000 measured steps after 1000 prefix steps and 5439 dense samples; coverage and identity checks passed.

Functional evidence includes actual successful continuation preparation, later eligible staff, explicitly injected one-shot reservation failure with next-tick retry, preparation expiry, physical operator-place occupancy, and real water-need completion followed by original session reinstatement. In the final strict test, 329 real steps lead to reinstatement at tick1851: suspension/preparation/resume ticket removed, ownership restored, original attempt/supply issue unchanged, remaining work539→538 through one actual work tick. Original/candidate complete outputs match. This is continuation of treatment, not completed treatment.

Limits: nine rejection variants do not individually isolate every predicate. Static full-path disconnection and migrated legacy bed commitments remain untested; injected reserve failure is not a naturally observed race. Public-seat definitions are disjoint from current clinical equipment, not a guarantee for future content.

## Measurement and adoption rationale
New guarded rounds (P95/P99/max milliseconds):
- 122.791 /153.129 /436.242
- 125.202 /152.013 /430.977
- 119.312 /142.850 /469.464
Medians:122.791 /152.013 /436.242; total Simulation.step time median382.664726 seconds.

The previous isolated reference medians were P95 122.408ms/P99 148.838ms. Whole-run improvement is not established. Diagnostics identify five expensive suspended-dispatch scans and prove eligibility exclusion before route work; this local reduction supports retention under the agreed strategy when overall performance does not materially regress. Absolute CPU targets remain failed.

Important limitation: three earlier r2 attempts are invalid because of overlap/execution uncertainty and were excluded. New runs use one cooperative cross-session lock, but an older unguarded process could not be conclusively accounted for; user authorized remeasurement. Therefore numeric gains are not presented as certain causal improvements. Every new raw round was separately persisted and actually read back member-by-member; the invalid attempts remain archived separately.
