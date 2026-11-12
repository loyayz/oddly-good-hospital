# Selected passenger summon: qualified actual-contact evidence

No production change in this checkpoint. Source remains1d9f0f2. The failed original continuation ends at7633 with lift idle on3F assigned to `bench_patient_0003`; the upgrade worker is on1F and is not a3F blocker. Input completeWorld SHA256 `14a9a3c17ad52e684d6a803a38e48fb08be15a07718f19100e26bfd85ee3aecf`.

## Zero/one-step result and counterevidence
Pure FileAccess exported all actor/move/connector and task facts without constructing World/Simulation or querying business logic. Selected0003 has ticket29 and an active floor/local summon;0038 has ticket36 and a completed physical waiting route at[86,46], cursor back on connector. Proximity alone is not collision evidence.

Independent plain1/observer1 each run exactly one ordinary fullSimulation .1s step to7634. Complete original/pre/final binaries, RNG and ordered events match byte-for-byte. Observer only copies actual MotionResult and at-contact facts, then invokes normal production handling. Crucially, selected0003 moves east0.2 cells with no blocker that step. Other real retreat contacts into held-ticket connector waiters are recorded, but that does not close the selected passenger's dependency.

## Fixed32-step result
A single fixed32-step pair from the same complete7633 input ends at7665. This covers the current local leg and attempted return, not another full validation window. Every step's completeWorld/RNG and ordered events match between plain and passive observer. No added route, geometry or readiness queries. Complete per-stepWorld files retain the7658 boundary before the important contact.

Actual selected contacts:0106 at7639/40 and7642/43 (later clears normally);cleaner0030 at7648;held-ticket connector waiter0038 at7659. At the last contact, selected retains ticket29/assignment and0038 retains ticket36 with no active local/floor movement. Selected subsequently side-steps again. This proves an actual contact at the movement/Transit ownership boundary, **not an infinite deadlock or proof that no bypass exists**.

The static interface gap is conditional: generic local courtesy handles active floor movement, but not a waiter whose cursor is connector; the old incoming-trip retreat helper rejects held tickets and does not cover idle assigned summon. Do not simply remove its guard or cancel legitimate queue identity. A shared owner-authorized physical-yield handoff must be designed and validated against actual contacts before any production change or further long run.

## Recoverable raw evidence
Stage1 ZIP:2,875,183bytes,69 members,SHA256 `09b827819f6eb0a19a722fe8a4218e43ac4b1cdeaea6c876f254505e67661409`.
Stage2 original ZIP:22,345,157bytes,333 members,SHA256 `1e03d362248ecf9d903834971c15677fd40ca1f4012a854115bbe08053140e0e`. To keep individual transfer requests bounded it is stored as four ordered parts, not recompressed or edited. [parts.json](evidence/2026-11-12-upgrade-summon-boundary/stage2/parts.json) specifies order, exact bytes and part/archive SHA256; concatenate those bytes to recover the original ZIP, then check CRC and all members against members.json. Published readback must reassemble and validate the whole original archive, not just verify part existence.

Both archives retain commands, process outcomes, raw World/events/contacts, executed scripts, production/native identity and safe host metadata. All processes were reaped; production and original663 UID bytes were unchanged. Older raw runs and failed outcomes remain intact.
