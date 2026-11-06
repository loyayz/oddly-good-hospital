# Integer waiting-entry safety path (isolated Linux check)

```sh
python tests/native/entry_safety.py --output <new-directory>
python tests/native/entry_safety.py --control --output <new-directory>
python tests/native/entry_safety.py --targeted --output <new-directory>
python tests/native/entry_safety.py --check-only --output <new-directory>
python tests/native/entry_safety.py --prepare-only --output <new-directory>
```

The production `_waiting_point` passes its integer candidate directly to a
private safety helper and materializes an Array only for a complete route
fallback or a strictly better returned result. It does not change the order,
number, budget or tie handling of candidates. Public `safe_wait` retains its
existing Array API, fractional coordinates, preparation and call depth.

## Preconditions and safety guard

Only `_waiting_point` uses `_safe_wait_at`: `region()` already called `_ensure`
for this floor, and the actor and nonempty geometry are those of the same
synchronous, read-only enumeration. The helper must not become a general public
entry or hold data beyond that enumeration. It does not cache dynamic success.
The complete original tail still checks static geometry, then actual reservation
permission, then current dynamic bodies and accepted movement sweeps.
Reservation clearance is still created lazily through the original `read_view`.

The test rejects a helper whose entire safety tail differs from public
`safe_wait`, or a public entry which now calls the helper. This deliberate small
duplication avoids adding a call to every existing fractional public entry.
Changes to safety logic must update both copies and review these preconditions.
Complete `travel_quote` reads/serializes its target without mutating it or
retaining its Array identity; returned waiting cells remain fresh Arrays.

## Reference and scope

The runner extracts the **actual current scan, actual public safe_wait and actual
private helper**, rather than silently generating the rejected shared-helper
variant. By default its reference reverses only the private-path/Array change,
retaining unrelated cumulative improvements. Optional `--baseline-source <file>`
asserts this reference and the unchanged public entry exactly match an archived
pre-change `public_areas.gd`. Source and extracted SHA-256 values are recorded.

Explicit adapters supply region/containment, ordering, static geometry,
reservation checks, current bodies/sweeps and navigation results. The default
matrix has 540 scan inputs plus 20 public fractional inputs and 3,789 assertions:
results, ordered safety traces, clearance construction counts, field acquisition
and query counters; independent empty/first-success/fractional-coordinate checks.
`--check-only` runs these checks without timing. `--prepare-only` checks source
identities and writes the isolated project without starting Godot.

Normal timings use two ABBA cycles for packed/fallback 0/1/96/512 entry workloads.
`--control` compares current/current. `--targeted` runs longer ABBA and adjacent
current/current windows for the observed single-candidate and field outliers,
cold static rejection, cold success, cold failed routes and empty control; it
contains timing windows only, not additional correctness assertions.

These are wrapper and safety-chain measurements with declared adapters, **not**
full game, actual geometry, native index, cross-floor or real arrival acceptance.
No full-frame/FPS improvement or formal performance pass is asserted. The
separate older `entry_scan` test still adapts both safety entries and only checks
scan control flow.
