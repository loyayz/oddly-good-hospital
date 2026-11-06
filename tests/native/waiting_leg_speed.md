# Waiting leg speed reuse (isolated Linux check)

`python tests/native/waiting_leg_speed.py --output <new-directory>`

`--control` runs current/current under the same alternating window order. Default
baseline is `35d656dc58c4f7afac8419218a12051d3617c47b`.

The production `_waiting_cost_basis` already resolves speed for the sealed
single-actor candidate enumeration. Successful `waiting_travel_ticks` now uses
that speed just as the ready-field branch does, instead of rebuilding the body
key and resolving clearance/content for every successful leg. Arithmetic order,
ceil and overflow-aware addition are unchanged; failures and unsupported
contexts keep their existing branches. No cache lifetime or graph behavior is
changed.

The harness extracts actual `waiting_travel_ticks`, `_waiting_cost_basis`,
`walking_ticks`, `_add`, `body`, and `clearance`. Explicit adapters provide floor
route results, subject preparation, world/content inputs and read views. It
checks two body sizes, four speeds, eight distances, successful/failed legs,
prefix overflow, unique-lift quote proof versus mismatched/unknown proof, and
unscoped/multi-connector fallbacks. Cold windows rebuild the basis each call;
warm windows reuse it. Windows preserve returned sums and the correctness
checks compare route-call and query counts.

This measures **quote-wrapper overhead only**, with no AStar or full navigation
cost. It is not a SPACE/STAFF acceptance result, a full game performance claim,
or evidence that existing Windows-only extension / Godot-version blockers are
resolved. Formal performance acceptance remains unpassed.
