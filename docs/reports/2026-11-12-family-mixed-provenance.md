# Original mixed160 family coverage: offline findings

No engine, source edits, probability changes, seed selection or new input. FAMILY06/12 remains separate functional evidence, not mixed coverage.

## Verified current available full coverage artifact
waiting-fixed-full-plain-20261112/plain/result.json identifies original input75f5e1d922f39f12382c0ceb74806bda0293251189f68a1ac158842f65fa78ca,1000 prefix+6000 sample; sample ticks1634–7633. This is the published full coverage run, not the later cold-restored upgrade-only continuation and not a claim of a fresh full run on today's candidate.
- effective_ward_visit: actual0, required>=1.
- Prefix actual ward admissions1; sample admissions1 and actual surgical ward returns2.
- Only companion work is recorded: sample movement5692, surgery waiting1459, actual ward entry4/exit4.
- Final family_roles={companion:2}; natural_additional_actors records only two relatives, owned by visits0004/0010, the surviving companions. There is no recorded admitted independent ward visitor. Final ward_stays is empty, so final decoding alone cannot recover vanished daily-intent facts.

## Not an event-name mismatch
comprehensive_observer.gd:61 registers only purpose=ward_visit. Its _observe_ward_visit_progress:132–146 requires actual remaining delta1, valid nonterminal visit, visitor and patient actually in ward, no life task/medical/yielding/transfer phase. Coverage:308 requires at least1 such effective tick. It does not look for a ward_visit event name. Production HospitalVisitors.advance:216–228 implements the same real work boundary. Nurse care and companion entry cannot substitute.

## Exact known versus missing cause
Actual admissions and companion admission disprove a blanket 'nobody was admitted' explanation. Current available full result establishes missing independent visitor admission/work, but not whether daily intent was false, consent false, a request was waiting for entry/public space, or its window/ward expired. No current per-admission intent/request lifecycle was archived in this plain result. The final empty ward map cannot settle earlier intent.
Old Windows history in docs/reports/evidence/2026-11-12-current-mixed-full/evidence.zip, history-r2/result.json.business.ndjson DOES establish one earlier trajectory: ward_00000196/visit0004 admitted1356 (observed1357); day becomes0 at1401, intent remainsfalse and requestedfalse; ward removed5002 with those values. That old trajectory is not the current Linux draw and cannot prove both current admissions missed30%.

## Actual legal request chain
hospital_visitors.gd:40–64: scan due -> real admitted ward, nonterminal visit -> daytime -> one daily arrival-stream draw with unchanged30% probability -> visitor_intent and consent(defaulttrue) and no existing ward_visit role -> private _request -> actual _admit entrance and public waiting space -> real route/ward arrival ->300 effective ticks -> real departure. Companion probability80% is a separate role/draw.
clinical_runtime.gd:2190 clinical_visit_consent only changes consent. It cannot request a visit when natural intent isfalse. No public forced-request API was found. Calling private _request or writing intent/stay/remaining would not be an acceptable scenario fix.

## Minimum next evidence, attached to next already-planned full input run
Keep original bytes,128+32 core identities/species/cohorts, four-floor layout, staffing/hours/resources/operations, seed/streams, prefix1000 and original sample boundary unchanged. At actual admission and daily-scan transitions record original visit/ward ids, admitted_tick, ward phase, visitor_day/intent/requested, consent, next_scan_tick, day/time; existing request id/window/request_tick and actual admission result; family purpose/phase/remaining, actor location, destination and movement ownership; patient ward position and medical/yielding/transfer guards. Capture actual draw result and stream before/after at its already-executed call if needed, without another draw. Save full World/RNG before first actual daily draw and at real request/admission; these are input facts, not warmed-cache snapshots. Preserve cancellations as cancellations, not work. Plain/observer qualification is needed if instrumented.

## Minimal executable preparation decision
1. Do not rerun FAMILY06/12 merely to replace missing mixed coverage; its legal request/300tick/departure chain already passed.
2. If current natural intent istrue but admission/route/work fails, use that unchanged complete request boundary for one bounded functional diagnostic. Remedy the actual rule defect if established; keep all original load.
3. If no natural intent istrue within the fixed window, no existing command guarantees coverage while preserving the same full input/RNG/window. Consent=true only helps actual refused consent. Do not silently add visitors, extend stays, hold patients or redraw.
4. A separately named v2 generator could declare an independent probability seed before generation while preserving numeric/core/layout/clinical/operations contracts. This changes RNG and potentially workload; it needs its own frozen input/baseline and cannot be compared against v1 as optimization evidence. A single predeclared seed does not guarantee30% hit; do not search seeds or promise coverage. Alternatively freeze a naturally reached request boundary from v1, but verify remaining dense load and clinical prerequisites; it is a later-state functional scenario, not unchanged160 initial benchmark. Neither alternative is part of this recorded run or implemented here.

The tight conflict is guarantee versus preservation: with exact original stochastic input and time horizon, missing natural intent cannot be guaranteed away without changing a declared input or business rule. First capture the missing actual lifecycle rather than choosing a probability explanation by guess.

## Verified zero-step final export (additional evidence)

Read only family-final-zero-20261112/decode02/decoded.json, SHA94a909b183b32a833d3c330f20f5c427fa917ee4eea6fc32c696d4ae1b8b2f83, derived from original Linux final d5b8a6520051d7170ed625e4f0077e6e3cd8c491312f710d2bcac920016c54c5 at tick7633. decode01 used the wrong wrapper and is invalid; not used here.

- ward_stays={}, visitors.requests={}, next_scan_tick7650, sessions={}. Thus no surviving pending independent family request or admitted ward owner can be resumed from this final snapshot to fill the missing visit.
- Exactly two visitor stays remain, both purpose=companion, phase=leaving, remaining_ticks0, life_task{}, destination exit1F[48,91]. visitor202 belongs to visit0004/relative201; visitor240 belongs to visit0010/relative239. Their zero remaining is a companion/terminal state, NOT300 ticks of effective ward_visit.
- Both original visits remain phase=leaving, final_result=cured. Their real result receipts are5084 and5401 respectively. No visit among134 has an explicit visitor_consent field; current production therefore reads defaulttrue. This proves no current explicit refusal, not that historical daily intent wastrue.
- Relative201 is physically at1F[49.1999778747559,90.8000030517578], move request4060 with original target1F[48,91], visitor_stay_id202 and local return. Relative239 is physically at3F[83.5999908447266,44.4000015258789], request4159, same original exit target, visitor_stay_id240, local return. These are actual outbound companion journeys, not independent visitors en route into a ward. Snapshot alone does not prove stalled or completed departure.
- Only these two actors carry relative_of. Top-level exported visitor_ids=[] is not a replacement for the two real visitors.stays; no current game reference to visitor_ids was found. Do not interpret that empty auxiliary field as proof there were no companions.

The zero-step export narrows the CURRENT boundary: there is no existing eligible ward/request/ward_visit stay to continue here. It does not recover erased ward.visitor_day/intent/requested or discarded request windows and cannot distinguish historical false intent from a request that expired before admission. Combined with the full observer's retained natural-actor inventory and zero effective work, no admitted independent ward visitor is recorded in the full run; why the pre-admission chain produced none still needs lifecycle evidence.

Minimum next capture remains the real admission/daily-scan/request boundary, not another final decode: copy ward identity, admitted_tick, visitor_day/intent/requested before/after the existing daily draw, consent, original request and actual admission return/reason, plus complete World/RNG at the first such boundary. Do not call _request or draw again. If an already-saved intermediate full input retains those fields, read it first; otherwise obtain them in the next authorized original-input run rather than creating a new long run solely from this empty terminal state.
