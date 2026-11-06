# Front-to-back queue transit regression

## Rules and handoffs

The queue leader is the only movement permission subject. Other members publish poses along the accepted, protected trail. A lift ticket may be issued only when the whole real trail is aligned at its entrance. Boarding and alighting must advance that trail physically, without overlaps, pose jumps, or a second walking budget in the same tick. The current ride owns the connector until safe exit; an obstructed exit retains that ownership. The existing stair capacity, committed empty-trip timing, failure-after-safe-exit policy, and one-use wear receipt remain unchanged.

The tested handoffs are formation → route → actual landing → ticket → portal movement → riding → portal exit → ordinary walking, plus frozen-world reconstruction during each transport phase. Pure plan checks are separate from actual collision and lifecycle checks.

## Selected cases

Run `tests/acceptance/convoy_transit.gd` with an absolute result path, optionally followed by a comma-separated case list. Each selected case constructs only its own prerequisites.

| Selector | Checks |
| --- | --- |
| `cache` | Repeated pure plans build once; rotation, position, envelope, and leader-speed changes invalidate; caller mutation cannot poison canonical plans; separate runtime spaces have separate caches. |
| `mixed` | Incoming convoy with an ordinary solo waiter, and incoming solo with a waiting convoy, both really clear the exit and finish. |
| `opposing` | Two complete queues waiting on opposite floors use the same lift without deadlock; real stand-aside retains original ticket 2 and quotes become unknown until physical re-entry. |
| `retarget` | Change the goal back to the origin floor during riding, preserve the committed ride, then really exit, turn, board again, and return. |
| `plans` | All four portal rotations, no member overlap, one distance budget across corners, plan/prediction/timing agreement. |
| `rotations` | Real build/extend for all four orientations of VC01/02/03, operation squares outside shafts, and VC02 two-person round trips with per-tick safety and exact transport times. |
| `journey` | Actual group request from a distant point on 1F to a real goal on 2F; freeze/rebind during boarding, riding, and alighting; world validation and one leader budget every tick. |
| `ride` | Legal complete group already at the entrance; actual boarding/riding/alighting; exact 65-tick current-content quote, no teleport, one wear debit. |
| `blocked` | A real body obstructs the destination; the queue stops and keeps ownership; the blocker really walks away; the ride finishes before a pending failure becomes effective. |
| `admission` | Leader at the entrance but trail sideways: no ticket, no pose/connector change. |
| `cancel` | Cancel a waiting group after empty pickup starts; the original empty trip completes without passengers or use receipt. |
| `stairs` | A two-member group cannot board a one-person stair. |
| `solo_stairs` | A one-member convoy keeps the original 25-tick stair trip and rebinds its trail on the destination floor. |
| `solo` | Existing ordinary single-person lift request really reaches its original goal. |

The admission tests start from explicit legal pre-operation geometry. They do not claim to test gathering from fixture spawn positions. Every motion under test uses the real movement phase and production collision/index code. The frozen-world test reconstructs the simulation from its complete facts; it is not SQLite, process-restart, or Windows persistence coverage.

## Execution

Use the project's supported isolated runtime preparation before invoking this script. Preserve the source identity, engine/native identities, import status, exit code, result JSON, and engine log. A row reporting `ok` is insufficient if the engine logs an error or the process fails.

`tests/native/convoy_portal_geometry.py` provides a separate backend-independent geometry check. It copies the actual `ConvoyPortal` and `ConvoyTrail` implementations, actual connector/balance data, and current cell-size constant into a small literal typed context. It covers four rotations and three sizes/member configurations plus incompatible cabin, stair, capacity, and overlong-tail rejections. This is a pure-algorithm check, not full-game collision, route, persistence, graphics, or packaging evidence.

Larger-body real rotated journeys, arbitrary dense multi-connector traffic, Windows behavior, graphics, and full-game regression are not covered by this focused suite.
