# Reservation mask helper isolation

Run `python3 -B tests/native/reservation_mask.py --output <new-directory>`.
The tool extracts the complete production `_mark_reservation_mask` function
unchanged and compares it with the baseline commit (default `35d656dc`).
Only the fixed floor-side/ID definition is supplied locally. Rectangle overlap
uses the real Godot `Rect2` predicate, not a geometry mock.

Independent expected masks scan every grid origin. Cases include bodies of
size 1/2/3/8, integer/fractional/negative offsets, out-of-grid rectangles,
overlapping regions, empty/zero-area regions and existing set bits. The
independent oracle deliberately does not use the production candidate bounds.

Each of the empty and 1/8/32-cell region workloads has twelve A-B-B-A windows,
with 500 complete helper calls per window, including fresh mask duplication.
All windows and source hashes are retained. This measures mask generation,
not the frequency of its use, permissions, group construction, native distance
fields, complete SPACE-51 or whole-game performance.
