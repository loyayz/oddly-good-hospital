# Exhausted local rejoin collision repair

## Rule and scope

`docs/design/01-simulation.md` requires an actual blocked local mover to use the existing one-person side/retreat rules, preserve its original task/path/request, and earn route progress only by actual arrival. Later original-route attempts must still follow B → C → D. Temporary intentions do not reserve future dynamic corridors.

The affected handoff is `HospitalMovement._local_collision`: after `_local_try_return(advance=true)` exhausts later original-route points, it previously rebuilt the same rejoin, alternating orthogonal first legs according to the last blocked heading. Both geometrically legal connectors could hit bodies, yet each rebuild returned “changed” and swallowed the actual contact. The repair removes only this fallback. Failed later-target selection now falls through to existing contact classification and side/retreat choice. Successful later-target selection is unchanged. No new pathfinding, rights, priorities, actor omission, RNG, gameplay, load or ownership semantics were introduced.

## Regression before and after

The new `end_rejoin_actual_collision` case in `local_return_intent.gd` begins at a valid already-side-stepped boundary:

- Walker `[40,71]`, original route origin `[40,70]`, original final/unearned rejoin and goal `[38,75]`, request 1, cursor 0.
- Fixed bodies `[39.4,71]` and `[40,71.6]` block the west and south first legs. The north exit remains legal.
- Baseline fails to arrive within 180 real 0.1 s movement ticks. The first eight recorded positions show zero displacement while targets alternate `[40,75]` / `[38,71]`. Initial validity, body/sweep/speed safety, original ownership, and restore checks pass, but movement and arrival fail.
- Patched code moves within the first eight ticks and reaches the original goal after 43 production movement ticks (`movement_detour._tick`, not full clinical simulation steps). Each step checks real body/sweep separation, speed budget and World validity. Fixed actors, original path/goal/request and contact-time cursor are preserved.
- After the first collision, HospitalJsonStream writes and decodes the complete checkpoint. Fresh services continue the decoded state alongside the original through goal arrival, with equal complete World facts on every subsequent real tick. This is actual continuation, not validation alone.

The first exploratory fixture used 0.8-cell body separation and allowed two small initial steps before the same stall. It was tightened to the above valid immediate-contact boundary; only that final regression input is archived here.

## Selected checks

All selected checks passed on the patch:

- `local_return_intent`: B_C_D (33 ticks), compressed_B_C_D (33), bent_route_B_C_D (49), fixed-contact handling, binary32 retreat axis, and the new end-rejoin case (43).
- `LOCAL-BLOCKED-MOVER`: both original goals reached, 44 ticks; cold continuation 43 ticks. Process wall time 5.293 s.
- `LOCAL-ONE-AVOIDER`: preserves the existing effective local mover and resumes without waiting for its whole detour. Process wall time 5.286 s.
- `RETURN-EARLIER-SIDE` / `RETURN-EARLIER-RETREAT`: earlier unearned route points remain recoverable after actual side/retreat, preserving original requests and safe restore. Combined process wall time 5.468 s.
- `git diff --check`: passed. Godot loading/execution of the selected tests passed. Source line endings restored to LF, with no semantic change after the test runs.

These cases cover the changed movement handoff and stop at unchanged clinical/maintenance ownership interfaces. Full SPACE/OPS/CLIN suites, long performance sampling, Release/GPU and two-hour acceptance were not run. Timings above are diagnostic execution timings, not CPU acceptance results.

## Reproduction and evidence

Use the existing Godot 4.7.2 runtime and verified native DLL from the handoff. Once imports/runtime dependencies are available, run:

```text
godot --headless --path PROJECT --script res://tests/acceptance/run_local_return_intent.gd -- OUTPUT.json
godot --headless --path PROJECT --script res://tests/acceptance/run_blocked_local_mover.gd -- OUTPUT.json
godot --headless --path PROJECT --script res://tests/acceptance/run_one_local_avoider.gd -- OUTPUT.json
godot --headless --path PROJECT --script res://tests/acceptance/local_return_recovery_runner.gd -- OUTPUT.json RETURN-EARLIER-SIDE RETURN-EARLIER-RETREAT
```

For the failing baseline, use the new test with `hospital_movement.gd` from base commit `2e57de8e39ea7af616fc1d5cdff291517ecc10f6` in a separate project. Do not overwrite accepted evidence or the user's original checkout.

Raw [baseline](evidence/2026-11-12-local-return-cycle/baseline.json), [patched intent cases](evidence/2026-11-12-local-return-cycle/patched.json), [blocked local mover](evidence/2026-11-12-local-return-cycle/blocked.json), [one local avoider](evidence/2026-11-12-local-return-cycle/one.json), [earlier rejoin recovery](evidence/2026-11-12-local-return-cycle/earlier.json), [commands/timings](evidence/2026-11-12-local-return-cycle/selected-runs.json), and [identities](evidence/2026-11-12-local-return-cycle/identity.json) are archived together.

The separate [exact full-world eight-step verification](2026-11-12-transit-boundary-fixed.md) confirms that patient0013 physically moves and patient0018 alights at tick7640, releasing trip37. Workers238/239 are still waiting at that boundary. Neither the regression nor that bounded run establishes completion of the workers or overall traffic/performance success.
