# Cached floor-path packing isolation

Run `python3 -B tests/native/path_cache_codec.py --output <new directory>`.

The runner extracts the complete production `cached_floor_path()` without
rewriting it. Godot owns actual dictionaries, packed integer arrays, deep copies,
Variant serialization and capacity arithmetic. Explicit input adapters supply a
world, a fixed graph result, graph identity/source and no-op budget trimming.
This is not a search, reservation, graph invalidation, eviction policy or complete
SPACE-51 integration test.

Checks cover every bounded 96×96 cell ID, cost-only records upgraded to full
paths, cold builds, cache hits, failure caching, unavailable-cache fallback,
returned nested-array ownership and unchanged cache charges/counts. Original
SPACE-51 checks remain responsible for real graph/query ownership and eviction.

The benchmark alternates twelve A-B-B-A windows for zero/32/192 cell results,
with 1,000 calls per window. Empty results are an unaffected control. Each hit
reconstructs a caller-owned nested array; each miss includes the adapter's
result copy and the production cache packing/charging. Retain all windows,
including regressions. These timings describe local representation work only;
actual hospital hit rates, path lengths and complete-step gains are unknown.
