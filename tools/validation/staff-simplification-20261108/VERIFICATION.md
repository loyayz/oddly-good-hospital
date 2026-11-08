# Staff simplification verification

Base: `be3875728fe6e20029b02b54fefe81fc04c90712` (H8). Linux Godot 4.7.2.

## Changed business boundaries

- Four hireable employee roles: doctor, nurse, cleaner, researcher. No receptionist or decorator recruitment, payroll, schedule, initial staff or registration service.
- An admitted patient must physically complete the floor desk workflow before physician consultation. An unavailable desk nurse pauses guidance; it does not permit a bypass. Same-floor and cross-floor subsequent guidance remains in place.
- Existing external maintenance actors perform surface and upper-floor work. They enter through the actual entrance, collect tools, travel to the work position, complete original work and leave. They reuse the same visiting workers across eligible units of one order (at most two), rather than admitting a new person per tile. They never enter staff payroll or practice. Surface material charges, upper-floor prices, standard durations, pause/resume and cancellation/refund rules remain unchanged.
- Final design and generated content agree. Deleted-role talents are removed; remaining former registration talents apply to actual guidance, including tested mood idempotency. No replacement cleaning bonus was invented.

## Selected verification

Passed on the changed source:

- OPS-12,13,14,16,17,21,33,35,36,37,42,43,47,48,51,52: surface material accounting, actual tool pickup/work, pause/cancel/resume/refund, cleanup, existing maintenance, economic carry, rescue, observations, relocation.
- SPACE-14,15,16,17,18,19,20,42: no hired builder prerequisite, valid tool prerequisite, actual completed floor ownership, work conservation, recovery/cancellation and blueprint surface orders.
- CORE-01,02,55: new/initial hospital and resting-layout economic prerequisites.
- STAFF-01,36,37,39,40; CLIN-01,33,36; GROW-76; four GUIDE checks: roles and current clinical/guidance handoffs.
- `staff_simplification_runner.gd`: 180 ticks without a desk nurse cannot start consultation; resumed actual guidance precedes doctor service; old-role recruitment rejected; 6 initial employees, 690/day wages, 11050 cash; rescue provides 2 doctors/1 nurse and FUR02/M37/SE01; guidance talents and one-time mood receipt.
- `schedule_preview.gd`: all schedule/UI assertions pass, including fixed desk nurse ownership and no simultaneous clinical promise.
- `staff_performance_fixture.gd`: input integrity only, no performance steps. Exactly 160 actors = 32 staff + 120 patients + 8 visitors, 4 floors, 64 rooms, 1328 facilities, 24 beds; all roles and floor desks legal, world validation empty. Existing receptionist slots become guidance nurses, reception desks become SE01. This is a changed-business baseline, not evidence of performance improvement.
- Godot final import/parse, `git diff --check`, exact content regeneration, atlas generation and 10 HTML exporter tests pass.

Final content fingerprint: `91b9f45771eb3b6253d9cc5799185a91a74f5c3fc69e0032d9c03bf6e669181a`.

## Corrections during verification

Initial runtime content validation still required every species to have an employee talent. It now permits species with no valid employee talent while retaining uniqueness and valid handler/rig checks. Construction resume tests now allow the new worker's real entrance-to-tool-to-work journey (500-step bound, no teleport or work rewrite); the previous 120-step bound assumed an employee already onsite. Economic expected values reflect the removed desk/employee. The added crew-lifecycle check also corrected its test cash baseline to include the already purchased tool; three units conserve 24000 work, reuse two external workers, charge materials once, and both workers actually depart. Every affected failed selected check was rerun successfully.

## Scope and next handoff

No full acceptance run, Windows verification or formal 160-person timing was performed. Native capacity API retains an empty historical `reception` parameter to avoid an unrelated native ABI change; gameplay does not create those resources or use their deleted configuration. No old-save compatibility is provided, as requested.

Rebuild performance prerequisites from the new content and same committed code on Linux/Windows. Current preparation tools no longer recruit a deleted decorator; existing workbench evidence is historical and was not rewritten. Raw Linux logs are preserved in the adjacent `ogh-staff-simplification-evidence` workspace directory, separate from product design.

## Integration handoff recheck

After the prerequisite candidate verification, rechecked this isolated staff branch without merging or publishing it. Final design now consistently uses `guidance_choice`, `GuidanceRoute` and guidance destination rather than registration. The construction UI explains external-worker arrival/tool availability instead of an absent decorator. Displayed charges are material prices/totals and original refunds, not a new work-time fee. Selected recheck passed OPS-12/14/37/52 and SPACE-14/17, plus the complete staff-simplification runner and exact content check. No formal performance round was started. Raw recheck logs are alongside the prior evidence.
