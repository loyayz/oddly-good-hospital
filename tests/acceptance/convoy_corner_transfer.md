# Convoy local-corner transfer regression

Run `convoy_corner_transfer.gd` with four arguments: result JSON, comma-separated `probe,journey,restore`, real transfer boundary BIN, and real pre-turn corner BIN. The CLIN-29 repair evidence archive includes both immutable inputs and their hashes. Inputs come from the unchanged real CLIN-29 guidance/diagnostic/treatment sequence, not authored completion facts.

- `probe`: legal pre-turn corner at leader [51,78], tail [53,78], original next waypoint [51,79], fixed round doctor [51,79]. Verify current doctor outside the first 0.2 movement step but inside one-width turn is detected read-only. Separate query-only clones test next-corner bound, exact outer-edge touch, beyond-range body, unchanged straight and single-actor paths. Query-only obstacle positions are not used for either real journey.
- `journey`: begin before actual outpatient-to-transfer handoff. Run every production clinical phase in the existing clinical harness and each real 0.1-second movement until recovery begins. No actor or facility repositioning. Check body overlap, full world validation, fixed room/facility geometry, unchanged blocking clinician, one leader movement permission per tick, speed bound, same group/goal/order and no recovery work before bed arrival.
- `restore`: same real trip, reopen full frozen facts during the actually moving local detour, reconstruct services and continue. The restored trail is never edited.

The original `CLIN-29` separately tests the complete 1800 real recovery steps, bedside care/round and exact final settlement. These tests do not replace its assertions or claim all traffic deadlocks are solved.
