# Missing installed clinical equipment reason (item49)

Authority: docs/design/03-experience.md:343 requires actual missing causes; docs/design/07-clinical-team.md §6 distinguishes no installed compatible machine (structural false) from temporary resource unavailability (structural true). This change concerns explanation only, never admission, eligibility, pricing or an active clinical service.

Standalone quote-only selected regression, official Godot4.7.2:

`godot --headless --path . --script res://tests/acceptance/missing_clinic_reason.gd -- <ordered-evidence-directory> <unique-output-prefix>`

Read immutable item049-review-final-variants-v1-{missing,failed,closed,offshift}-input.bin and item049-writer-fault-green-v1-repaired-input.bin. The missing input came from actual accepted BuildService.build_store of sole zombie_machine at2167, receipt build_00000017, with ownership/inventory/history preserved and no time advance. It is not fabricated removal; stored equipment is not an installed treatment resource. The other legal input controls retain the independently verified room/fault/schedule states.

Copy each raw full-world input before binding, assert exact restore/empty validation, and check COMMON/GENTLE current and structural queries against exact respective reasons. Require missing equipment to remain ok=false/structural_ok=false, temporary fault/closure/off-shift to retain structural applicability, and healthy open equipment to remain executable. Candidate status, no future holds and complete query purity cover unchanged state/eligibility boundaries. The same script is run red and green without alteration. No simulation steps, movement, work, clock changes or entire treatment/referral journeys are needed for this reason-only change. Prior closed/fault tests are unchanged; other failure-cause priority and later-candidate enumeration stay on their existing paths.
