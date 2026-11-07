# Reception/GP reservation and cancellation handoff repair

## Rules and actual handoff

The rules are docs/design/01-simulation.md §3 and docs/design/07-clinical-team.md §1, §6: one employee owns one active assignment, real gathering precedes work, and cancellation releases uncommitted work while occupied physical envelopes remain until actual exit. The affected handoffs are ticket → gathering reservation → real service, and canceled preparation → safe employee departure.

A21: `_gather_assigned` previously returned false both when the pair arrived and when the pair was invalid. Dispatch then selected a new earliest desk without releasing the old ticket-owned reservation. Reception/GP now keep their valid original pair through complete start-time checks. Invalid pairs retire old ownership before reselection, reset the called state, and retain the original queue ticket. If all desks are unavailable, the ticket waits and resumes when a desk reopens.

A29: releasing preparation previously transferred the reservation to the patient but never moved an already-arrived employee away. Release now cancels only the obsolete matching solo approach, or uses the existing actual safe-exit workflow. Active transit/support-exit is not erased. A refused cancellation persists until a safe boundary, even if the unoccupied facility reservation disappears. Mere bed-access permission and staff already owned by another job/session/visit do not become canceled gathering assignments.

## Evidence

- New CLIN-36 runs 18 real variants: reception and GP, unchanged control, earlier desk opening at arrival, held desk closing or employee leaving shift during travel and at arrival, all desks closed then reopened, referral while walking and after actual employee arrival. Departure tests continue through 600 full `HospitalSimulation.step()` calls. They check valid input/boundaries, no teleport, old-ticket release, eventual service/departure and valid final worlds.
- The same final CLIN-36 against unchanged production passed only the two controls, failing the other 16 variants. Against repaired production all 18 pass.
- Selected existing CLIN-01, CLIN-05, CLIN-16, CLIN-33, CLIN-34 pass. They cover real reception duration, frozen GP charge, preparation cancellation/expiry, employee exclusivity, failure atomicity, and 192 candidate-order/quote/facts/RNG variants. Final CLIN-36 passes. Six distinct acceptance cases, not a full clinical suite.
- Original external A21 audit harness also passes its four scenarios: maximum held facilities is one, the original desk remains selected at arrival, reception completes, and world validation stays empty.
- An independent supplementary probe uses synthetic released-reservation metadata with genuine lift boarding, ride, landing and world freeze/restore. Pending cancellation survives mid-ride restoration, leaves the employee at the floor-2 landing rather than the canceled destination, and clears movement/release with a valid world. This is not a complete elevator clinical-referral acceptance case.
- Final isolated Godot editor import succeeds; selected logs contain no script/parse/engine errors or warnings.

## Scope and limits

Only clinical_runtime.gd changes production behavior. Pair retention/reselection is explicitly scoped to reception and GP; exam/consult/outpatient selection policy is unchanged. The safe preparation-release helper is shared, with CLIN-16 covering the existing preparation cancellation contract. No work duration, price, qualifications, RNG, move engine or physical-envelope release rule was changed.

Tests use Godot 4.7.2 Linux headless with the documented POSIX native adapter. They do not establish Windows packaging, rendering, whole-game acceptance, or disk save/load behavior. Shared integration source and GitHub were not changed.
