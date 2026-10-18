"""Run through qrenderdoc --python; capture/replay display geometry only.

Instrumentation changes timings and memory. None of this output is a formal
performance population, allocation ledger, OS residency measurement or GPU budget.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
import traceback

import renderdoc as rd


def digest(path):
    value = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def source(path):
    return {"path": str(Path(path).resolve()), "sha256": digest(path)}


def actions(items):
    for item in items:
        yield item
        yield from actions(item.children)


def inspect_capture(path):
    capture = rd.OpenCaptureFile()
    controller = None
    try:
        status = capture.OpenFile(str(path), "", None)
        if status != rd.ResultCode.Succeeded:
            raise RuntimeError("Capture OpenFile: " + str(status))
        status, controller = capture.OpenCapture(rd.ReplayOptions(), None)
        if status != rd.ResultCode.Succeeded:
            raise RuntimeError("Capture OpenCapture: " + str(status))
        textures = {item.resourceId: item for item in controller.GetTextures()}
        groups = {}
        for action in actions(controller.GetRootActions()):
            if not action.flags & rd.ActionFlags.Drawcall:
                continue
            controller.SetFrameEvent(action.eventId, False)
            pipeline = controller.GetPipelineState()
            depth = pipeline.GetDepthTarget().resource
            viewport = pipeline.GetViewport(0)
            for output in pipeline.GetOutputTargets():
                texture = textures.get(output.resource)
                if texture is None:
                    continue
                depth_texture = textures.get(depth)
                key = (str(output.resource), int(viewport.width), int(viewport.height), bool(depth_texture))
                if key not in groups:
                    groups[key] = {"output_resource": str(output.resource),
                        "output_pixels": [texture.width, texture.height],
                        "viewport_pixels": [viewport.width, viewport.height],
                        "depth_resource": str(depth) if depth_texture else None,
                        "depth_pixels": [depth_texture.width, depth_texture.height] if depth_texture else None,
                        "first_draw_event": action.eventId, "draw_calls": 0}
                groups[key]["draw_calls"] += 1
        return {"api": str(controller.GetAPIProperties().pipelineType),
            "draw_target_groups": list(groups.values()), "capture": source(path),
            "scope": "actual replayed draw attachment and viewport dimensions, not requested-size multiplication"}
    finally:
        if controller is not None:
            controller.Shutdown()
        capture.Shutdown()


def main(config):
    output = Path(config["output_dir"])
    opts = rd.CaptureOptions()
    opts.refAllResources = True
    result = rd.ExecuteAndInject(config["exe"], str(Path(config["exe"]).parent),
        subprocess.list2cmdline(["--", "--config=" + config["scenario"]]), [],
        str(output / "display"), opts, False)
    if result.result != rd.ResultCode.Succeeded:
        raise RuntimeError("ExecuteAndInject: " + str(result.result))
    target = rd.CreateTargetControl("", result.ident, "Hospital display boundary", True)
    if target is None:
        raise RuntimeError("RenderDoc target control unavailable")
    identity = output / "target-identity.json.next"
    identity.write_text(json.dumps({"pid": target.GetPID(),
        "exe": config["exe"], "exe_sha256": digest(config["exe"])}), encoding="utf-8")
    identity.replace(output / "target-identity.json")
    captures, current, deadline = [], 0, time.monotonic() + config.get("timeout_seconds", 300)
    try:
        while current < config["condition_count"]:
            ready = output / ("display-%02d.json" % current)
            requested = False
            while time.monotonic() < deadline:
                if ready.is_file() and not requested:
                    try:
                        record = json.loads(ready.read_text(encoding="utf-8-sig"))
                    except json.JSONDecodeError:
                        time.sleep(0.01)
                        continue
                    if record["pid"] != target.GetPID():
                        raise RuntimeError("Owned renderer PID changed")
                    target.TriggerCapture(1)
                    requested = True
                message = target.ReceiveMessage(None)
                if message.type == rd.TargetControlMessageType.NewCapture:
                    if not requested:
                        raise RuntimeError("Unrequested capture")
                    incoming = message.newCapture
                    if not incoming.local:
                        raise RuntimeError("Local capture expected; remote bytes not substituted")
                    path = Path(incoming.path)
                    if path.resolve().parent != output.resolve() or not path.is_file():
                        raise RuntimeError("Capture outside owned output")
                    captures.append({"condition": record, "metadata_source": source(ready),
                        "frame_number": incoming.frameNumber, "path": str(path.resolve())})
                    (output / ("display-%02d.ack" % current)).write_text("captured\n", encoding="utf-8")
                    current += 1
                    break
                if not target.Connected():
                    raise RuntimeError("Renderer exited before all display conditions")
                time.sleep(0.01)
            else:
                raise RuntimeError("Display capture watchdog expired")
    finally:
        target.Shutdown()
    # Replay is independent and occurs after the capture workload has finished.
    conditions = []
    for capture in captures:
        replay = inspect_capture(Path(capture["path"]))
        record = capture["condition"]
        physical = record["scene_control_physical_extent"]
        output_size = record["scene_output_pixels"]
        expected = [int(value * record["scene_scale"]) for value in output_size]
        depth_draws = [group for group in replay["draw_target_groups"] if group["depth_pixels"]
            and all(abs(group["viewport_pixels"][i] - expected[i]) <= 1 for i in (0, 1))
            and all(abs(group["output_pixels"][i] - expected[i]) <= 1 for i in (0, 1))]
        native = all(0 <= output_size[i] - physical[i] < 1.001 for i in (0, 1))
        root_draws = [group for group in replay["draw_target_groups"]
            if group["output_pixels"] == record["root_raster_pixels"]]
        release = record["features"].get("template") is True and record["features"].get("release") is True and record["features"].get("debug") is False
        requested = record["window_pixels"] == record["condition"]["window_pixels"] and record["ui_scale_percent"] == record["condition"]["ui_scale_percent"]
        conditions.append({**capture, "backend": replay, "geometry_matches_control": native,
            "actual_3d_depth_draw_targets": depth_draws, "actual_root_draw_targets": root_draws,
            "actual_release": release, "requested_display_matches": requested,
            "verified": native and bool(depth_draws) and bool(root_draws) and release and requested and record["native_2d_mode"] == 1})
    report = {"kind": "renderdoc_display_boundaries", "status": "verified" if all(c["verified"] for c in conditions) else "incomplete",
        "condition_count": len(conditions), "conditions": conditions,
        "sources": [source(config["exe"]), source(config["pack"]), source(__file__), source(config["scenario"])],
        "scope": "display-only legal preset; injected capture/replay overhead excluded from formal performance; not allocation/residency or 160-person load evidence"}
    (output / "render-target-evidence.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")


try:
    main(json.loads(Path(os.environ["HOSPITAL_RENDERDOC_CONFIG"]).read_text(encoding="utf-8-sig")))
except BaseException:
    target = Path(os.environ["HOSPITAL_RENDERDOC_CONFIG"]).parent
    (target / "renderdoc-error.txt").write_text(traceback.format_exc(), encoding="utf-8")
    (target / "display.abort").write_text("capture failed\n", encoding="utf-8")
    os._exit(2)
os._exit(0)
