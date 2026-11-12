# Narrow movement-stage diagnostic qualification

The complete root-stage profile established `movement.space` as the largest measured span (35.45%), but not a particular collision routine. This next diagnostic stays inside `Simulation.step_nonblocking -> HospitalSpace.advance -> HospitalMovement.advance`. Gameplay sources remain `e232c42389e614cf13d305c4376d59892c4aa0c3`; the fixed mixed workload, commands, 0.1s step, thread-task settings and acceptance gates are unchanged.

## Scope and qualification

A separate isolated project times six disjoint `advance` spans: setup/projection, transit.advance, route.dispatch, route.cleanup, actor.loop and boundary.cleanup. Seven existing instance methods are separately timed only while this `advance` is active and are bucketed by their entry span: `_active_route_clear`, `_replan_goal`, `_local_resume`, `_continue_detour`, `_local_collision`, `_convoy_turn_contact` and `_move_step`. The original static transit call remains static and in place. Removing markers and reversing wrapper names restores the original source and driver exactly.

Method inclusive/exclusive times are a different layer from disjoint spans and must never be added to them. Exclusive selected-method time is subtracted only from its own span to describe the uninstrumented remainder. Handler bodies are measured separately; dispatch and timer-read overhead are not completely removable. Outside-span time includes other simulation phases, not just movement gaps.

Three pure-Python test groups check actual source inverse transforms, preserved static call/driver anchors, missing-anchor failures and identity/syntax. A new plain/narrow 0+2 pair then passed complete World/RNG/ordered-event and full business/failure-state equality, final SHA256 `21aff2546935022312333b67605680c491292575aaa845b07733db993a415a51`. Both processes exited 0, with startup-inclusive walls 4.213/3.813 s. Six-span partition, tick/elapsed correspondence, scope and method-exclusive subtraction passed with no timer errors. Source and driver bytes were restored; the archived root-stage project was unchanged.

Only `_active_route_clear`, `_convoy_turn_contact` and `_move_step` were exercised by these two steps. The other four methods' business branches are not claimed as tested. Coverage=false and performance=null are preserved: this short qualification is not a complete performance round or an accepted repeat. No complete narrow profile was run in this qualification batch.

CPU model/affinity, load, memory, kernel and available cgroup information were captured before and after the engine, never inside timed steps. Unavailable cgroup fields are marked as such; these current readings cannot reconstruct the prior lost cloud executor's conditions or explain the earlier P95 difference causally.

## Evidence and retention

[Qualification raw archive](evidence/2026-11-12-movement-stage-profile/qualification.zip): 705083 bytes, SHA256 `6af002837a69bb826c6a4dea602d645e1edee8be2e37715f6e12953caa8a2d22`, 34 raw members plus manifest. [Member manifest](evidence/2026-11-12-movement-stage-profile/qualification.members.json) accompanies it. [Helper support](evidence/2026-11-12-movement-stage-profile/helper-support.zip): 4196 bytes, SHA256 `cb5710f25dfb6a6527c2b83dbe8668c8690635c409c9c0af5635594ebab3b3ed`, preserves the exact imported qualification helper and dependency binding. ZIP CRC and every payload size/hash were independently checked.

Tool identities: preparation `0b5fafb65747238ef317ee1823be31d31a972a384710a4bdce69cd1fffd57888`, qualification controller `da12ae0c9ea4d3f5d796d84832342c2e2db51c63186c1a6f849ab5e45e133cbb`, movement timer `1ad59339d3db2a1fea0793375ad802e97be315e5a8f64cdcb195355fa1c18789`.

The [raw-run retention index](evidence/performance-raw-run-index.json) distinguishes short qualification from complete ordinary/profile windows. At least the latest three raw results will remain recoverable, with a durable backup and remote readback before another long run. Earlier published files are retained, not deleted. Numeric comparisons must use compatible run kinds, workload and runtime identities; an instrumentation qualification does not become a full performance repeat merely because it appears in the backup index.

## Complete narrow window

Exactly one new 1000+6000 narrow window completed after its qualification had been published and remotely read back. The previously checkpointed full plain result was reused as the control; no extra plain window was run. All 7000 steps completed, and all 6000 measured steps qualify as the same dense interval. Complete World/RNG/ordered-event bytes, the full business observer and failure status equal the plain baseline, final SHA256 `41928476a199dbf3e35b3ff74cd54a52fd0801feb92c5b1d1a5d6fe035258a68`. Scope, all record tick/elapsed values, timing partitions and source restoration checks passed.

| Disjoint movement span | Total | Share of six movement spans |
| --- | ---: | ---: |
| actor.loop | 129.769953 s | 92.23% |
| route.dispatch | 6.537597 s | 4.65% |
| setup.projection | 1.366741 s | 0.97% |
| boundary.cleanup | 1.274690 s | 0.91% |
| transit.advance | 1.269532 s | 0.90% |
| route.cleanup | 0.480391 s | 0.34% |

Inside actor.loop, selected-method exclusive totals are `_move_step` 67.766973 s / 746446 calls; `_local_collision` 22.831114 s / 166616 calls; `_active_route_clear` 8.520851 s; `_local_resume` 5.967868 s; `_convoy_turn_contact` 0.888098 s; `_continue_detour` 0.004212 s. `_replan_goal` was not called in the observed advance scope. The uninstrumented actor.loop remainder is 23.790837 s and is not assigned to any of those methods. Do not add method totals to their enclosing span totals.

The largest cumulative cost and movement tail spikes are different: route.dispatch dominates 49 of the 60 largest movement-span steps. At tick 6240, the whole step is 333.121 ms, route.dispatch 232.057 ms and actor.loop 30.685 ms. Ticks 1634 and 2884 are predominantly outside the measured movement spans. The evidence does not support treating every slow step as local collision.

Whole-step time is 398.298792 s: movement spans 140.698904 s, measured handlers 10.702139 s, other phases and gaps 246.897749 s. P95/P99/max are 100.752/136.486/333.121 ms; sample wall 444.658939 s, speed 1.3493487871x, process wall 521.382 s. This is an instrumented diagnostic with measurable perturbation, not an optimization gain or an interchangeable plain timing. The latency gates fail; coverage remains 29/31 with the same rejected upgrade and missing effective visit, and raw complete=false/exit 1 remain unchanged.

Before/after host snapshots report 9 logical CPUs and affinity 0–8. The checked cgroup v1/v2 quota and throttling paths were unavailable, so neither throttling nor its contribution is established. These snapshots do not reconstruct conditions on the earlier lost executor.

[Complete narrow raw archive](evidence/2026-11-12-movement-stage-profile/full-narrow.zip): 2124581 bytes, SHA256 `b2f61b94d079596b1839f5ff70436c895526e3b36a180974473b0828ed22f493`, 29 raw members plus internal manifest. [Member manifest](evidence/2026-11-12-movement-stage-profile/full-narrow.members.json) and [derived attribution](evidence/2026-11-12-movement-stage-profile/narrow-attribution.json) accompany it. CRC, every payload size/SHA, full final-state equality and restoration were independently checked. The recent-three complete-window retention list now covers the plain, root-stage and narrow-stage windows as distinct run kinds; all older artifacts are still retained. No gameplay edit or additional run was made in this diagnostic batch.
