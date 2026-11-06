# Optional waiting chairs: exact-method contract checks

Run against the current source with a new output directory:

```sh
python3 -B tests/native/waiting_seat_arrival.py --output /tmp/waiting-seat-contract --godot /path/to/godot
```

The harness extracts the actual seat dispatcher, claim, actual-seated predicate, public turn check, anger sampling and cause-clock methods. It checks first-arrival eligibility, actual-position/no-remote-claim boundaries, occupied and failed-reservation atomicity, the existing five-second retry cadence, new-area arrival, failed movement requests and the existing 15-second no-seat anger boundary. Toilet FIFO and life-service absence remain separate.

World, route/geometry, movement, reservation and personality lookup are explicit test adapters. The balance data is copied from the current source. This is not real movement, collision, full-game or performance acceptance. Results contain engine identity and production-source hashes; `formal_pass` stays false.

Real-movement acceptance remains in the official runner. Select affected cases rather than the full suite:

```powershell
pwsh -NoProfile -File tests/run-acceptance.ps1 -Case 'STAFF-29,STAFF-31,STAFF-45,STAFF-46,STAFF-47,STAFF-48,STAFF-50,STAFF-51,STAFF-57,STAFF-62,STAFF-64,STAFF-69,STAFF-70,STAFF-72'
```

STAFF-48 includes an earlier far-away request and a later nearby request competing through real movement for the same chair. STAFF-69 checks standing in an occupied area, no failed-seat subscriptions, retries at the existing scan boundary, the no-seat reaction and real release followed by actual use. Its former seat-FIFO/failed-result-cache expectations are superseded by the explicit first-physical-arrival rule; they must not be described as preserved behavior.
