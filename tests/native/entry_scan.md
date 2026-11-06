# Waiting entry scan (isolated Linux check)

```
python tests/native/entry_scan.py --output <new-directory>
python tests/native/entry_scan.py --short --output <new-directory>
python tests/native/entry_scan.py --short --control --output <new-directory>
```

The baseline defaults to `35d656dc58c4f7afac8419218a12051d3617c47b`.
`--control` compares current/current; `--short` enlarges empty/single-candidate
windows. Normal timing uses two ABBA cycles per workload, 20,000 calls for small
or successful scans and 1,000 calls for larger scans; short windows use 50,000.

The production `_waiting_point` now snapshots the returned order's compact flag
and additive tick offset once per synchronous scan. An empty order returns the
same empty result before allocating the unused best/field dictionaries. The
order builder and all its counters still run. Candidate order, travel budget,
strict best replacement, safe-wait checks, field acquisition and route fallback
remain unchanged. No shared-cache lifetime, maximum candidate count or business
rule changes. Relevant contract: public-facility-area-use specification §3.1.

The harness extracts the **complete actual `_waiting_point`** from baseline and
working-tree source. Region, containment, safe-wait, ordered entries, view and
navigation outputs are explicit adapters, not a fake full-game benchmark. It
covers 360 input combinations / 1,728 assertions: 0/1/8/96/512 entries; packed and
fallback (including missing `offset_ticks`); absent/current region; unsafe,
failed, successful and resident-field paths; zero/nonzero prefix and budget
boundaries. Results, safe-wait calls, field acquisition calls and counters must
match; independent empty/current-position/first-success checks also run.

This measures only the entry-scan wrapper with adapted dependencies. It does
**not** validate native ordering, geometry, AStar, cross-floor integration or
real arrival; it is not a SPACE acceptance pass or full game/frame performance
claim. Timing noise is recorded through current/current controls, and no formal
performance acceptance is asserted (`formal_pass=false`).

The integer private safety entry is also an explicit safe-wait adapter in this
older wrapper-only harness. `entry_safety.py` separately extracts the actual
public and private safety bodies and guards their identical safety tails.
