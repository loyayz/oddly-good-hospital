# Door reservation lifecycle: selected regression cases

Rule sources: `docs/specs/26-11/2026-11-05-convoy-following.md`, `docs/specs/26-11/2026-11-06-convoy-validation.md`, and the original-envelope restore contract in `WorldState.validate`.

A held door retains its original owner, participants, opening and convoy envelope until physical release. A different current journey does not erase that obligation. A former participant can depart through the held opening without replacing its reservation. Every member of a current movement must already have permission, and its required span, width and height must fit the held opening exactly. Facility/support permissions are unchanged. Original participant bodies and all their authorized current convoy ground trails prevent premature release. Formation inside a doorway remains refused.

Run only named cases. The first argument is an output prefix outside the source tree; the second is a comma-separated selection. Unknown cases or missing selection are rejected.

```
godot --headless --path . --script res://tests/acceptance/convoy_door_lifecycle.gd -- /tmp/door-lifecycle normal_three_straight,cancel_then_new_singleton,cancel_then_follower_exit
```

Selectable cases:

- `normal_three_straight`: three actual bodies, independent retained-history oracle, original record and complete tail release.
- `normal_three_corner`: the same with actual turns and whole trail retention.
- `mixed_large_reverse`: S49/S59 reverse crossing, size-5/span-6 opening and shared leader movement budget.
- `cancel_then_new_singleton`: cancel at the actual tick-22 boundary, start a new owner singleton, retain the still-overlapping old participant, then actually depart and release.
- `cancel_then_follower_exit`: the same boundary with normal independent owner/member departures, proving the old permission permits actual departure.
- `cancel_restart_same_group`: the safe doorway formation refusal remains atomic.
- `mixed_cancel_exit`: cancel while the giant former participant overlaps; retain original owner, members, span and envelope during its independent departure.
- `permissions`: original participants are allowed; actual outsider and new group containing the old owner plus an outsider are denied without a physical blocker masking the reservation. The test executes generated route segments with the real fixed-step movement function to capture denial before courtesy/detour bookkeeping. No paths, actor positions or completions are fabricated.
- `authorized_regroup_tail`: an authorized subgroup changes leader after cancellation. Actual original participants clear, but the new leader's live trail still holds the original door with no physical body inside; only later full clearance releases it.
- `atomic_acquisition`: isolated admission calculation for a two-door bundle. A held foreign second door rejects the whole bundle without publishing the first. This is not a physical two-door crossing or a claim about single-body contact/acquisition phase ordering.
- `held_fit_boundary`: exact held-opening admission calculations. Equal dimensions succeed unchanged; a width or height excess of 0.0000005 is rejected unchanged. These proxy calculations are not fabricated actor facts or a claim of physical crossing.
- `serialized_obligations`: typed JSON stream round-trip; nonexistent participant identities, changed physical opening and insufficient envelope mutations are rejected read-only. Integer/float region equivalents, duplicate authorized staff entries, an owner not repeated in staff_ids, and an empty staff list for a genuine single-owner door remain valid; each valid form is restored into a fresh runtime and actually departs before release.

Cancelled-departure cases restore through the production typed JSON stream into a fresh simulation and continue actual fixed 0.1-second movement. Normal and departure flows check body separation, movement budgets and world validation. Traces, input/final facts, restore bytes and results are saved under the caller's unique prefix. Existing red reproductions remain separate and immutable.

This is a focused lifecycle regression entrypoint, not a full movement, transit, clinical or performance suite. Related transit/clinical handoffs must be selected independently when the shared paths change. Single-body contact/acquisition ordering and facility permissions are outside the repair.
