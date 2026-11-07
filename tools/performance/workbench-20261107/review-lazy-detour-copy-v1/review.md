# Lazy detour actor copy: independent static review

## Decision

The narrowly proposed change is statically supported: replace the eager private `actor.duplicate(true)` with a not-yet-created private sample, compute the initial rectangle from the original actor at the same point, and create a deep sample immediately before its first facing write. This is not approval of an unseen patch, executed functionality, or performance improvement.

The original method has one sample allocation, exactly two writes (`sample.facing`) and three rectangle reads. It never writes sample location, id, body binding or nested facts. There is no asynchronous boundary. Before the first write, the relevant actor values are unchanged by the intervening production predicates. The first write overwrites facing before any later rectangle read, so delaying its initial copy does not omit an input needed by that read.

## Required boundaries

- Keep `space._ensure_actor_index`, structural query creation, convoy trial copy, origin, initial `previous`, members and all existing proof operations in their original order. Only allocation timing changes.
- `_actor_rect` is **not globally pure**: it maintains `_actor_shapes`, `_envelope_next`, and the body cache. It is read-only with respect to its actor argument. Compute the initial rectangle at its old point even if a failed segment is about to return. Using the real actor instead of its deep copy preserves the scalar inputs and cache effects; do not skip the call.
- For a nonempty proof, create the sample before assigning facing and calculating `next_rect`/`proof_key`, even when a sweep cache hit subsequently avoids structural/contact work. Moving the copy to a later sweep miss is invalid because an earlier write would alias the real actor or an uninitialized sample.
- With empty proof and no convoy, retain the existing structural sweep rejection before sample creation/facing/rectangle. A rejection can avoid the allocation because sample has not otherwise been used beyond the preserved initial rectangle.
- Normal convoy calls use empty proof and the private trial's rectangles. Their actor sample is unused; eliminating it must not eliminate trial/proxy work or leader/follower/trail/contact checks. Do not change behavior for any branch merely because the normal caller would not take it.
- Retain a deep, private sample. A raw alias followed by `sample.facing=...` mutates world actor facts. Do not introduce a shallow copy or shared cross-call sample as part of this change.
- `body()`/`actor_body()` read id/species/binding/posture/body dimensions, and `_actor_rect` stores computed scalar geometry, not the input actor. There is no actor-reference identity test in the reviewed rectangle path. Mutable custom test doubles are not the production contract; existing CountingSpace only increments a counter then calls the original method.

## Minimal executable equivalence gates

Use independent old/new service instances with equivalent worlds and relevant runtime cache state, not two calls sharing a cache that hides the first path. Preserve the original implementation as an oracle in a test-only file; requirements remain the business authority. Capture complete original actor/world/RNG/movement before and after every read-only call, booleans, exact chosen links, proof entries/terminal rectangles and actual predicate-call traces.

1. Empty path, zero/sub-0.001 legs, diagonal rejection, and already-proven negative segment. Nonconvoy initial rectangle must still occur once; no sample copy should be necessary for these early exits. Obtain proof failures from real queries rather than inventing fake safety approvals.
2. Proven positive segment(s) followed by an uncached turn, including multiple directions and a near-axis end within tolerance. `origin` and `previous` must come from the exact saved terminal proof, with unchanged continuation and sample initialization.
3. Positive and negative quarter-sweep hits for non-square/lying or symptom-bound bodies, changed facing, and near-axis exact-key cases. Actor facing must remain unchanged, while next rectangle, cache keys and actual hit/rejection decisions match. A sweep hit still needs the rectangle/facing preparation.
4. Empty proof with null and prebuilt queries: static rejection before copy, legal static but dynamic rejection after copy, and successful turn. All original safety predicates still execute when required; no position/facing/ownership mutation.
5. Convoy bypass and reverse/tail rejection with real trial/propose state. Trial and world remain unmodified by proof; leader proxy/trail checks are retained. Existing focused `detour_step_proof.convoy_bypass` and movement-detour tail cases cover this boundary.

Reuse focused `detour_segment_proof` positive_negative_and_selection, exact_segment_keys, terminal_tolerance and zero_length_legs plus focused `detour_step_proof` exact_rectangle_keys, same_tick_dynamic_boundaries and convoy_bypass as appropriate. No whole-game regression is implied. The unchanged proof cap/lifetime is still checked where existing focused fixtures traverse those boundaries, not expanded into a new cache policy.

After a candidate exists, independently inspect the exact diff and execute affected functional gates first. The fixed 800-step window must preserve the preregistered complete facts/RNG/events check. Copy-count instrumentation is diagnostic only; its timing cannot establish speedup. Only the separately preregistered uninstrumented matched B series, with all A records retained, can support the limited performance claim. No formal load, collision, personality or clinical work may be reduced.

## Verification limits

No engine, test suite or benchmark was run by this review. No repository source was edited. Input files and static method counts are recorded. The actual candidate patch and its runtime checks were not yet available at this review's cutoff.
