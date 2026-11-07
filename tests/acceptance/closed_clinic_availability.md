# Closed clinical room availability (item49)

Authority: docs/design/07-clinical-team.md §6 (structural recommendation versus current resources, original waiting ticket and committed Attempt), its natural-admission handoff, docs/design/03-experience.md plan comparison (真实待齐原因), and docs/design/08-hospital-life.md destination openness. Temporary room closure does not prevent natural admission or require advance treatment reservations.

Run the standalone selected regression with official Godot 4.7.2:

`godot --headless --path . --script res://tests/acceptance/closed_clinic_availability.gd -- <diagnosed-full-facts.bin> <unique-evidence-prefix>`

The input is the immutable item49 naturally diagnosed boundary, SHA256 c04b34ad0a92ac5f9e6433d11c42c3f047ac298330741281e7750cbda2bdf957. It was obtained by 766 actual fixed 0.1 steps from the item47 admitted snapshot. Copy raw facts before binding and require exact restoration. Keep the original input and all per-run outputs; never overwrite a prefix.

Selected boundaries: closed-room current quotes and precise room reason; retained structural COMMON/GENTLE recommendations; new service candidate and floor-guidance destination exclusion; query purity; actual consultation while treatment room is closed without future reservations; original treatment-stage ticket/evidence/decision through waiting and recovery; open positive control; real movement/start; one real active-work step after closing to new starts preserving the original Attempt/session. Consultation-to-treatment legitimately creates a new stage ticket and starting consumes that ticket into session.original_ticket. Preserve that outpatient ticket during resource waiting, not the already-completed consultation ticket.

A separate copy uses real build commands to add a later-sorted open alternative room/machine, explicitly includes that room in the general department as a legal pre-operation input, initializes new-equipment maintenance defaults before fixture freeze, checks exact restore and validation, and proves current quote, candidate selection and guidance skip the earlier closed machine. It does not advance actors or invent successful routes.

The room.open changes are explicit pre-operation resource-state inputs, not proof of a room-control UI or construction workflow. No actor positions, path cursors, timers, work, evidence, attempts or ticket values are fabricated. Simulation uses unchanged fixed 0.1 steps. This is selected functional coverage only, not the full distinct-doctor treatment/payment/exit journey, independent review, broad regression or performance evidence.
