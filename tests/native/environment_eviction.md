# Environment coverage eviction isolation

Run `python3 -B tests/native/environment_eviction.py --output <new directory>`.
The runner extracts the exact `HospitalEnvironment.end_query()` body from the
working tree and baseline commit into otherwise minimal service holders. No
Dictionary operations are mocked. It tests nested scope completion, absent floor
cache entries, unrelated floors, overlap without overwrite, ordered retention,
and the original 128-result capacity against independent expected keys/values.

The measured operation is only scope completion. Twelve A-B-B-A windows for each
128/129/256/640-key merged cache use 300 calls, with fixture construction outside
the timed interval. These are explicit overflow stress inputs, not a claim about
normal hospital workload frequency. The optimization replaces repeated complete
`keys()` allocations during eviction with one snapshot of the same insertion
order. It does not change source invalidation, coverage values, cache capacity,
or ownership. No full environment, native coverage, whole-step, or FPS result is
implied. Existing OPS-11 environment coverage checks now also assert retention
order but still require the matching complete project environment.
