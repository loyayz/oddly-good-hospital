"""Compile the actual Boost R-tree core with explicit Godot boundary adapters.

Requires repository-pinned Boost 1.92.0 headers, no installed Godot bridge.
The independent oracle checks inclusive broadphase rectangles, not BodyIndex's
strict contact filtering or complete hospital acceptance.
"""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--boost-include', type=Path, required=True)
parser.add_argument('--compiler', default='g++')
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=False)
p=repo / 'game/platform/windows/platform_spatial_index.h'
s=p.read_text()
core=s[s.index('namespace bg ='):s.index('Builtin spatial_class;')]
update='''            instance.remove(id);
            instance.floors[floor].insert({box, id}); instance.records.emplace(id, std::make_pair(floor, box));'''
assert update in s
query='''                    auto predicate = bgi::intersects(spatial_box(args[1]));
                    for (auto it = floor->second.qbegin(predicate); it != floor->second.qend(); ++it) ids.append(V::text(it->second));'''
assert query in s
many='''                    std::set<std::string> candidates;
                    for (const auto& box : rectangles) {
                        auto predicate = bgi::intersects(box);
                        for (auto it = floor->second.qbegin(predicate); it != floor->second.qend(); ++it) candidates.insert(it->second);
                    }
                    for (const auto& id : candidates) ids.append(V::text(id));'''
assert many in s
# The production R-tree/record implementation above is verbatim. Only argument/result adapters
# in the three extracted invocation branches are translated to std::vector/SpatialBox.
helpers='''
void update(SpatialInstance& instance, const std::string& id, int64_t floor, const SpatialBox& box) { UPDATE }
std::vector<std::string> query(SpatialInstance& instance,int64_t floor_id,const SpatialBox& rectangle) {
std::vector<std::string> ids; auto floor=instance.floors.find(floor_id); if(floor!=instance.floors.end()) { QUERY } return ids;
}
std::vector<std::string> query_many(SpatialInstance& instance,int64_t floor_id,const std::vector<SpatialBox>& rectangles) {
std::vector<std::string> ids; auto floor=instance.floors.find(floor_id); if(floor!=instance.floors.end()) { MANY } return ids;
}
'''.replace('UPDATE',update).replace('QUERY',query.replace('spatial_box(args[1])','rectangle').replace('ids.append(V::text(it->second))','ids.push_back(it->second)')).replace('MANY',many.replace('ids.append(V::text(id))','ids.push_back(id)'))
main=r'''
using Oracle=std::map<std::string,std::pair<int64_t,SpatialBox>>;
bool overlaps(const SpatialBox&a,const SpatialBox&b) {
return bg::get<bg::min_corner,0>(a)<=bg::get<bg::max_corner,0>(b)&&bg::get<bg::max_corner,0>(a)>=bg::get<bg::min_corner,0>(b)&&bg::get<bg::min_corner,1>(a)<=bg::get<bg::max_corner,1>(b)&&bg::get<bg::max_corner,1>(a)>=bg::get<bg::min_corner,1>(b);
}
std::vector<std::string> oracle(const Oracle&o,int64_t floor,const std::vector<SpatialBox>&boxes) {
std::vector<std::string> r; for(const auto&[id,record]:o)if(record.first==floor)for(const auto&box:boxes)if(overlaps(record.second,box)){r.push_back(id);break;} return r;
}
void equal(std::vector<std::string>a,std::vector<std::string>b){std::sort(a.begin(),a.end());std::sort(b.begin(),b.end());if(a!=b)throw std::runtime_error("query mismatch");}
int main(){
static_assert(BOOST_VERSION==109200,"Use repository-pinned Boost 1.92.0");
SpatialInstance index; Oracle state; std::mt19937_64 rng(230731); uint64_t checks=0,updates=0,removals=0;
auto box=[&](){double x=int(rng()%400)-200,y=int(rng()%400)-200,w=(rng()%40)/4.,h=(rng()%40)/4.;return SpatialBox{{x,y},{x+w,y+h}};};
for(int tick=0;tick<20000;++tick){std::string id="actor_"+std::to_string(rng()%640);int64_t floor=int(rng()%7)-3;auto r=box();
if(tick%13==0){index.remove(id);state.erase(id);++removals;}else{update(index,id,floor,r);state[id]={floor,r};++updates;}
if(tick%499==0){index.floors.clear();index.records.clear();state.clear();}
auto q=box();equal(query(index,floor,q),oracle(state,floor,{q}));++checks;
std::vector<SpatialBox> qs{q,box(),q};equal(query_many(index,floor,qs),oracle(state,floor,qs));++checks;
}
// Closed broadphase edges and zero-sized boxes are deliberate; BodyIndex handles strict contact.
for(int floor=-1;floor<=1;++floor){index.floors.clear();index.records.clear();state.clear();
std::vector<SpatialBox> boxes{{{0,0},{1,1}},{{1,0},{2,1}},{{1,1},{1,1}},{{-1,-1},{0,0}}};
for(int i=0;i<int(boxes.size());++i){auto id="edge_"+std::to_string(i);update(index,id,floor,boxes[i]);state[id]={floor,boxes[i]};}
for(auto&q:boxes){equal(query(index,floor,q),oracle(state,floor,{q}));++checks;} equal(query_many(index,floor,{}),{});++checks;
}
std::cout<<"{\"boost_version\":"<<BOOST_VERSION<<",\"updates\":"<<updates<<",\"removals\":"<<removals<<",\"query_comparisons\":"<<checks<<",\"passed\":true,\"godot_bridge_tested\":false}\n";
}
'''
headers='#include <boost/geometry.hpp>\n#include <boost/geometry/index/rtree.hpp>\n#include <boost/version.hpp>\n#include <map>\n#include <set>\n#include <string>\n#include <vector>\n#include <random>\n#include <iostream>\n#include <stdexcept>\n#include <algorithm>\n'
translation = output / 'spatial_core.cpp'
translation.write_text(headers+core+helpers+main)
exe = output / 'spatial_core'
command = [args.compiler, '-std=c++17', '-O2', '-I', str(args.boost_include.resolve()), str(translation), '-o', str(exe)]
compile_result = subprocess.run(command, text=True, capture_output=True)
(output / 'compile.log').write_text(compile_result.stdout+compile_result.stderr)
compile_result.check_returncode()
run = subprocess.run([str(exe)], text=True, capture_output=True, timeout=120)
(output / 'run.log').write_text(run.stdout+run.stderr)
run.check_returncode()
result = json.loads(run.stdout)
result.update({
    'scope': 'production Boost R-tree core; Godot Variant and registration adapters excluded',
    'source_sha256': hashlib.sha256(p.read_bytes()).hexdigest(),
    'translation_sha256': hashlib.sha256(translation.read_bytes()).hexdigest(),
    'compiler': subprocess.run([args.compiler, '--version'], text=True, capture_output=True, check=True).stdout.splitlines()[0],
    'command': command,
    'boost_package_sha256_expected': '2f9935335e17f9930cba7e93a8db95bf699df2dd1c250cffe6dce89c7ea70154',
    'formal_pass': False,
})
(output / 'result.json').write_text(json.dumps(result, indent=2)+'\n')
print(json.dumps(result, indent=2))
