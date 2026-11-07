# Final limited CPU measurement tool review

## Decision

The narrow measurement-tool gate is available for run_series_v4.py plus plain_v4.gd, with the exact accepted source manifest and frozen protocol supplied by the coordinator. The earlier v2 aggregation and v3 population acceptance gaps are closed. This is not a performance result, workload pass, completed treatment or whole-product acceptance. Every real repetition must still pass its configured qualification and business evidence review.

## Checked corrections

The final aggregator requires a positive repeat count and every requested record explicitly qualified with no failure reasons. Engine/controller errors, timeouts, missing or syntax-malformed result JSON, raw ERROR/SCRIPT ERROR, mismatched input/counts and reception-only work reject the repetition and persist a failed summary. A final failed repetition cannot become all_repeats_complete. The main function exits nonzero for an unsuccessful series.

At initial, sample-start and final boundaries, population must be a record with an empty unclassified_actor_ids list, nonnegative integer counts, an other_owned_present list with nonempty unique actor IDs, and patients+staff+visitors+other_owned count equal present. Different actual population at these boundaries is allowed; there is no fixed-final160 assumption. The current-rule mechanic classifier was independently compared against Maintenance.validate and its five positive/negative cases in the prior review. It retains other unexplained actors as unclassified rather than dropping them.

The19 original pure Python gate cases were read, then replayed without engine execution or source writes. The new replay exactly matches the recorded result, including failure at each unknown-owner boundary, count mismatch rejection and a legitimate dynamic-owned positive case. Frozen manifest bytes were checked after replay. V2 and V3 artifacts remain unchanged.

The Godot snapshot and entire measurement body from func snapshot onward are byte-identical between plain_v3 and plain_v4. The sole v4 change is the reviewed classifier. Reuse of the recorded v3 one-prefix/one-sample smoke and the v4 classifier run is therefore limited to those unchanged measurement semantics and the changed helper. The two-step smoke has no clinical work and must not be counted as clinical qualification. No new engine run was performed by this reviewer.

## Source and protocol gate

The runner requires explicit accepted_source_manifest and accepted_source_manifest_sha256. It verifies those bytes, then every listed source file before running; it does not silently ignore differences from the old copy proof. The coordinator must provide the complete, accepted integrated source identity, not an ad hoc subset. This review does not independently approve the10-file exporter integration or its reported1388-file count.

Bind the selected plain_v4 tool, series_v4, run_engine and engine identities with the final protocol, maintain the selected files unchanged across the series, and retain each run's identity and environment evidence. The existing wrapper records the current engine hash but does not itself compare it to the accepted hash; coordinator verification remains necessary. Do not mix source versions or reinterpret the old reception-only window as qualified by a later continuation.

## Measurement limits

Step latency is monotonic wall duration of a real production step, including any internal waiting. The loop window includes before-state copying, observations and logging, while initialization and final serialization are separately outside it. This is supported HospitalSimulation CPU-path observation, not process CPU consumption, GameSession, rendering, GPU/FPS or persistence throughput. Work increments are explicitly lower bounds; positive GP work does not prove completed treatment. Within-run percentiles are descriptive and do not turn adjacent steps into independent runs. No speedup or formal acceptance is claimed.
