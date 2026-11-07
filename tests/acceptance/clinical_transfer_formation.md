# Transfer formation at a blocked bedside

## Rule and handoff

A clinical transfer is a front-to-back queue. Its patient remains the leader; the nurse first walks to a reachable gathering position. Only after actual assembly may the ordinary convoy movement begin. Movement still uses the leader's complete envelope and protected trail, never independent follower movement permissions. Initial gathering must not place the tail through a wall, furniture or a doorway.

The previous formation helper picked the first travel segment's heading and blindly placed the nurse behind the patient. At the recorded legal bedside `[46,69]`, the eastward route to `[50,69]` put the nurse at `[44,69]`, beyond the ward wall. The helper returned success although the nurse could never reach that cell. The original source and the staff-release candidate produced identical read-only results; this was a pre-existing formation defect.

The repaired helper prefers the travel heading, then checks the other cardinal alignments at the patient's unchanged real position. Each candidate must have a legal full initial trail outside doorways, a reachable gathering cell, and a route computed from that specific proposed trail. These are read-only projections. Actual actors are not moved by planning. There is no global search for arbitrary assembly sites or new traffic-priority rule.

For the recorded case, the legal queue faces west: the patient stays at `[46,69]`, the nurse walks to `[48,69]`. The leader then follows the ordinary safe route through `[46,70]` and along the aisle to the destination. Both actors genuinely move; no pose is reassigned to bypass gathering or transit.

The transport quote reuses the same successful gathering quote and includes the route of the selected formation. Existing source-bed release, final independent bedside handoff, recovery work, receipts and fees retain their owners.

## Selected tests

Run `clinical_transfer_formation.gd` with an absolute output JSON path, a comma-separated selection, and the recorded real `.bin` boundary:

- `geometry`: the original eastward tail is rejected, a legal west-facing queue is found, the nurse can reach it, and successful and rejected queries leave complete world facts unchanged.
- `journey`: continue the real blocked snapshot through the full simulation. Observe the nurse at the gathering cell before the group moves, the actual convoy, bounded leader movement, no actor overlaps, valid world state each step, and completed bedside handoff without spending recovery work during transfer.
- `restore`: the same real flow, with a complete saved-world reconstruction during the convoy.

The binary input in the evidence archive was produced by the actual `clinical_transfer_bed` command and 100 full simulation steps. Its generating and read-only probe, original-source comparison, exact hash and source identities are retained. It is a boundary input, not a replacement for the tested walking or handoff.

Related regression: `CLIN-25` from freshly built prerequisites (outward transfer, return to the original bed, progress/care preservation, no duplicate wear or fees), `CLIN-20` (surgery-to-bed handoff), `CLIN-28` (ward restoration boundaries), and `clinical_convoy.gd` (quote accounting, actual bedside arrival, malformed-state rejection and equivalent final facts after restore).

## Observed result and scope

All three new selected cases passed. The original stuck snapshot completed the real handoff in 54 simulation steps, with or without restoration. `CLIN-25`, `CLIN-20`, `CLIN-28`, and both existing clinical-convoy continuations passed. All runs used pinned Godot 4.7.2 and the real Linux native backend.

This is targeted clinical formation/transport evidence, not a full-game, dense-traffic performance, Windows-build or rendering acceptance claim. Only the clinical formation helper, its read-only gathering result consumer and new tests/docs changed. The separate clinical staff-release repair is retained unchanged.
