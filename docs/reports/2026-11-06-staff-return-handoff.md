# Staff return target handoff

## Rule and production change

The supported schedule UI and scheduler accept staff leave/recall, including nurses. Design `09-consultation-wellbeing.md` §4–5 requires real departure/return, retention of unfinished rest/sleep obligations and resumption under the current schedule. Its leave wording mainly discusses doctors; it does not explicitly prescribe a nurse's alternative standing coordinate. A historical departure coordinate does not reserve a bedside operating position after another nurse has safely taken over.

Previously `_begin_return` copied that old coordinate into a mandatory destination. If a replacement occupied it, movement correctly refused overlap, but the returning life task blocked schedule/base preparation indefinitely. The repaired wellbeing owner keeps a usable old destination. Once both former facility/seat references are physically released, it can replace an occupied, statically invalid or failed-route destination with the existing full current-region safe-standing search. That search checks body geometry, actual occupancy, reservations, doors/work points and real routes; it has no nearest-N truncation. An already-safe current point can finish the optional return obligation; otherwise the actor must actually walk to the selected point.

The implementation does not move the replacement, acquire its bed or force on_shift. Completion safely cancels the old movement, performs normal leave/rest bookkeeping and lets the next ordinary scheduler/base-preparation boundary acquire current work. Active jobs/base/training and committed transit are not overridden. Both facility_id and leaving_facility_id must clear before the new fallback/completion path.

## Direct natural evidence

The supplied natural history begins with real arrival, diagnosis, surgery, wake, transfer and completed nursing. At tick 3674 a formal leave command is accepted for clin_cover; recall is formally accepted at 4074. The replacement remains at the old bedside [45,67]. Original production leaves clin_cover returning at [44.6,91] through tick 7077; the legal control that formally sends the replacement on leave lets the original nurse return.

With this patch, the supplied already-stuck but valid tick-5877 world reaches a real safe standing point [45,92] and completes return at 5885. The replacement is unchanged. Normal schedule/base preparation is ready at 6061. The full 1200-step continuation to 7077 has no body overlaps, outside moves or validation errors.

The original natural harness was also rerun from the actual tick-3674 care-completed checkpoint, with the same formal leave/recall commands. It reaches normal cured departure at 5877, no errors or overlap, and clin_cover is idle/base-prepared at [45,72]. No patient, RNG, service progress or completed work was injected.

## Focused regression results

- New STAFF-77: six actual flows. Free old target remains preferred; occupied before recall, occupied midwalk, restored after reentry, statically built-over target, and occupied during a real lift ride all complete safely. The ride's location/move record is unchanged when the fallback cannot yet act. Original production passes only the free control; repaired production passes all six.
- STAFF-76's full sleep/reentry test still executes all 4500 offsite ticks, waits for the real entrance occupant and follows a fresh return route. Its final assertion now accepts a genuinely safe return endpoint rather than requiring the historical exact coordinate. This is the intentional rule change, not a removed physical/temporal check. All 14 variants pass.
- Passed related existing cases: STAFF-16,17,18,19,21,22,25,26,27,70 and SPACE-44. Together with STAFF-76/77, 13 distinct affected cases pass. Existing sleep debt/remaining-time, long-rest, leave, group recreation, safe movement and support-exit protections remain covered.
- CLIN-22 and CLIN-27 were selected to check ward handoffs, but fail on both unchanged baseline and candidate, at the same pre-existing clinical_release nurse-departure boundary. They are **not** counted as passes. Their baseline/candidate results are preserved for separate investigation. The complete natural ward leave/recall continuation above passes on the candidate.
- Final isolated editor import succeeds without errors or warnings. An independent read-only review found no introduced safety/business regression.

## Scope and limits

Production changes only staff_wellbeing.gd. This repair concerns a released staff-life return preference, not clinical_release destinations or original bed/support exit selection. If the old physical support has not yet been exited, its existing safe-exit workflow continues unchanged. Fallback searches the current region; no safe reachable point means continued visible waiting, not teleportation into another region. These limits are not claims of universal return-path repair.

Execution used the supplied current Linux stage-2 native runtime and Godot 4.7.2 headless. This is not Windows/GPU verification, disk-save acceptance or a complete clinical-suite pass. Shared source and GitHub were not modified. Timing is not presented as a performance result.
