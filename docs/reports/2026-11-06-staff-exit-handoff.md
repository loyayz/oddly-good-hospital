# Staff offsite movement handoff

## Rule and boundary

The authority is docs/design/09-consultation-wellbeing.md §4–5: six staff roles sleep for real; missing a usable bed can require actual departure; paid leave starts at actual departure; an unavailable route or occupied reentry point cannot teleport staff. The affected handoff is the existing staff life task's `exiting` → `offsite` transition.

The route mover reaches its exact endpoint and advances its cursor, but may retain the completed movement until the next movement phase. Wellbeing dispatch previously published an outside actor in between, leaving the terminal floor movement behind. The next `_active_route_clear` read `location.floor_id`, which an outside actor does not have.

The fix is one guard before publishing outside: require `space.cancel_ground_move` to succeed. This existing operation cleans route ownership, route caches and transit waiting. It refuses unsafe movement (including actual transit, support exit and convoy followers). It is called even when the staff member has no directly keyed move, because convoy followers are owned by their primary actor's move. Production clinical convoy creation uses the patient as primary and staff as follower. No movement tolerances, route validation, sleep duration, leave timing or recovery rates change.

## Verification

- The original long-run state at tick 16407 validates and contains a nurse at the exact exit with `path.size()==1` and `cursor==1`. One full original simulation step creates outside + offsite + stale movement at 16408, emits the original floor_id script error, and fails the world invariant.
- The identical boundary with the fix reaches 16408 outside/offsite without a movement; 120 full simulation steps complete to 16527 with no such stale actor or validation error.
- From the original valid tick-16000 checkpoint, 2000 full simulation steps complete to 18000. Every step checks for outside actors retaining moves; none occur. Final world validation is empty and the log has no script/engine errors.
- New STAFF-76 runs 14 real-arrival variants: six roles sleeping and a doctor's approved one-day leave, each fresh and world-restored at the terminal-movement boundary. All 14 fail the original production file and pass the fixed file. It checks real travel, valid input, zero initial offsite clock, exact leave start/end, repeated dispatch and the next movement phase.
- The nurse variant additionally executes all 4500 real offsite recovery ticks while another actual body occupies the entrance. The nurse waits outside with completed sleep and no move, then reenters and follows a fresh return route once the occupant walks away.
- STAFF-16, STAFF-18, STAFF-19, STAFF-24, STAFF-26 and SPACE-44 pass unchanged. These cover safe handoff, leave/long-rest clocks, missing-bed departure and obstruction, sleep credit, and movement cancellation/support exit. They are reused after test-fixture-only corrections; STAFF-76 was rerun separately.
- Final editor import passes. The source directory is unmodified; only an isolated copy was edited.

## Test preparation and limits

The initial isolated setup placed the Linux native library under the old windows/bin path while the supplied descriptor pointed to linux/bin. This was corrected to the descriptor's declared path using identical verified library bytes. Those setup failures are retained separately. The first STAFF-76 registration incorrectly reached the public-area dispatcher and was corrected. The added entrance occupant then needed the same service initialization as the standard staff fixture; schedule, payroll and practice defaults were initialized before measuring recovery. These were test-preparation errors, not additional production changes. The final corrected test passes.

Godot 4.7.2 Linux headless and the current stage-2 Linux native library match the source pressure test's runtime identity. This is not Windows, GPU, a whole-suite performance claim or disk-save acceptance. Restoration is an actual WorldState reconstruction at the measured boundary. The change prevents the invalid transition; it does not repair an already-invalid outside-plus-move save. Resume the supplied valid pre-failure checkpoint for recovery testing.
