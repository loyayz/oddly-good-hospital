# Local furniture-corner continuity

## Rule and handoff

A person must really reach the original destination without moving stationary people, replacing the journey, or dispatching a second global route. Local connectors must remain continuous when a later obstacle no longer intersects the person's immediate neighborhood. Only physically reaching an original-route rejoin earns original cursor progress. Restoring a save midturn must preserve completion and all safety checks.

This focused movement regression starts at legal input worlds built by `space.gd._fixture()`. It adds ordinary FUR05 desks and S49 people before requesting movement. It does not teleport a tested actor, advance nonstandard time steps, fabricate arrival, or drive movement through a test pathfinder. The observer only calls through to production and records accepted connector observations.

## Selection

- `LOCAL-CORNER-WIDE`: desks at [42,69] and [42,71], both 2×1; stationary person [44,70]; walker [40,70] to [48,70]. A four-leg return around the desks must finish, followed by the original destination.
- `LOCAL-CORNER-LOST`: additionally a rotated 1×2 desk at [44,71] and stationary people [40,70], [41,69]; walker starts [41,70]. The independent feasible connector is [41,70] → [41,73] → [45,73] → [45,70]. Its later desk intersects the body's one-width neighborhood at the connector's starting position but not at the first corner. The test requires the actual first corner to be reached and eventual arrival, not merely finding a hypothetical connector.

Both cases check real body and swept-body safety against every person and desk each tick, real walking budget, unchanged complete stationary actors, exact original target/request sequence/path, cursor progress only on a physically swept rejoin, exactly one initial route dispatch, and no new dispatch after cold restoration. A real midturn snapshot is JSON-stream encoded/decoded into a fresh WorldState and HospitalSimulation, then run to completion. Malformed corner chains are checked independently from a valid live snapshot: more than two corners, another floor, a diagonal leg, no rejoin, repeated/reversing corners, and an out-of-range original rejoin index must be rejected.

## Run

From the repository root:

```
XDG_DATA_HOME=<unique-data> XDG_CONFIG_HOME=<unique-config> XDG_CACHE_HOME=<unique-cache> \
  /workspace/scratch/6962cc21ddf3/movement-handoff-v1/runtime/Godot_v4.7.2-stable_linux.x86_64 \
  --headless --path . --script tests/acceptance/local_obstacle_corners_runner.gd \
  -- <output.json> LOCAL-CORNER-WIDE LOCAL-CORNER-LOST
```

## Initial counterexample

The first-corner-only prototype passed WIDE, including full cold continuation. LOST failed to arrive after 350 real ticks both warm and cold. Its independent four-leg connector was clear; the second desk was present in the initial neighborhood and absent at the actually reached first corner. Movement repeatedly returned toward the stationary blocker instead of continuing around the desk, approximately every 25 ticks. Safety, original journey, stationary actors, and single initial dispatch remained intact. The expectation remains arrival; the failure is not reclassified as acceptable waiting.

Initial red evidence: `/workspace/scratch/6962cc21ddf3/clinical-chain-evidence/corner_tests/final.json` and `final.log`.

The separately checked existing `unified_local_behavior` furniture/entrance case also fails on original HEAD. It is a preexisting counterexample, not evidence of a new regression; see the isolated HEAD control artifacts in the same evidence directory. These focused tests do not claim whole-game or whole-suite coverage.

## Continuity fix check

After retaining the remaining intermediate corners, both cases reached the original destination warm and cold, with every safety and journey invariant satisfied. The first post-fix run found one validator gap: a duplicated remaining intermediate corner was accepted. The other six malformed-save mutations were rejected. Evidence: `corner_tests/continuity.json`. This result is intentionally not reported as a full pass until the duplicate-corner validation is corrected and the affected checks rerun.

The clean isolated HEAD control is `corner_tests/control-unified-clean.json` and `.log`; its movement source was restored using `git show HEAD:game/building/hospital_movement.gd` without editing the active checkout.

## Final affected verification

The corrected validator and connector passed both selected cases, including complete warm/cold arrival and all seven malformed-save rejections. Real rejoin, original route/sequence/goal, stationary actors, body/sweep safety, and dispatch limits all passed. LOST independently witnessed the later desk leaving the neighborhood at the actually reached first corner.

- Result: `corner_tests/verified.json`, process exit 0; clean log `verified.log`.
- Source/runtime identities: `corner_tests/verified.sha256`.
- Measured fixture preparation: WIDE 12 ms, LOST 4 ms. Test execution including cold continuation and malformed-save probes: WIDE 356 ms, LOST 485 ms. These are functional-run timings, not performance claims.
- Scope: only the two selected movement regressions and their restore/validation boundaries. No production files were edited by this test task; no commit or publication was performed.
