"""Offline DxgKrnl allocation accounting. Never starts a process or ETW session.

Only local manifest event versions listed below are interpreted. Global allocation
IDs identify allocation objects; device/process handles are aliases, never extra bytes.
allocSize is reported as emitted, not asserted to be unique physical resident bytes.
Raw-QPC input and converted wall-time input remain distinct. A trace without a
formal capture window is startup/lifecycle corroboration, never a formal pass.
"""
import argparse
from collections import Counter, defaultdict
from dataclasses import dataclass, field
import hashlib
import heapq
import json
from pathlib import Path
import sys
import unittest
import xml.etree.ElementTree as ET


VERSIONS = {27: 2, 28: 2, 29: 2, 33: 3, 34: 3, 35: 3, 36: 2, 37: 2, 38: 2, 39: 0, 78: 1,
            110: 1, 320: 0, 321: 0, 367: 0, 371: 0, 373: 0, 374: 0}


def number(value):
    if type(value) not in (int, str):
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
    associated_processes: set = field(default_factory=set)
    alias_history: list = field(default_factory=list)
    created_sequence: int | None = None
    stopped_sequence: int | None = None
    recorded: bool = False
    metadata: dict = field(default_factory=dict)


class Ledger:
    def __init__(self, target_pid):
        self.target = target_pid
        self.current = {}
        self.records = []
        self.generations = Counter()
        self.aliases = {}
        self.devices = {}
        self.adapters = {}
        self.segments = {}
        self.aggregate = {}
        self.counts = Counter()
        self.issues = Counter()
        self.examples = []
        self.times = {}
        self.sequence = 0
        self.seen_versions = set()
        self.processed = 0
        self.current_clock = None
        self.first_qpc = self.last_qpc = None
        self.qpc_frequencies = set()
        self.previous_qpc = None
        self.previous_sequence = None
        self.non_qpc_events = 0

    def issue(self, reason, **details):
        self.issues[reason] += 1
        if len(self.examples) < 32:
            self.examples.append({"reason": reason, "sequence": self.sequence, **details})

    def interested(self, allocation):
        return allocation.alive and (allocation.creator == self.target or allocation.owner == self.target or allocation.target_aliases > 0)

    def changed(self, allocation, change):
        before = self.interested(allocation)
        change()
        after = self.interested(allocation)
        if not before and after:
            if not allocation.recorded:
                allocation.recorded = True
                self.records.append(allocation)
            allocation.opened = self.sequence
            self.times[self.sequence] = self.current_clock
        elif before and not after:
            allocation.intervals.append((allocation.opened, self.sequence))
            self.times[self.sequence] = self.current_clock
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
        return found

    def consume(self, row):
        event = number(row["event_id"])
        version = number(row["version"])
        if event not in VERSIONS:
            return
        self.processed += 1
        self.sequence = number(row.get("sequence", self.sequence + 1))
        if self.previous_sequence is not None and self.sequence <= self.previous_sequence:
            self.issue("interpreted_event_sequence_not_increasing")
        self.previous_sequence = self.sequence
        self.counts[str(event) + ":" + str(version)] += 1
        if row.get("clock_domain") == "windows_qpc" and row.get("qpc_ticks") is not None:
            stamp, frequency = number(row["qpc_ticks"]), number(row["qpc_frequency"])
            self.current_clock = ("windows_qpc", frequency, stamp)
            if self.previous_qpc is not None and stamp < self.previous_qpc:
                self.issue("raw_qpc_event_order_reversed", previous=self.previous_qpc, current=stamp)
            self.previous_qpc = stamp
            self.qpc_frequencies.add(frequency)
            self.first_qpc = stamp if self.first_qpc is None else min(self.first_qpc, stamp)
            self.last_qpc = stamp if self.last_qpc is None else max(self.last_qpc, stamp)
        else:
            self.current_clock = ("etw_converted_system_time", row.get("system_time"))
            self.non_qpc_events += 1
        self.seen_versions.add((event, version))
        if version != VERSIONS[event]:
            self.issue("unsupported_event_version", event_id=event, version=version)
            return
        if row.get("decode_status") not in (None, "decoded"):
            self.issue("event_decode_incomplete", event_id=event, message=row.get("decode_error"))
            return
        data = row.get("data", {})
        names = Counter(f.get("name") for f in row.get("data_fields", []))
        if any(names[name] > 1 for name in data):
            self.issue("duplicate_named_data_fields", event_id=event)
            return
        try:
            self.event(event, data)
        except (KeyError, ValueError, TypeError) as error:
            self.issue("undecodable_required_field", event_id=event, message=str(error))

    def event(self, event, data):
        if event in (27, 28, 29):
            key = number(data["pDxgAdapter"]), number(data["hDevice"])
            process = number(data["hProcessId"])
            if event == 28:
                self.devices.pop(key, None)
            else:
                if key in self.devices and self.devices[key][0] != process:
                    self.issue("live_device_pid_changed", adapter=hex(key[0]), device=hex(key[1]))
                self.devices[key] = process, self.sequence
        elif event == 110:
            adapter = number(data["pDxgAdapter"])
            identity = {name: number(data[name]) for name in ("AdapterLuid", "VendorID", "DeviceID")}
            identity["AdapterLuid"] = hex(identity["AdapterLuid"])
            if adapter in self.adapters and self.adapters[adapter] != identity:
                self.issue("adapter_pointer_identity_changed", adapter=hex(adapter))
            self.adapters[adapter] = identity
        elif event == 78:
            key = (number(data["pDxgAdapter"]), number(data["ulSegmentId"]))
            self.segments[key] = {name: number(data[name]) for name in (
                "Size", "MemorySegmentGroup", "Flags", "CommitLimit", "BaseAddress", "CpuTranslatedAddress",
                "NbOfBanks", "SystemMemoryEndAddress") if name in data}
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
                allocation.size, allocation.creator = size, owner
                allocation.physical_adapter = physical
                allocation.source_event, allocation.created_sequence = event, self.sequence
                # The saved template has no Flags value map. Preserve the exact
                # fields without treating undocumented bits as DDI bit fields.
                allocation.metadata = {name: data[name] for name in (
                    "Flags", "ulAlignment", "dwReadSegment", "dwWriteSegment", "PreferredSegment",
                    "HintedBank", "dwEvictionSegment", "UsageVersion", "UsageFlags", "Format",
                    "ByteOffset", "Width", "Height", "Pitch", "Depth", "SlicePitch",
                    "BackingStoreWasPinned", "pSectionObject", "PageTableOrDirectory",
                    "hDxgGlobalAlloc", "hDxgSharedResource") if name in data}
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
            self.current.pop(key, None)
        elif event in (36, 37, 38):
            process = number(data["hProcessId"])
            adapter = number(data["pDxgAdapter"])
            device = number(data["hDevice"])
            alias = (adapter, device, number(data["hVidMmAlloc"]))
            if event == 37:
                previous = self.aliases.pop(alias, None)
                if previous is None:
                    if process == self.target:
                        self.issue("target_alias_stop_without_live_start", alias=[hex(v) for v in alias])
                else:
                    allocation, alias_pid, record = previous
                    record["stop_sequence"] = self.sequence
                    record["stop_associated_pid"] = process
                    if allocation.handle != number(data["hVidMmGlobalAlloc"]):
                        self.issue("alias_stop_global_identity_mismatch", alias=[hex(v) for v in alias])
                    self.changed(allocation, lambda: setattr(allocation, "target_aliases", allocation.target_aliases - (alias_pid == self.target)))
                return
            allocation = self.allocation(adapter, number(data["hVidMmGlobalAlloc"]))
            if alias in self.aliases:
                if event != 38 or self.aliases[alias][0] is not allocation:
                    self.issue("live_alias_identity_repeated_or_conflicting", alias=[hex(v) for v in alias])
                return
            binding = self.devices.get((adapter, device))
            alias_pid = binding[0] if binding is not None else None
            if alias_pid is None and process == self.target:
                self.issue("target_associated_alias_device_pid_unresolved", device=hex(device))
            record = {"device": hex(device), "device_allocation": hex(alias[2]), "device_pid": alias_pid,
                      "device_pid_source_sequence": binding[1] if binding is not None else None,
                      "start_associated_pid": process, "start_sequence": self.sequence, "stop_sequence": None}
            record["resource_fields"] = {name: data[name] for name in (
                "hDxgResource", "hDxgSharedResource", "hThunkAllocation", "hThunkResource",
                "PrivateRuntimeResourceHandle", "pVirtualAddress", "hProcessAllocDetails") if name in data}
            allocation.alias_history.append(record)
            self.aliases[alias] = allocation, alias_pid, record
            allocation.associated_processes.add(process)
            if alias_pid is not None:
                allocation.alias_processes.add(alias_pid)
            self.changed(allocation, lambda: setattr(allocation, "target_aliases", allocation.target_aliases + (alias_pid == self.target)))
        elif event == 39:
            handle = number(data["hVidMmAlloc"])
            found = [(a, process) for alias, (a, process, record) in self.aliases.items() if alias[2] == handle]
            for alias, (a, process, record) in self.aliases.items():
                if alias[2] == handle:
                    record["termination_sequence"] = self.sequence
            self.counts["terminate_allocation_events"] += 1
            if any(process == self.target or a.creator == self.target for a, process in found):
                self.counts["target_terminate_allocation_events"] += 1
            # Termination is not global-storage destruction. Keep bytes until 34.
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
            candidates = {id(a) for alias, (a, process, record) in self.aliases.items() if alias[2] == handle}
            self.counts["residency_events"] += 1
            self.counts["residency_alias_resolved" if len(candidates) == 1 else "residency_alias_unresolved"] += 1
            # ResidencyCount is not a byte count or a confirmed segment mapping.
        elif event in (367, 371) and number(data["ProcessId"]) == self.target:
            kind, new_field, old_field = ("usage", "NewUsage", "OldUsage") if event == 367 else ("commitment", "Commitment", "OldCommitment")
            key = (kind, number(data["pDxgAdapter"]), number(data["PhysicalAdapterIndex"]), number(data["MemorySegmentGroup"]))
            new, old = number(data[new_field]), number(data[old_field])
            value = self.aggregate.setdefault(key, {"samples": 0, "first_old_bytes": old, "last_bytes": old,
                                                     "observed_peak_bytes": old, "continuous": True, "changes": []})
            if value["last_bytes"] != old:
                self.issue("target_aggregate_counter_discontinuity", counter=kind)
                value["continuous"] = False
            value["samples"] += 1
            value["last_bytes"] = new
            value["observed_peak_bytes"] = max(value["observed_peak_bytes"], old, new)
            value["changes"].append((self.current_clock, old, new))

    def report(self, trace=None, schema_versions=None, decode_meta=None, capture=None):
        trace = trace or {}
        decode_meta = decode_meta or {}
        capture = capture or {}
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
                        if stamp is not None and all(v is not None for v in stamp):
                            timed[stamp][amount < 0] += amount
            identity = self.adapters.get(a.adapter)
            if identity is None:
                self.issue("target_adapter_luid_unresolved", adapter=hex(a.adapter))
            details.append({"adapter_pointer": hex(a.adapter), "global_allocation": hex(a.handle),
                            "generation": a.generation, "physical_adapter_index": a.physical_adapter,
                            "adapter_identity": identity, "allocated_bytes": a.size,
                            "allocation_event_metadata": a.metadata,
                            "size_source_event": a.source_event, "creator_pid": a.creator, "last_owner_pid": a.owner,
                            "alias_pids": sorted(a.alias_processes), "creation_associated_pids": sorted(a.associated_processes), "alive_at_trace_end": a.alive,
                            "aliases": a.alias_history,
                            "target_intervals_sequence": intervals,
                            "target_intervals_clock": [[self.times.get(begin), self.times.get(end)] for begin, end in intervals],
                            "created_sequence": a.created_sequence, "stopped_sequence": a.stopped_sequence})
        current = sequence_peak = 0
        peak_sequence = None
        for sequence in sorted(deltas):
            current += deltas[sequence]
            if current > sequence_peak:
                sequence_peak, peak_sequence = current, sequence
        current, plateau_start = 0, None
        plateaus = []
        for sequence in sorted(deltas):
            if not deltas[sequence]:
                continue
            before = current
            current += deltas[sequence]
            clock = self.times.get(sequence)
            if before != sequence_peak and current == sequence_peak:
                plateau_start = clock
            elif before == sequence_peak and current != sequence_peak and plateau_start and clock:
                if plateau_start[:2] == clock[:2] and clock[0] == "windows_qpc":
                    plateaus.append({"start_qpc": plateau_start[2], "end_qpc": clock[2], "duration_ms": (clock[2] - plateau_start[2]) * 1000 / clock[1]})
                plateau_start = None
        current = timestamp_upper_peak = 0
        for stamp in sorted(timed):
            positive, negative = timed[stamp]
            timestamp_upper_peak = max(timestamp_upper_peak, current + positive)
            current += positive + negative
        window = window_summary(details, capture, self.target, trace, decode_meta, self.qpc_frequencies)
        groups = defaultdict(lambda: {"lifetimes": 0, "known_peak_live_allocations": 0, "known_peak_alloc_size_bytes": 0})
        for a in details:
            metadata = a["allocation_event_metadata"]
            key = tuple(metadata.get(name) for name in ("Flags", "PageTableOrDirectory", "UsageVersion", "UsageFlags", "dwWriteSegment", "PreferredSegment"))
            value = groups[key]
            value["lifetimes"] += 1
            if peak_sequence is not None and any(begin <= peak_sequence < end for begin, end in a["target_intervals_sequence"]):
                value["known_peak_live_allocations"] += 1
                if a["allocated_bytes"] is not None:
                    value["known_peak_alloc_size_bytes"] += a["allocated_bytes"]
        missing = ["OS residency view with explicit per-process/adapter/node/segment semantics and window coverage",
                   "initial live shared allocation rundown completeness", "backend coverage and allocation-size semantics corroboration"]
        if not window["verified"]:
            missing.append("formal window not verified: " + "; ".join(window["missing"]))
        if not relevant:
            missing.append("no target allocation identities observed; absence is not zero usage")
        final = trace.get("trace_final") or {}
        if final.get("code") != 0 or any(final.get(name) != 0 for name in ("events_lost", "log_buffers_lost", "realtime_buffers_lost")):
            missing.append("successful final trace stop with all loss counters zero")
        if not trace.get("started_before_target"):
            missing.append("trace armed before target renderer initialization, or a validated complete attach baseline")
        if not trace.get("target_start_utc_ticks"):
            missing.append("target PID lifetime identity")
        if schema_versions is None:
            missing.append("actual provider schema identity")
        elif self.seen_versions - schema_versions:
            missing.append("emitted interpreted event versions absent from saved provider schema")
        if self.issues:
            missing.append("allocation event or identity gaps listed in issues")
        result = decode_meta.get("result") or {}
        header = result.get("TraceHeader") or {}
        raw_qpc_checks = {
            "decoder_raw_qpc_valid": decode_meta.get("raw_qpc_valid") is True,
            "full_etl_read_complete": result.get("RawFileReadComplete") is True,
            "process_and_close_succeeded": result.get("ProcessStatus") == 0 and result.get("CloseStatus") == 0,
            "qpc_header_clock": header.get("reserved_flags_clock_type") == 1,
            "zero_file_loss": header.get("events_lost") == 0 and header.get("buffers_lost") == 0,
            "all_interpreted_events_have_raw_qpc": self.non_qpc_events == 0,
            "one_matching_positive_frequency": len(self.qpc_frequencies) == 1 and (header.get("perf_frequency") or 0) > 0
                                               and header.get("perf_frequency") in self.qpc_frequencies,
        }
        raw_qpc_verified = all(raw_qpc_checks.values())
        if not raw_qpc_verified:
            missing.append("complete raw-QPC decode with matching trace header, frequency and zero loss")
        return {"schema_version": 2, "kind": "dxgkrnl_allocation_ledger", "status": "incomplete",
                "target_pid": self.target, "target_start_utc_ticks": trace.get("target_start_utc_ticks"),
                "scope": "observed target-origin/device/explicit-owner global allocation graph; full backend coverage and physical residency not established",
                "formal_window": window,
                "raw_qpc_verified": raw_qpc_verified, "qpc_frequency": next(iter(self.qpc_frequencies)) if len(self.qpc_frequencies) == 1 else None,
                "raw_qpc_checks": raw_qpc_checks,
                "interpreted_event_qpc_range": [self.first_qpc, self.last_qpc], "interpreted_events": self.processed,
                "interpreted_events_without_raw_qpc": self.non_qpc_events,
                "retained_target_interval_clock_points": len(self.times),
                "attribution": "target-origin global allocations until global stop, explicit transferred ownership, or live aliases on target-owned devices; creation-associated PID is not assumed to be current owner",
                "dedup_key": "adapter pointer + global allocation handle + lifetime generation; resource/content hashes and alias handles do not create storage",
                "known_sequence_peak_allocated_bytes": sequence_peak if relevant else None,
                "known_peak_sequence": peak_sequence, "known_peak_clock": self.times.get(peak_sequence),
                "known_peak_plateaus_qpc": plateaus,
                "known_live_at_trace_end_bytes": sum(a.size for a in relevant if self.interested(a) and a.size is not None),
                "known_same_timestamp_upper_peak_allocated_bytes": timestamp_upper_peak if relevant else None,
                "peak_coverage_complete": False, "shared_dedup_verified": False, "residency_verified": False,
                "allocation_accounting": {"status": "incomplete", "byte_basis": "AdapterAllocation 33/35 allocSize, once per adapter/global/lifetime",
                    "physical_resident_bytes": None, "backend_coverage_verified": False,
                    "flags_semantics": "raw UInt32 without a saved manifest value map; no DDI flag decoding assumed",
                    "excluded_from_sum": ["device/process aliases", "GPU virtual address reservations and mappings", "heap/process allocation totals", "OS usage/commitment counters"],
                    "unreleased_observed_globals_included": True},
                "allocation_metadata_groups": [{**dict(zip(("Flags", "PageTableOrDirectory", "UsageVersion", "UsageFlags", "dwWriteSegment", "PreferredSegment"), key)), **value}
                                               for key, value in sorted(groups.items(), key=lambda item: -item[1]["known_peak_alloc_size_bytes"])],
                "rundown_event_counts": {str(event): self.counts[str(event) + ":" + str(VERSIONS[event])] for event in (35, 38, 374)},
                "target_allocation_lifetimes": len(relevant), "target_unknown_size_lifetimes": sum(a.size is None for a in relevant),
                "observed_identity_join": {"all_target_sizes_and_adapter_ids_joined": bool(relevant) and not self.issues,
                                           "shared_global_lifetimes": sum(len(a.alias_processes) > 1 for a in relevant),
                                           "scope": "observed target-origin/device/explicit-owner graph only; not proof that every backend allocation was emitted"},
                "counts": dict(self.counts), "issues": dict(self.issues), "issue_examples": self.examples,
                "missing": missing, "allocations": details,
                "os_aggregate_counters": [{"kind": key[0], "adapter_pointer": hex(key[1]), "physical_adapter_index": key[2],
                                           "adapter_identity": self.adapters.get(key[1]), "memory_segment_group": key[3],
                                           **{name: item for name, item in value.items() if name != "changes"},
                                           "formal_window": counter_window(value, window),
                                           "byte_basis": "raw VidMmProcessUsageChange" if key[0] == "usage" else "raw VidMmProcessCommitmentChange",
                                           "scope": "OS process charge view; separate from deduplicated allocation objects and physical page ownership"}
                                          for key, value in sorted(self.aggregate.items())],
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
        if entry.get("Template", "").strip():
            ET.fromstring(entry["Template"])
        result.add((number(entry["Id"]), number(entry["Version"])))
    return result


def window_summary(allocations, capture, target, trace, decode_meta, frequencies):
    """Compute an observed-graph window peak; this does not assert backend coverage."""
    missing = []
    start, end = capture.get("window_start_qpc"), capture.get("window_end_qpc")
    if type(start) is not int or type(end) is not int or start <= 0 or start >= end:
        return {"verified": False, "missing": ["positive, ordered raw-QPC capture bounds unavailable"],
                "known_sequence_peak_alloc_size_bytes": None, "known_same_timestamp_upper_peak_alloc_size_bytes": None}
    if capture.get("pid") != target:
        missing.append("capture PID differs from trace target")
    game = [p for p in capture.get("processes", []) if p.get("pid") == target and p.get("stem") == "game"]
    if len(game) != 1 or game[0].get("start_utc_ticks") != trace.get("target_start_utc_ticks"):
        missing.append("capture and trace target lifetime identities differ or are absent")
    frequency = capture.get("qpc_frequency")
    if type(frequency) is not int or frequency <= 0 or frequencies != {frequency}:
        missing.append("capture and raw event QPC frequencies differ")
    result = decode_meta.get("result") or {}
    first, last = result.get("FirstRawTimestamp"), result.get("LastRawTimestamp")
    if type(first) is not int or type(last) is not int or first > start or last < end:
        missing.append("full ETL raw timestamps do not cover capture window")
    baseline, changes, by_time = 0, [], defaultdict(lambda: [0, 0])
    for allocation in allocations:
        size = allocation["allocated_bytes"]
        if size is None:
            continue
        for interval, clocks in zip(allocation["target_intervals_sequence"], allocation["target_intervals_clock"]):
            begin, finish = clocks
            if begin is None or begin[0] != "windows_qpc" or (finish is not None and finish[0] != "windows_qpc"):
                missing.append("target allocation interval lacks raw QPC")
                continue
            b, e = begin[2], finish[2] if finish is not None else None
            if b < start and (e is None or e > start):
                baseline += size
            if start <= b < end:
                changes.append((b, interval[0], size))
                by_time[b][0] += size
            if e is not None and start <= e < end and b < end:
                # Intervals already ended at the left boundary are not in baseline.
                if e == start and b < start:
                    continue
                changes.append((e, interval[1], -size))
                by_time[e][1] -= size
    current = sequence_peak = baseline
    for stamp, sequence, amount in sorted(changes):
        current += amount
        sequence_peak = max(sequence_peak, current)
    current = upper_peak = baseline
    for positive, negative in (by_time[stamp] for stamp in sorted(by_time)):
        upper_peak = max(upper_peak, current + positive)
        current += positive + negative
    return {"verified": not missing, "missing": sorted(set(missing)), "start_qpc": start, "end_qpc": end,
            "qpc_frequency": frequency, "membership": "[start,end); same-QPC callback order and conservative upper bound both reported",
            "known_sequence_peak_alloc_size_bytes": sequence_peak if allocations else None,
            "known_same_timestamp_upper_peak_alloc_size_bytes": upper_peak if allocations else None,
            "scope": "observed allocation graph only; not a complete graphics allocation or physical residency claim"}


def counter_window(counter, window):
    if not window["verified"]:
        return {"verified": False, "reason": "formal raw-QPC window unavailable"}
    start, end = window["start_qpc"], window["end_qpc"]
    changes = counter["changes"]
    valid_clock = all(clock is not None and clock[0] == "windows_qpc" and clock[1] == window["qpc_frequency"] for clock, old, new in changes)
    # A first update after window start cannot reconstruct the left boundary.
    baseline_known = bool(changes) and valid_clock and changes[0][0][2] <= start
    if not baseline_known or not counter["continuous"]:
        return {"verified": False, "reason": "continuous raw-QPC counter baseline before window unavailable"}
    current = counter["first_old_bytes"]
    for clock, old, new in changes:
        if clock[2] >= start:
            break
        current = new
    baseline, peak = current, current
    for clock, old, new in changes:
        if start <= clock[2] < end:
            peak = max(peak, old, new)
            current = new
    return {"verified": True, "initial_bytes": baseline, "last_bytes": current, "observed_peak_bytes": peak,
            "start_qpc": start, "end_qpc": end, "scope": "exact emitted OS counter changes; not allocation or physical page dedup"}


class OfflineChecks(unittest.TestCase):
    def event(self, ledger, event, **data):
        ledger.consume({"event_id": event, "version": VERSIONS[event], "system_time": f"2026-10-18T00:00:{ledger.sequence:02d}Z", "data": data})

    def create(self, ledger, handle=7, size=100, owner=42):
        self.event(ledger, 33, pDxgAdapter=1, hVidMmGlobalAlloc=handle, allocSize=size, hProcessId=owner, PhysicalAdapterIndex=0)

    def alias(self, ledger, local, global_handle=7, process=42, stop=False):
        device = process + 1000
        if not stop and (1, device) not in ledger.devices:
            self.event(ledger, 27, pDxgAdapter=1, hDevice=device, hProcessId=process)
        self.event(ledger, 37 if stop else 36, pDxgAdapter=1, hVidMmGlobalAlloc=global_handle, hProcessId=process, hDevice=device, hVidMmAlloc=local)

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

    def test_alias_stop_pid_is_not_the_alias_identity(self):
        ledger = Ledger(42)
        self.create(ledger)
        self.alias(ledger, 10)
        self.event(ledger, 37, pDxgAdapter=1, hVidMmGlobalAlloc=7, hProcessId=4, hDevice=1042, hVidMmAlloc=10)
        self.assertFalse(ledger.aliases)
        self.assertEqual(ledger.records[0].target_aliases, 0)
        self.assertFalse(ledger.issues)

    def test_creation_associated_pid_does_not_override_device_pid(self):
        ledger = Ledger(42)
        self.create(ledger, owner=99)
        self.event(ledger, 27, pDxgAdapter=1, hDevice=5, hProcessId=99)
        self.event(ledger, 36, pDxgAdapter=1, hVidMmGlobalAlloc=7, hProcessId=42, hDevice=5, hVidMmAlloc=10)
        self.assertIsNone(ledger.report()["known_sequence_peak_allocated_bytes"])

    def test_unmapped_flags_and_page_tables_are_preserved_without_arbitrary_exclusion(self):
        ledger = Ledger(42)
        self.event(ledger, 33, pDxgAdapter=1, hVidMmGlobalAlloc=7, allocSize=100,
                   hProcessId=42, PhysicalAdapterIndex=0, Flags="536871040", PageTableOrDirectory="true")
        report = ledger.report()
        self.assertEqual(report["known_sequence_peak_allocated_bytes"], 100)
        self.assertEqual(report["allocation_metadata_groups"][0]["Flags"], "536871040")
        self.assertIsNone(report["allocation_accounting"]["physical_resident_bytes"])
        self.assertEqual(report["allocation_accounting"]["status"], "incomplete")

    def test_window_peak_includes_initial_live_and_unreleased_allocations(self):
        allocations = [{"allocated_bytes": 100, "target_intervals_sequence": [(1, 3)],
                        "target_intervals_clock": [[("windows_qpc", 10, 10), ("windows_qpc", 10, 30)]]},
                       {"allocated_bytes": 200, "target_intervals_sequence": [(2, 5)],
                        "target_intervals_clock": [[("windows_qpc", 10, 20), None]]}]
        capture = {"pid": 42, "window_start_qpc": 20, "window_end_qpc": 40, "qpc_frequency": 10,
                   "processes": [{"pid": 42, "stem": "game", "start_utc_ticks": 7}]}
        result = window_summary(allocations, capture, 42, {"target_start_utc_ticks": 7},
                                {"result": {"FirstRawTimestamp": 1, "LastRawTimestamp": 50}}, {10})
        self.assertTrue(result["verified"])
        self.assertEqual(result["known_sequence_peak_alloc_size_bytes"], 300)
        capture["pid"] = 99
        self.assertFalse(window_summary(allocations, capture, 42, {}, {}, {10})["verified"])

    def test_window_same_qpc_callback_peak_is_separate_from_upper_bound(self):
        allocations = [{"allocated_bytes": 100, "target_intervals_sequence": [(1, 2)],
                        "target_intervals_clock": [[("windows_qpc", 10, 1), ("windows_qpc", 10, 25)]]},
                       {"allocated_bytes": 100, "target_intervals_sequence": [(3, 5)],
                        "target_intervals_clock": [[("windows_qpc", 10, 25), None]]}]
        capture = {"pid": 42, "window_start_qpc": 20, "window_end_qpc": 40, "qpc_frequency": 10,
                   "processes": [{"pid": 42, "stem": "game", "start_utc_ticks": 7}]}
        result = window_summary(allocations, capture, 42, {"target_start_utc_ticks": 7},
                                {"result": {"FirstRawTimestamp": 1, "LastRawTimestamp": 50}}, {10})
        self.assertEqual(result["known_sequence_peak_alloc_size_bytes"], 100)
        self.assertEqual(result["known_same_timestamp_upper_peak_alloc_size_bytes"], 200)

    def test_float_timestamps_and_ambiguous_values_are_rejected(self):
        for value in (float(2**53), True, None, ["1"]):
            with self.assertRaises(ValueError):
                number(value)
        self.assertEqual(number(str(2**63 - 1)), 2**63 - 1)

    def test_os_counter_window_keeps_usage_and_commitment_separate(self):
        window = {"verified": True, "start_qpc": 20, "end_qpc": 40, "qpc_frequency": 10}
        counter = {"continuous": True, "first_old_bytes": 0,
                   "changes": [(("windows_qpc", 10, 10), 0, 100), (("windows_qpc", 10, 30), 100, 50),
                               (("windows_qpc", 10, 40), 50, 1000)]}
        result = counter_window(counter, window)
        self.assertTrue(result["verified"])
        self.assertEqual((result["initial_bytes"], result["observed_peak_bytes"], result["last_bytes"]), (100, 100, 50))
        counter["continuous"] = False
        self.assertFalse(counter_window(counter, window)["verified"])

    def test_mixed_converted_wall_time_does_not_verify_as_raw_qpc(self):
        ledger = Ledger(42)
        raw = {"event_id": 110, "version": 1, "clock_domain": "windows_qpc", "qpc_ticks": 10,
               "qpc_frequency": 10, "data": {"pDxgAdapter": 1, "AdapterLuid": 1, "VendorID": 1, "DeviceID": 1}}
        ledger.consume(raw)
        self.event(ledger, 110, pDxgAdapter=1, AdapterLuid=1, VendorID=1, DeviceID=1)
        meta = {"raw_qpc_valid": True, "result": {"RawFileReadComplete": True, "ProcessStatus": 0, "CloseStatus": 0,
                "TraceHeader": {"reserved_flags_clock_type": 1, "events_lost": 0, "buffers_lost": 0, "perf_frequency": 10}}}
        self.assertFalse(ledger.report(decode_meta=meta)["raw_qpc_verified"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--events", type=Path)
    parser.add_argument("--trace", type=Path)
    parser.add_argument("--schema", type=Path)
    parser.add_argument("--decode-meta", type=Path)
    parser.add_argument("--capture", type=Path, help="Completed capture.json with actual formal raw-QPC window, if available")
    parser.add_argument("--selection-meta", type=Path)
    parser.add_argument("--adapter-events", type=Path)
    parser.add_argument("--lifecycle-events", type=Path)
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
    decode_path = args.decode_meta or Path(str(args.events) + ".meta.json")
    decode_meta = json.loads(decode_path.read_text(encoding="utf-8-sig")) if decode_path.is_file() else {}
    capture_path = args.capture or args.trace.parent.parent / "capture.json"
    capture = json.loads(capture_path.read_text(encoding="utf-8-sig")) if capture_path.is_file() else {}
    ledger = Ledger(target)
    adapter_replacements = {}
    if args.adapter_events:
        for row in read_rows(args.adapter_events):
            if number(row.get("event_id")) != 110:
                parser.error("--adapter-events may only contain the decoded adapter identity event")
            adapter_replacements[number(row["sequence"])] = row
    streams = [read_rows(args.events)]
    if args.lifecycle_events:
        streams.append(read_rows(args.lifecycle_events))
    for row in heapq.merge(*streams, key=lambda r: number(r.get("sequence", 0))):
        if row.get("provider") == "Microsoft-Windows-DxgKrnl":
            replacement = adapter_replacements.pop(number(row.get("sequence", 0)), None)
            if replacement is not None:
                if any(row.get(key) != replacement.get(key) for key in ("sequence", "event_id", "version", "qpc_ticks")):
                    ledger.issue("supplemental_adapter_original_identity_mismatch")
                else:
                    row = replacement
            ledger.consume(row)
    if adapter_replacements:
        ledger.issue("supplemental_adapter_sequence_absent_from_original_events", sequences=sorted(adapter_replacements))
    report = ledger.report(trace, read_schema(schema) if schema.is_file() else None, decode_meta, capture)
    paths = [args.events, args.trace] + [path for path in (schema, decode_path, capture_path, args.selection_meta, args.adapter_events, args.lifecycle_events) if path and path.is_file()]
    report["supplemental_source_validation"] = []
    for path in (args.adapter_events, args.lifecycle_events):
        if not path:
            continue
        meta_path = Path(str(path) + ".meta.json")
        validation = {"path": str(path.resolve()), "verified": False}
        if meta_path.is_file():
            supplement = json.loads(meta_path.read_text(encoding="utf-8-sig"))
            paths.append(meta_path)
            parent_path = Path(supplement["source_decode_meta"])
            parent = json.loads(parent_path.read_text(encoding="utf-8-sig"))
            paths.append(parent_path)
            validation["output_hash_matches"] = digest(path) == supplement.get("output_sha256")
            validation["parent_meta_hash_matches"] = digest(parent_path) == supplement.get("source_decode_meta_sha256")
            validation["same_original_etl"] = supplement.get("original_etl_sha256") == decode_meta.get("etl_sha256") == parent.get("etl_sha256") == parent.get("etl_sha256_after")
            validation["parent_read_complete"] = parent.get("result", {}).get("RawFileReadComplete") is True and parent.get("result", {}).get("ProcessStatus") == 0 and parent.get("result", {}).get("CloseStatus") == 0
            validation["verified"] = all(validation.get(key) is True for key in ("output_hash_matches", "parent_meta_hash_matches", "same_original_etl", "parent_read_complete"))
        if not validation["verified"]:
            report["missing"].append("supplemental raw decode provenance not verified: " + str(path))
        report["supplemental_source_validation"].append(validation)
    if args.selection_meta:
        selection = json.loads(args.selection_meta.read_text(encoding="utf-8-sig"))
        report["streaming_selection"] = {key: selection.get(key) for key in ("source", "source_sha256", "source_bytes", "selected", "total_events", "first_qpc", "last_qpc", "all_counts", "selected_counts")}
        report["streaming_selection"]["original_source_hash_matches_raw_decode_meta"] = selection.get("source_sha256") == decode_meta.get("output_sha256")
        if not report["streaming_selection"]["original_source_hash_matches_raw_decode_meta"]:
            report["missing"].append("selected events source hash does not match raw decode meta")
    report["sources"] = [{"path": str(path.resolve()), "sha256": digest(path)} for path in paths]
    hashes = {item["path"]: item["sha256"] for item in report["sources"]}
    source_checks = {
        "events_hash_matches_decode_output": hashes[str(args.events.resolve())] == decode_meta.get("output_sha256"),
        "schema_hash_matches_decode_input": hashes.get(str(schema.resolve())) == decode_meta.get("schema_sha256") == decode_meta.get("schema_sha256_after", decode_meta.get("schema_sha256")),
        "etl_input_unchanged_during_decode": bool(decode_meta.get("etl_sha256")) and decode_meta.get("etl_sha256") == decode_meta.get("etl_sha256_after"),
        "supplemental_provenance_verified": all(value["verified"] for value in report["supplemental_source_validation"]),
        "required_event_families_in_decode_selection": not decode_meta.get("selected_event_ids") or set(VERSIONS) <= set(decode_meta["selected_event_ids"]),
    }
    if args.selection_meta:
        source_checks["events_hash_matches_decode_output"] = bool(selection.get("selected_sha256")) and hashes[str(args.events.resolve())] == selection.get("selected_sha256") and report["streaming_selection"]["original_source_hash_matches_raw_decode_meta"]
    report["input_provenance"] = {"verified": all(source_checks.values()), "checks": source_checks}
    if not report["input_provenance"]["verified"]:
        report["missing"].append("raw event output/schema/ETL provenance checks incomplete; a manually selected file needs its own recorded selected_sha256")
    identity_verified = (report["input_provenance"]["verified"] and report["raw_qpc_verified"]
                         and report["observed_identity_join"]["all_target_sizes_and_adapter_ids_joined"]
                         and schema.is_file() and not (ledger.seen_versions - read_schema(schema))
                         and bool(trace.get("target_start_utc_ticks")) and trace.get("started_before_target") is True
                         and trace.get("trace_final", {}).get("code") == 0
                         and all(trace.get("trace_final", {}).get(name) == 0 for name in ("events_lost", "log_buffers_lost", "realtime_buffers_lost")))
    report["allocation_identity"] = {"status": "verified" if identity_verified else "incomplete",
        "scope": "observed target graph only; identity join and device/process alias dedup, not complete backend coverage or physical page dedup",
        "dedup_key": report["dedup_key"], "unreleased_observed_globals_included": True}
    report["tool"] = {"path": str(Path(__file__).resolve()), "sha256": digest(Path(__file__))}
    with args.output.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(report, stream, indent=2)
        stream.write("\n")
    print(json.dumps({"status": report["status"], "target_allocation_lifetimes": report["target_allocation_lifetimes"], "known_sequence_peak_allocated_bytes": report["known_sequence_peak_allocated_bytes"], "output": str(args.output.resolve())}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
