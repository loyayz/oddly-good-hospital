"""Check extracted production DAG expansion with the same GMP number types.

The former recursive expansion is an independent bounded oracle. Deep repeated
ANDs use their independently computed exact coefficient, without expanding an
exponential old tree. This is a native numerical check, not hospital acceptance.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--zig", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    path = repo / "game/platform/windows/platform_arrivals.cpp"
    source = path.read_text(encoding="utf-8-sig")
    start = source.index("    void expand(int id, const std::vector<int>& choices, Resources& output) const {")
    finish = source.index("    V resource_values(", start)
    body = source[start:finish]
    instrumented = body.replace("const Node& node = nodes[next];", "++visits; const Node& node = nodes[next];")
    if instrumented == body:
        raise SystemExit("Production sparse expansion instrumentation point missing")
    template = r'''
#include <boost/multiprecision/gmp.hpp>
#include <algorithm>
#include <chrono>
#include <cstdint>
#include <iostream>
#include <iterator>
#include <map>
#include <random>
#include <stdexcept>
#include <utility>
#include <vector>
using Q = boost::multiprecision::number<boost::multiprecision::gmp_rational, boost::multiprecision::et_off>;
using Z = boost::multiprecision::number<boost::multiprecision::gmp_int, boost::multiprecision::et_off>;
using Resources = std::map<int,Q>;
struct Node { bool choice; Resources resources; std::vector<int> children; };
struct Model {
    std::vector<Node> nodes;
    mutable uint64_t visits = 0, original_visits = 0;
    @BODY@
    void original(int id, const std::vector<int>& choices, Resources& output) const {
        ++original_visits;
        const Node& node = nodes[id];
        if (node.choice) { if (choices[id] >= 0) original(choices[id],choices,output); }
        else {
            for (const auto& item : node.resources) output[item.first] += item.second;
            for (int child : node.children) original(child,choices,output);
        }
    }
};
int main() {
    std::mt19937 random(20261019);
    int checks = 0;
    uint64_t original_visits = 0, new_visits = 0;
    for (int sample=0; sample<1000; ++sample) {
        Model model; std::vector<int> choices;
        // Forty nodes with exact signed fractions, shared subgraphs, repeated
        // edges, empty choices and nonzero preexisting destination values.
        for (int i=0; i<40; ++i) {
            Node node{random()%3==0,{}, {}};
            if (!node.choice) for (int resource=0; resource<3; ++resource) {
                Q value = Q(static_cast<int>(random()%9)-4) / Q(random()%7+1);
                if (value!=0) node.resources[resource]=value;
            }
            if (i>0) for (unsigned edge=0, count=random()%4; edge<count; ++edge)
                node.children.push_back(static_cast<int>(random()%i));
            choices.push_back(node.choice && !node.children.empty() ? node.children[random()%node.children.size()] : -1);
            model.nodes.push_back(std::move(node));
        }
        for (int root : {0,19,39}) {
            Resources expected{{7,Q(1)/Q(5)}}, actual=expected;
            model.original(root,choices,expected);
            model.expand(root,choices,actual);
            if (actual!=expected) { std::cerr<<"expansion mismatch sample="<<sample<<" root="<<root<<"\n"; return 1; }
            ++checks;
        }
        original_visits+=model.original_visits; new_visits+=model.visits;
    }
    Model deep; std::vector<int> choices{-1};
    deep.nodes.push_back(Node{false,{{0,Q(3)/Q(7)}},{}});
    Z multiple=1;
    for (int i=1; i<=70; ++i) {
        deep.nodes.push_back(Node{false,{}, {i-1,i-1}});
        choices.push_back(-1); multiple*=2;
    }
    Resources exact; deep.expand(70,choices,exact);
    Q required=Q(multiple)*Q(3)/Q(7);
    if (exact!=Resources{{0,required}}) { std::cerr<<"big integer repeated edge mismatch\n"; return 2; }
    // Bounded same-input comparison retains both wins and no-gain results.
    std::cout<<"{\"random_root_checks\":"<<checks<<",\"original_visits\":"<<original_visits
        <<",\"dag_visits\":"<<new_visits<<",\"deep_reference_count\":\""<<multiple
        <<"\",\"deep_node_visits\":"<<deep.visits<<",\"deep_exact\":true,\"timings\":[";
    for (int depth : {0,1,4,14}) {
        Model bounded;
        bounded.nodes.assign(deep.nodes.begin(),deep.nodes.begin()+depth+1);
        std::vector<int> selected(choices.begin(),choices.begin()+depth+1);
        auto measure = [&](bool original) {
            auto start=std::chrono::steady_clock::now();
            for (int repeat=0; repeat<30; ++repeat) {
                Resources result;
                if (original) bounded.original(depth,selected,result);
                else bounded.expand(depth,selected,result);
                Q expected=(Q(Z(1)<<depth)*Q(3))/Q(7);
                if (result!=Resources{{0,expected}}) throw std::runtime_error("timed expansion mismatch");
            }
            return std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-start).count();
        };
        auto before=measure(true), after=measure(false);
        if (depth) std::cout<<",";
        std::cout<<"{\"depth\":"<<depth<<",\"repeats\":30,\"before_us\":"<<before<<",\"after_us\":"<<after<<"}";
    }
    std::cout<<"]}\n";
}
'''
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    cpp = output / "expansion.cpp"
    cpp.write_text(template.replace("@BODY@", instrumented), encoding="utf-8")
    executable = output / "expansion.exe"
    dependencies = repo / ".cache/native-math/ucrt64"
    command = [str(args.zig.resolve()), "c++", "-target", "x86_64-windows-gnu", "-std=c++17", "-O2",
               "-Wall", "-Wextra", "-Werror", "-isystem", str(dependencies / "include"), str(cpp),
               str(dependencies / "lib/libgmp.dll.a"), "-o", str(executable)]
    compiled = subprocess.run(command, capture_output=True, text=True, timeout=90)
    (output / "compile.log").write_text(compiled.stdout + compiled.stderr, encoding="utf-8")
    record = {"source": str(path), "source_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
              "expansion_body_sha256": hashlib.sha256(body.encode()).hexdigest(), "command": command,
              "compile_exit_code": compiled.returncode,
              "scope": "Extracted expansion body, actual GMP rational/integer types; excludes LP, Godot and hospital workload."}
    if compiled.returncode == 0:
        shutil.copyfile(dependencies / "bin/libgmp-10.dll", output / "libgmp-10.dll")
        result = subprocess.run([str(executable)], capture_output=True, text=True, timeout=60)
        record.update(run_exit_code=result.returncode, stdout=result.stdout, stderr=result.stderr)
    (output / "result.json").write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(record, ensure_ascii=False))
    raise SystemExit(compiled.returncode or record.get("run_exit_code", 1))


if __name__ == "__main__":
    main()
