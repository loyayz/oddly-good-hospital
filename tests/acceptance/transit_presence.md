# A41: elevator tickets follow physical presence

## Requirement and affected handoffs

The adopted behavior announced on 2026-11-04 at 11:54 UTC (conversation message `Sentinel_2632acffae6881919a1ce96c659201fc`) was: passengers actually leaving the landing leave that wait; returning passengers obtain a new ticket; people still present board in order; boarding and committed trips are not interrupted. The later front-to-back queue decision changes movement geometry, not this waiting-ticket rule.

The prior convoy reconstruction kept a ticket during ground stand-aside. This was not compatible with A41. Both ordinary solo passengers and two-person queues reproduced the mismatch: they walked away, restored the departed state, returned and boarded with original ticket 1.

The repair shares one physical-landing predicate for admission, queue queries and cancellation. Lift convoys require the real aligned trail and leader at the canonical entry; ordinary solo/stair units use the existing actual landing positions. Tickets disappear in the departure movement boundary. Returned units receive a new sequence. Quote queries exclude absent units without changing world state. Cancelling an empty-car assignment leaves its committed travel and remaining time intact. A unit clearing an incoming rider waits off the exit until the rider safely finishes, then returns by ordinary movement. It does not receive a new priority or teleport.

The affected handoffs are actual movement → waiting-ticket publication → quote/dispatch, departure → save/restore, return → new admission, and safe connector removal's waiting-unit query. The connector's active rider, committed travel, full-body geometry, collisions, failure policy and wear accounting remain owned by their original mechanisms.

## Selectable cases

Run `tests/acceptance/transit_presence.gd` with an absolute result JSON path, optionally followed by a comma-separated case list:

- `leave_solo`: a solo passenger calls an empty car, really walks away, loses ticket/assignment in that same boundary, restores the departed world, walks back and boards on ticket 2. The original empty trip finishes unchanged.
- `leave_convoy`: the equivalent complete two-person trail, checking the leader budget and legal state throughout.
- `order_solo`: three actual floors. A leaves after ticket 1; B remains on ticket 2; A returns with ticket 3. B then A physically board and reach separate final goals.
- `order_convoy`: the same ordering and arrival checks for two complete queues.
- `repeated`: two queues exchange floors for three consecutive real journeys each. Both reach their goals every round, with no overlapping trail and valid world state.

`convoy_transit.gd` case `opposing` now checks that departing queue B drops ticket 2, absent waiters do not add a fictitious quote prefix, and B returns and boards on ticket 3. Its previous assertion that ticket 2 survived was itself incorrect against A41.

Related regression selection: `mixed,opposing,retarget,journey,ride,blocked,admission,cancel,stairs,solo_stairs,solo`, and `SPACE-25` through `SPACE-30`. These cover mixed units, committed retarget, all portal-stage restore boundaries, blocked egress, timing/wear, stair behavior, ordinary solo queue fairness, readonly quotes, empty trips, active-ride restore/faults and safe removal.

## Results and limits

The isolated Godot 4.7.2 Linux native-backed execution passed all five new cases, all eleven selected convoy cases and all six selected SPACE cases, with no engine script errors. The new three-round scenario completed in 228, 308 and 308 ticks. Three-floor ordering completed in 216 ticks for solos and 277 ticks for convoys. All actual arrivals were performed by normal movement at the original simulation step size.

This is evidence for the selected transport boundaries. It does not prove starvation freedom under arbitrary infinite arrivals, overall high-density performance, full-game acceptance, Windows builds or visual quality. No new priority/fairness rule was invented to claim those guarantees.
