# Resume displaced transit waiters after safe landing release

## Rule, defect and scope

The adopted A41 contract is recorded in `tests/acceptance/transit_presence.md`: actual departure cancels the current wait, actual return earns a new ticket, and a unit clearing an incoming rider waits until that rider safely finishes before returning by ordinary movement. This is consistent with `docs/specs/26-10/2026-10-19-task-navigation-movement.md` §4: an otherwise executable walk must not wait for remote temporary occupancy; real motion, collision/sweep checks, stable order and complete-group handoffs remain mandatory. `docs/design/11-growth-arrivals-recruitment.md` §4.1 keeps actual arrival, queue order and committed boarding/riding/alighting ownership separate. The test alone is not the rule source.

The defect is the recovery handoff after a temporary ground waypoint. Both `HospitalTransit.begin` and `_begin_convoy` previously returned on every non-idle phase before requesting an off-landing return. Another already-ticketed unit could take the car immediately after the incoming rider safely finished. The displaced waiter then missed recovery throughout unrelated empty trips, even though no current passenger owned that landing. This is not a reason to restore its canceled ticket or give maintenance priority.

The fix moves only the existing preserve-request ground-route request ahead of the blanket busy return, behind a shared landing-use guard:

- Boarding protects both the source entrance and the incoming destination.
- Riding/alighting protects the destination, including a blocked actual alight.
- Idle and empty-riding have no boarding/alighting body to protect.
- Loaded work at unrelated floors does not suspend this ground recovery.

Recovery only requests an ordinary route. It does not move bodies, consume extra step distance, create a ticket or reserve a cabin. Actual return still passes all existing collision, sweep, complete-group alignment and FIFO admission checks. Prices, hours, RNG, benchmark input, maintenance and clinical ownership are unchanged. The production diff is16 additions and8 deletions in one file.

## Fresh replay diagnosis, kept separate from earlier runs

This work uses the new complete mixed-window final input `e5c6b6e2d146187e8ba7edcd707802f8dc1d8c6287872ac734580d1e62a34c75`, tick7633. It does not reuse old workers238/239 or trip37/40.

Fresh history establishes worker226/request629/job maintenance222 at the landing with ticket56 at6505. It departs west and cancels the ticket at6520, reaches temporary endpoint[84,44] at6529 and has no later movement-state change through7633. Incoming trip49 safely finishes at tick6595; end-tick6596 is already an unrelated empty1F→2F trip. Subsequent trips53/54/57/61 likewise finish and immediately hand off to other work. See the separate current-mixed-full report for the full-window identity and owner history.

One actual full production step from tick7633, independently repeated with the observer, confirms worker226's actual `begin` call has at_entry=false, request629, owner maintenance222 and current position[84,44]. The lift is now carrying patient0118 in trip63 alighting3F→1F. Stand-aside is called but commits no waypoint from the off-anchor position. This specific current loaded arrival remains protected under the fix. Independent complete-body geometry identifies patient0073 at that exit; the one-step observer does not claim an internal dynamic-index rejection branch. Plain and observed complete World/RNG/ordered-event outputs match exactly at tick7634, SHA `2f3ed8f30801c529b1d223deebca11ff72af5f32fdbbd811cc21fef7b28033f3`.

## Minimal regression and result

`tests/acceptance/transit_busy_recovery.gd` has four cases:

1. Solo post-release recovery. Three lawful floors, an incoming passenger, an already-present passenger at another floor and a waiting contractor. The contractor really leaves the landing and loses ticket3. Incoming trip1 completes at tick40; the existing ticket2 passenger immediately starts empty2F→3F. At boundary41, baseline does not request recovery; the fix does. The contractor returns physically, obtains new ticket4, boards after the already-ticketed passenger and reaches its original work position. A real maintenance order is created through the ordinary command; the assigned contractor at the initial landing is a declared legal precondition, not tested admission. Job identity, request, goal, remaining/completed work, payment and ownership remain unchanged through motion. No maintenance work or payment is fabricated.
2. Convoy post-release recovery. Same handoff with the complete two-person trail, real departure/return/boarding/alighting and final arrival. There is no invented convoy maintenance task.
3. Solo source-boarding guard. A legal post-waypoint input starts clear of the source entrance. Another actor actually boards through production movement. Recovery stays suspended throughout boarding, then queues on actual riding departure.
4. Convoy source-boarding guard. Equivalent source protection for the complete aligned trail.

The post-release cases serialize the actually departed world to bytes and decode it into fresh services. Original and restored simulations execute every subsequent real movement tick separately and retain identical complete facts through actual goal arrival. Every floor-body pair is checked for separation and synchronized sweep safety; the convoy additionally checks its actual trail/body positions. Speed budget, valid World, clinical ticket collection, no off-landing ticket and exact actual boarding order `aaa_incoming → bbb_present → leader` all pass. The fixed ticket is4, never the canceled3.

The final test source fails on the baseline at the required recovery handoff. It passes on the final guarded fix. Downstream arrival/new-ticket assertions in the baseline are false because that case deliberately stops at the demonstrated missing recovery, not because an arbitrary long timeout was used.

## Selected checks and timings

All final selected checks pass, serially in the same prepared runtime. These fixtures invoke production movement ticks (`suite._movement_tick` / `space.advance`), not full `HospitalSimulation.step()` ticks. Only the separate qualified one-step full-world capture above executes the complete simulation pipeline:

- New four recovery/guard cases:6.652 seconds process wall time.
- Existing `transit_waypoint_order`: waypoint_solo, waypoint_convoy, aside_solo, aside_convoy.6.865 seconds.
- Existing `transit_presence`: leave_solo, leave_convoy, order_solo, order_convoy.7.238 seconds.
- Existing `convoy_transit`: blocked, ride, opposing.6.662 seconds.
- Final baseline four-case comparison:5.640 seconds, expected failing result.
- `git diff --check`: passed. Final Godot script loading/execution had no errors.

These are functional execution timings, not performance measurements. Scope stops at unchanged clinical/maintenance work interfaces; no full SPACE/OPS/CLIN suite was run. All four new cases and eleven existing selected cases passed. Earlier candidate runs are retained and labeled separately in the evidence; they are not extra accepted benchmark repetitions.

## Artifacts and continuation

[Evidence manifest](evidence/2026-11-12-transit-recovery-fix/manifest.json) and [archive](evidence/2026-11-12-transit-recovery-fix/evidence.zip) contain raw baseline/fixed results, every process command/log, final sources, baseline source, scoped harness, the fresh one-step observer, and identities. ZIP CRC and every member SHA were verified. The full binary inputs/outputs remain at their recorded workspace paths rather than being duplicated in this archive.

Final production SHA: `2ead5adfdcd4be9c2530a0b3f6a20ba4bdf11b64616b4457a540a3b643489d73`. Final test SHA: `b1056ff6a1b0783b4d303a31f3427b4164f641ad37d7af16867bd5f9ac2401a5`. Tests executed byte-equivalent sources with Windows CRLF; final files were normalized to LF, and exact normalized-byte equality is recorded. No semantic edit occurred after final tests. The borrowed `ogh-fixed-boundary-20261112/.cache/boundary-project` was restored against every original source and native-library hash; do not assume it contains this new patch.

The useful full-world input for follow-up remains `C:/Users/cong/dot-work/ogh-full-mixed-20261112/plain-r1/result.json.final.bin`, SHA `e5c6b6e2d146187e8ba7edcd707802f8dc1d8c6287872ac734580d1e62a34c75`. The one-step pre-fix continuation is at `C:/Users/cong/dot-work/ogh-fresh-worker226-20261112/plain1/result.json.final.bin`, SHA `2f3ed8f30801c529b1d223deebca11ff72af5f32fdbbd811cc21fef7b28033f3`.

No post-fix full mixed window was run in this focused test batch. The prior full-window failure and0/3 accepted repeats were not changed by these movement tests. Actual arrival in the minimal fixture is not a claim that worker226 reaches its real benchmark job. Release/GPU/two-hour acceptance remain unrun. Validation completed locally without a push; subsequent full-window measurements are recorded separately. Such a measurement must use the fixed production source with the unchanged benchmark and serial execution.
