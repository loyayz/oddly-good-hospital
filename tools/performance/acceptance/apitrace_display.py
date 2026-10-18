"""Reconstruct actual OpenGL draw attachments; never a timing or memory budget."""
import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
import re
import struct


CALL = re.compile(r"^(\d+)\s+@([0-9a-fA-F]+)\s+(\w+)\((.*)\)(?: = (.*?))?(?: //.*)?$")


def number(value):
    return int(str(value).lstrip("&"), 0)


def split_args(value):
    parts, start, depth, quoted, escaped = [], 0, 0, False, False
    for index, char in enumerate(value):
        if quoted:
            if escaped: escaped = False
            elif char == "\\": escaped = True
            elif char == '"': quoted = False
        elif char == '"': quoted = True
        elif char in "({[": depth += 1
        elif char in ")}]": depth -= 1
        elif char == "," and depth == 0:
            parts.append(value[start:index]); start = index+1
    parts.append(value[start:])
    return dict(part.strip().split(" = ", 1) for part in parts if " = " in part)


def source(path):
    path = Path(path)
    with path.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    return {"path":str(path.resolve()), "sha256":digest}


class GLState:
    def __init__(self):
        self.threads, self.contexts, self.groups = {}, {}, {}
        self.frame_draws, self.last_frame_draws, self.readbacks = [], [], []
        self.generation, self.calls, self.swaps = 0, 0, 0
        self.ignored_synthetic_calls = 0

    def context(self, handle):
        return self.contexts.setdefault(handle, {"group":handle,"textures":{},"unit":"GL_TEXTURE0",
            "draw":0,"read":0,"rb":None,"viewport":None,"fbos":{}})

    def namespace(self, context):
        return self.groups.setdefault(context["group"], {"textures":{},"renderbuffers":{}})

    def object(self, context, kind, name):
        objects = self.namespace(context)[kind]
        if name not in objects:
            self.generation += 1
            objects[name] = {"name":name,"generation":self.generation,"levels":{}}
        return objects[name]

    def fbo(self, context, name):
        return context["fbos"].setdefault(name, {"attachments":{},"complete":False,"check_call":None})

    def texture(self, context, target):
        return context["textures"].get((context["unit"],target))

    def attachment(self, value):
        if not value: return None
        obj = value["object"]
        storage = obj["levels"].get(value["level"])
        if storage is None: return None
        return {"kind":value["kind"],"object":obj["name"],"generation":obj["generation"],
            "level":value["level"],"pixels":storage["pixels"],"storage_call":storage["call"],
            "attachment_call":value["call"]}

    def draw(self, context, call):
        fbo = self.fbo(context,context["draw"])
        if context["viewport"] is None: return
        colors = [self.attachment(value) for name,value in fbo["attachments"].items() if name.startswith("GL_COLOR_ATTACHMENT")]
        depth = next((self.attachment(value) for name,value in fbo["attachments"].items() if "DEPTH" in name),None)
        for color in colors:
            if color:
                self.frame_draws.append({"draw_call":call,"frame_index":self.swaps,"context":self.threads[self.tid],
                    "framebuffer":context["draw"],"framebuffer_complete":fbo["complete"],"framebuffer_check_call":fbo["check_call"],
                    "viewport_pixels":context["viewport"][0],"viewport_call":context["viewport"][1],"color":color,"depth":depth,
                    "bound_textures":[{"unit":unit,"target":target,"object":obj["name"],"generation":obj["generation"],
                        "pixels":obj["levels"][0]["pixels"],"storage_call":obj["levels"][0]["call"]}
                        for (unit,target),obj in context["textures"].items() if obj and 0 in obj["levels"]]})

    def readback(self, context, name, args, call):
        if name == "glReadPixels":
            pixels = [number(args["width"]),number(args["height"])]
            fbo = self.fbo(context,context["read"])
            image = self.attachment(fbo["attachments"].get("GL_COLOR_ATTACHMENT0"))
        else:
            obj = (self.object(context,"textures",number(args["texture"])) if name == "glGetTextureImage"
                else self.texture(context,args["target"]))
            level = number(args.get("level",0))
            storage = obj["levels"].get(level) if obj else None
            if storage is None: return
            pixels = storage["pixels"]
            image = {"object":obj["name"],"generation":obj["generation"],"pixels":pixels,"storage_call":storage["call"]}
        self.readbacks.append({"call":call,"kind":name,"pixels":pixels,"image":image,
            "draws":copy.deepcopy(self.frame_draws or self.last_frame_draws)})

    def consume(self, line):
        match = CALL.match(line.strip())
        if not match: return
        if re.search(r" //.*\bincomplete\b",line):
            raise ValueError("Incomplete selected GL call: "+line.strip())
        if re.search(r" //.*\bfake\b",line):
            self.ignored_synthetic_calls += 1
            return
        call, tid, name, arguments, result = match.groups()
        call, self.tid = int(call), int(tid,16)
        self.calls += 1
        args = split_args(arguments)
        if name == "wglMakeCurrent":
            if result in ("TRUE","true","1"): self.threads[self.tid] = args["hglrc"]
            return
        if name in ("wglCreateContext", "wglCreateContextAttribsARB"):
            if not result or result in ("NULL","0x0"): return
            context = self.context(result)
            share = args.get("hShareContext")
            if share and share not in ("NULL","0x0"): context["group"] = self.context(share)["group"]
            return
        if name == "wglShareLists":
            if result in ("TRUE","true","1"): self.context(args["hglrc2"])["group"] = self.context(args["hglrc1"])["group"]
            return
        if name == "wglDeleteContext":
            if result in ("TRUE","true","1"):
                deleted = self.contexts.pop(args["hglrc"],None)
                if deleted and not any(other["group"] == deleted["group"] for other in self.contexts.values()):
                    self.groups.pop(deleted["group"],None)
            return
        if name in ("SwapBuffers","wglSwapBuffers","wglSwapLayerBuffers","glXSwapBuffers","eglSwapBuffers"):
            if self.frame_draws: self.last_frame_draws = self.frame_draws
            self.frame_draws = []
            self.swaps += 1
            return
        handle = self.threads.get(self.tid)
        if not handle or handle in ("NULL","0x0"): return
        context = self.context(handle)
        if name == "glActiveTexture": context["unit"] = args["texture"]
        elif name == "glBindTexture":
            texture = number(args["texture"])
            context["textures"][(context["unit"],args["target"])] = self.object(context,"textures",texture) if texture else None
        elif name.startswith(("glGenTextures","glGenRenderbuffers","glDeleteTextures","glDeleteRenderbuffers")):
            kind = "textures" if "Textures" in name else "renderbuffers"
            values = [int(value) for value in re.findall(r"\d+", args[kind])]
            for value in values:
                if name.startswith("glGen"): self.object(context,kind,value)
                else: self.namespace(context)[kind].pop(value,None)
        elif name == "glBindRenderbuffer": context["rb"] = self.object(context,"renderbuffers",number(args["renderbuffer"]))
        elif name.startswith(("glTexImage","glTexStorage","glTextureStorage","glTextureImage","glRenderbufferStorage")):
            if "width" not in args or "height" not in args: return
            if name.startswith("glRenderbuffer"): obj = context["rb"]
            elif "texture" in args: obj = self.object(context,"textures",number(args["texture"]))
            else: obj = self.texture(context,args["target"])
            if obj is None: return
            level = number(args.get("level",0))
            obj["levels"][level] = {"pixels":[number(args["width"]),number(args["height"])],"call":call}
            for other in self.contexts.values():
                for fbo in other["fbos"].values():
                    if any(value["object"] is obj for value in fbo["attachments"].values()): fbo["complete"] = False
        elif name == "glBindFramebuffer":
            target, framebuffer = args["target"],number(args["framebuffer"])
            if target in ("GL_FRAMEBUFFER","GL_DRAW_FRAMEBUFFER"): context["draw"] = framebuffer
            if target in ("GL_FRAMEBUFFER","GL_READ_FRAMEBUFFER"): context["read"] = framebuffer
        elif name.startswith("glDeleteFramebuffers"):
            for value in re.findall(r"\d+",args["framebuffers"]): context["fbos"].pop(int(value),None)
        elif name.startswith(("glFramebufferTexture","glFramebufferRenderbuffer")):
            target = args["target"]
            fbo = self.fbo(context,context["read"] if target == "GL_READ_FRAMEBUFFER" else context["draw"])
            kind = "textures" if "texture" in args else "renderbuffers"
            value = number(args.get("texture",args.get("renderbuffer")))
            if value:
                fbo["attachments"][args["attachment"]] = {"object":self.object(context,kind,value),
                    "kind":kind,"level":number(args.get("level",0)),"call":call}
            else: fbo["attachments"].pop(args["attachment"],None)
            fbo["complete"] = False
        elif name == "glCheckFramebufferStatus":
            fbo = self.fbo(context,context["read"] if args["target"] == "GL_READ_FRAMEBUFFER" else context["draw"])
            fbo.update(complete=result == "GL_FRAMEBUFFER_COMPLETE",check_call=call)
        elif name == "glViewport": context["viewport"] = ([number(args["width"]),number(args["height"])],call)
        elif name.startswith(("glDrawArrays","glDrawElements")): self.draw(context,call)
        elif name in ("glReadPixels","glGetTexImage","glGetTextureImage"): self.readback(context,name,args,call)


def analyze(folder):
    folder = Path(folder)
    identity = json.loads((folder/"apitrace-identity.json").read_text(encoding="utf-8-sig"))
    cleanup = json.loads((folder/"process-cleanup.json").read_text(encoding="utf-8-sig"))
    for key,name in (("trace","display.trace"),("dump","gl-calls.txt")):
        if source(folder/name)["sha256"] != identity[key+"_sha256"]:
            raise ValueError("Preserved original trace/dump identity differs: "+name)
    if cleanup.get("pid") != identity["pid"] or cleanup.get("exit_code") != 0 or cleanup.get("forced") is not False:
        raise ValueError("Owned renderer did not complete normally")
    products = json.loads((folder/"product-copy.json").read_text(encoding="utf-8-sig"))
    for product in products:
        if source(product["copy"])["sha256"] != product["sha256"]:
            raise ValueError("Original same-byte product copy changed: "+product["path"])
    for observer in json.loads((folder/"observer-sources.json").read_text(encoding="utf-8-sig")):
        if source(observer["path"])["sha256"] != observer["sha256"]:
            raise ValueError("Captured observer source changed: "+observer["path"])
    state = GLState()
    with (folder/"gl-calls.txt").open(encoding="utf-8-sig") as stream:
        for line in stream: state.consume(line)
    conditions = []
    metadata = sorted(folder.glob("display-[0-9][0-9].json"))
    if state.swaps < len(metadata):
        raise ValueError("Actual GL swap boundaries unavailable for each display condition")
    if len(metadata) != identity["condition_count"] or len(metadata) != len(state.readbacks):
        raise ValueError("Root metadata/readback count differs: %d/%d; no guessed call association" % (len(metadata),len(state.readbacks)))
    for path,readback in zip(metadata,state.readbacks):
        record = json.loads(path.read_text(encoding="utf-8-sig"))
        png = Path(record["root_png"]["path"])
        with png.open("rb") as stream: header = stream.read(24)
        if header[:8] != b"\x89PNG\r\n\x1a\n" or list(struct.unpack(">II",header[16:24])) != record["root_raster_pixels"]:
            raise ValueError("Actual PNG dimensions differ from root metadata")
        if source(png)["sha256"] != record["root_png"]["sha256"] or record["pid"] != identity["pid"]:
            raise ValueError("PNG or owned process identity differs")
        physical = record["scene_control_physical_extent"]
        output = record["scene_output_pixels"]
        expected = [int(value*record["scene_scale"]) for value in output]
        root_draws,depth_draws = [],[]
        for draw in readback["draws"]:
            if not draw["framebuffer_complete"]: continue
            if draw["color"]["pixels"] == record["root_raster_pixels"] and readback["image"] and all(
                draw["color"][key] == readback["image"][key] for key in ("object","generation")):
                root_draws.append(draw)
            if draw["depth"] and all(abs(draw["viewport_pixels"][i]-expected[i])<=1
                and abs(draw["color"]["pixels"][i]-expected[i])<=1
                and abs(draw["depth"]["pixels"][i]-expected[i])<=1 for i in (0,1)):
                depth_draws.append(draw)
        root_scene_inputs = {(texture["object"],texture["generation"]) for draw in root_draws
            for texture in draw["bound_textures"] if texture["pixels"] == output}
        scene_chains = []
        for draw in depth_draws:
            color = draw["color"]
            key = color["object"],color["generation"]
            if key in root_scene_inputs:
                scene_chains.append({"depth_draw_call":draw["draw_call"],"upscale_draw_call":None,"root_input":list(key)})
            for upscale in readback["draws"]:
                target = upscale["color"]
                target_key = target["object"],target["generation"]
                if (upscale["framebuffer_complete"] and target_key in root_scene_inputs
                    and any((texture["object"],texture["generation"]) == key for texture in upscale["bound_textures"])):
                    scene_chains.append({"depth_draw_call":draw["draw_call"],"upscale_draw_call":upscale["draw_call"],"root_input":list(target_key)})
        release = record["features"] == {"template":True,"release":True,"debug":False}
        requested = (record["window_pixels"] == record["condition"]["window_pixels"]
            and record["ui_scale_percent"] == record["condition"]["ui_scale_percent"]
            and math.isclose(record["scene_scale"],record["condition"]["scene_scale_bp"]/10000,abs_tol=1e-5))
        geometry = all(abs(output[i]-physical[i])<3.001 for i in (0,1))
        nearest_even = [2*math.floor(value*record["scene_scale"]/2+0.5) for value in physical]
        even_draws = [draw for draw in depth_draws if draw["color"]["pixels"] == nearest_even
            and draw["depth"]["pixels"] == nearest_even and draw["viewport_pixels"] == nearest_even]
        correspondence = (release and requested and geometry and record["native_2d_mode"] == 1
            and record.get("native_2d_raster_matches_canvas") is True
            and readback["pixels"] == record["root_raster_pixels"] and bool(root_draws) and bool(depth_draws) and bool(scene_chains))
        verified = correspondence and bool(even_draws)
        conditions.append({"metadata":source(path),"record":record,"verified":verified,"backend_attachment_correspondence_verified":correspondence,
            "root_readback":{k:v for k,v in readback.items() if k != "draws"},"actual_root_draw_targets":root_draws,
            "actual_3d_depth_draw_targets":depth_draws,"geometry_matches_control":geometry,
            "scene_depth_to_output_root_bound_texture_chains":scene_chains,
            "nearest_even_3d_policy_pixels":nearest_even,"nearest_even_3d_policy_satisfied":bool(even_draws),
            "actual_release":release,"requested_display_matches":requested})
    return {"kind":"actual_opengl_display_attachments","status":"verified" if conditions and all(c["verified"] for c in conditions) else "incomplete",
        "condition_count":len(conditions),"interpreted_calls":state.calls,"swap_calls":state.swaps,
        "ignored_synthetic_calls":state.ignored_synthetic_calls,"conditions":conditions,
        "sources":[source(folder/"display.trace"),source(folder/"gl-calls.txt"),source(folder/"apitrace-identity.json"),source(__file__)],
        "scope":"real traced GL allocation calls, successful FBO checks, attachments, viewport and draws associated with actual PNG readbacks; instrumented display-only preset, not timing, GPU memory budget, OS presentation or business-load evidence"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("folder",type=Path)
    parser.add_argument("--output",type=Path)
    args = parser.parse_args()
    report = analyze(args.folder)
    output = args.output or args.folder/"gl-render-target-evidence.json"
    with output.open("x",encoding="utf-8") as stream:
        stream.write(json.dumps(report,indent=2)+"\n")
    print(str(output))
    raise SystemExit(0 if report["status"] == "verified" else 2)
