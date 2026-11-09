"""Check portable output and write the final complete hash inventory."""
import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image
from catalog import write_json

p=argparse.ArgumentParser()
p.add_argument("--destination",type=Path,required=True)
a=p.parse_args();root=a.destination.resolve();errors=[]
models=json.loads((root/"art-source/production/validation/glb-files.json").read_text(encoding="utf-8"))["models"]
for record in models:
    target=root/record["path"]
    if not target.is_file() or hashlib.sha256(target.read_bytes()).hexdigest()!=record["sha256"]:
        errors.append("GLB identity mismatch: "+record["path"])
plan=json.loads((root/"assets/asset-plan.json").read_text(encoding="utf-8"))
for requirement in plan["requirements"]:
    for relative in requirement["required_paths"]:
        file=root/relative
        if not file.is_file() or not file.stat().st_size:errors.append("Required file missing/empty: "+relative)
images=[];manifest=[];source_count=0
for path in sorted(root.rglob("*")):
    if ".godot" in path.relative_to(root).parts:continue
    if path.is_symlink() or path.is_junction():errors.append("Nonportable link: "+str(path))
    if not path.is_file() or path.name=="asset-package.json":continue
    relative=path.relative_to(root).as_posix()
    if path.suffix==".png":
        with Image.open(path) as image:image.load();dimensions=list(image.size)
        if path.stat().st_size>=50000:errors.append("Image exceeds byte budget: "+relative)
        images.append({"path":relative,"bytes":path.stat().st_size,"dimensions":dimensions})
    if path.suffix==".blend":source_count+=1
    if path.suffix in (".blend1",".pyc",".tmp") or path.name=="prompts.json":errors.append("Draft/cache in delivery: "+relative)
    raw=path.read_bytes()
    manifest.append({"path":relative,"bytes":len(raw),"sha256":hashlib.sha256(raw).hexdigest()})
if errors:raise ValueError("\n".join(errors))
inventory={"schema":1,"status":"verified","counts":plan["counts"],"file_count":len(manifest),
    "total_bytes":sum(f["bytes"] for f in manifest),"source_blend_files":source_count,
    "png_count":len(images),"png_max_bytes":max(v["bytes"] for v in images),
    "source_commit":"43be3ca41d950e6fde4597edb3b746cdaa826610",
    "code_branch":"codex/complete-game-assets-20261108","runtime":"Godot 4.7.2 Compatibility",
    "validation":"art-source/production/validation/asset-audit.json","files":manifest}
write_json(root/"asset-package.json",inventory)
print(json.dumps({k:inventory[k] for k in ("status","file_count","total_bytes","source_blend_files","png_count","png_max_bytes")},ensure_ascii=False))
