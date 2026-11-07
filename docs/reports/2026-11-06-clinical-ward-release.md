# Clinical ward release repair, 2026-11-06

## Scope and authority

The change is limited to the clinical task owner after real escort/care/round work ends. It preserves the bed adaptation's one-cell exit buffer, actual bodies, active work ownership, schedules, existing movement rules and costs. It does not grant traffic priority or promise another actor will yield. The prior staff recall patch remains separate.

Baseline: welfare-day source, 1259 files, aggregate SHA-256 `ff00d06a71e05ee53e109b6466179ddd866dea8209b205fea064bf5d010c901f`. Production changes only `game/clinic/clinical_runtime.gd`.

## Mechanism

The old parking selector checked the destination and structural route estimate, but not stationary bodies along that route. The release task then waited for an exact parking point even after ordinary local movement could no longer return to its route. A later stationary occupant of the destination could also block without setting a textual waiting reason.

Ward release now keeps its own pending state if no safe route is available. Candidate endpoints retain the existing full-body, reservation and one-cell bed-buffer checks. The existing movement sweep proof checks each selected same-floor route against current real bodies; ordinary movement still validates every later step. A blocked owned single-person ground trip may select another safe parking point. Pending routes and active local prefixes are allowed to finish. At completion, the actual arrived body must clear the current expanded bed regions.

No unrelated move, convoy, supported exit, ride or active clinical work is taken over. `wait_safe` and queued training/base preparation are not mistaken for competing active work. Their original obligations remain. Repeated same-bed, same-visit release requests preserve the existing target and movement; a different owner is not overwritten.

## Verification

Linux Godot 4.7.2, native library SHA-256 `39345d5c19a87e23a0aa16e7c25d25f3fcdea6c6eef1f0e64d961688be4b814d`.

- CLIN-22 and CLIN-27 are unchanged and pass, including actual ward coverage, 119.9/120-second prompting and 300-second safe referral.
- CLIN-37 adds nine complete simulation flows: normal release; old blocked parking; world restore during movement; formal leave; all safe parking blocked then reopened; a later actor occupying the target; queued training; interrupted base preparation; repeated same-owner release requests. All pass. Every simulation step checks body overlap and world validation. Real completion clears the bed buffer. No-availability retains the pending release. Training work and base preparation remainder are preserved.
- The same nine-flow test against unmodified production passes two controls and fails seven relevant regressions.
- An independent original stuck snapshot runs tick 2698 to 2709, ending at [48,70], while the stationary colleague remains [45,71]. A legal later-target-occupancy flow runs 2498 to 2524, ending at [45,71] while its colleague keeps [45,72]. Both clear the full buffer, with no overlap or validation errors. These executions used the pre-idempotency revision; the final added idempotency branch is covered by the repeated-exit test and a read-only final review.
- Final selected batch: CLIN-20/22/23/24/26/27/28/32/36/37 and STAFF-16/18 pass. CLIN-25 does not pass. Import exits 0 without script/engine warnings or errors.

## Outstanding CLIN-25 result

Do not call the selected batch fully green. In the unmodified baseline, CLIN-25 cannot get past the original blocked release and rejects the transfer. With this repair it reaches actual transfer: the patient walks down from bed to [46,69], but the unchanged escort formation computes a tail target [44,69] beyond the ward's west wall. The official escort destination and route reject it with “通路不足1格”.

The exact same valid transfer snapshot, with no clinical release left, was queried under baseline and candidate. The entire read-only formation/destination/route reports are identical. The leader path is valid; the selected tail position is not. This is a separately exposed formation-start defect, not a passing transfer result. Its fix is outside this parking-owner patch.

## Limits

This is affected-case Linux headless evidence, not a full suite, Windows/GPU, disk-save or performance claim. Candidate selection checks existing ward endpoints and proposed routes at the current boundary; it does not add a global multi-actor routing algorithm. When no clear candidate exists, the task safely waits and retains its obligation.
