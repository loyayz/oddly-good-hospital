# Worker transport handoff: bounded current-state diagnosis

## Result and stopping boundary

No new business defect is established, so no production fix or extra regression suite was run. The two workers have not reached their work sites. The next observed blocker is trip40's real alighting attempt, not a missing maintenance payment or an invented queue priority.

Two serial 64-step continuations preserve the complete production world from tick7641 to7705 to7769. Each continuation was independently repeated once with read-only branch instrumentation; complete World, RNG and ordered-event binary outputs match its plain run byte-for-byte. This is128 logical continuation steps,256 executed steps including observer qualification, not historical or performance sampling. Stop here; no full7000-step, Release/GPU, performance-window or two-hour acceptance was started.

## Actual ownership and transitions

- At tick7670 the empty lift reaches4F and enters idle. Patient0119 then boards in the same movement phase before either worker's `HospitalTransit.begin` call. Trip40 retains its existing ticket40. The workers never observe an idle lift in their256 recorded begin calls across these128 steps.
- Patient0051 physically reaches the4F landing and receives ticket44 at7675. The lift enters riding at7685 and alighting at7715 for trip40,4F→1F.
- There are39 actual alight attempts from7730 through7768. Every attempt takes the `egress_clear_false` branch and keeps patient0119 in transit. Independent complete-body geometry intersects patient0018 with the exit region on every attempt. This observer does not identify the internal `_dynamic_clear` return branch, so body intersection must not be confused with a recorded index/reservation/sweep branch.
- Patient0018 is the passenger released by the earlier fix. It now has real local motion:41 floor-displacement steps in the second64-step continuation, with original request16351 and route cursor3 retained. It revisits the landing while pursuing different original-route rejoin points. This is not the previously fixed zero-motion alternating-heading loop, and the present evidence does not prove a new local-motion defect.
- Workers238/239 remain at[88,44]/[85,44], floor1, with requests669/670 and owners maintenance_00000233/upgrade_00000234. Every recorded begin call has `at_entry=false`; neither gets a ticket or queues landing recovery. Their original job targets remain floor2,[5,72]/[71,72]. Both jobs remain travelling, started=false, completed work0, remaining20000/30000 milli-units respectively. The upgrade's original420 payment remains; no new charge or work was invented.

## Why the workers currently wait

`HospitalTransit.begin` computes actual landing presence first. A ticket requires actual landing presence. While the connection is not idle, it may request stand-aside for an incoming trip but returns before the non-entry landing-recovery branch. These two workers are not at the exact anchor[86,44], so `_stand_aside` returns without committing a waypoint. The only observed idle transition was consumed by the legitimate already-ticketed patient0119 before their turn. Therefore this bounded trace contains no eligible idle opportunity at which worker recovery can be judged.

Their complete saved paths explain why a connector segment can be current away from the anchor: worker238 starts `[87,44] → [88,44] → connector1→2`, cursor2; worker239 starts `[85,44] → connector1→2`, cursor1. The last recorded travelled checkpoints match those real floor endpoints. `queue_waypoint` explicitly saves the original remainder and route dispatch appends it after the temporary floor path; transit later owns landing recovery. This shape is consistent with that temporary-waypoint handoff. The actual historical creation call was not traced, so its provenance is not asserted. Neither the shape nor the current cursor proves an illegally skipped landing.

## Follow-on capture and current stopping boundary

The proposed eight-step capture below was subsequently completed from the exact tick7769 input. See the qualified results following that proposal.

### Initial next-step proposal

Use the complete tick7769 output as a read-only continuation input. First inspect patient0018's local-resume/contact/rejoin branches statically. If execution is needed, record1–8 actual full-world steps with its real MotionResult, collision ownership and the exact `_dynamic_clear` rejection branch for patient0119. Qualify a new observer against a plain run at the same boundary. Do not run farther merely to wait for maintenance completion. A later eligible idle boundary is required to judge the workers' landing recovery; a new business patch requires a reproducible violation and affected-interface cases first.

## Evidence and limitations

[Manifest](evidence/2026-11-12-worker-handoff/manifest.json) records input/output identities and source restoration. [Evidence archive](evidence/2026-11-12-worker-handoff/evidence.zip) includes both plain/observed outputs, ordered branch events, full final movement/maintenance snapshots, process commands/logs, reversible overlays and harnesses. Complete binary worlds remain at the manifest's local paths rather than duplicating them in Git. Archive CRC and member hashes pass.

Godot4.7.2, the verified native DLL, app main-thread policy,4 environmental worker tasks, OMP_NUM_THREADS=1 and0.1-second simulation ticks were retained. Engine processes ran serially with hidden windows, isolated profiles and the existing owned-process guard. The first harness's Python result reader hit Windows default GBK decoding after both successful engine runs; result comparison was completed separately using UTF-8, without rerunning either engine. All production source hashes were verified restored. The user's original checkout was not touched. No remote push was made. Runtime numbers in raw files are diagnostic and are not performance acceptance results.

## Patient0018 eight-step follow-on (tick7769–7777)

The next diagnostic step was completed rather than left as a proposal. The plain and instrumented eight-step outputs again match in complete World/RNG/ordered events. This adds8 logical steps and16 actual executions, for136 logical steps and272 total executions in this investigation. The earlier128-step evidence archive remains unchanged.

Actual call records show:

- Tick7769: patient0018 moves south about0.2 cells to[86,44.4].
- Tick7770: its next south step is blocked by staff0028. The real collision advances the attempted original rejoin from index33,[55,44] to index34,[54,44], choosing a west connector. It does not advance original route cursor3.
- Ticks7771/7772: it moves west twice, reaching[85.600006,44.400002].
- Tick7773: west motion is blocked by worker239. The actual collision advances attempted rejoin to index35,[53,44] and chooses a north first leg.
- Ticks7774/7775: it moves north twice, reaching[85.600006,44].
- Tick7776: local resume connects to the same attempted index35, then the real west step again contacts worker239. Collision advances attempted rejoin to index36,[52,44]. Since the new first leg is still west, fixed-contact selection runs and chooses a retreat to the actually reached checkpoint[86,44]. The retreat is only an intention at this final boundary, not a teleport or earned route progress.

All8 trip40 alighting failures are directly traced to `current_body_index`. Independent geometry identifies patient0018 at the exit. The patient's actual movement has no static, reservation or door rejection. Five real displacement steps occurred; its original request16351, original route cursor3 and final goal remain intact. This is actual local motion with unearned rejoin-target progression, not evidence of final-route progress and not a reproduced identical-state loop.

Worker239's connector segment means `_local_floor_segment` is false, so local collision must not steal its transport ownership or push it under a new movement request. The concrete dependency is now observed: patient0018's local path contacts worker239/staff0028, its body blocks trip40 alighting, and worker239's off-landing recovery is gated on an idle lift. This explains the current wait but does not by itself establish that no valid local exit exists, that the finite B→C→D sequence is broken, or that queue fairness may be changed.

No narrow defect has been proven, so production code and regression expectations remain unchanged. The remaining technical decision is the intended handoff for a temporary off-landing transit waiter while a lift is busy. The next useful investigation is a requirement-led minimal traffic fixture isolating that handoff, not another full-world wait window. Any change must preserve the current passenger's safe alighting, actual ground arrival before ticket issuance, original movement identity and existing ticket order. Do not label a delay deadlock or patch priority solely from this capture.

[Follow-on manifest](evidence/2026-11-12-patient18-handoff/manifest.json) and [raw evidence](evidence/2026-11-12-patient18-handoff/evidence.zip) preserve the new MotionResult/resume/collision/return records, exact branch hooks, complete final movement facts, commands and qualified output hashes. Source restoration and native DLL hashes were rechecked. There were no new engine errors. The harness console retained a stale “64 steps” text label; the command, steps variable, completed output and assertion all specify8. No output was overwritten and no remote push or local commit was made.
