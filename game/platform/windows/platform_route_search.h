// Include Boost adjacency_list.hpp and dijkstra_shortest_paths.hpp globally,
// then include this adapter after V/A/D in platform_arrivals.cpp.
GDExtensionInterfaceVariantCall route_search_variant_call;
Builtin route_search_callable_call;

namespace route_search_backend {
struct Weight {
    int64_t ticks;
    size_t target_rank;
};
struct Distance {
    bool finite = false;
    int64_t ticks = 0;
    size_t rank = 0;
};
struct Earlier {
    bool operator()(const Distance& first, const Distance& second) const {
        if (first.finite != second.finite) return first.finite;
        if (!first.finite) return false;
        return first.ticks != second.ticks ? first.ticks < second.ticks : first.rank < second.rank;
    }
};
struct Add {
    Distance operator()(const Distance& from, const Weight& edge) const {
        if (!from.finite || edge.ticks < 0 || from.ticks > INT64_MAX - edge.ticks) return {};
        return {true, from.ticks + edge.ticks, edge.target_rank};
    }
};
using Graph = boost::adjacency_list<boost::vecS, boost::vecS, boost::directedS,
    boost::no_property, boost::property<boost::edge_weight_t, Weight>>;
using Vertex = boost::graph_traits<Graph>::vertex_descriptor;
struct GoalReached {};

struct Search {
    Graph graph;
    std::vector<std::string> names;
    std::map<std::string, Vertex> vertices;
    std::vector<Distance> distances;
    V expand;
    Vertex goal;
    int64_t expanded = 0;

    explicit Search(const V& callback) : expand(callback) {}

    void examine(Vertex vertex) {
        if (!distances[vertex].finite) return;
        if (vertex == goal) throw GoalReached{};
        ++expanded;
        V id = V::text(names[vertex]);
        const GDExtensionConstVariantPtr arguments[] = {&id.raw};
        V result;
        destroy(&result.raw); // variant_call constructs an uninitialized result.
        GDExtensionCallError error{};
        route_search_variant_call(&expand.raw, &route_search_callable_call, arguments, 1, &result.raw, &error);
        if (error.error != GDEXTENSION_CALL_OK || type(&result.raw) != GDEXTENSION_VARIANT_TYPE_ARRAY)
            throw std::runtime_error("路线出边回调未返回有效数组");
        A edges(result);
        for (int64_t i = 0; i < edges.size(); ++i) {
            V raw_edge = edges.at(i);
            if (type(&raw_edge.raw) != GDEXTENSION_VARIANT_TYPE_DICTIONARY)
                throw std::runtime_error("路线边必须是字典");
            D edge(raw_edge);
            V to = edge.get("to"), ticks = edge.get("ticks");
            if (type(&to.raw) != GDEXTENSION_VARIANT_TYPE_STRING || type(&ticks.raw) != GDEXTENSION_VARIANT_TYPE_INT || ticks.number() < 0)
                throw std::runtime_error("路线边需要已声明目标和非负整数耗时");
            auto target = vertices.find(to.text());
            if (target == vertices.end()) throw std::runtime_error("路线边引用未声明节点");
            boost::add_edge(vertex, target->second, Weight{ticks.number(), target->second}, graph);
        }
    }
};
struct Visitor : boost::default_dijkstra_visitor {
    Search* search;
    explicit Visitor(Search* value) : search(value) {}
    template<class GraphType> void examine_vertex(Vertex vertex, const GraphType&) const { search->examine(vertex); }
};
}

V solve_route_search(const V& raw_request) {
    using namespace route_search_backend;
    D request(raw_request);
    V raw_nodes = request.get("nodes"), start_name = request.get("start"), goal_name = request.get("goal");
    V initial = request.get("initial_ticks"), callback = request.get("expand");
    if (type(&raw_nodes.raw) != GDEXTENSION_VARIANT_TYPE_ARRAY || type(&start_name.raw) != GDEXTENSION_VARIANT_TYPE_STRING ||
        type(&goal_name.raw) != GDEXTENSION_VARIANT_TYPE_STRING || type(&initial.raw) != GDEXTENSION_VARIANT_TYPE_INT ||
        initial.number() < 0 || type(&callback.raw) != GDEXTENSION_VARIANT_TYPE_CALLABLE)
        throw std::runtime_error("路线搜索需要完整节点、起终点、整数初始耗时和出边回调");
    Search search(callback);
    A nodes(raw_nodes);
    for (int64_t i = 0; i < nodes.size(); ++i) {
        V name = nodes.at(i);
        if (type(&name.raw) != GDEXTENSION_VARIANT_TYPE_STRING) throw std::runtime_error("路线节点身份必须是字符串");
        search.vertices.emplace(name.text(), 0);
    }
    for (auto& item : search.vertices) { item.second = search.names.size(); search.names.push_back(item.first); }
    auto start = search.vertices.find(start_name.text()), goal = search.vertices.find(goal_name.text());
    if (start == search.vertices.end() || goal == search.vertices.end()) throw std::runtime_error("路线起终点未声明");
    search.goal = goal->second;
    search.graph = Graph(search.names.size());
    search.distances.resize(search.names.size());
    std::vector<Vertex> previous(search.names.size());
    auto indices = get(boost::vertex_index, search.graph);
    auto distances = boost::make_iterator_property_map(search.distances.begin(), indices);
    auto predecessors = boost::make_iterator_property_map(previous.begin(), indices);
    try {
        // Each target owns its fixed ID rank. Relaxing two paths to that same
        // target therefore compares integer ticks only, while the library heap
        // breaks equal-tick frontier ties by the original node ID. Rank zero
        // for the source also keeps Boost's zero-edge nonnegative check valid.
        boost::dijkstra_shortest_paths(search.graph, start->second,
            boost::predecessor_map(predecessors).distance_map(distances)
                .weight_map(get(boost::edge_weight, search.graph))
                .distance_compare(Earlier{}).distance_combine(Add{})
                .distance_inf(Distance{}).distance_zero(Distance{true, initial.number(), 0})
                .visitor(Visitor(&search)));
    } catch (const GoalReached&) {
        // The settled goal has the same minimum tick/ID frontier position as
        // the former queue. Its outgoing edges are never quoted.
    }
    D output;
    GDExtensionBool reached = search.distances[search.goal].finite;
    output.set("ok", V::typed(GDEXTENSION_VARIANT_TYPE_BOOL, &reached));
    output.set("expanded_nodes", V::number(search.expanded));
    if (!reached) return output.value();
    std::vector<Vertex> reverse;
    Vertex current = search.goal;
    while (current != start->second) {
        reverse.push_back(current);
        if (reverse.size() >= search.names.size() || previous[current] == current)
            throw std::runtime_error("路线前驱链未连接到起点");
        current = previous[current];
    }
    A path;
    path.append(V::text(search.names[start->second]));
    for (auto item = reverse.rbegin(); item != reverse.rend(); ++item) path.append(V::text(search.names[*item]));
    output.set("nodes", path.value());
    output.set("travel_ticks", V::number(search.distances[search.goal].ticks));
    return output.value();
}

void route_search_initialize(GDExtensionInterfaceGetProcAddress api) {
    route_search_variant_call = reinterpret_cast<GDExtensionInterfaceVariantCall>(api("variant_call"));
    new_name(&route_search_callable_call, "call");
}
void route_search_deinitialize(GDExtensionInterfaceGetProcAddress api) {
    auto get_dtor = reinterpret_cast<GDExtensionInterfaceVariantGetPtrDestructor>(api("variant_get_ptr_destructor"));
    get_dtor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&route_search_callable_call);
}
