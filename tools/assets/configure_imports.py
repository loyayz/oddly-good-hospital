"""Use the same vertex-color and Compatibility import contract for every GLB."""
import argparse
import re
import json
import struct
from pathlib import Path

p=argparse.ArgumentParser();p.add_argument("--root",type=Path,required=True);a=p.parse_args()
count=0
for path in (a.root/"assets").rglob("*.glb.import"):
    if path.parent.name=="gags":continue
    text=path.read_text(encoding="utf-8")
    value='import_script/path="res://assets/runtime/import_hospital_assets.gd"'
    if re.search(r'^import_script/path=',text,re.M):
        text=re.sub(r'^import_script/path=.*$',value,text,flags=re.M)
    else:text=text.replace("_subresources=",value+"\n_subresources=")
    glb=Path(str(path).removesuffix(".import")).read_bytes()
    doc=json.loads(glb[20:20+struct.unpack_from("<I",glb,12)[0]])
    if doc.get("skins"):
        text=re.sub(r'^meshes/force_disable_compression=.*$',"meshes/force_disable_compression=true",text,flags=re.M)
    # The explicit root identity also causes existing imports to pick up the
    # portable post-import dependency rather than retaining an old game path.
    root_name=path.name.removesuffix(".glb.import")
    text=re.sub(r'^nodes/root_name=.*$',f'nodes/root_name="{root_name}"',text,flags=re.M)
    path.write_text(text,encoding="utf-8",newline="\n")
    count+=1
print("CONFIGURED_IMPORTS="+str(count))
