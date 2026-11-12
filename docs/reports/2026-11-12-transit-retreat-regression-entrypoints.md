# Focused regression entrypoints

The following repository scripts are byte-identical copies of the executed archived scripts, not new simulations or new test claims:

- `tests/acceptance/transit_retreat_waiting.gd`: archived `generic_declared.gd`.
- `tests/acceptance/transit_retreat_waiting_edges.gd`: archived `generic_edges.gd`.
- `tests/acceptance/transit_retreat_waiting_budget.gd`: archived `generic_budget.gd`.
- `tests/acceptance/transit_contact_service_phases.gd`: archived `stage_table.gd`.
- `tests/acceptance/transit_selected_contact.gd`: archived `selected_compat.gd`.
- `tests/acceptance/transit_incoming_ticket_contact.gd`: archived `incoming_ticket_compat.gd`.
- `tests/acceptance/transit_contact_convoy_protection.gd`: archived `convoy_compat.gd`.

Run through Godot headless with this repository as --path and the named script as --script; arguments follow --. Output directories must already exist. The first argument is a mode label, second the output directory. The generated fixtures ignore subsequent reference arguments; their actual preWorld/declaration/pending files are the input provenance.

- Generic positive: `flow OUT`; real ticket/parking, declared legal retreat, subsequent real contact and walking. Produces actual-generic-pending.bin.
- Generic budget: `budget OUT`; 9 actual earlier requests, unchanged dispatch budget8, real deferred handoff and later root departure.
- Generic edges: `edges OUT ACTUAL_GENERIC_PENDING_BIN`.
- Selected representative: `nurse OUT` (other declared modes are flow/up).
- Incoming ticket: `ticket OUT`; actual parking, declared legal pre-contact retreat boundary.
- Convoy protection: `guards OUT`; direct guard negative only, not group liveness.
- Service phase table: `table OUT HISTORICAL_INCOMING_PENDING_BIN ACTUAL_GENERIC_PENDING_BIN`; the first is archived prefix-edges05/pending.bin (cf5578b1…), the second is generic01/actual-generic-pending.bin (3f763a95…); use the exact archived table01 command/input index, pure copied-descriptor helper cases, not lifecycle simulation.

Keep the original failed natural01 and all coverage limitations. Narrow passes are not full traffic, upgrade or performance acceptance.
