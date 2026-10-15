"""Functional release-content checks; never measures performance."""
import copy
import csv
import io
import json
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/"game/content"))
from content_pipeline import (CHINESE, ROOT, SCHEMA_PATH, ContentError, design_sources,
                              encoded, load_packs, normalize, publish, sha, thaw)

schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
core = ROOT/"content/core"
checks = []


def check(condition, label):
    if not condition:
        raise ContentError(label)
    checks.append(label)


def write_pack(directory, tables, requires=None, pack_id="official.garden"):
    directory.mkdir(parents=True, exist_ok=True)
    locale = {}
    def text(value, prefix):
        if isinstance(value,str) and CHINESE.search(value):
            key=pack_id+"."+prefix
            locale[key]=value
            return "@zh:"+key
        if isinstance(value,list):
            return [text(child,prefix+"."+str(index)) for index,child in enumerate(value)]
        if isinstance(value,dict):
            return {key:text(child,prefix+"."+key) for key,child in value.items()}
        return value
    payloads={name+".json":encoded(text(value,name)) for name,value in tables.items()}
    csv_text=io.StringIO(newline="")
    writer=csv.writer(csv_text,lineterminator="\n")
    writer.writerow(["key","zh_CN"])
    writer.writerows(sorted(locale.items()))
    payloads["locale/zh_CN.csv"]=csv_text.getvalue().encode("utf-8")
    manifest={"pack_id":pack_id,"version":"1.0.0","schema_version":100,"min_game_version":"1.97.0",
              "requires":requires if requires is not None else [{"pack_id":"core","version_range":"^1.97.0"}],
              "files":[{"path":name,"sha256":sha(value)} for name,value in sorted(payloads.items())]}
    for name,value in payloads.items():
        target=directory/name
        target.parent.mkdir(parents=True,exist_ok=True)
        target.write_bytes(value)
    (directory/"manifest.json").write_bytes(encoded(manifest))


def rejected(paths,label):
    try:
        load_packs(paths)
    except ContentError as error:
        check(bool(str(error)),label)
    else:
        raise ContentError("accepted invalid content: "+label)


source,*_=design_sources()
registry=load_packs([core])
check(bool(registry.resolve_bindings("S49","D37")),"explicit normalized binding index")
try:
    registry.definition("species","S49")["body"]["width_m"]=0
except TypeError:
    check(True,"nested definitions immutable")
else:
    raise ContentError("mutable registry")

with tempfile.TemporaryDirectory(prefix="ogh-content-rules-") as temporary:
    temp=Path(temporary)
    publish(temp/"one")
    publish(temp/"two")
    check({p.relative_to(temp/"one"):p.read_bytes() for p in (temp/"one").rglob("*") if p.is_file()} ==
          {p.relative_to(temp/"two"):p.read_bytes() for p in (temp/"two").rglob("*") if p.is_file()},"byte-identical compilation")
    # A new species reuses an old disease/routine and registered staff rig/handler.
    sid=next(row["id"] for row in source["species"] if row["rig"]=="plant")
    species=thaw(registry.definition("species",sid))
    species.update(id="official.garden:moss_person",name="苔藓人")
    binding=next(thaw(row) for row in registry.indexes["treatment_bindings"].values() if row["species_id"]=="core:"+sid)
    binding.update(id="official.garden:moss_case",species_id=species["id"])
    talent=next(thaw(row) for row in registry.indexes["staff_talents"].values() if row["species_id"]=="core:"+sid)
    talent.update(id="official.garden:moss_talent",species_id=species["id"])
    tables={"species":[species],"treatment_bindings":[binding],"staff_talents":[talent],"profiles":{}}
    write_pack(temp/"species",tables)
    merged=load_packs([core,temp/"species"])
    check(len(merged.indexes["species"])==81 and len(merged.collections["profiles"])==3,"new species and omitted/empty mapping merge")
    # A new disease has two plans, one old body binding and its own unlock.
    disease=thaw(registry.definition("diseases",binding["disease_id"]))
    disease.update(id="official.garden:firefly_yawn",name="萤火哈欠")
    disease_binding=copy.deepcopy(binding)
    disease_binding.update(id="official.garden:yawn_case",species_id="core:"+sid,disease_id=disease["id"])
    plans=[]
    for index,protocol in enumerate(("core:TP_COMMON","core:TP_GENTLE")):
        plans.append({"id":"official.garden:yawn_plan_"+str(index),"name":"哈欠方案","disease_id":disease["id"],"protocol_id":protocol,"requires_research":[]})
    disease_tables={"diseases":[disease],"treatment_bindings":[disease_binding],"treatment_plans":plans,
                    "research":[{"id":"official.garden:yawn_unlock","name":"微光照护","requires":[],"disease_ids":[disease["id"]],"price":100,"work_seconds":10}]}
    write_pack(temp/"disease",disease_tables)
    check(len(load_packs([core,temp/"disease"]).indexes["diseases"])==155,"new disease reuses old body/equipment with two plans")
    for label,mutate in [
        ("unknown collection",lambda x:x.update(unregistered=[])),
        ("wrong mapping type",lambda x:x.update(profiles=[])),
        ("unknown field",lambda x:x["species"][0].update(execute_script="bad")),
        ("boolean body",lambda x:x["species"][0]["body"].update(width_m=True)),
        ("duplicate ID",lambda x:x["species"].append(copy.deepcopy(x["species"][0]))),
        ("missing reference",lambda x:x["treatment_bindings"][0].update(routine_id="core:absent")),
        ("rig mismatch",lambda x:x["treatment_bindings"][0].update(animation_profile="biped")),
        ("missing handler",lambda x:x["staff_talents"][0].update(handler_id="core:absent")),
        ("invalid geometry",lambda x:x["species"][0]["body"].update(width_m=100)),
        ("conflicting case envelope",lambda x:x["treatment_bindings"].append(dict(copy.deepcopy(x["treatment_bindings"][0]),id="official.garden:conflict",symptom_envelope={"width_m":6.5,"depth_m":6.5,"height_m":6.5}))),
    ]:
        broken=copy.deepcopy(tables)
        mutate(broken)
        write_pack(temp/"broken",broken)
        rejected([core,temp/"broken"],label)
    write_pack(temp/"broken",tables,requires=[{"pack_id":"core","version_range":">=9.0.0"}])
    rejected([core,temp/"broken"],"dependency version")
    write_pack(temp/"broken",tables,requires=[{"pack_id":"core","version_range":"*"},{"pack_id":"official.absent","version_range":"*"}])
    rejected([core,temp/"broken"],"missing dependency")
    write_pack(temp/"broken",tables,requires=[{"pack_id":"core","version_range":"*"},{"pack_id":"official.garden","version_range":"*"}])
    rejected([core,temp/"broken"],"pack cycle")
    rejected([temp/"species"],"missing mandatory core")
    (temp/"species"/"species.json").write_bytes(b"[]")
    rejected([core,temp/"species"],"hash mismatch")
    check(len(registry.indexes["species"])==80,"failed candidates preserve prior registry")

print(json.dumps({"stage":4,"checks":len(checks),"accepted":True,"fingerprint":registry.fingerprint,"performance":"skipped"}))
