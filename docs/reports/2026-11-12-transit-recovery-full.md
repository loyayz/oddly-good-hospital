# Full mixed160 window after transit recovery fix

One new uninstrumented full window is complete. **The fix changes real progression, but the benchmark still fails acceptance and the specifically commanded maintenance worker has not reached its job. Accepted repeats remain0/3.** No further full history, repetitions2/3, Release/GPU or two-hour tests were run.

## Identity and unchanged protocol

At execution, this run used Git base `63b0c38fb68a450d12b01279805f7e860e15b419` plus the then-uncommitted, scoped [transit recovery fix](2026-11-12-transit-recovery-fix.md). The exact working-tree patch is archived and was subsequently committed as `5971377`, without further production changes. Production `hospital_transit.gd` SHA256 is `2ead5adfdcd4be9c2530a0b3f6a20ba4bdf11b64616b4457a540a3b643489d73`; `hospital_movement.gd` remains `fd9d720d6c7688eff475bb15968c64a3e4fcdeb0a2acb8878c00619e1e556ca4`.

The complete original mixed input is `75f5e1d922f39f12382c0ceb74806bda0293251189f68a1ac158842f65fa78ca`. Neither the previous final World nor the older v3 input was substituted. Exactly1000 real prefix steps and6000 measured steps execute tick633→7633 with the original0.1s step, app main-thread policy, four environmental tasks, `OMP_NUM_THREADS=1`, observed floor1, all original actors/candidates/commands and unchanged observer/coverage gates. No diagnostic hooks or stage timers were added to plain production.

The isolated workspace is `C:\Users\cong\dot-work\ogh-recovery-full-20261112`. The previously verified imports, bridge `ab025d4367b7a13264f8a33cfefa5c177e19f591cc62cf36c1ca01d0e805249b`, four dependencies and Godot4.7.2 were reused without rebuild/import or repeated local tests. Console/actual engine hashes remain `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643` and `ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`. The manifest contains2405 source entries (2403 tracked plus the two new recovery test sources), complete runtime hashes and exact process argv/environment. Engine work remained serial and used isolated profiles.

## Plain performance and density

| Scope | Samples | P95 ms | P99 ms | Maximum ms | Speed ratio |
| --- | ---: | ---: | ---: | ---: | ---: |
| All measured steps | 6000 | 68.967 | 82.703 | 300.642 | 1.881224× |
| Continuous dense interval, tick1634–6616 | 4983 | 70.320 | 85.018 | 300.642 | 1.801425× |

The original P95≤10ms, P99≤15ms and maximum≤30ms gates all fail, in both scopes. Speed≥0.99× and at least1000 continuous samples with144 real present actors pass. Whole-window population is minimum121, median159, maximum167; dense population is144/160/167. The1017 later low-population samples are not used to hide the dense interval. Final actual population121 consists of82 patients,32 staff and7 correctly owned contractors; there are no unclassified actors.

Prefix wall64.929163s; measured wall318.941297s; complete simulation loop383.870460s; whole process389.143310s. Production steps sum283.730341s, and observation/logging/loop account for35.210956s. The first measured step is the300.642ms maximum and includes the original legal operating commands.

The previous current-code window had64.470/76.127/280.600ms,308.658929s measured wall, and6000 dense samples. This new result is not a latency improvement claim. Population, actual transport, departures and service progression changed, so these two single windows do not isolate runtime noise or prove a pure CPU regression/optimization percentage. The functional recovery fix must not be described as overall performance acceptance.

## Complete execution versus failed acceptance

All7000 ordered enter/complete records, exact tick sequence, source/input/runtime stability and complete final binary hash passed independent checks. P95/P99/maximum were independently recomputed. World validation has no reported error. The engine returned1 after completing the full window because the original benchmark contract failed, not because sampling was interrupted.

Activity coverage remains29/31. Missing gates are `upgrade=0` and `effective_ward_visit=0`. The observer also retains exactly one command-acceptance invariant failure: at tick1633, `comprehensive160-v3-upgrade` is rejected with `maintenance_unavailable` / `缺少真实合法维修操作位`. There is no final UpgradeOrder. This is not promoted to a coverage-qualified witness; shared strict validators and gates were not changed. The prior run's separate command-boundary capture established a live protected service reservation for the same rejection, but no new full-history causality trace is claimed for this run.

Measured activity includes examination342ticks/2 completions, original-doctor review257ticks/4 completions, outpatient3603ticks/15 completions, GP127ticks/1 completion, surgery1165ticks/1 completion, wake149ticks/1 completion, care76ticks/1 completion, recovery1798ticks and one surgical ward return. Eleven new Attempts and58 real patient departures occurred (9 cured,49 abandoned). Transport work is1420ticks, versus601 previously; research completes once. Two companion ward entries are not effective ward visitation. Full work/event/coverage tables remain in the raw result and summary.

## Specifically commanded maintenance, not aggregate coverage

Only a no-step binary inspection followed the plain process. It decodes the complete final World/ordered events and exports owner facts without creating a Simulation, executing a command, querying services or advancing any step. The binary's hash was checked again after reading.

The target remains `maintenance_00000222`, facility `bench_room_2_12_0`, worker `maintenance_contractor_00000226`:

- Created tick1633; final phase `travelling`, `started=false`, `completed_milli=0`, `remaining_milli=20000`, `paid_parts=0`, empty contributions and no completion receipt.
- Worker is actually on1F at `[85.3999481201172,44]`, still owned by job222 and original request629, with no transit ticket.
- Its final route now begins with ordinary ground return to `[86,44]`, then the1→2 connector; cursor0. A local retreat has origin `[85,44]`, target `[88,44]`, and original rejoin `[86,44]` at index0. Goal remains2F `[5,72]`.
- The final lift is trip147, patient0111 alighting4→1, ticket_next156. The earlier trip63/patient0118 final no longer describes this outcome.

This is a changed ground-recovery/local-movement state rather than the prior unchanged off-landing connector state. It is **not** proof of target arrival, service work, a permanent deadlock or an identical-state loop. The plain observer does not provide every movement branch or chronological MotionResult. No additional waiting window or new patch was used to force a conclusion.

The aggregate43800ms maintenance gate comes from other jobs: automatic repair188/worker189 completes30000ms with a real receipt at tick2519; automatic repair405/worker406 has13800ms completed and10200ms remaining, phaseworking,25 parts paid. Target222 contributes zero. In the previous run, the aggregate instead consisted of two other completed repairs; aggregate counters cannot substitute for tracking this target.

## Outcome and evidence

The new complete World/RNG/ordered-events SHA256 is `876e2502aa2f7b853f94aa50a9d0fe02a2bff68ce3cab6a4666ce3cef2ec6c58`. No equality to the old final was required after a real movement fix. The scope ends at this full result and no-step owner inspection. Further worker diagnosis, if selected, should start at this exact final local-return/collision boundary rather than reuse old trip identities or launch a blind full-history repeat.

[Summary](evidence/2026-11-12-transit-recovery-full/summary.json), [raw archive](evidence/2026-11-12-transit-recovery-full/evidence.zip), and [manifest](evidence/2026-11-12-transit-recovery-full/manifest.json) preserve original input, full final binary, ordered steps/events, commands/exits/time, exact working-tree production patch, source/runtime identities and no-step owner export. All ZIP member SHA256 values and CRCs were read back. Archive SHA256: `bd6ba1405b43ba18909df3b8e21a0dae8504306bcb078854319773b920a16c5c`.

The original `C:\code\loyayz\oddly-good-hospital` remains untouched. Existing evidence is preserved. This validation added only its report/evidence; no production edit, commit or push was made.
