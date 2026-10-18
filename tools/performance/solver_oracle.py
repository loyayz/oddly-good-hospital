"""Independent exact vertices of the full Visit-allocation LP, for diagnostics."""
from fractions import Fraction as Q
from itertools import combinations, product
from copy import deepcopy
import json
from pathlib import Path
import random
from math import gcd
import sys


def solve_linear(equations, size):
    rows = [[Q(x) for x in a] + [Q(b)] for a, b in equations]
    for col in range(size):
        pivot = next((i for i in range(col, size) if rows[i][col]), None)
        if pivot is None:
            return None
        rows[col], rows[pivot] = rows[pivot], rows[col]
        divisor = rows[col][col]
        rows[col] = [x / divisor for x in rows[col]]
        for i in range(size):
            if i != col:
                factor = rows[i][col]
                rows[i] = [a - factor * b for a, b in zip(rows[i], rows[col])]
    return [row[-1] for row in rows]


def optimum(options, probabilities, budgets):
    count = sum(map(len, options))
    equalities, cursor = [], 0
    for variants, probability in zip(options, probabilities):
        row = [0] * count + [-probability]
        row[cursor : cursor + len(variants)] = [1] * len(variants)
        equalities.append((row, 0))
        cursor += len(variants)
    constraints = []
    for i in range(count):
        row = [0] * (count + 1)
        row[i] = -1
        constraints.append((row, 0))
    for r, budget in enumerate(budgets):
        constraints.append(([v[r] for variants in options for v in variants] + [0], budget))
    best = Q(0)
    for active in combinations(constraints, count + 1 - len(equalities)):
        value = solve_linear(equalities + list(active), count + 1)
        if value is None or any(x < 0 for x in value):
            continue
        if all(sum(a * x for a, x in zip(row, value)) <= b for row, b in constraints):
            best = max(best, value[-1])
    return best


def fraction(value):
    value = Q(value)
    return {"n": str(value.numerator), "d": str(value.denominator)}


def resources(demand):
    return {key: fraction(value) for key, value in zip(("a", "b"), demand) if value}


rng = random.Random(20261017)
vectors = []
for index in range(80):
    probability = rng.choice([Q(1, 4), Q(1, 3), Q(2, 5), Q(1, 2)])
    probabilities = [probability, 1 - probability]
    budgets = [rng.randrange(0, 121), rng.randrange(0, 121)]
    cases, explicit = [], []
    for p in probabilities:
        first = [(rng.randrange(1, 9), rng.randrange(1, 9)) for _ in range(2)]
        if index < 64:
            variants = first
            case = {"bundles": [{"resources": resources(v)} for v in variants]}
        else:
            second = [(rng.randrange(1, 5), rng.randrange(1, 5)) for _ in range(2)]
            variants = [(a[0] + b[0], a[1] + b[1]) for a, b in product(first, second)]
            case = {"bundles": [{"resources": {}, "choices": ["first", "second"]}],
                    "choice_groups": {"first": [{"resources": resources(v)} for v in first],
                                      "second": [{"resources": resources(v)} for v in second]}}
        case["probability"] = fraction(p)

        if index in (0, 1, 2, 3, 64, 65) and cases:
            case = deepcopy(cases[0])
            case["probability"] = fraction(p)
            variants = list(explicit[0])
            if "choice_groups" in case:
                case["choice_groups"] = {key + "_renamed": value for key, value in case["choice_groups"].items()}
                case["bundles"][0]["choices"] = [key + "_renamed" for key in case["bundles"][0]["choices"]]
        cases.append(case)
        explicit.append(variants)
    expected = optimum(explicit, probabilities, budgets)
    changed = [budgets[0] // 2, budgets[1] + 17]
    vectors.append({"index": index, "cases": cases,
                    "budgets": {r: fraction(b) for r, b in zip(("a", "b"), budgets)}, "expected": fraction(expected),
                    "changed_budgets": {r: fraction(b) for r, b in zip(("a", "b"), changed)},
                    "changed_expected": fraction(optimum(explicit, probabilities, changed))})
for index in range(12):
    first = (1 + index % 3, 2)
    tails = [(1, 0), (0, 1 + index % 2)]
    standalone = (3, 1)
    explicit = [[standalone] + [(first[0] + tail[0], first[1] + tail[1]) for tail in tails]]
    budgets = [7 + index, 11 + index % 4]
    changed = [budgets[0] // 2, budgets[1] + 3]
    case = {"probability": fraction(1), "bundles": [{"resources": {}, "choices": ["start"]}],
            "choice_groups": {"start": [{"resources": resources(standalone)}, {"resources": resources(first), "choices": ["tail"]}],
                              "tail": [{"resources": resources(tail)} for tail in tails]}}
    vectors.append({"index": len(vectors), "cases": [case], "budgets": {r: fraction(b) for r, b in zip(("a", "b"), budgets)},
                    "expected": fraction(optimum(explicit, [Q(1)], budgets)),
                    "changed_budgets": {r: fraction(b) for r, b in zip(("a", "b"), changed)},
                    "changed_expected": fraction(optimum(explicit, [Q(1)], changed))})
Path(sys.argv[1]).write_text(json.dumps(vectors, ensure_ascii=False), encoding="utf-8")
print(f"EXACT_VERTEX_VECTORS={len(vectors)}")


def structure_optimum(cases, blocked, reception, bed_limit):
    """Enumerate complete subsets, separately from SCIP's constraint model."""
    patterns, edges = set(), set()
    for case in cases:
        parts = case.get("reception_bundles", case["bundles"] + [part for group in case.get("choice_groups", {}).values() for part in group])
        for part in parts:
            resources = set(part.get("resources", {})) - set(blocked)
            edges.update(product(resources & set(reception["people"]), resources & set(reception["desks"])))
        def expand(part):
            names = part.get("structural_choices", [part["structural_group"]] if "structural_group" in part else [])
            variants = [frozenset(part.get("structural_resources", []))]
            for name in names:
                options = [resources for option in case.get("choice_groups", {}).get(name, []) for resources in expand(option)]
                variants = [base | option for base, option in product(variants, options)]
            return variants

        for base in case["bundles"]:
            for resources in expand(base):
                nurse, ward = base.get("coverage_nurse_id", ""), base.get("ward_id", "")
                if resources and not resources.intersection(blocked) and (not nurse or (ward and "staff:" + nurse not in blocked and "staff:" + nurse not in resources)):
                    patterns.add((resources, nurse, ward))
    reception_max = 0
    for size in range(len(edges) + 1):
        for subset in combinations(edges, size):
            if len({a for a, _ in subset}) == size == len({b for _, b in subset}):
                reception_max = max(reception_max, size)
    ceiling = reception_max * reception["ratio"]
    for size in range(min(len(patterns), ceiling), -1, -1):
        for subset in combinations(patterns, size):
            used, wards = set(), {}
            valid = True
            for resources, nurse, ward in subset:
                if used.intersection(resources):
                    valid = False
                    break
                used.update(resources)
                if nurse:
                    prior_ward, count = wards.get(nurse, (ward, 0))
                    if prior_ward != ward or count >= bed_limit:
                        valid = False
                        break
                    wards[nurse] = (ward, count + 1)
            if valid and not used.intersection("staff:" + nurse for nurse in wards):
                return size
    return 0


packing = []
for index in range(96):
    reception = {"people": {"staff:r0": True, "staff:r1": True}, "desks": {"facility:d0": True, "facility:d1": True}, "ratio": 3}
    blocked = {rng.choice(["staff:a0", "facility:t0", "staff:n0", "staff:r0", "facility:d0"]): True} if index % 4 == 0 else {}
    bed_limit = 1 + index % 3
    cases = []
    for case_index in range(2):
        bases = []
        for _ in range(2):
            nurse = rng.choice(["", "n0", "n1"])
            resources = ["staff:a" + str(rng.randrange(3)), "facility:t" + str(rng.randrange(3))]
            if nurse:
                resources.append("facility:b" + str(rng.randrange(3)))
            if index % 5 == 0:
                resources.append("staff:n" + str(rng.randrange(2)))
            bases.append({"structural_resources": resources, "coverage_nurse_id": nurse,
                          "ward_id": "w" + str(rng.randrange(2)) if nurse else "", "structural_group": "gp", "resources": {}})
        prefixes = [{"structural_resources": ["staff:g" + str(j), "facility:g" + str(j)],
                     "resources": {"staff:r" + str(rng.randrange(2)): fraction(1), "facility:d" + str(rng.randrange(2)): fraction(1)}} for j in range(2)]
        cases.append({"bundles": bases, "choice_groups": {"gp": prefixes}})
    packing.append({"index": index, "cases": cases, "blocked": blocked, "reception": reception, "bed_limit": bed_limit,
                    "expected": structure_optimum(cases, blocked, reception, bed_limit)})
    if index % 2:
        for case in cases:
            case["reception_bundles"] = case["bundles"] + [part for group in case.get("choice_groups", {}).values() for part in group]
# Independent shared coverage example: two teams and beds fit one covering nurse;
# a third bed, a different ward or assigning that nurse an active job does not.
for limit, wards, active, expected in [(8, ["w", "w"], False, 2), (1, ["w", "w"], False, 1),
                                       (8, ["w", "other"], False, 1), (8, ["w", "w"], True, 1)]:
    reception = {"people": {"staff:r": True}, "desks": {"facility:d": True}, "ratio": 3}
    bases = [{"structural_resources": ["staff:a" + str(j), "facility:b" + str(j)] + (["staff:n"] if active and j == 0 else []),
              "coverage_nurse_id": "n", "ward_id": ward,
              "resources": {"staff:r": fraction(1), "facility:d": fraction(1)}} for j, ward in enumerate(wards)]
    cases = [{"bundles": bases}]
    assert structure_optimum(cases, {}, reception, limit) == expected
    packing.append({"index": len(packing), "cases": cases, "blocked": {}, "reception": reception, "bed_limit": limit, "expected": expected})
for bases, prefixes, expected in [([[]], [["staff:g0"], ["staff:g1"]], 2),
                                  ([["staff:a"], ["staff:b"]], [["staff:g0"], ["staff:g1"]], 2),
                                  ([["staff:g0"], ["staff:g1"]], [["staff:g0"], ["staff:g1"]], 2),
                                  ([["staff:a"], ["staff:b"]], [["staff:g0"]], 1)]:
    reception = {"people": {"staff:r": True}, "desks": {"facility:d": True}, "ratio": 3}
    parts = [{"structural_resources": resources, "resources": {"staff:r": fraction(1), "facility:d": fraction(1)}} for resources in prefixes]
    cases = [{"bundles": [{"structural_resources": resources, "structural_group": "gp", "resources": {}} for resources in bases],
              "choice_groups": {"gp": parts}, "reception_bundles": parts}]
    assert structure_optimum(cases, {}, reception, 8) == expected
    packing.append({"index": len(packing), "cases": cases, "blocked": {}, "reception": reception, "bed_limit": 8, "expected": expected})
for index in range(16):
    reception = {"people": {"staff:r": True}, "desks": {"facility:d": True}, "ratio": 3}
    registration = {"resources": {"staff:r": fraction(1), "facility:d": fraction(1)}}
    cases = [{"bundles": [{"structural_resources": ["staff:a" + str(j), "facility:t" + str(rng.randrange(2))],
                            "structural_choices": ["gp", "consult"], "resources": {}} for j in range(2)],
              "choice_groups": {"gp": [{"structural_resources": ["staff:g" + str(j), "facility:g" + str(j)], "resources": {}} for j in range(2)],
                                "consult": [{"structural_resources": ["staff:g" + str(rng.randrange(2)), "facility:g" + str(j)], "resources": {}} for j in range(2)]},
              "reception_bundles": [registration]}]
    blocked = {"staff:g0": True} if index % 4 == 0 else {}
    packing.append({"index": len(packing), "cases": cases, "blocked": blocked, "reception": reception, "bed_limit": 8,
                    "expected": structure_optimum(cases, blocked, reception, 8)})
for index in range(24):
    reception = {"people": {"staff:r": True}, "desks": {"facility:d": True}, "ratio": 3}
    registration = {"resources": {"staff:r": fraction(1), "facility:d": fraction(1)}}
    cases = [{"bundles": [{"structural_resources": ["staff:t" + str(j)], "structural_choices": ["gp"]} for j in range(2)],
              "choice_groups": {"gp": [{"structural_resources": ["staff:g0"], "structural_choices": ["spectrum"]},
                                         {"structural_resources": ["staff:g1"]}],
                                "spectrum": [{"structural_resources": ["staff:g0", "facility:s0"], "structural_choices": ["resonance"]},
                                             {"structural_resources": ["staff:g1", "facility:s1"]}],
                                "resonance": [{"structural_resources": ["staff:g" + str(index % 2), "facility:r0"]},
                                              {"structural_resources": ["staff:g1", "facility:r1"]}]},
              "reception_bundles": [registration]}]
    blocked = {rng.choice(["staff:g0", "facility:s1", "facility:r0", "staff:t0"]): True} if index % 3 else {}
    packing.append({"index": len(packing), "cases": cases, "blocked": blocked, "reception": reception, "bed_limit": 8,
                    "expected": structure_optimum(cases, blocked, reception, 8)})
Path(sys.argv[1]).with_name("structure-vectors.json").write_text(json.dumps(packing), encoding="utf-8")
print(f"EXACT_STRUCTURE_VECTORS={len(packing)}")
arithmetic = []
for index in range(256):
    limit = 10**23 if index < 32 else (10**9 if index < 128 else 10**17)
    a = Q(rng.randrange(-limit, limit), rng.randrange(1, limit))
    b = Q(rng.randrange(-limit, limit) or 1, rng.randrange(1, limit))
    if index < 4:
        a, b = Q(index - 2), Q(1 if index % 2 else -1)
    scale = (index + 2) * (-1 if index % 2 else 1)
    raw = {"n": str(a.numerator * scale), "d": str(a.denominator * scale)}
    arithmetic.append({"a": fraction(a), "b": fraction(b), "uncanonical": raw, "add": fraction(a + b),
                       "sub": fraction(a - b), "mul": fraction(a * b), "div": fraction(a / b),
                       "compare": (a > b) - (a < b),
                       "aggregate": {"stage_resources": {"first": {"a": fraction(a*b), "b": fraction(b*b)}, "second": {"a": fraction(b*b)}},
                                     "resources": {"a": fraction((a+b)*b), "b": fraction(b*b)}}})
Path(sys.argv[1]).with_name("fraction-vectors.json").write_text(json.dumps(arithmetic), encoding="utf-8")
integers = []
for index in range(256):
    a = rng.randrange(0, 10 ** rng.randrange(1, 121))
    b = rng.randrange(1, 10 ** rng.randrange(1, 91))
    if index < 12:
        b = [10**9 - 1, 10**9, 10**9 + 1, 10**18 - 1][index % 4]
        a = b + (index // 4 - 1)
    integers.append({"a": str(a), "b": str(b), "sum": str(a + b), "difference": str(a - b),
                     "product": str(a * b), "quotient": str(a // b), "remainder": str(a % b), "gcd": str(gcd(a, b))})
Path(sys.argv[1]).with_name("integer-vectors.json").write_text(json.dumps(integers), encoding="utf-8")


def role_optimum(cases, budgets):
    """Enumerate original nurse roles and explicit bundles, then LP vertices."""
    names = sorted(budgets)
    wards = {}
    for name in names:
        if name.startswith("coverage:"):
            _, nurse, ward = name.split(":")
            wards.setdefault(nurse, set()).add(ward)

    def expand(part, groups, roles):
        local = part.get("resources", {})
        for nurse, role in roles.items():
            required = [name.split(":")[2] for name in local if name.startswith("coverage:" + nurse + ":")]
            if required:
                if len(required) != 1 or required[0] != role:
                    return []
            elif role and "staff:" + nurse in local:
                return []
        options = [[Q(local.get(name, {"n": "0", "d": "1"})["n"]) /
                    Q(local.get(name, {"n": "0", "d": "1"})["d"]) for name in names]]
        for group in part.get("choices", []):
            children = [value for child in groups[group] for value in expand(child, groups, roles)]
            options = [[a + b for a, b in zip(parent, child)] for parent, child in product(options, children)]
        return options

    best = Q(0)
    for choices in product(*[[""] + sorted(value) for value in wards.values()]):
        roles = dict(zip(wards, choices))
        explicit = [[option for part in case["bundles"] for option in expand(part, case.get("choice_groups", {}), roles)] for case in cases]
        if any(not options for options in explicit):
            continue
        probabilities = [Q(case["probability"]["n"]) / Q(case["probability"]["d"]) for case in cases]
        best = max(best, optimum(explicit, probabilities, [budgets[name] for name in names]))
    return best


role_vectors = []
for index in range(24):
    budgets = {"staff:n0": rng.randrange(4, 17), "staff:n1": rng.randrange(4, 17),
               "coverage:n0:w0": 40, "coverage:n0:w1": 40, "coverage:n1:w0": 40,
               "facility:a": rng.randrange(12, 41)}
    cases = []
    for case_index in range(1 if index >= 16 else 2):
        parts = []
        for option in range(2):
            nurse = "n" + str(rng.randrange(2))
            demand = {"facility:a": fraction(rng.randrange(1, 5)), "staff:" + nurse: fraction(rng.randrange(1, 5))}
            if rng.randrange(3) != 0:
                ward = "w" + str(rng.randrange(2) if nurse == "n0" else 0)
                demand["coverage:" + nurse + ":" + ward] = fraction(rng.randrange(4, 11))
            parts.append({"resources": demand})
        # Keep explicit vertex enumeration small even for repeated AND factors.
        if index >= 16:
            parts = parts[:1]
        case = {"probability": fraction(1 if index >= 16 else Q(1, 2)), "bundles": parts}
        if index >= 16:
            case["choice_groups"] = {"active": [{"resources": {"staff:n0": fraction(2)}}, {"resources": {"staff:n1": fraction(3)}}]}
            for part in parts:
                part["choices"] = ["active", "active"] if index % 2 else ["active"]
        cases.append(case)
    changed = dict(budgets)
    changed["staff:n0"] //= 2
    changed["coverage:n0:w0"] //= 2
    role_vectors.append({"index": index, "cases": cases,
                         "budgets": {name: fraction(value) for name, value in budgets.items()},
                         "expected": fraction(role_optimum(cases, budgets)),
                         "changed_budgets": {name: fraction(value) for name, value in changed.items()},
                         "changed_expected": fraction(role_optimum(cases, changed))})
manual_budgets = {"staff:n0": 12, "staff:n1": 12, "coverage:n0:w0": 40, "coverage:n0:w1": 40, "facility:a": 30}
cover = {"resources": {"staff:n0": fraction(2), "coverage:n0:w0": fraction(8), "facility:a": fraction(3)}}
for mode, expected in [("own_care", 5), ("cross_ward", 0), ("extra_active", 0), ("other_active", 4), ("repeated_active", 2)]:
    case = {"probability": fraction(1), "bundles": [deepcopy(cover)]}
    cases = [case]
    if mode == "cross_ward":
        case["probability"] = fraction(Q(1, 2))
        other = deepcopy(case)
        other["bundles"][0]["resources"]["coverage:n0:w1"] = other["bundles"][0]["resources"].pop("coverage:n0:w0")
        cases.append(other)
    elif mode in ("extra_active", "other_active", "repeated_active"):
        case["bundles"][0]["choices"] = ["active", "active"] if mode == "repeated_active" else ["active"]
        case["choice_groups"] = {"active": [{"resources": {"staff:n0": fraction(1)}}]}
        if mode != "extra_active":
            case["choice_groups"]["active"].append({"resources": {"staff:n1": fraction(3)}})
    assert role_optimum(cases, manual_budgets) == expected
    changed = dict(manual_budgets, **{"staff:n0": 6})
    role_vectors.append({"index": len(role_vectors), "cases": cases,
                         "budgets": {name: fraction(value) for name, value in manual_budgets.items()}, "expected": fraction(expected),
                         "changed_budgets": {name: fraction(value) for name, value in changed.items()},
                         "changed_expected": fraction(role_optimum(cases, changed))})
closed_budgets = {name: 0 for name in manual_budgets}
for initial, changed in [(manual_budgets, closed_budgets), (closed_budgets, manual_budgets)]:
    cases = [{"probability": fraction(1), "bundles": [deepcopy(cover)]}]
    role_vectors.append({"index": len(role_vectors), "cases": cases,
                         "budgets": {name: fraction(value) for name, value in initial.items()},
                         "expected": fraction(role_optimum(cases, initial)),
                         "changed_budgets": {name: fraction(value) for name, value in changed.items()},
                         "changed_expected": fraction(role_optimum(cases, changed))})
for vector in role_vectors:
    budgets = {name: Q(value["n"]) / Q(value["d"]) for name, value in vector["budgets"].items()}
    changed = dict(budgets)
    source = next((name for name, value in budgets.items() if value > 0), None)
    if source is not None:
        target = next(name for name in budgets if name != source)
        delta = budgets[source] / 2
        changed[source] -= delta
        changed[target] += delta
    vector["redistributed_budgets"] = {name: fraction(value) for name, value in changed.items()}
    vector["redistributed_expected"] = fraction(role_optimum(vector["cases"], changed))
    vector["grown_budgets"] = {name: fraction(value * 2) for name, value in budgets.items()}
    vector["grown_expected"] = fraction(role_optimum(vector["cases"], {name: value * 2 for name, value in budgets.items()}))
Path(sys.argv[1]).with_name("role-vectors.json").write_text(json.dumps(role_vectors), encoding="utf-8")
print(f"EXACT_ROLE_VECTORS={len(role_vectors)}")
