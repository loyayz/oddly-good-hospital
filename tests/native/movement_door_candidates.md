# Empty door-candidate projection

Run `python3 -B tests/native/movement_door_candidates.py --output <new directory>`.
The tool extracts the complete production `movement_doors()` from the baseline
and working tree without rewriting its body. Explicit inputs supply the floor
version, body clearance, broadphase candidates and current reservation regions.
Those adapters do not prove native spatial indexing, expansion geometry, door
permissions or complete movement behavior.

Independent expected output and baseline comparison cover empty floors, default
and explicit floors, duplicate candidate/reservation IDs, non-door reservations,
unknown reservation doors, original floor order, counters, unchanged facts and a
version-triggered view rebuild. All candidate and reservation queries still run
on the empty-result path; only sorting and projection of an empty union are
skipped. SPACE-56/57 integration remains necessary in the complete project.

Measurements retain 12 A-B-B-A windows per candidate count (0, 1, 4 and 32), each
with 20,000 calls after warmup. Zero-candidate inputs represent the ordinary
GP867 diagnosis's 112 queries with no doors, not every legal hospital layout.
Nonempty controls and slower windows must remain in the result. Local time does
not include actual native query work and cannot be extrapolated to the reported
2ms door-query stage or whole-step performance.
