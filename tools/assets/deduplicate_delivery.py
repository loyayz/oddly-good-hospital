"""Consolidate identical delivered media without changing content identities.

The published indices own file locations. Canonical paths are shared only for
byte-identical pictures/sources and equal decoded audio with equal loop policy.
"""
from __future__ import annotations

import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path
import re

from catalog import write_json


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def natural_key(value: str):
    return [int(part) if part.isdigit() else part for part in re.split(r"(\d+)",value)]


def duplicate_groups(root: Path, suffixes: set[str]):
    sizes=defaultdict(list)
    for base in (root/"assets/ui",root/"art-source/production"):
        for path in base.rglob("*"):
            if path.is_file() and path.suffix in suffixes:
                sizes[path.stat().st_size].append(path)
    for paths in sizes.values():
        if len(paths)<2:
            continue
        hashes=defaultdict(list)
        for path in paths:
            hashes[digest(path)].append(path)
        for group in hashes.values():
            if len(group)>1:
                yield sorted((p.relative_to(root).as_posix() for p in group),key=natural_key)


def rewrite_paths(value, aliases):
    if isinstance(value,str):
        return aliases.get(value,value)
    if isinstance(value,list):
        return [rewrite_paths(item,aliases) for item in value]
    if isinstance(value,dict):
        return {key:rewrite_paths(item,aliases) for key,item in value.items()}
    return value


def compact_package(root: Path, apply=False):
    import soundfile as sf
    aliases={}
    for group in duplicate_groups(root,{".png",".svg",".wav"}):
        for redundant in group[1:]:
            aliases[redundant]=group[0]

    audio=json.loads((root/"assets/audio/index.json").read_text(encoding="utf-8"))
    sources=defaultdict(list)
    for clip in audio["clips"]:
        source=aliases.get(clip["source_path"],clip["source_path"])
        sources[(source,bool(clip["loop"]),int(clip["channels"]),int(clip["sample_rate"]),int(clip["frames"]))].append(clip)
    for group in sources.values():
        if len(group)<2:
            continue
        decoded=defaultdict(list)
        for clip in group:
            samples,rate=sf.read(root/clip["path"],dtype="float32",always_2d=True)
            key=(rate,samples.shape,hashlib.sha256(samples.tobytes()).hexdigest())
            decoded[key].append(clip["path"])
        for paths in decoded.values():
            paths=sorted(set(paths),key=natural_key)
            for redundant in paths[1:]:
                aliases[redundant]=paths[0]

    duplicate_plan=root/"art-source/production/resource-plan.json"
    if duplicate_plan.exists():
        if digest(duplicate_plan)!=digest(root/"assets/asset-plan.json"):
            raise ValueError("The source resource plan differs from the published plan")
        aliases[duplicate_plan.relative_to(root).as_posix()]="assets/asset-plan.json"

    sidecars=[path+".import" for path in aliases if (root/(path+".import")).is_file()]
    retired={**{path:digest(root/path) for path in aliases},**{path:digest(root/path) for path in sidecars}}
    retired_sizes={path:(root/path).stat().st_size for path in retired}
    removed_bytes=sum(retired_sizes.values())
    # Native resources use exact quoted res:// paths; update those with indices.
    runtime_changes={}
    for path in root.rglob("*"):
        if ".godot" not in path.parts and path.suffix in {".gd",".tscn",".tres",".gdshader",".ps1",".godot"}:
            text=path.read_text(encoding="utf-8")
            original_text=text
            for retired_path in aliases:
                if retired_path in text:
                    text=text.replace('"res://'+retired_path+'"','"res://'+aliases[retired_path]+'"')
                    if retired_path in text:
                        raise ValueError("Unrecognized direct reference needs repair: "+str(path)+":"+retired_path)
            if text!=original_text:
                runtime_changes[path]=(digest(path),text)
    report={"schema":1,"aliases":aliases,"retired_hashes":retired,"removed_files":len(retired),
            "removed_bytes":removed_bytes,"audio_identity":"exact decoded float32 samples and matching loop/rate/channel/frame policy",
            "content_identity":"all IDs and authored definitions retained"}
    if not apply:
        return report
    previous_report=root/"art-source/production/validation/packaging.json"
    if not aliases and previous_report.is_file():
        return json.loads(previous_report.read_text(encoding="utf-8"))
    for relative,expected in retired.items():
        path=root/relative
        if not path.resolve().is_relative_to(root) or path.is_symlink() or path.is_junction() or digest(path)!=expected:
            raise ValueError("Retired file changed after inspection: "+relative)
    for path,(expected,text) in runtime_changes.items():
        if digest(path)!=expected:
            raise ValueError("Runtime resource changed after inspection: "+str(path))
        path.write_text(text,encoding="utf-8",newline="\n")

    # The report is prepared before mutations; each delete is confined to root
    # and rechecks the inspected content hash.
    metadata={};original={}
    for path in (root/"assets").rglob("*.json"):
        original[path]=json.loads(path.read_text(encoding="utf-8"))
        metadata[path]=rewrite_paths(original[path],aliases)
    published=metadata[root/"assets/asset-plan.json"]
    published["file_aliases"]={**published.get("file_aliases",{}),**aliases}
    for clip in metadata[root/"assets/audio/index.json"]["clips"]:
        clip["sha256"]=digest(root/clip["path"])
        clip["encoded_bytes"]=(root/clip["path"]).stat().st_size
    for path,data in metadata.items():
        if data!=original[path]:
            write_json(path,data)
    image_manifest=root/"art-source/production/validation/png-files.json"
    if image_manifest.exists():
        images=rewrite_paths(json.loads(image_manifest.read_text(encoding="utf-8")),aliases)
        images["images"]=list({image["path"]:image for image in images["images"]}.values())
        write_json(image_manifest,images)
    for relative,expected in retired.items():
        path=root/relative
        if not path.resolve().is_relative_to(root) or path.is_symlink() or path.is_junction() or digest(path)!=expected:
            raise ValueError("Retired file changed after inspection: "+relative)
        path.unlink()
    report["physical_audio_streams"]=len({c["path"] for c in metadata[root/"assets/audio/index.json"]["clips"]})
    report["physical_audio_sources"]=len({c["source_path"] for c in metadata[root/"assets/audio/index.json"]["clips"]})
    report["physical_ui_png"]=len(list((root/"assets/ui").rglob("*.png")))
    report["logical_audio_cues"]=len(audio["clips"])
    report["logical_ui_entries"]=len(metadata[root/"assets/ui/icon-index.json"]["icons"])
    if previous_report.is_file():
        previous=json.loads(previous_report.read_text(encoding="utf-8"))
        report["last_pass_removed_files"]=report["removed_files"]
        report["aliases"]={**previous.get("aliases",{}),**report["aliases"]}
        report["retired_hashes"]={**previous.get("retired_hashes",{}),**report["retired_hashes"]}
        report["removed_files"]=len(report["retired_hashes"])
        report["removed_bytes"]=previous.get("removed_bytes",0)+sum(retired_sizes[path]
            for path in retired if path not in previous.get("retired_hashes",{}))
        if "native_media_check" in previous:
            report["native_media_check"]=previous["native_media_check"]
    report["rewritten_runtime_files"]=len(runtime_changes)
    write_json(root/"art-source/production/validation/packaging.json",report)
    return report


if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("--root",type=Path,required=True)
    parser.add_argument("--apply",action="store_true")
    args=parser.parse_args()
    result=compact_package(args.root.resolve(),args.apply)
    print(json.dumps({key:value for key,value in result.items() if key not in {"aliases","retired_hashes"}},ensure_ascii=False))
