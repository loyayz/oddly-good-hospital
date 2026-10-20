// Included inside platform_arrivals.cpp's anonymous namespace after V/A/D.
// Hospital priority and tie-breaking remain here; Boost owns the matching search.
// Include Boost adjacency_list.hpp and max_cardinality_matching.hpp globally.

namespace personal_bed_matching {
struct Edge {
    size_t bed;
    int64_t ticks;
};

struct Problem {
    using Graph = boost::adjacency_list<boost::vecS, boost::vecS, boost::undirectedS>;
    using Vertex = boost::graph_traits<Graph>::vertex_descriptor;
    std::vector<std::string> staff, beds;
    std::vector<std::vector<Edge>> edges;

    // Decide only whether all selected staff can be covered. Fixed earlier
    // choices are represented by unavailable beds, not by modified world facts.
    bool complete(const std::vector<size_t>& selected, const std::set<size_t>& unavailable,
                  std::map<size_t, size_t>& owners) const {
        Graph graph(selected.size() + beds.size());
        for (size_t i = 0; i < selected.size(); ++i)
            for (const Edge& edge : edges[selected[i]])
                if (!unavailable.count(edge.bed)) boost::add_edge(i, selected.size() + edge.bed, graph);
        std::vector<Vertex> mate(boost::num_vertices(graph), boost::graph_traits<Graph>::null_vertex());
        auto mapping = boost::make_iterator_property_map(mate.begin(), get(boost::vertex_index, graph));
        boost::edmonds_maximum_cardinality_matching(graph, mapping);
        if (boost::matching_size(graph, mapping) != selected.size()) return false;
        owners.clear();
        for (size_t i = 0; i < selected.size(); ++i) owners.emplace(mate[i] - selected.size(), selected[i]);
        return true;
    }

    V solve() const {
        std::vector<size_t> covered;
        std::map<size_t, size_t> owners;
        // Matchable staff sets form a transversal matroid. Accepting staff in
        // hospital order yields maximum coverage and its required priority set.
        for (size_t i = 0; i < staff.size(); ++i) {
            if (edges[i].empty()) continue;
            std::vector<size_t> trial = covered;
            trial.push_back(i);
            std::map<size_t, size_t> next;
            if (complete(trial, {}, next)) { covered.swap(trial); owners.swap(next); }
            if (covered.size() == beds.size()) break;
        }
        std::set<size_t> fixed_beds;
        std::map<size_t, size_t> fixed_owners;
        for (size_t i = 0; i < covered.size(); ++i) {
            const size_t staff_id = covered[i];
            for (const Edge& edge : edges[staff_id]) {
                if (fixed_beds.count(edge.bed)) continue;
                auto current = owners.find(edge.bed);
                if (current != owners.end() && current->second == staff_id) {
                    fixed_beds.insert(edge.bed); fixed_owners.emplace(edge.bed, staff_id); break;
                }
                auto blocked = fixed_beds;
                blocked.insert(edge.bed);
                std::vector<size_t> remaining(covered.begin() + i + 1, covered.end());
                std::map<size_t, size_t> next;
                if (!complete(remaining, blocked, next)) continue;
                fixed_beds.insert(edge.bed); fixed_owners.emplace(edge.bed, staff_id);
                next.insert(fixed_owners.begin(), fixed_owners.end()); owners.swap(next);
                break;
            }
        }
        D result;
        for (const auto& owner : owners) result.set(beds[owner.first].c_str(), V::text(staff[owner.second]));
        return result.value();
    }
};
}

V solve_personal_bed_matching(const V& staff_ids, const V& raw_candidates) {
    using namespace personal_bed_matching;
    Problem problem;
    std::set<std::string> seen;
    std::map<std::string, size_t> bed_indices;
    A requested(staff_ids);
    D candidates(raw_candidates);
    for (int64_t i = 0; i < requested.size(); ++i) {
        V raw_staff = requested.at(i);
        if (type(&raw_staff.raw) != GDEXTENSION_VARIANT_TYPE_STRING)
            throw std::runtime_error("个人床分配员工身份必须是字符串");
        std::string staff = raw_staff.text();
        if (staff.empty()) throw std::runtime_error("个人床分配员工身份不能为空");
        if (!seen.insert(staff).second) continue;
        std::map<std::string, int64_t> travel;
        V raw_edges = candidates.get(raw_staff);
        if (!raw_edges.nil()) {
            if (type(&raw_edges.raw) != GDEXTENSION_VARIANT_TYPE_ARRAY)
                throw std::runtime_error("个人床候选必须是数组");
            A values(raw_edges);
            for (int64_t j = 0; j < values.size(); ++j) {
                V value = values.at(j);
                if (type(&value.raw) != GDEXTENSION_VARIANT_TYPE_DICTIONARY)
                    throw std::runtime_error("个人床候选必须是字典");
                D candidate(value);
                V bed = candidate.get("bed_id"), ticks = candidate.get("travel_ticks");
                if (type(&bed.raw) != GDEXTENSION_VARIANT_TYPE_STRING || type(&ticks.raw) != GDEXTENSION_VARIANT_TYPE_INT)
                    throw std::runtime_error("个人床候选需要床身份和整数通行时间");
                if (bed.text().empty() || ticks.number() < 0)
                    throw std::runtime_error("个人床候选需要有效床身份和非负通行时间");
                auto found = travel.emplace(bed.text(), ticks.number());
                if (!found.second) found.first->second = std::min(found.first->second, ticks.number());
            }
        }
        std::vector<Edge> edges;
        for (const auto& choice : travel) {
            auto bed = bed_indices.emplace(choice.first, problem.beds.size());
            if (bed.second) problem.beds.push_back(choice.first);
            edges.push_back({bed.first->second, choice.second});
        }
        std::sort(edges.begin(), edges.end(), [&](const Edge& first, const Edge& second) {
            if (first.ticks != second.ticks) return first.ticks < second.ticks;
            return problem.beds[first.bed] < problem.beds[second.bed];
        });
        problem.staff.push_back(std::move(staff));
        problem.edges.push_back(std::move(edges));
    }
    D result;
    GDExtensionBool ok = true;
    result.set("ok", V::typed(GDEXTENSION_VARIANT_TYPE_BOOL, &ok));
    result.set("owners", problem.solve());
    return result.value();
}
