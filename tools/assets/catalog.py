"""Read the authored content and enumerate every presentation resource.

Content owns rules and identities. This module only resolves localized source
text and maps those identities to asset paths and presentation requirements.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path

BODY_ACTIONS = (
    "idle", "walk", "sit", "notice", "talk", "cheer", "upset", "recover",
    "interact", "work", "pause", "symptom", "recovery", "low_motion",
    "sleep", "wake", "rest", "recreation",
    "blink",
)
CASE_ACTIONS = (
    "symptom", "prepare", "process", "climax", "safe_finish", "work",
    "failure", "paused", "awaiting_result", "recovery", "recovery_hold",
    "low_motion", "low_motion_work", "low_motion_recovery",
    "gentle_prepare", "gentle_process", "gentle_climax", "gentle_safe_finish",
)
BODY_SLOTS = (
    "head", "look_target", "hand_l", "hand_r", "treatment_anchor",
    "emotion_anchor", "carry_anchor",
)
EQUIPMENT_SLOTS = (
    "patient_anchor", "operator_anchor", "repair_anchor",
    "effect_anchor", "camera_focus",
)
OPERATIONS = (
    "build", "staff", "admissions", "research", "tasks", "residents",
    "save", "load", "pause", "play", "speed", "settings", "close", "confirm",
    "cancel", "delete", "move", "rotate_left", "rotate_right", "zoom_in",
    "zoom_out", "floor_up", "floor_down", "follow", "info", "repair",
    "upgrade", "supplies", "blueprint", "remodel", "camera", "sound",
)
MUSIC = ("lobby", "garden", "night", "celebration")
STRUCTURES = ("floor_tile", "wall_straight", "wall_corner", "window", "fence",
              "path_1", "path_2", "path_3", "construction_scaffold",
              "land_marker", "floor_build_outline")
UI_SOUNDS = (
    "hover", "press", "confirm", "cancel", "panel_open", "panel_close",
    "select", "build_place", "build_reject", "purchase", "save",
    "notice", "warning", "task_complete", "research_complete", "floor_change",
)
FACILITY_COLLECTIONS = (
    "machines", "clinical_equipment", "service_equipment",
    "accessibility_equipment", "staff_recreation_equipment",
    "vertical_connectors", "doors",
)
PRESENTATION_COLLECTIONS = (
    "incidents", "interactions", "memory_callbacks", "community_activities",
    "stories", "community_cast", "species_gifts", "gratitude_effects",
    "ward_scenes", "ward_neighbor_cues", "amenity_scenes", "patient_behaviors",
    "hospital_situations", "consultation_behaviors", "diagnostic_work_styles",
    "staff_base_cues", "queue_cues", "medical_progress_cues", "rest_cues",
    "growth_moments", "research_trails", "maintenance_scenes",
    "facility_magic_scenes", "movement_cues", "upgrade_presentations",
    "onboarding_steps", "context_lessons", "comedy_corner_guides",
    "visitor_cues", "colleague_scenes", "task_guides", "history_templates",
    "finance_views", "remodel_guides", "blueprint_presets",
    "staff_talents", "gratitude_abilities", "staff_rig_adapters",
    "supply_reactions", "cleanup_sources", "chair_variants", "observation_cues",
    "journey_reason_cards", "staff_work_styles", "doctor_responses", "medical_supplies",
    "amenity_services", "patient_personalities", "service_equipment",
    "staff_practice_profiles", "staff_recreation_equipment",
    "story_patient_bindings", "vertical_connectors",
)

SCENE_ONLY_COLLECTIONS = {
    "amenity_services", "patient_personalities", "service_equipment",
    "staff_practice_profiles", "staff_recreation_equipment",
    "story_patient_bindings", "vertical_connectors",
}


def authored_scenes(value, pointer=""):
    """Yield actual authored scene text, including nested protocol beats."""
    if isinstance(value, dict):
        for key, child in value.items():
            path = pointer + "/" + key
            if isinstance(child, str) and "scene" in key:
                yield path, child
            elif isinstance(child, (dict, list)):
                yield from authored_scenes(child, path)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from authored_scenes(child, pointer + "/" + str(index))


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def load_catalog(root: Path) -> dict:
    root = root.resolve()
    core = root / "content/core"
    with (core / "locale/zh_CN.csv").open(encoding="utf-8-sig", newline="") as stream:
        translations = {row["key"]: row["zh_CN"] for row in csv.DictReader(stream)}

    def localized(value):
        if isinstance(value, str) and value.startswith("@zh:"):
            key = value[4:]
            if key not in translations:
                raise ValueError("Missing localized source: " + key)
            return translations[key]
        if isinstance(value, list):
            return [localized(item) for item in value]
        if isinstance(value, dict):
            return {key: localized(item) for key, item in value.items()}
        return value

    data = {}
    hashes = {}
    for filename in sorted(core.glob("*.json")):
        raw = filename.read_bytes()
        data[filename.stem] = localized(json.loads(raw))
        hashes[str(filename.relative_to(root)).replace("\\", "/")] = digest(raw)
    data["source_hashes"] = hashes
    data["equipment"] = [
        {**item, "id": item["definition_id"], "collection": "furniture_equipment"}
        for item in data["furniture_equipment"]
    ]
    for collection in FACILITY_COLLECTIONS:
        data["equipment"].extend(
            {**item, "collection": collection} for item in data[collection]
        )
    data["species_by_id"] = {item["id"]: item for item in data["species"]}
    data["diseases_by_id"] = {item["id"]: item for item in data["diseases"]}
    data["equipment_by_id"] = {item["id"]: item for item in data["equipment"]}
    data["bindings_by_id"] = {item["id"]: item for item in data["treatment_bindings"]}
    if len(data["species"]) != len(data["species_by_id"]):
        raise ValueError("Duplicate species identity")
    if len(data["equipment"]) != len(data["equipment_by_id"]):
        raise ValueError("Duplicate equipment identity")
    return data


def variants(record: dict) -> list[dict]:
    result = []
    for key in ("variations", "response_variants"):
        values = record.get(key, [])
        if isinstance(values, list):
            result.extend(value for value in values if isinstance(value, dict))
    return result


def effective_body(catalog: dict, binding: dict) -> dict:
    body = catalog["species_by_id"][binding["species_id"]]["body"]
    symptom = binding.get("symptom_envelope", body)
    return {key: max(float(body[key]), float(symptom[key]))
            for key in ("width_m", "depth_m", "height_m")}


def resource_plan(catalog: dict) -> dict:
    items = []

    def add(kind, identity, name, paths, source, **extra):
        items.append({
            "kind": kind, "id": identity, "name": name,
            "required_paths": paths, "source": source,
            "owner": "asset-production", **extra,
        })

    for species in catalog["species"]:
        key = species["id"].lower()
        paths = [f"assets/models/core_{key}_body.glb",
                 f"assets/models/core_{key}_body_near.glb",
                 f"assets/models/core_{key}_body_far.glb",
                 f"art-source/production/bodies/core_{key}_body.blend",
                 f"assets/appearances/core_{key}.json"]
        add("body", species["id"], species["name"], paths,
            "content/core/species.json#" + species["id"],
            body=species["body"], rig=species["rig"],
            appearance_count=int(species["variants"]), actions=list(BODY_ACTIONS),
            slots=list(BODY_SLOTS))

    for rig in sorted({item["rig"] for item in catalog["species"]}):
        add("rig", rig, rig, [f"assets/rigs/{rig}.json",f"assets/animations/staff/{rig}.tres"],
            "content/core/species.json#rig=" + rig,
            actions=list(BODY_ACTIONS), slots=list(BODY_SLOTS), max_bones=40)

    for role in sorted({role for record in catalog["staff_rig_adapters"] for role in record["roles"]}):
        for rig in sorted({s["rig"] for s in catalog["species"]}):
            add("uniform",rig+":"+role,role,[f"assets/accessories/uniforms/{rig}_{role}.glb"],
                "content/core/staff_rig_adapters.json#SRA_"+rig,rig=rig,role=role)
    for species in catalog["species"]:
        for look in range(1,5):
            add("appearance",species["id"]+":"+str(look),species["name"],
                [f"assets/accessories/looks/{'core_s49' if species['id']=='S49' else species['rig']}_look_{look:02}.glb"],
                "content/core/species.json#"+species["id"],rig=species["rig"],look=look)
    for record in catalog["upgrade_presentations"]:
        for level in (1,2):
            add("upgrade",record["definition_id"]+":"+str(level),record[f"level{level}_static"],
                [f"assets/upgrades/{record['definition_id'].lower()}_level_{level}.glb"],
                "content/core/upgrade_presentations.json#"+record["id"])
    for record in catalog["species_gifts"]:
        add("gift",record["id"],record["name"],
            [f"assets/props/species_gifts/{record['id'].lower()}.glb"],
            "content/core/species_gifts.json#"+record["id"])
    for record in catalog["stories"]:
        add("memento",record["id"],record["reward_text"].split("；")[0],
            [f"assets/props/mementos/{record['id'].lower()}.glb"],
            "content/core/stories.json#"+record["id"])

    for module in STRUCTURES:
        add("architecture", module, module,
            [f"assets/architecture/{module}.glb",
             f"art-source/production/architecture/{module}.blend"],
            "docs/design/05-production.md#建筑模块")

    for equipment in catalog["equipment"]:
        key = equipment["id"].lower()
        add("equipment", equipment["id"], equipment["name"],
            [f"assets/models/core_{key}_machine.glb",
             f"assets/models/core_{key}_machine_far.glb",
             f"art-source/production/equipment/core_{key}_machine.blend"],
            "content/core/" + equipment["collection"] + ".json#" + equipment["id"],
            slots=list(EQUIPMENT_SLOTS),
            footprint=equipment.get("footprint"))

    for binding in catalog["treatment_bindings"]:
        key = binding["id"].lower()
        add("case", binding["id"],
            catalog["diseases_by_id"][binding["disease_id"]]["name"],
            [f"assets/cases/{key}.glb", f"assets/animations/cases/{key}.tres",
             f"art-source/production/cases/{key}.blend"],
            "content/core/treatment_bindings.json#" + binding["id"],
            binding_ids=[binding["id"]], species_id=binding["species_id"],
            disease_id=binding["disease_id"], body=effective_body(catalog, binding),
            symptom=binding["symptom_variant"],
            treatment=binding["treatment_variant"],
            recovery=binding["recovery_variant"], actions=list(CASE_ACTIONS))

    for routine in catalog["treatment_routines"]:
        key = routine["id"].lower()
        add("routine", routine["id"], routine["name"],
            [f"assets/animations/treatments/{key}.tres",f"assets/presentation/treatments/{key}.tscn"],
            "content/core/treatment_routines.json#" + routine["id"],
            equipment_id=routine["equipment_id"], beats=routine["beats"])

    for adapter in catalog["surgical_adapters"]:
        key = adapter["id"].lower()
        add("surgery", adapter["id"], adapter["target_description"],
            [f"assets/animations/surgery/{key}.tres",
             f"assets/surgery/{key}.glb"],
            "content/core/surgical_adapters.json#" + adapter["id"],
            binding_ids=[adapter["binding_id"]],
            required_anchors=adapter["required_anchors"])

    for collection in PRESENTATION_COLLECTIONS:
        for record in catalog.get(collection, []):
            if not isinstance(record, dict) or "id" not in record:
                continue
            if collection in SCENE_ONLY_COLLECTIONS and not list(authored_scenes(record)):
                continue
            identity = record["id"]
            key = identity.lower()
            add("presentation", collection + ":" + identity,
                record.get("name", record.get("scene", identity)),
                [f"assets/presentation/{collection}/{key}.tscn"],
                f"content/core/{collection}.json#{identity}",
                collection=collection, record=record)
            for variation in variants(record):
                vid = variation.get("id", variation.get("response_variant_id"))
                if not vid:
                    raise ValueError("Variant without identity in " + identity)
                add("presentation", collection + ":" + vid,
                    variation.get("name", vid),
                    [f"assets/presentation/{collection}/{str(vid).lower()}.tscn"],
                    f"content/core/{collection}.json#{identity}/{vid}",
                    collection=collection, parent_id=identity, record=variation)

    for material in catalog["renovation_materials"]:
        key = material["id"].lower()
        add("material", material["id"], material["name"],
            [f"assets/materials/{key}.tres"],
            "content/core/renovation_materials.json#" + material["id"],
            record=material)

    task_kinds = sorted({item["kind"] for item in catalog["tasks"]})
    icon_groups = (
        ("species", "species", catalog["species"]),
        ("diseases", "diseases", catalog["diseases"]),
        ("equipment", "equipment", catalog["equipment"]),
        ("rooms", "build_room_types", catalog["build_room_types"]),
        ("tasks", "tasks", [{"id": key, "name": key} for key in task_kinds] +
         [{"id": "story", "name": "居民故事"}]),
        ("operations", "operations", [{"id": key, "name": key} for key in OPERATIONS]),
    )
    for group, collection, records in icon_groups:
        for record in records:
            key = record["id"].lower()
            source_collection = record.get("collection", collection)
            source = ("docs/design/03-experience.md#操作图形" if group == "operations"
                      else f"content/core/{source_collection}.json#{record['id']}")
            add("icon", group + ":" + record["id"], record["name"],
                [f"assets/ui/icons/{group}/{key}.png"],
                source,
                group=group, content_id=record["id"], max_bytes=50000)

    for name in MUSIC:
        add("music", name, name,
            [f"assets/audio/music/{name}.ogg",
             f"art-source/production/audio/music/{name}.wav"],
            "docs/design/05-production.md#声音与安静的信息提示",
            min_duration=120.0, max_duration=180.0)

    audio_groups = (
        ("treatments", catalog["treatment_routines"], ("prepare", "process", "climax", "safe_finish")),
        ("families", catalog["families"], ("notice", "move", "interact", "recover")),
        ("events", catalog["incidents"], ("prepare", "process", "resolve")),
        ("ui", [{"id": key, "name": key} for key in UI_SOUNDS], ("oneshot",)),
    )
    for group, records, phases in audio_groups:
        for record in records:
            for phase in phases:
                identity = str(record["id"]).lower()
                key = identity + "_" + phase
                source_collection = {"treatments": "treatment_routines", "families": "families",
                                     "events": "incidents"}.get(group)
                source = (f"content/core/{source_collection}.json#{record['id']}" if source_collection
                          else "docs/design/05-production.md#声音与安静的信息提示")
                add("sound", group + ":" + key, record.get("name", identity),
                    [f"assets/audio/{group}/{key}.ogg",
                     f"art-source/production/audio/{group}/{key}.wav"],
                    source,
                    group=group, phase=phase)

    from design_assets import requirements as design_requirements
    items.extend(design_requirements(catalog))
    counts = {}
    for item in items:
        counts[item["kind"]] = counts.get(item["kind"], 0) + 1
    return {
        "schema": 1, "source": "authored content and production specifications",
        "counts": counts, "requirements": items,
        "source_hashes": catalog["source_hashes"],
        "validation": {
            "static": "pending", "godot_import": "pending",
            "visual": "pending", "gameplay_handoffs": "pending",
            "performance": "pending",
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    root = args.root.resolve()
    catalog = load_catalog(root)
    plan = resource_plan(catalog)
    output = args.output or root / "art-source/production/resource-plan.json"
    write_json(output, plan)
    print(json.dumps({"requirements": len(plan["requirements"]),
                      "counts": plan["counts"], "path": str(output)}, ensure_ascii=False))


if __name__ == "__main__":
    main()

