"""Account selected real steps using decision_profile.gd's complete call tree."""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path


def analyze(report: dict) -> dict:
    result = {"diagnostic_only": True, "formal_pass": False,
              "formal_acceptance_paused": True, "steps": []}
    for step in report["profile"]["decision_ledger"]:
        calls = step["calls"]
        by_id = {row["id"]: row for row in calls}
        assert len(by_id) == len(calls) == step["call_count"]
        children = defaultdict(list)
        for row in calls:
            children[row["parent"]].append(row)
            assert row["parent"] == -1 or row["parent"] < row["id"]

        def ancestors(row):
            while row["parent"] != -1:
                row = by_id[row["parent"]]
                yield row

        def within(row, operation):
            return next((p for p in ancestors(row) if p["operation"] == operation), None)

        def descendants(row):
            pending = list(children[row["id"]])
            while pending:
                item = pending.pop()
                yield item
                pending.extend(children[item["id"]])

        exclusive = Counter()
        stage_exclusive = defaultdict(Counter)
        stage_counts = defaultdict(Counter)
        counts = Counter()
        for row in calls:
            assert row["inclusive_us"] == row["exclusive_us"] + sum(c["inclusive_us"] for c in children[row["id"]])
            exclusive[row["operation"]] += row["exclusive_us"]
            stage_exclusive[row["root"]][row["operation"]] += row["exclusive_us"]
            counts[row["operation"]] += 1
            stage_counts[row["root"]][row["operation"]] += 1
        assert step["call_partition_difference_us"] == 0
        assert step["outer_elapsed_us"] == step["root_stage_us"] + step["observer_handler_us"] + step["residual_us"]
        assert step["root_stage_us"] == sum(exclusive.values()) + sum(s["untimed_body_us"] for s in step["root_partition"])

        operations = lambda rows, counter: [{"operation": name, "calls": counter[name], "exclusive_us": us}
                                   for name, us in rows.most_common()]
        dispatch = [r for r in calls if r["operation"] == "clinic._dispatch_service"]
        outcomes = Counter((r["arguments"].get("ticket", {}).get("kind", ""),
                            r.get("dispatch_outcome", {}).get("visit", {}).get("phase", ""),
                            r.get("dispatch_outcome", {}).get("visit", {}).get("waiting_reason", "")) for r in dispatch)
        pair_groups = defaultdict(lambda: {"calls": 0, "inclusive_us": 0, "exclusive_subtree": Counter(), "visits": set(), "candidate_keys": Counter()})
        pair_records = []
        for row in calls:
            if row["operation"] != "clinic._service_pair_reachable":
                continue
            scope = within(row, "clinic.service_candidates")
            assert scope
            a = scope["arguments"]
            nested = list(descendants(row))
            preflight = next((c for c in nested if c["operation"] == "space.facility_preflight_quote"), None)
            reach = sorted((c for c in nested if c["operation"] == "space.can_reach"), key=lambda c: c["id"])
            unknown = sorted((c for c in nested if c["operation"] == "transit._quote_known_fit" and isinstance(c["result"], dict) and c["result"].get("status") == "estimate_unknown"), key=lambda c: c["id"])
            reason = "accepted" if row["result"] else ("fit_rejected" if preflight and not preflight["result"].get("ok") else "patient_route_reused_failure" if preflight and preflight["result"].get("ok") and not reach else "patient_route_rejected" if reach and not reach[0]["result"] else "staff_route_rejected" if len(reach) > 1 and not reach[1]["result"] else "exit_rejected")
            key = json.dumps([a.get("kind"), a.get("structural_only"), a.get("reference_schedule"), reason])
            group = pair_groups[key]
            group["calls"] += 1
            group["inclusive_us"] += row["inclusive_us"]
            group["visits"].add(row["owner"])
            group["candidate_keys"][(row["owner"], row["arguments"].get("facility_id"), row["arguments"].get("staff_id"))] += 1
            for c in [row, *nested]:
                group["exclusive_subtree"][c["operation"]] += c["exclusive_us"]
            pair_records.append({"call": row["id"], "owner": row["owner"], "facility_id": row["arguments"].get("facility_id"), "staff_id": row["arguments"].get("staff_id"),
                                 "scope": scope["id"], "kind": a.get("kind"), "reason": reason, "inclusive_us": row["inclusive_us"],
                                 "first_unknown": {"call": unknown[0]["id"], "arguments": unknown[0]["arguments"], "result": unknown[0]["result"]} if unknown else None})
        groups = []
        for key, value in pair_groups.items():
            groups.append({"classification": json.loads(key), "calls": value["calls"], "inclusive_us": value["inclusive_us"], "unique_visits": len(value["visits"]),
                           "unique_candidate_keys": len(value["candidate_keys"]), "repeated_candidate_calls": sum(n-1 for n in value["candidate_keys"].values()),
                           "exclusive_subtree": [{"operation": k, "us": v} for k, v in value["exclusive_subtree"].most_common()]})
        route_groups = defaultdict(lambda: Counter())
        path_groups = defaultdict(lambda: Counter())
        path_owners = defaultdict(lambda: Counter())
        for row in calls:
            if row["operation"] == "transit.route":
                a = row["arguments"]
                status = row["result"].get("status", "<none>")
                key = json.dumps([row["root"], a["source_floor"], a["target_floor"], a["stop_on_unknown"], a["quote_only"], status])
                route_groups[key].update(calls=1, inclusive_us=row["inclusive_us"])
            if row["operation"] == "floor_graph.find_path":
                owner = "boolean" if within(row, "space.can_reach") else "other"
                key = json.dumps([row["root"], owner, row["result"].get("status", "<none>")])
                path_groups[key].update(calls=1, exclusive_us=row["exclusive_us"])
                chain = [p["operation"] for p in ancestors(row)]
                business = next((name for name in chain if name.startswith("visitors.")), None)
                if business is None:
                    business = next((name for name in chain if name.startswith("clinic.")), "<none>")
                proof = next((name for name in chain if name in ["space._facility_exit_quote", "space._exit_witness", "space.can_reach"]), "<none>")
                visitor = within(row, "visitors._public_waiting")
                stay = visitor["arguments"].get("stay", {}) if visitor else {}
                owner = stay.get("actor_id", row["owner"])
                path_owners[json.dumps([row["root"], business, proof, owner])].update(calls=1, exclusive_us=row["exclusive_us"])
        clinical_partition = Counter()
        for entry in calls:
            if entry["operation"] == "clinic.dispatch":
                clinical_partition["clinic.dispatch body"] += entry["exclusive_us"]
                for child in children[entry["id"]]:
                    key = child["operation"]
                    if key == "clinic._dispatch_service": key += ":" + child["arguments"]["ticket"]["kind"]
                    clinical_partition[key] += child["inclusive_us"]
        row = {"index": step["index"], "tick": step["tick"], "outer_us": step["outer_elapsed_us"], "root_us": step["root_stage_us"],
               "observer_us": step["observer_handler_us"], "residual_us": step["residual_us"], "call_count": len(calls), "accounting_checks": True,
               "root_partition": step["root_partition"], "exclusive_operations": operations(exclusive, counts),
               "stage_exclusive_operations": {k: operations(v, stage_counts[k]) for k, v in stage_exclusive.items()},
               "clinical_dispatch_partition": dict(clinical_partition.most_common()),
               "dispatch_count": len(dispatch), "dispatch_outcomes": [{"kind": k[0], "phase": k[1], "reason": k[2], "calls": v} for k, v in outcomes.most_common()],
               "pair_groups": groups, "pair_records": pair_records,
               "route_groups": [{"key": json.loads(k), **v} for k, v in route_groups.items()],
               "path_groups": [{"key": json.loads(k), **v} for k, v in path_groups.items()],
               "path_owners": sorted([{"key": json.loads(k), **v} for k, v in path_owners.items()], key=lambda p:p["exclusive_us"], reverse=True),
               "largest_calls": [{"id": r["id"], "operation": r["operation"], "owner": r["owner"], "arguments": r["arguments"], "result": r["result"], "inclusive_us": r["inclusive_us"], "exclusive_us": r["exclusive_us"], "ancestors": [p["operation"] for p in ancestors(r)]} for r in sorted(calls,key=lambda c:c["inclusive_us"],reverse=True)[:30]]}
        result["steps"].append(row)
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError(args.output)
    result = analyze(json.loads(args.report.read_text(encoding="utf-8-sig")))
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf8")
    print(json.dumps({"output": str(args.output), "steps": [{k: v for k, v in s.items() if k in ["index", "tick", "outer_us", "observer_us", "call_count", "accounting_checks", "dispatch_count", "path_groups"]} for s in result["steps"]]}, ensure_ascii=False))
