"""Offline DxgKrnl allocation accounting. Never starts a process or ETW session.

Only local manifest event versions listed below are interpreted. Global allocation
IDs identify storage; device/process handles are aliases, never additional bytes.
The current Get-WinEvent decoder supplies wall time, not raw QPC. Consequently
this report does not certify a formal QPC window or physical residency.
"""
import argparse
from collections import Counter, defaultdict
from dataclasses import dataclass, field
import hashlib
import json
from pathlib import Path
import sys
import unittest
import xml.etree.ElementTree as ET


VERSIONS = {33: 3, 34: 3, 35: 3, 36: 2, 37: 2, 38: 2, 78: 1,
            110: 1, 320: 0, 321: 0, 367: 0, 371: 0, 373: 0, 374: 0}


def number(value):
    if isinstance(value, bool) or value is None or isinstance(value, list):
        raise ValueError("missing or ambiguous numeric field")
    return int(value, 16 if value.lower().startswith("0x") else 10) if isinstance(value, str) else int(value)


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


@dataclass
class Allocation:
    adapter: int
    handle: int
    generation: int
    size: int | None = None
    physical_adapter: int | None = None
    creator: int | None = None
    owner: int | None = None
    source_event: int | None = None
    alive: bool = True
    target_aliases: int = 0
    intervals: list = field(default_factory=list)
    opened: int | None = None
    alias_processes: set = field(default_factory=set)
    created_sequence: int | None = None
    stopped_sequence: int | None = None


class Ledger:
    def __init__(self, target_pid):
        self.target = target_pid
        self.current = {}
        self.records = []
        self.generations = Counter()
        self.aliases = {}
        self.adapters = {}
        self.segments = {}
        self.aggregate = {}
        self.counts = Counter()
        self.issues = Counter()
        self.examples = []
        self.times = {}
        self.sequence = 0
        self.seen_versions = set()

    def issue(self, reason, **details):
        self.issues[reason] += 1
        if len(self.examples) < 32:
            self.examples.append({"reason": reason, "sequence": self.sequence, **details})

    def interested(self, allocation):
        return allocation.alive and (allocation.owner == self.target or allocation.target_aliases > 0)

    def changed(self, allocation, change):
        before = self.interested(allocation)
        change()
        after = self.interested(allocation)
        if not before and after:
            allocation.opened = self.sequence
        elif before and not after:
            allocation.intervals.append((allocation.opened, self.sequence))
            allocation.opened = None

    def allocation(self, adapter, handle):
        if not adapter or not handle:
            raise ValueError("zero adapter/global allocation identity")
        key = (adapter, handle)
        found = self.current.get(key)
        if found is None or not found.alive:
            self.generations[key] += 1
            found = Allocation(adapter, handle, self.generations[key])
            self.current[key] = found
            self.records.append(found)
        return found

    def consume(self, row):
        self.sequence += 1
        self.times[self.sequence] = row.get("system_time")
        event = number(row["event_id"])
        version = number(row["version"])
        self.counts[str(event) + ":" + str(version)] += 1
        if event not in VERSIONS:
            return
        self.seen_versions.add((event, version))
        if version != VERSIONS[event]:
            self.issue("unsupported_event_version", event_id=event, version=version)
            return
        data = row.get("data", {})
        try:
            self.event(event, data)
        except (KeyError, ValueError, TypeError) as error:
            self.issue("undecodable_required_field", event_id=event, message=str(error))

    def event(self, event, data):
        if event == 110:
            adapter = number(data["pDxgAdapter"])
            identity = {name: number(data[name]) for name in ("AdapterLuid", "VendorID", "DeviceID")}
            identity["AdapterLuid"] = hex(identity["AdapterLuid"])
            if adapter in self.adapters and self.adapters[adapter] != identity:
                self.issue("adapter_pointer_identity_changed", adapter=hex(adapter))
            self.adapters[adapter] = identity
        elif event == 78:
            key = (number(data["pDxgAdapter"]), number(data["ulSegmentId"]))
            self.segments[key] = {name: number(data[name]) for name in ("Size", "MemorySegmentGroup")}
        elif event in (33, 35):
            key = number(data["pDxgAdapter"]), number(data["hVidMmGlobalAlloc"])
            allocation = self.allocation(*key)
            size = number(data["allocSize"])
            owner = number(data["hProcessId"])
            physical = number(data["PhysicalAdapterIndex"])
            if size < 0:
                raise ValueError("negative allocation size")
            if allocation.size is not None:
                if event != 35 or (allocation.size, allocation.physical_adapter) != (size, physical):
                    self.issue("live_global_identity_repeated_or_conflicting", adapter=hex(key[0]), allocation=hex(key[1]))
                return
            def fill():
                allocation.size, allocation.creator, allocation.owner = size, owner, owner
                allocation.physical_adapter = physical
                allocation.source_event, allocation.created_sequence = event, self.sequence
            self.changed(allocation, fill)
        elif event == 34:
            key = number(data["pDxgAdapter"]), number(data["hVidMmGlobalAlloc"])
            allocation = self.current.get(key)
            if allocation is None or not allocation.alive:
                if number(data["hProcessId"]) == self.target:
                    self.issue("target_global_stop_without_live_start", adapter=hex(key[0]), allocation=hex(key[1]))
                return
            def stop():
                allocation.alive = False
                allocation.stopped_sequence = self.sequence
            self.changed(allocation, stop)
        elif event in (36, 37, 38):
            process = number(data["hProcessId"])
            adapter = number(data["pDxgAdapter"])
            alias = (adapter, process, number(data["hDevice"]), number(data["hVidMmAlloc"]))
            if event == 37:
                allocation = self.aliases.pop(alias, None)
                if allocation is None:
                    if process == self.target:
                        self.issue("target_alias_stop_without_live_start", alias=[hex(v) for v in alias])
                else:
                    self.changed(allocation, lambda: setattr(allocation, "target_aliases", allocation.target_aliases - (process == self.target)))
                return
            allocation = self.allocation(adapter, number(data["hVidMmGlobalAlloc"]))
            if alias in self.aliases:
                if event != 38 or self.aliases[alias] is not allocation:
                    self.issue("live_alias_identity_repeated_or_conflicting", alias=[hex(v) for v in alias])
                return
            self.aliases[alias] = allocation
            allocation.alias_processes.add(process)
            self.changed(allocation, lambda: setattr(allocation, "target_aliases", allocation.target_aliases + (process == self.target)))
        elif event == 373:
            handle = number(data["hVidmmGlobalAlloc"])
            previous, following = number(data["OldOwnerPid"]), number(data["NewOwnerPid"])
            found = [a for a in self.current.values() if a.alive and a.handle == handle]
            if len(found) != 1:
                if self.target in (previous, following):
                    self.issue("target_ownership_global_identity_unresolved", allocation=hex(handle), candidates=len(found))
                return
            allocation = found[0]
            if allocation.owner is not None and allocation.owner != previous:
                self.issue("ownership_previous_pid_mismatch", allocation=hex(handle))
            self.changed(allocation, lambda: setattr(allocation, "owner", following))
        elif event in (320, 321, 374):
            handle, count = number(data["pVidMmAlloc"]), number(data["ResidencyCount"])
            candidates = {id(a) for alias, a in self.aliases.items() if alias[3] == handle}
            self.counts["residency_events"] += 1
            self.counts["residency_alias_resolved" if len(candidates) == 1 else "residency_alias_unresolved"] += 1
            # ResidencyCount is not a byte count or a confirmed segment mapping.
        elif event in (367, 371) and number(data["ProcessId"]) == self.target:
            kind, new_field, old_field = ("usage", "NewUsage", "OldUsage") if event == 367 else ("commitment", "Commitment", "OldCommitment")
            key = (kind, number(data["pDxgAdapter"]), number(data["PhysicalAdapterIndex"]), number(data["MemorySegmentGroup"]))
            new, old = number(data[new_field]), number(data[old_field])
            value = self.aggregate.setdefault(key, {"samples": 0, "first_old_bytes": old, "last_bytes": old, "observed_peak_bytes": old})
            if value["last_bytes"] != old:
                self.issue("target_aggregate_counter_discontinuity", counter=kind)
            value["samples"] += 1
            value["last_bytes"] = new
            value["observed_peak_bytes"] = max(value["observed_peak_bytes"], old, new)

    def report(self, trace=None, schema_versions=None):
        trace = trace or {}
        relevant = [a for a in self.records if a.intervals or a.opened is not None]
        deltas, timed = Counter(), defaultdict(lambda: [0, 0])
        details = []
        for a in relevant:
            intervals = a.intervals + ([(a.opened, self.sequence + 1)] if a.opened is not None else [])
            if a.size is None:
                self.issue("target_alias_global_size_unresolved", allocation=hex(a.handle))
            else:
                for begin, end in intervals:
                    deltas[begin] += a.size
                    deltas[end] -= a.size
                    for sequence, amount in ((begin, a.size), (end, -a.size)):
                        stamp = self.times.get(sequence)
                        if stamp is not None:
                            timed[stamp][amount < 0] += amount
            identity = self.adapters.get(a.adapter)
            if identity is None:
                self.issue("target_adapter_luid_unresolved", adapter=hex(a.adapter))
            details.append({"adapter_pointer": hex(a.adapter), "global_allocation": hex(a.handle),
                            "generation": a.generation, "physical_adapter_index": a.physical_adapter,
                            "adapter_identity": identity, "allocated_bytes": a.size,
                            "size_source_event": a.source_event, "creator_pid": a.creator, "last_owner_pid": a.owner,
                            "alias_pids": sorted(a.alias_processes), "alive_at_trace_end": a.alive,
                            "target_intervals_sequence": intervals,
                            "created_sequence": a.created_sequence, "stopped_sequence": a.stopped_sequence})
        current = sequence_peak = 0
        for sequence in sorted(deltas):
            current += deltas[sequence]
            sequence_peak = max(sequence_peak, current)
        current = timestamp_upper_peak = 0
        for stamp in sorted(timed):
            positive, negative = timed[stamp]
            timestamp_upper_peak = max(timestamp_upper_peak, current + positive)
            current += positive + negative
        missing = ["raw QPC join to formal capture window", "physical residency bytes and segment transitions",
                   "initial live shared allocation rundown completeness", "backend coverage and allocation-size semantics corroboration"]
        if not relevant:
            missing.append("no target allocation identities observed; absence is not zero usage")
        final = trace.get("trace_final") or {}
        if final.get("code") != 0 or any(final.get(name) != 0 for name in ("events_lost", "log_buffers_lost", "realtime_buffers_lost")):
            missing.append("successful final trace stop with all loss counters zero")
        if not trace.get("started_before_target_launch"):
            missing.append("trace armed before target renderer initialization, or a validated complete attach baseline")
        if not trace.get("target_start_utc_ticks"):
            missing.append("target PID lifetime identity")
        if schema_versions is None:
            missing.append("actual provider schema identity")
        elif self.seen_versions - schema_versions:
            missing.append("emitted interpreted event versions absent from saved provider schema")
        if self.issues:
            missing.append("allocation event or identity gaps listed in issues")
        return {"schema_version": 1, "kind": "dxgkrnl_allocation_ledger", "status": "incomplete",
                "target_pid": self.target, "target_start_utc_ticks": trace.get("target_start_utc_ticks"),
                "scope": "decoded full trace; known target-owned or target-aliased global allocations, not a formal QPC window",
                "attribution": "AdapterAllocation creator PID initializes owner; TransferAllocationOwnership updates owner; live target DeviceAllocation aliases also attribute storage",
                "dedup_key": "adapter pointer + global allocation handle + lifetime generation; resource/content hashes and alias handles do not create storage",
                "known_sequence_peak_allocated_bytes": sequence_peak if relevant else None,
                "known_same_timestamp_upper_peak_allocated_bytes": timestamp_upper_peak if relevant else None,
                "peak_coverage_complete": False, "shared_dedup_verified": False, "residency_verified": False,
                "rundown_event_counts": {str(event): self.counts[str(event) + ":" + str(VERSIONS[event])] for event in (35, 38, 374)},
                "target_allocation_lifetimes": len(relevant), "target_unknown_size_lifetimes": sum(a.size is None for a in relevant),
                "counts": dict(self.counts), "issues": dict(self.issues), "issue_examples": self.examples,
                "missing": missing, "allocations": details,
                "os_aggregate_counters": [{"kind": key[0], "adapter_pointer": hex(key[1]), "physical_adapter_index": key[2],
                                           "memory_segment_group": key[3], **value} for key, value in sorted(self.aggregate.items())],
                "segments": [{"adapter_pointer": hex(key[0]), "segment_id": key[1], **value} for key, value in sorted(self.segments.items())]}


def read_rows(path):
    with path.open(encoding="utf-8-sig") as stream:
        for line in stream:
            if line.strip():
                yield json.loads(line)


def read_schema(path):
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    entries = value if isinstance(value, list) else [value]
    result = set()
    for entry in entries:
        ET.fromstring(entry["Template"])
        result.add((number(entry["Id"]), number(entry["Version"])))
    return result


class OfflineChecks(unittest.TestCase):
    def event(self, ledger, event, **data):
        ledger.consume({"event_id": event, "version": VERSIONS[event], "system_time": f"2026-10-18T00:00:{ledger.sequence:02d}Z", "data": data})

    def create(self, ledger, handle=7, size=100, owner=42):
        self.event(ledger, 33, pDxgAdapter=1, hVidMmGlobalAlloc=handle, allocSize=size, hProcessId=owner, PhysicalAdapterIndex=0)

    def alias(self, ledger, local, global_handle=7, process=42, stop=False):
        self.event(ledger, 37 if stop else 36, pDxgAdapter=1, hVidMmGlobalAlloc=global_handle, hProcessId=process, hDevice=5, hVidMmAlloc=local)

    def test_shared_aliases_count_once_and_retain_owner_until_global_stop(self):
        ledger = Ledger(42)
        self.create(ledger)
        self.alias(ledger, 10)
        self.alias(ledger, 11)
        self.alias(ledger, 12, process=99)
        self.alias(ledger, 10, stop=True)
        self.alias(ledger, 11, stop=True)
        report = ledger.report()
        self.assertEqual(report["known_sequence_peak_allocated_bytes"], 100)
        self.assertEqual(report["allocations"][0]["alias_pids"], [42, 99])
        self.assertTrue(report["allocations"][0]["alive_at_trace_end"])

    def test_different_actual_copies_and_handle_reuse_remain_distinct(self):
        ledger = Ledger(42)
        self.create(ledger, 7, 100)
        self.create(ledger, 8, 100)
        self.event(ledger, 34, pDxgAdapter=1, hVidMmGlobalAlloc=7, hProcessId=42)
        self.create(ledger, 7, 200)
        report = ledger.report()
        self.assertEqual(report["known_sequence_peak_allocated_bytes"], 300)
        self.assertEqual([(a["global_allocation"], a["generation"]) for a in report["allocations"]], [("0x7", 1), ("0x8", 1), ("0x7", 2)])

    def test_late_size_and_unknown_size_do_not_become_zero(self):
        ledger = Ledger(42)
        self.alias(ledger, 10)
        self.create(ledger, 8, 50)
        self.create(ledger, 7, 100, owner=99)
        self.alias(ledger, 11, global_handle=9)
        report = ledger.report()
        self.assertEqual(report["known_sequence_peak_allocated_bytes"], 150)
        self.assertEqual(report["target_unknown_size_lifetimes"], 1)
        self.assertIn("target_alias_global_size_unresolved", report["issues"])
        self.assertFalse(report["peak_coverage_complete"])

    def test_imported_storage_and_owner_transfer(self):
        ledger = Ledger(42)
        self.create(ledger, owner=99)
        self.alias(ledger, 10)
        self.alias(ledger, 10, stop=True)
        self.event(ledger, 373, hVidmmGlobalAlloc=7, OldOwnerPid=99, NewOwnerPid=42)
        report = ledger.report()
        self.assertEqual(len(report["allocations"][0]["target_intervals_sequence"]), 2)
        self.assertEqual(report["known_sequence_peak_allocated_bytes"], 100)

    def test_counter_and_residency_are_separate_from_allocated_bytes(self):
        ledger = Ledger(42)
        self.create(ledger)
        self.alias(ledger, 10)
        self.event(ledger, 320, pVidMmAlloc=10, ResidencyCount=6)
        self.event(ledger, 367, ProcessId=42, pDxgAdapter=1, PhysicalAdapterIndex=0, MemorySegmentGroup=0, NewUsage=150, OldUsage=0)
        report = ledger.report()
        self.assertEqual(report["known_sequence_peak_allocated_bytes"], 100)
        self.assertEqual(report["os_aggregate_counters"][0]["observed_peak_bytes"], 150)
        self.assertFalse(report["residency_verified"])

    def test_unsupported_versions_and_zero_events_stay_incomplete(self):
        ledger = Ledger(42)
        ledger.consume({"event_id": 33, "version": 99, "data": {}})
        report = ledger.report()
        self.assertIsNone(report["known_sequence_peak_allocated_bytes"])
        self.assertEqual(report["issues"]["unsupported_event_version"], 1)
        self.assertEqual(report["status"], "incomplete")

    def test_same_timestamp_release_and_create_have_separate_upper_bound(self):
        ledger = Ledger(42)
        self.create(ledger)
        self.event(ledger, 34, pDxgAdapter=1, hVidMmGlobalAlloc=7, hProcessId=42)
        released_at = ledger.times[ledger.sequence]
        self.create(ledger, 8)
        ledger.times[ledger.sequence] = released_at
        report = ledger.report()
        self.assertEqual(report["known_sequence_peak_allocated_bytes"], 100)
        self.assertEqual(report["known_same_timestamp_upper_peak_allocated_bytes"], 200)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--events", type=Path)
    parser.add_argument("--trace", type=Path)
    parser.add_argument("--schema", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args()
    if args.self_check:
        return 0 if unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(OfflineChecks)).wasSuccessful() else 1
    if not all((args.events, args.trace, args.output)):
        parser.error("--events, --trace and --output are required")
    trace = json.loads(args.trace.read_text(encoding="utf-8-sig"))
    target = number(trace["target_pid"])
    if target <= 0:
        parser.error("trace must bind a positive actual target_pid")
    schema = args.schema or args.trace.parent / "provider-schema.json"
    ledger = Ledger(target)
    for row in read_rows(args.events):
        if row.get("provider") == "Microsoft-Windows-DxgKrnl":
            ledger.consume(row)
    report = ledger.report(trace, read_schema(schema) if schema.is_file() else None)
    paths = [args.events, args.trace] + ([schema] if schema.is_file() else [])
    report["sources"] = [{"path": str(path.resolve()), "sha256": digest(path)} for path in paths]
    report["tool"] = {"path": str(Path(__file__).resolve()), "sha256": digest(Path(__file__))}
    with args.output.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(report, stream, indent=2)
        stream.write("\n")
    print(json.dumps({"status": report["status"], "target_allocation_lifetimes": report["target_allocation_lifetimes"], "known_sequence_peak_allocated_bytes": report["known_sequence_peak_allocated_bytes"], "output": str(args.output.resolve())}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
