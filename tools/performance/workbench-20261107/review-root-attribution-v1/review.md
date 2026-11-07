# Independent root diagnostic v1 review

Verdict: limited diagnostic tool admission supported by recorded two-step smoke, with no blocking defect found for the registered 800-step protocol. The 800-step semantic/performance result is NOT approved by this review. No engine was run by reviewer; no source/live output was edited.

## Verified evidence

All 28 qualification-manifest files match their frozen hashes. Accepted manifest hash matches protocol; all 1388 listed copied source files match accepted hashes, with diagnostic driver added separately. Input hash matches protocol. Smoke plain/root each completed ticks 1021→1023, exit 0, no raw ERROR and no declared errors. Their entire final.bin envelopes are byte-identical, which includes frozen facts/RNG and ordered event records, not merely summary counts. Root attach report records unchanged encoded facts/RNG, returned instance and checked graph references, empty errors. Profile has two complete records, no incomplete steps/nested calls/errors. Soft-stop completed zero steps, tick unchanged, exit 1, incomplete result and final envelope saved. This supports the exercised paths, not all failure modes or full-window transparency.

## Actual driver contracts

References below are diagnostic_v1.gd lines. Lines 68–87 check attach facts on both success and returned-null paths, require explicit references and observer errors, use external output.generated, and abandon diagnostic on failure; old is released without dispose after reference transfer. Lines 115–123 surround the actual sim.step() with monotonic timer and root observer, require complete result and exact tick increment. No reset, teleport, arrival disable, or production rule changes were found. Source hash comparison substantiates unchanged production code.

Lines 105–107 implement a 360-second *loop* deadline checked between steps, excluding initialization. Wrapper timeout covers the whole engine lifetime at 400 seconds, sends TERM then allows up to 10 more seconds before KILL. Hard interruption preserves flushed enter/complete records and raw log, but cannot guarantee final.bin or profile output. No hard-timeout test was performed here. Soft-stop at zero only verifies the boundary-stop path, not interruption in a blocked step.

Lines 144–165 save final boundary/envelope and explicit incomplete status for ordinary detected errors. A runtime script exception or failed file open can bypass normal finalization; raw logs plus wrapper status must reject these cases. Attach failures save a gate report but not a full failed-world envelope. This is sufficient to reject, not to claim recoverable final state. run_engine.py itself can exit successfully while its child failed; its status.json is authoritative, not wrapper shell exit.

## Required post-run gates

Check both status files: returncode 0, timed_out false; raw ERROR absent; requested/actual 800, ticks 1021→1821; exact input/source/tool/runtime identities; empty errors; root attach success; profile 800 complete records with no truncation, no incomplete or nested calls/errors. Compare entire final.bin byte-for-byte (including facts/RNG/ordered events). Check actual population/work validity and scope independently. Driver complete is an intra-run count/error predicate, NOT the combined semantic acceptance gate. Any missing or failed gate leaves that pair invalid/incomplete, never a speedup result.

## Timing/semantic limits

Initialization includes attach and is separate from loop timing. Step timer includes instrumented simulation dispatch but excludes begin_step/end_step handlers; these and snapshots, event conversion, progress logging and flushes are included in loop wall. Root spans are intervals between markers, not exclusive named-function costs. Observer handler accounting is not all profiler overhead. Partition identity is algebraic, not independent correctness evidence.

Root attach constructs another simulation on the shared world before replacing references, potentially warming runtime/global caches without facts mutation. Fresh paired plain and root processes do not recreate A's uninterrupted prefix or make cache preparations equal. These are restored-window attribution measurements, not B, speedup, CPU-utilization, FPS or all-product qualification. Two-step equality does not imply 800-step equality. Final facts plus ordered event equality is strong end-state/event evidence for this deterministic input, not equality of every intermediate fact, every future input, or unrecorded cache state. Clinical work remains a lower-bound observation; no treatment claim follows.
