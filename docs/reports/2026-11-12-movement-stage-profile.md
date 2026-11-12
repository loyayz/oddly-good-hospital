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
