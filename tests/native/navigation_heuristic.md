# Navigation heuristic isolation

Run `python3 -B tests/native/navigation_heuristic.py --output <new-directory>`.

The tool extracts the exact production `_estimate_cost` and `_cell` functions
from the requested baseline and working tree, and subclasses real Godot
`AStar2D`. It checks 200,000 fixed-seed endpoint pairs against independently
constructed Manhattan distances, then compares 200 complete engine paths on an
explicit 96×96 graph with a barrier and openings. All IDs have the same bounded
range as the production floor graph. No search implementation or cost callback
is mocked.

It retains twelve A-B-B-A windows for 102,400 helper calls each, and twelve
windows for 200 actual engine searches each. The setup and initial equivalence
queries warm both graphs before measurement. Raw windows, checksums, engine and
source hashes are saved. This is a synthetic graph experiment, not a whole-game
benchmark: graph creation, reservation filtering, bodies, permissions, transit,
cache lifetimes and complete `HospitalNavigation` are outside the test scope.
The existing SPACE-51 navigation integration still needs the full environment.

The production change only removes two temporary cell vectors and helper calls
from an otherwise identical integer Manhattan heuristic; Godot retains search,
point ordering, edge costs and tie handling.
