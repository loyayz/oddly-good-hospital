"""Schema 100 content publishing and all-or-nothing offline pack loading.

Design JSON and the two explicitly referenced book tables own source values. The
checked-in schema is the game's type/handler registry, never inferred on load.
"""
from __future__ import annotations

import copy
import csv
import hashlib
import io
import json
import math
import re
from pathlib import Path, PurePosixPath
from types import MappingProxyType

ROOT = Path(__file__).resolve().parents[2]
GAME_VERSION = "1.97.0"
SCHEMA_PATH = Path(__file__).with_name("schema100.json")
MANIFEST_FIELDS = {"pack_id", "version", "schema_version", "min_game_version", "requires", "files"}
ID = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9_.-]*$")
PACK_ID = re.compile(r"^(core|[a-z][a-z0-9_-]*(?:\.[a-z][a-z0-9_-]*)+)$")
CHINESE = re.compile(r"[\u3400-\u9fff]")
AXES = ("width_m", "depth_m", "height_m")
FACILITY_COLLECTIONS = ("machines", "clinical_equipment", "furniture_equipment", "service_equipment",
                        "accessibility_equipment", "staff_recreation_equipment", "vertical_connectors", "doors")


class ContentError(ValueError):
    pass


def require(ok: bool, path: str, reason: str) -> None:
    if not ok:
        raise ContentError(f"{path}: {reason}")


def read_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"), parse_constant=lambda value: (_ for _ in ()).throw(ContentError(f"{path}: non-finite {value}")))
    except (OSError, json.JSONDecodeError) as error:
        raise ContentError(f"{path}: {error}") from error


def encoded(value) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8")


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def version(value: str) -> tuple[int, int, int]:
    require(isinstance(value, str) and re.fullmatch(r"\d+\.\d+\.\d+", value) is not None, str(value), "expected semantic version x.y.z")
    return tuple(map(int, value.split(".")))


def version_matches(actual: str, wanted: str) -> bool:
    current = version(actual)
    require(isinstance(wanted, str) and bool(wanted.strip()), "requires.version_range", "empty version range")
    for alternative in wanted.split("||"):
        good = True
        for token in alternative.strip().split():
            if token == "*":
                continue
            match = re.fullmatch(r"(>=|<=|>|<|=|\^|~)?(\d+\.\d+\.\d+)", token)
            require(match is not None, wanted, "unsupported semantic version range")
            op, requested = match.groups()
            target = version(requested)
            if op == "^":
                upper = (target[0]+1, 0, 0) if target[0] else ((0, target[1]+1, 0) if target[1] else (0, 0, target[2]+1))
                good &= target <= current < upper
            elif op == "~":
                good &= target <= current < (target[0], target[1]+1, 0)
            else:
                good &= {">=": current >= target, "<=": current <= target, ">": current > target,
                         "<": current < target, "=": current == target, None: current == target}[op]
        if good:
            return True
    return False


def canonical(value: str, pack_id: str) -> str:
    require(isinstance(value, str), str(value), "definition ID must be text")
    parts = value.split(":")
    require(len(parts) in (1, 2), value, "invalid definition ID")
    namespace, local = (pack_id, parts[0]) if len(parts) == 1 else parts
    require(PACK_ID.fullmatch(namespace) is not None and ID.fullmatch(local) is not None, value, "invalid pack/local ID")
    return namespace + ":" + local


def freeze(value):
    if isinstance(value, dict):
        return MappingProxyType({key: freeze(child) for key, child in value.items()})
    if isinstance(value, list):
        return tuple(freeze(child) for child in value)
    return value


def thaw(value):
    if isinstance(value, (dict, MappingProxyType)):
        return {key: thaw(child) for key, child in value.items()}
    if isinstance(value, (tuple, list)):
        return [thaw(child) for child in value]
    return value


def localized(value, locale: dict):
    if isinstance(value, str) and value.startswith("@zh:"):
        key = value[4:]
        require(key in locale and bool(locale[key].strip()), key, "missing Chinese localization")
        return locale[key]
    if isinstance(value, str):
        require(CHINESE.search(value) is None, value[:80], "display text must reference locale/zh_CN.csv")
    if isinstance(value, list):
        return [localized(child, locale) for child in value]
    if isinstance(value, dict):
        return {key: localized(child, locale) for key, child in value.items()}
    return value


def normalize(value, schema: dict, pack_id: str, path: str):
    kind = schema["type"]
    if value is None and schema.get("nullable"):
        return None
    if kind == "object":
        require(type(value) is dict, path, "expected object")
        properties = schema["properties"]
        require(set(value) <= set(properties), path, "unknown field(s): " + ", ".join(sorted(set(value)-set(properties))))
        require(set(schema["required"]) <= set(value), path, "missing field(s): " + ", ".join(sorted(set(schema["required"])-set(value))))
        return {key: normalize(child, properties[key], pack_id, path+"."+key) for key, child in value.items()}
    if kind == "map":
        require(type(value) is dict, path, "expected mapping object, not array")
        return {(canonical(key, pack_id) if schema.get("key_ref") else key): normalize(child, schema["values"], pack_id, path+"."+key)
                for key, child in value.items()}
    if kind == "array":
        require(type(value) is list, path, "expected array")
        return [normalize(child, schema["items"], pack_id, path+f"[{index}]") for index, child in enumerate(value)]
    if kind == "string":
        require(type(value) is str, path, "expected string")
        if schema.get("identity") or schema.get("ref"):
            return canonical(value, pack_id)
        if "enum" in schema:
            require(value in schema["enum"], path, "unregistered handler/condition: " + value)
    elif kind == "integer":
        require(type(value) is int, path, "expected integer (booleans are not integers)")
    elif kind == "number":
        require(type(value) in (int, float) and math.isfinite(value), path, "expected finite number")
    elif kind == "boolean":
        require(type(value) is bool, path, "expected boolean")
    elif kind == "null":
        require(value is None, path, "expected null")
    else:
        raise ContentError(f"{path}: unregistered field type {kind}")
    if type(value) in (int, float):
        require(math.isfinite(value), path, "non-finite number")
        if "minimum" in schema:
            require(value >= schema["minimum"], path, "value below minimum")
    return value


def validate_references(value, schema, indexes, path):
    if value is None:
        return
    if schema.get("ref"):
        require(any(value in indexes.get(collection, {}) for collection in schema["ref"]), path, "missing reference " + value)
    if schema["type"] == "object":
        for key, child in value.items():
            validate_references(child, schema["properties"][key], indexes, path+"."+key)
    elif schema["type"] == "map":
        for key, child in value.items():
            if schema.get("key_ref"):
                require(any(key in indexes.get(collection, {}) for collection in schema["key_ref"]), path, "missing mapping key " + key)
            validate_references(child, schema["values"], indexes, path+"."+key)
    elif schema["type"] == "array":
        for index, child in enumerate(value):
            validate_references(child, schema["items"], indexes, path+f"[{index}]")


def no_cycles(graph: dict[str, list[str]], label: str):
    visiting, complete = set(), set()
    def visit(key, chain):
        require(key not in visiting, label, "dependency cycle " + " -> ".join(chain+[key]))
        if key in complete:
            return
        visiting.add(key)
        for dependency in graph[key]:
            require(dependency in graph, label, "missing dependency " + dependency)
            visit(dependency, chain+[key])
        visiting.remove(key)
        complete.add(key)
    for key in sorted(graph):
        visit(key, [])


def validate_semantics(collections: dict, rules: dict, indexes: dict, schema: dict):
    def values(name):
        return indexes[name].values()
    def body(value, path):
        require(set(value) == set(AXES) and all(type(v) in (int, float) and math.isfinite(v) and 0 < v <= 7 for v in value.values()), path, "invalid complete metric envelope")
    def numeric_walk(value, path):
        if isinstance(value, dict):
            for key, child in value.items():
                current = path+"."+key
                if type(child) in (int, float) and "delta" not in key and (key.endswith("_seconds") or key.endswith("_ticks") or key in ("price", "unit_price", "supply_units", "target")):
                    require(child >= 0, current, "negative duration, quantity or price")
                if key in ("footprint", "min_inner_size", "cabin_size") and child is not None:
                    require(type(child) is list and len(child) == 2 and all(type(v) is int and 0 < v <= 96 for v in child), current, "invalid grid dimensions")
                numeric_walk(child, current)
        elif isinstance(value, list):
            for index, child in enumerate(value):
                numeric_walk(child, path+f"[{index}]")
    numeric_walk(collections, "content")
    numeric_walk(rules, "rules")
    no_cycles({row["id"]: row["requires"] for row in values("research")}, "research")
    species = indexes["species"]
    rig_roles = {row["rig"]: set(row["roles"]) for row in values("staff_rig_adapters")}
    roles = {row["role"] for row in values("staff_role_profiles")}
    talents = {}
    for row in values("staff_talents"):
        require(row["species_id"] not in talents, row["id"], "species has multiple talent owners")
        talents[row["species_id"]] = row
        handler = indexes["staff_talent_handlers"][row["handler_id"]]
        require(handler["min_value"] <= row["value"] <= handler["max_value"], row["id"], "talent outside handler range")
    for row in species.values():
        body(row["body"], row["id"])
        require(row["id"] in talents, row["id"], "species lacks staff talent")
        require(roles <= rig_roles.get(row["rig"], set()), row["id"], "rig does not adapt all staff roles")
    envelopes, species_bindings = {}, set()
    for row in values("treatment_bindings"):
        sid, did = row["species_id"], row["disease_id"]
        require(row["animation_profile"] == species[sid]["rig"], row["id"], "binding rig mismatch")
        envelope = row.get("symptom_envelope", species[sid]["body"])
        body(envelope, row["id"])
        effective = tuple(max(species[sid]["body"][axis], envelope[axis]) for axis in AXES)
        prior = envelopes.get((sid, did))
        require(prior is None or prior[0] == effective, row["id"], f"conflicting effective envelope for {sid}/{did}; prior {prior[1] if prior else ''}")
        envelopes[sid, did] = effective, row["id"]
        require(all(row.get(key, "").strip() for key in ("symptom_variant", "treatment_variant", "recovery_variant")), row["id"], "incomplete body presentations")
        species_bindings.add(sid)
    require(set(species) <= species_bindings, "species", "species lacks a complete treatment binding")
    facilities = {}
    for name in FACILITY_COLLECTIONS:
        for key, row in indexes[name].items():
            require(key not in facilities, key, "duplicate physical facility definition")
            facilities[key] = row
    for row in values("doors"):
        require(0 < row["clear_width_m"] < row["span_cells"]*1.5 and row["clear_height_m"] > 0 and row["fit_policy"] == "automatic", row["id"], "invalid automatic door geometry")
    for row in values("treatment_routines"):
        require(len(row["beats"]) == 4 and all(row["beats"]) and 0 < row["service_seconds"] <= 300, row["id"], "incomplete routine work or four beats")
    for row in values("treatment_protocols"):
        require(row["kind"] in ("outpatient", "surgery"), row["id"], "unregistered clinical protocol kind")
        if row["kind"] == "surgery":
            require(row["requires_distinct_staff"] and all(1 <= row[key] <= 5 for key in ("min_surgeon_surgery", "min_anesthetist_surgery", "min_nurse_surgery")), row["id"], "invalid three-position surgery qualification")
        elif not row["uses_disease_profile"]:
            require(set(row["clinical_profiles"]) == set(indexes["profiles"]), row["id"], "outpatient clinical profiles incomplete")
    disease_protocols = {}
    for row in values("treatment_plans"):
        disease_protocols.setdefault(row["disease_id"], set()).add(row["protocol_id"])
    unlocked = set(collections["initial_disease_ids"]) | {disease for row in values("research") for disease in row["disease_ids"]}
    bound_diseases = {row["disease_id"] for row in values("treatment_bindings")}
    for identifier in indexes["diseases"]:
        protocols = [indexes["treatment_protocols"][key] for key in disease_protocols.get(identifier, set())]
        require(any(row["kind"] == "outpatient" and row["uses_disease_profile"] for row in protocols)
                and any(row["kind"] == "outpatient" and not row["uses_disease_profile"] for row in protocols), identifier, "disease requires routine and gentle plans")
        require(identifier in unlocked and identifier in bound_diseases, identifier, "disease lacks unlock or complete body binding")
    adapter_pairs = set()
    for row in values("surgical_adapters"):
        binding = indexes["treatment_bindings"][row["binding_id"]]
        plan = indexes["treatment_plans"][row["plan_id"]]
        protocol = indexes["treatment_protocols"][plan["protocol_id"]]
        require(plan["disease_id"] == binding["disease_id"] and protocol["kind"] == "surgery", row["id"], "adapter does not bind this surgical case")
        require(set(row["required_anchors"]) == {"patient_support", "symptom_target", "exit"}, row["id"], "incomplete support/tool/exit anchors")
        pair = row["binding_id"], row["plan_id"]
        require(pair not in adapter_pairs, row["id"], "duplicate surgery adaptation")
        adapter_pairs.add(pair)
    for row in values("tasks"):
        rule = row["eligibility_rule"]
        if "maintainable_equipment_min" in rule:
            require(type(rule["maintainable_equipment_min"]) is int and rule["maintainable_equipment_min"] > 0, row["id"], "maintainable equipment minimum must be a positive integer")
    for row in values("incidents"):
        require(row["release_reservations_on_finish"] and row["restores_state"] and 4+row["natural_resolution_seconds"]+row["actor_recovery_seconds"] <= row["max_duration_seconds"], row["id"], "event lacks bounded complete release")
    for row in values("staff_talent_handlers"):
        require(schema["handler_versions"].get(row["id"]) == row["version"], row["id"], "missing or unsupported compiled handler version")
    return envelopes


class ContentRegistry:
    """Read-only normalized definitions. Queries return immutable records."""
    def __init__(self, collections, rules, layouts, starter, assets, packs, schema, indexes, envelopes):
        self.collections, self.rules, self.layouts, self.starter = map(freeze, (collections, rules, layouts, starter))
        self.assets, self.packs, self.indexes = map(freeze, (assets, packs, indexes))
        self.envelopes = freeze(envelopes)
        self.fingerprint = sha("".join(pack["id"]+"|"+pack["version"]+"|"+pack["fingerprint"]+"\n" for pack in packs).encode("utf-8"))
        bindings = {}
        for row in indexes["treatment_bindings"].values():
            bindings.setdefault((row["species_id"], row["disease_id"]), []).append(row)
        self._bindings = freeze({key: sorted(rows, key=lambda row: row["id"]) for key, rows in bindings.items()})
        self._sealed = True

    def __setattr__(self, name, value):
        if getattr(self, "_sealed", False):
            raise TypeError("ContentRegistry is immutable")
        object.__setattr__(self, name, value)

    def definition(self, collection, identifier):
        return self.indexes.get(collection, {}).get(canonical(identifier, "core"), MappingProxyType({}))

    def resolve_bindings(self, species_id, disease_id):
        return self._bindings.get((canonical(species_id, "core"), canonical(disease_id, "core")), ())


def load_packs(paths: list[Path], schema_path=SCHEMA_PATH) -> ContentRegistry:
    """Build a complete candidate; failure never mutates a previous registry."""
    schema = read_json(schema_path)
    manifests, payloads, packs = {}, {}, []
    for directory in paths:
        manifest = read_json(directory/"manifest.json")
        require(type(manifest) is dict and set(manifest) == MANIFEST_FIELDS, str(directory), "invalid manifest fields")
        pack_id = manifest["pack_id"]
        require(type(pack_id) is str and PACK_ID.fullmatch(pack_id) is not None, str(directory), "invalid pack_id")
        require(pack_id not in manifests, pack_id, "duplicate pack")
        require(type(manifest["schema_version"]) is int and manifest["schema_version"] == schema["schema_version"], pack_id, "unsupported schema version")
        version(manifest["version"])
        require(version(GAME_VERSION) >= version(manifest["min_game_version"]), pack_id, "requires newer game")
        require(type(manifest["requires"]) is list and type(manifest["files"]) is list, pack_id, "manifest collections must be arrays")
        dependencies = set()
        for dependency in manifest["requires"]:
            require(type(dependency) is dict and set(dependency) == {"pack_id", "version_range"}, pack_id, "invalid dependency")
            require(dependency["pack_id"] not in dependencies, pack_id, "duplicate dependency")
            dependencies.add(dependency["pack_id"])
        require(pack_id == "core" or "core" in dependencies, pack_id, "extension must require core")
        manifests[pack_id] = manifest
        pack_files = {}
        for item in manifest["files"]:
            require(type(item) is dict and set(item) == {"path", "sha256"}, pack_id, "invalid file record")
            path = item["path"]
            require(type(path) is str and "\\" not in path and not PurePosixPath(path).is_absolute() and all(part not in ("..", ".", "") for part in path.split("/")), pack_id, "unsafe relative path")
            require(path not in pack_files, pack_id, "duplicate manifest file " + path)
            file = directory/path
            require(file.is_file() and not file.is_symlink(), path, "missing pack file")
            data = file.read_bytes()
            require(type(item["sha256"]) is str and sha(data) == item["sha256"], path, "SHA-256 mismatch")
            require(path in schema["files"] or path.startswith("assets/") and not path.endswith(".json"), path, "unregistered content collection/file")
            pack_files[path] = data
        if pack_id == "core":
            require(set(schema["core_required_files"]) <= set(pack_files), pack_id, "missing required core rules/collection/localization/index")
        else:
            require(not any(name in pack_files for name in ("rules.json", "layouts.json", "starter_layout.json")), pack_id, "extension cannot replace core rules or layouts")
        payloads[pack_id] = pack_files
        packs.append({"id": pack_id, "version": manifest["version"], "fingerprint": sha(encoded(manifest))})
    require("core" in manifests, "packs", "missing mandatory core pack")
    no_cycles({key: [row["pack_id"] for row in value["requires"]] for key, value in manifests.items()}, "packs")
    for pack_id, manifest in manifests.items():
        for dependency in manifest["requires"]:
            require(version_matches(manifests[dependency["pack_id"]]["version"], dependency["version_range"]), pack_id, "dependency version mismatch " + dependency["pack_id"])
    collections = {name: [] if contract["type"] == "array" else {} for name, contract in schema["collections"].items()}
    indexes = {name: {} for name in collections}
    special, assets = {}, {"assets": []}
    for pack_id in sorted(manifests):
        files = payloads[pack_id]
        locale = {}
        if "locale/zh_CN.csv" in files:
            rows = csv.reader(io.StringIO(files["locale/zh_CN.csv"].decode("utf-8")))
            require(next(rows, None) == ["key", "zh_CN"], pack_id, "invalid Chinese CSV header")
            for row in rows:
                require(len(row) == 2 and row[0] and row[0] not in locale, pack_id, "duplicate/invalid locale key")
                locale[row[0]] = row[1]
        for path, data in files.items():
            if path not in schema["files"] or path.endswith(".csv"):
                continue
            try:
                source = json.loads(data)
            except (ValueError, UnicodeDecodeError) as error:
                raise ContentError(f"{pack_id}/{path}: invalid JSON") from error
            contract = schema["files"][path]
            value = normalize(localized(source, locale), contract, pack_id, pack_id+"/"+path)
            collection = path.removesuffix(".json")
            if collection in collections:
                if type(value) is list:
                    key_field = schema["identity_fields"].get(collection)
                    if key_field:
                        for record in value:
                            identifier = record[key_field]
                            require(identifier.startswith(pack_id+":"), identifier, "pack cannot publish another namespace")
                            require(identifier not in indexes[collection], identifier, "duplicate definition in " + collection)
                            indexes[collection][identifier] = record
                    collections[collection].extend(value)
                else:
                    for identifier, record in value.items():
                        require(identifier.startswith(pack_id+":"), identifier, "pack cannot publish another namespace")
                        require(identifier not in collections[collection], identifier, "duplicate definition in " + collection)
                        collections[collection][identifier] = record
                        indexes[collection][identifier] = record
            elif path == "assets/index.json":
                assets["assets"].extend(value["assets"])
            else:
                special[collection] = value
    for name, value in collections.items():
        validate_references(value, schema["collections"][name], indexes, name)
    for name, value in special.items():
        validate_references(value, schema["files"][name+".json"], indexes, name)
    validate_references(assets, schema["files"]["assets/index.json"], indexes, "assets/index")
    asset_ids = set()
    for asset in assets["assets"]:
        require(asset["content_id"] not in asset_ids, asset["content_id"], "duplicate resource binding")
        asset_ids.add(asset["content_id"])
    envelopes = validate_semantics(collections, special["rules"], indexes, schema)
    return ContentRegistry(collections, special["rules"], special["layouts"], special["starter_layout"], assets,
                           sorted(packs, key=lambda pack: pack["id"]), schema, indexes, envelopes)


def design_sources():
    catalog = read_json(ROOT/"docs/data/content-catalog.json")
    rules = read_json(ROOT/"docs/data/balance.json")
    content = (ROOT/"docs/design/02-content.md").read_text(encoding="utf-8")
    simulation = (ROOT/"docs/design/01-simulation.md").read_text(encoding="utf-8")
    arrivals = (ROOT/"docs/design/11-growth-arrivals-recruitment.md").read_text(encoding="utf-8")
    no_progress = re.search(r"或(\d+)秒无进展时", arrivals)
    require(no_progress is not None, "arrivals §2", "missing deterministic no-progress deadline")
    rules["wait_departure"]["no_progress_seconds"] = int(no_progress.group(1))
    stories = []
    for line in content.splitlines():
        if re.match(r"\| ST\d\d ", line):
            cells = [value.strip() for value in line.strip("|").split("|")]
            identifier, name = cells[0].split(" ", 1)
            stories.append({"id": identifier, "name": name, "availability_text": cells[1],
                            "conditions_text": cells[2], "reward_text": cells[3]})
    require(len(stories) == 12, "content chapter §7", "expected the 12 independently sourced core stories")
    catalog["stories"] = stories
    # The book's grouped furniture table is a source format, parsed exactly once.
    furniture = {row["definition_id"]: row for row in catalog["furniture_equipment"]}
    table = [line for line in content.splitlines() if re.match(r"\| (?:01、02、05—08|09—16|17—24|25—32|33—40|41—48|49—52) \|", line)]
    require(len(table) == 7, "content chapter §8", "furniture source table changed")
    groups = ([1,2,5,6,7,8], list(range(9,17)), list(range(17,25)), list(range(25,33)), list(range(33,41)), list(range(41,49)), list(range(49,53)))
    for line, numbers in zip(table, groups):
        cells = [value.strip() for value in line.strip("|").split("|")]
        names = cells[1].split("、")
        require(len(names) == len(numbers), cells[0], "furniture name count mismatch")
        for number, name in zip(numbers, names):
            furniture[f"FUR{number:02}"]["name"] = name
        text = cells[2]
        if numbers[0] == 1:
            specs = [tuple(map(int, match)) for match in re.findall(r"(\d+)×(\d+)/(\d+)", text)]
            require(len(specs) == len(numbers), cells[0], "furniture base geometry changed")
        elif numbers[0] == 9:
            common = re.search(r"其余(\d+)×(\d+)/(\d+)", text)
            specs = [tuple(map(int, common.groups()))]*8
            for index, prefix in ((0,"普通席"),(1,"宽席"),(7,"双人长椅")):
                specs[index] = tuple(map(int, re.search(prefix+r"(\d+)×(\d+)/(\d+)", text).groups()))
        elif numbers[0] == 17:
            size = tuple(map(int, re.search(r"(\d+)×(\d+)", text).groups()))
            prices = [int(value) for value in re.search(r"依次([\d、]+)", text).group(1).split("、")]
            specs = [size+(price,) for price in prices]
        elif numbers[0] == 25:
            specs = [(1,1,100)]*2+[(2,2,80)]*2+[(1,1,100)]*4
            require("1×1地面物/100" in text and "2×2地毯/80" in text and "1墙边/100" in text, cells[0], "furniture source grammar changed")
        elif numbers[0] in (33,41):
            spec = tuple(map(int, re.search(r"(\d+)×(\d+)/(\d+)", text).groups()))
            specs = [spec]*8
            if numbers[0] == 41:
                specs[3] = specs[7] = (1,1,spec[2])
        else:
            specs = [(row["footprint"][0],row["footprint"][1],row["price"]) for row in catalog["chair_variants"]]
        require(len(specs) == len(numbers), cells[0], "furniture geometry/price count mismatch")
        for number, spec in zip(numbers, specs):
            row = furniture[f"FUR{number:02}"]
            if "price" in row:
                require(row["price"] == spec[2], row["definition_id"], "conflicting source price")
            row.update(footprint=list(spec[:2]), price=spec[2], wall_mount=number in (29,30,31,32,44,48),
                       blocks_movement=number not in (23,27,28,29,30,31,32,44,48), requires_research=[])
            row["initially_available"] = True
            row["environment_function"] = "light" if number in (19,37,38) else ("water" if number == 17 else ("noise_barrier" if number == 23 else ""))
        if numbers[0] in (25,33,41):
            categories = re.search(r"类别(?:依次)?([^。；]+)", text)
            require(categories is not None, cells[0], "missing decoration categories")
            labels = categories.group(1).rstrip(" |").split("、")
            require(len(labels) == len(numbers), cells[0], "decoration category count mismatch")
            for number, category in zip(numbers, labels):
                furniture[f"FUR{number:02}"]["decoration_category"] = category
    for number, research in ((10,"R16"),(24,"R07"),(41,"R05"),(42,"R18"),(44,"R18"),(43,"R15")):
        furniture[f"FUR{number:02}"].update(requires_research=[research], initially_available=False)
    for number in (6,7,*range(9,18),*range(49,53)):
        furniture[f"FUR{number:02}"]["fit_profile_id"] = "FF05"
        furniture[f"FUR{number:02}"].update(max_clearance_cells=max(row["adapter_capacity"]["max_clearance_cells"] for row in catalog["machines"]),
                                            max_height_m=max(row["adapter_capacity"]["max_height_m"] for row in catalog["machines"]))
    for number in (1,2,5):
        furniture[f"FUR{number:02}"]["fit_profile_id"] = "FF06"
    for row in catalog["accessibility_equipment"]:
        row["fit_profile_id"] = "FF05"
    for row in catalog["machines"]:
        row["fit_profile_id"] = "FF03"
    for row in catalog["clinical_equipment"]:
        row["fit_profile_id"] = "FF04" if row["id"] == "EQ01" else "FF02"
    room_types = []
    for identifier, label in (("gp","诊断"),("research","研究"),("rest","员工休息"),("toilet","卫生间")):
        match = re.search(label+r"(\d+)×(\d+)", simulation)
        require(match is not None, "simulation room source", "missing support room geometry " + label)
        room_types.append({"id":identifier,"name":label,"min_inner_size":list(map(int,match.groups())),"requires_research":[]})
    for collection in ("specialties", "clinical_room_types", "staff_support_rooms"):
        for row in catalog[collection]:
            room_types.append({key:copy.deepcopy(row.get(key,[])) for key in ("id","name","min_inner_size","requires_research")})
    catalog["build_room_types"] = room_types
    catalog["tags"] = [{"id":tag,"kind":"filter"} for tag in sorted({tag for row in catalog["species"] for tag in row["tags"]})]
    catalog["preferences"] = [{"id":tag,"handler_id":"environment.preference@1"} for tag in sorted({tag for row in catalog["species"] for tag in row["preferences"]})]
    production = read_json(ROOT/"assets/models/stage01-production.json")
    assets = {"assets": production["assets"]}
    return catalog, rules, read_json(ROOT/"docs/data/clinical-layouts.json"), read_json(ROOT/"docs/data/starter-layout.json"), assets


def publish(destination: Path, check_only=False):
    catalog, rules, layouts, starter, assets = design_sources()
    schema = read_json(SCHEMA_PATH)
    for asset in assets["assets"]:
        resource = ROOT/asset["asset_path"]
        require(resource.is_file() and sha(resource.read_bytes()) == asset["asset_sha256"], asset["asset_path"], "indexed asset missing or source hash changed")
    files = {name+".json": value for name, value in catalog.items() if name not in ("schema_version", "content_version")}
    files.update({"rules.json":rules,"layouts.json":layouts,"starter_layout.json":starter,"assets/index.json":assets})
    locale = {}
    def translate(value, prefix):
        if isinstance(value, str) and CHINESE.search(value):
            key = "core."+prefix
            locale[key] = value
            return "@zh:"+key
        if isinstance(value, list):
            return [translate(child, prefix+"."+str(child.get("id",child.get("definition_id",index))) if isinstance(child,dict) else prefix+"."+str(index)) for index,child in enumerate(value)]
        if isinstance(value, dict):
            return {key:translate(child,prefix+"."+key) for key,child in value.items()}
        return value
    payloads = {path: encoded(translate(value,path.removesuffix(".json").replace("/","."))) for path,value in files.items()}
    csv_text = io.StringIO(newline="")
    writer = csv.writer(csv_text, lineterminator="\n")
    writer.writerow(["key","zh_CN"])
    writer.writerows(sorted(locale.items()))
    payloads["locale/zh_CN.csv"] = csv_text.getvalue().encode("utf-8")
    manifest = {"pack_id":"core","version":catalog["content_version"],"schema_version":catalog["schema_version"],
                "min_game_version":GAME_VERSION,"requires":[],"files":[{"path":path,"sha256":sha(data)} for path,data in sorted(payloads.items())]}
    payloads["manifest.json"] = encoded(manifest)
    require(set(files) == set(schema["files"])-{"locale/zh_CN.csv"}, "publisher", "source collections differ from fixed game schema")
    if check_only:
        for path,data in payloads.items():
            require((destination/path).is_file() and (destination/path).read_bytes() == data, path, "published content is stale; run tools/compile-content.py")
    else:
        destination.mkdir(parents=True,exist_ok=True)
        for path,data in payloads.items():
            target = destination/path
            target.parent.mkdir(parents=True,exist_ok=True)
            target.write_bytes(data)
    registry = load_packs([destination])
    return {"pack_id":"core","version":catalog["content_version"],"files":len(payloads),"definitions":sum(len(value) for value in registry.indexes.values()),
            "localizations":len(locale),"fingerprint":registry.fingerprint,"performance":"skipped"}
