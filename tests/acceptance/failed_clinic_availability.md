# Temporarily failed outpatient equipment (item49)

Authority: docs/design/03-experience.md:343 requires actual missing reasons; docs/design/07-clinical-team.md §6 and its temporary-resource paragraph classify equipment fault as waiting for the same plan, not structural invalidation. Actual faulty equipment must remain unavailable for new starts.

Selected standalone runner, official Godot4.7.2:

`godot --headless --path . --script res://tests/acceptance/failed_clinic_availability.gd -- <failed-diagnosed.bin> <alternative.bin> <outpatient-wait.bin> <unique-prefix>`

Immutable inputs from the ordered-verification archive:
- item049-review-continuation-v1-failed-equipment-input.bin: diagnosed original with explicit room.open=true and sole M09.failed=true, SHA256 dc420b956e31db25d360a7aab007f40e62a02263e2b23f34c24901aacc245ab0.
- item049-writer-green-v3-alternative-input.bin: validated actual-build second room/equipment with department membership and maintenance defaults, SHA256 42506f25e82532d9bf256d6b247d02e263d4898d318fcf8df580cf0d1e94759b.
- item049-writer-green-v3-waiting.bin: actual completed consultation, original outpatient wait ticket and decision, SHA256 e0d94fd6dfdc37fa6491893c452e0a0fe93128699ab42fd2c1b1f78ddc796d86.

Every input is copied before binding and must restore exactly with an empty WorldState.validate result. Variants change only declared room.open/failed flags before binding, not actor positions, paths, work, clocks, evidence, tickets or decisions. These flags are legal boundary inputs, not proof of repair UI/workflow. No simulation step or full clinical journey is needed: the changed handoffs are query eligibility and the single blocked new-dispatch boundary.

The same runner covers COMMON/GENTLE current fault reason plus retained structural recommendation, repaired positive control, previous closed-room predicate, later healthy candidate selection, no guidance to unavailable resources, and full-fact query purity. A direct actual dispatcher call at the genuine wait boundary must retain its decision/evidence/original outpatient ticket without Attempt/preparation, reconsultation or time advance. Active work, frozen Attempt completion, charging, referral and physical departure are unchanged and use existing independently reviewed evidence. Other facility flags and protocols are outside this narrow change.
