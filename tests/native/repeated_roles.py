"""Compile the current role-filter body against the former full-scan oracle.

This bounded native unit check does not start Godot or the capacity solvers.
Artifacts and the exact extracted production source identity remain on disk.
"""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--zig", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    path = repo / "game/platform/windows/platform_arrivals.cpp"
    source = path.read_text(encoding="utf-8-sig")
    start = source.index("        std::vector<bool> local_valid(nodes.size(), true);", source.index("    void update_roles("))
    finish = source.index("        // LP columns encode old legal choices.", start)
    body = source[start:finish]
    index_start = source.index("        resource_nodes.resize(resources.size());", source.index("struct Model {"))
    index_finish = source.index("        // Parsing reuse owns no hospital model", index_start)
    index_body = source[index_start:index_finish]
    template = r'''
#include <algorithm>
#include <iostream>
#include <map>
#include <set>
#include <string>
#include <utility>
#include <vector>
struct Node { bool choice = false; std::map<int,int> resources; std::vector<int> children; };
struct Model {
    std::vector<std::string> resources;
    std::map<std::string,int> resource_ids;
    std::vector<Node> nodes;
    std::vector<std::vector<int>> resource_nodes;
    std::map<std::string,std::string> locked_roles;
    std::vector<bool> enabled;
    bool dirty = false;
    int role_demand = 7, role_bottleneck_resource = 3, invalidations = 0;
    void make_index() { @INDEX@ }
    void update_roles(std::map<std::string,std::string> next) {
        if (next == locked_roles) return;
        locked_roles = std::move(next);
        @BODY@
        ++invalidations;
    }
    void original() {
        for (size_t i = 0; i < nodes.size(); ++i) {
            const Node& node = nodes[i]; bool valid = true;
            for (const auto& role : locked_roles) {
                bool own = false, active = false;
                for (const auto& term : node.resources) {
                    const auto& name = resources[term.first];
                    const std::string prefix = "coverage:" + role.first + ":";
                    if (name.compare(0, prefix.size(), prefix) == 0) {
                        if (name.substr(prefix.size()) != role.second) valid = false;
                        else own = true;
                    }
                    if (name == "staff:" + role.first) active = true;
                }
                if (active && !own) valid = false;
            }
            bool children = !node.choice;
            for (int child : node.children) {
                if (node.choice) children = children || enabled[child];
                else children = children && enabled[child];
            }
            enabled[i] = valid && children;
        }
    }
};
int main() {
    Model actual;
    for (const char* staff_text : {"a", "a:b", "worker:with:colons", "n"}) {
        const std::string staff(staff_text);
        actual.resources.push_back("staff:" + staff);
        for (const char* ward : {"w1", "w2", "ward:x"}) actual.resources.push_back("coverage:" + staff + ":" + ward);
    }
    actual.resources.push_back("facility:unrelated");
    std::sort(actual.resources.begin(), actual.resources.end());
    for (size_t i=0; i<actual.resources.size(); ++i) actual.resource_ids[actual.resources[i]]=static_cast<int>(i);
    actual.nodes.push_back(Node{}); // Empty AND and OR retain different semantics.
    actual.nodes.push_back(Node{true,{}, {}});
    const int resource_count=static_cast<int>(actual.resources.size());
    for (int a=0; a<resource_count; ++a) {
        actual.nodes.push_back(Node{false,{{a,1}}, {}});
        for (int b=a+1; b<resource_count; ++b) actual.nodes.push_back(Node{false,{{a,1},{b,1}}, {}});
    }
    const int leaves=static_cast<int>(actual.nodes.size());
    for (int a=0; a<leaves; ++a) {
        const int b=(a*7+3)%leaves;
        actual.nodes.push_back(Node{false,{}, {a,b}});
        actual.nodes.push_back(Node{true,{}, {a,b}});
    }
    actual.enabled.assign(actual.nodes.size(),true);
    actual.make_index();
    Model control=actual;
    std::vector<std::map<std::string,std::string>> locks{{}};
    for (const char* staff : {"a", "a:b", "worker:with:colons", "n", "missing", ""})
        for (const char* ward : {"w1", "w2", "ward:x", "b:w1", ""}) locks.push_back({{staff,ward}});
    locks.push_back({{"a","w1"},{"a:b","w2"},{"n","ward:x"}});
    locks.push_back({{"a","b:w1"},{"a:b","w1"},{"worker:with:colons","w2"}});
    locks.push_back({});
    int checked=0, unchanged_masks=0;
    // Repeat transitions on the same graph, including clearing and relocking.
    for (int pass=0; pass<3; ++pass) for (const auto& value : locks) {
        const auto old_mask = actual.enabled;
        const bool map_changed = actual.locked_roles != value;
        const int previous_invalidations = actual.invalidations;
        // A preceding budget update must remain dirty even if roles are equal.
        const bool budget_dirty = checked % 2;
        actual.dirty = budget_dirty; actual.role_demand = 7; actual.role_bottleneck_resource = 3;
        actual.update_roles(value);
        if (map_changed) { control.locked_roles=value; control.original(); }
        if (actual.enabled!=control.enabled) { std::cerr<<"role enabled mismatch at transition "<<checked<<"\n"; return 1; }
        const bool mask_changed = old_mask != actual.enabled;
        if (actual.locked_roles != value || actual.dirty != (budget_dirty || mask_changed)
                || actual.role_demand != (mask_changed ? 0 : 7)
                || actual.role_bottleneck_resource != (mask_changed ? -1 : 3)
                || actual.invalidations != previous_invalidations + mask_changed) {
            std::cerr<<"role invalidation mismatch at transition "<<checked<<"\n"; return 2;
        }
        if (map_changed && !mask_changed) ++unchanged_masks;
        ++checked;
    }
    std::cout<<"{\"transitions\":"<<checked<<",\"nodes\":"<<actual.nodes.size()<<",\"resources\":"<<actual.resources.size()<<",\"enabled_equal\":true,\"same_mask_map_changes\":"<<unchanged_masks<<",\"invalidation_equal\":true}\n";
}
'''
    generated = template.replace("@INDEX@", index_body).replace("@BODY@", body)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    cpp = output / "roles.cpp"
    cpp.write_text(generated, encoding="utf-8")
    executable = output / "roles.exe"
    command = [str(args.zig.resolve()), "c++", "-target", "x86_64-windows-gnu", "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror", str(cpp), "-o", str(executable)]
    compiled = subprocess.run(command, capture_output=True, text=True, timeout=60)
    (output / "compile.log").write_text(compiled.stdout + compiled.stderr, encoding="utf-8")
    record = {"source":str(path),"source_sha256":hashlib.sha256(path.read_bytes()).hexdigest(),
              "role_body_sha256":hashlib.sha256(body.encode()).hexdigest(),"command":command,"compile_exit_code":compiled.returncode,
              "scope":"Actual extracted local role filter, resource-node index construction and enabled propagation; excludes solver and Godot integration."}
    if compiled.returncode == 0:
        result = subprocess.run([str(executable)], capture_output=True, text=True, timeout=30)
        record.update(run_exit_code=result.returncode, stdout=result.stdout, stderr=result.stderr)
    (output / "result.json").write_text(json.dumps(record, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print(json.dumps(record, ensure_ascii=False))
    raise SystemExit(compiled.returncode or record.get("run_exit_code", 1))


if __name__ == "__main__":
    main()
