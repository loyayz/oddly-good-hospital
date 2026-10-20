// Included after V/A/D. Boost owns traversal, colors and the FIFO frontier.
// The implicit graph borrows the floor's four-bit edges without constructing
// another adjacency list or calling Godot once per point/connection.
namespace grid_distance_backend {
constexpr int SIDE = 96, LIMIT = SIDE * SIDE;
struct Edge {
    int from = 0, to = -1, direction = 0;
    bool operator==(const Edge& other) const { return from == other.from && to == other.to; }
    bool operator!=(const Edge& other) const { return !(*this == other); }
};
struct Graph;
struct Allowed {
    const Graph* graph = nullptr;
    bool operator()(const Edge& edge) const;
};
struct Neighbour {
    int from = 0;
    Edge operator()(int direction) const {
        int to = -1;
        if (direction == 0 && from >= SIDE) to = from - SIDE;
        else if (direction == 1 && from % SIDE > 0) to = from - 1;
        else if (direction == 2 && from % SIDE + 1 < SIDE) to = from + 1;
        else if (direction == 3 && from + SIDE < LIMIT) to = from + SIDE;
        return {from, to, direction};
    }
};
struct Graph {
    using vertex_descriptor = int;
    using edge_descriptor = Edge;
    using vertex_iterator = boost::counting_iterator<int>;
    using RawIterator = boost::transform_iterator<Neighbour, boost::counting_iterator<int>>;
    using out_edge_iterator = boost::filter_iterator<Allowed, RawIterator>;
    using directed_category = boost::directed_tag;
    using edge_parallel_category = boost::disallow_parallel_edge_tag;
    struct traversal_category : boost::vertex_list_graph_tag, boost::incidence_graph_tag {};
    using vertices_size_type = size_t;
    using edges_size_type = size_t;
    using degree_size_type = size_t;
    const uint8_t* enabled = nullptr;
    const uint8_t* edges = nullptr;
    const uint8_t* reservations = nullptr;
    bool reverse = false;
    static vertex_descriptor null_vertex() { return -1; }
};
bool Allowed::operator()(const Edge& edge) const {
    if (edge.to < 0 || !graph->enabled[edge.from] || !graph->enabled[edge.to]) return false;
    if (graph->reverse) {
        // Reverse expansion may discover a reserved start, but cannot expand
        // through a reserved current cell. Its original incoming edge remains
        // directional: neighbour -> current, not current -> neighbour.
        return (!graph->reservations || !graph->reservations[edge.from]) &&
            (graph->edges[edge.to] & (1 << (3 - edge.direction)));
    }
    return (!graph->reservations || !graph->reservations[edge.to]) &&
        (graph->edges[edge.from] & (1 << edge.direction));
}
std::pair<Graph::vertex_iterator, Graph::vertex_iterator> vertices(const Graph&) {
    return {Graph::vertex_iterator(0), Graph::vertex_iterator(LIMIT)};
}
[[maybe_unused]] size_t num_vertices(const Graph&) { return LIMIT; }
std::pair<Graph::out_edge_iterator, Graph::out_edge_iterator> out_edges(int vertex, const Graph& graph) {
    auto first = boost::make_transform_iterator(boost::counting_iterator<int>(0), Neighbour{vertex});
    auto last = boost::make_transform_iterator(boost::counting_iterator<int>(4), Neighbour{vertex});
    return {Graph::out_edge_iterator(Allowed{&graph}, first, last), Graph::out_edge_iterator(Allowed{&graph}, last, last)};
}
size_t out_degree(int vertex, const Graph& graph) {
    auto edges = out_edges(vertex, graph); return static_cast<size_t>(std::distance(edges.first, edges.second));
}
int source(const Edge& edge, const Graph&) { return edge.from; }
int target(const Edge& edge, const Graph&) { return edge.to; }
struct Visitor : boost::default_bfs_visitor {
    int32_t* distances;
    int32_t* successors;
    Visitor(int32_t* values, int32_t* next) : distances(values), successors(next) {}
    template<class GraphType> void tree_edge(const Edge& edge, const GraphType&) const {
        distances[edge.to] = distances[edge.from] + 1;
        if (successors) successors[edge.to] = edge.from;
    }
};
}

GDExtensionPtrBuiltInMethod grid_distance_bytes_size, grid_distance_ints_resize;
GDExtensionInterfacePackedByteArrayOperatorIndexConst grid_distance_byte_index;
GDExtensionInterfacePackedInt32ArrayOperatorIndex grid_distance_int_index;
struct GridDistanceBytes {
    alignas(8) unsigned char raw[OGH_PACKED_BYTE_ARRAY_SIZE];
    explicit GridDistanceBytes(const V& value) { to_type[GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY](raw, const_cast<Raw*>(&value.raw)); }
    ~GridDistanceBytes() { destruct[GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY](raw); }
    int64_t size() const { int64_t count; grid_distance_bytes_size(const_cast<unsigned char*>(raw), nullptr, &count, 0); return count; }
    const uint8_t* data() const { return grid_distance_byte_index(raw, 0); }
};
struct GridDistanceInts {
    alignas(8) unsigned char raw[OGH_PACKED_INT32_ARRAY_SIZE];
    explicit GridDistanceInts(int64_t size) {
        construct[GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY](raw, nullptr);
        const void* args[] = {&size}; int64_t error = 0;
        grid_distance_ints_resize(raw, args, &error, 1);
        if (error) { destruct[GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY](raw); throw std::runtime_error("距离场所需内存不足"); }
        if (size) std::fill(data(), data() + size, -1);
    }
    ~GridDistanceInts() { destruct[GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY](raw); }
    int32_t* data() { return grid_distance_int_index(raw, 0); }
    V value() const { return V::typed(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, raw); }
};
V solve_grid_distance_field(const V& raw_enabled, const V& raw_edges, const V& raw_reservations, const V& raw_options) {
    using namespace grid_distance_backend;
    if (!grid_distance_bytes_size || !grid_distance_ints_resize || !grid_distance_byte_index || !grid_distance_int_index)
        throw std::runtime_error("距离场原生数组接口不可用");
    GridDistanceBytes enabled(raw_enabled), edges(raw_edges), reservations(raw_reservations);
    if (enabled.size() != LIMIT || edges.size() != LIMIT || (reservations.size() != 0 && reservations.size() != LIMIT))
        throw std::runtime_error("距离场需要完整96×96有效点、出边和预约掩码");
    D options(raw_options); V root = options.get("root"), backwards = options.get("reverse");
    if (type(&root.raw) != GDEXTENSION_VARIANT_TYPE_INT || root.number() < -1 || root.number() >= LIMIT ||
        type(&backwards.raw) != GDEXTENSION_VARIANT_TYPE_BOOL)
        throw std::runtime_error("距离场需要有效起点和明确搜索方向");
    GDExtensionBool reverse = false; to_type[GDEXTENSION_VARIANT_TYPE_BOOL](&reverse, &backwards.raw);
    GridDistanceInts distances(LIMIT), successors(reverse ? LIMIT : 0);
    if (root.number() >= 0 && enabled.data()[root.number()]) {
        Graph graph; graph.enabled = enabled.data(); graph.edges = edges.data(); graph.reverse = reverse;
        graph.reservations = reservations.size() ? reservations.data() : nullptr;
        distances.data()[root.number()] = 0;
        std::vector<boost::default_color_type> colors(LIMIT);
        auto color = boost::make_iterator_property_map(colors.begin(), boost::typed_identity_property_map<int>());
        boost::queue<int> frontier;
        boost::breadth_first_search(graph, static_cast<int>(root.number()), frontier,
            Visitor(distances.data(), reverse ? successors.data() : nullptr), color);
    }
    D result; GDExtensionBool ok = true;
    result.set("ok", V::typed(GDEXTENSION_VARIANT_TYPE_BOOL, &ok));
    result.set("distances", distances.value()); result.set("successors", successors.value()); return result.value();
}
void grid_distance_initialize(GDExtensionInterfaceGetProcAddress api) {
    auto method = reinterpret_cast<GDExtensionInterfaceVariantGetPtrBuiltinMethod>(api("variant_get_ptr_builtin_method"));
    Builtin size, resize; new_name(&size, "size"); new_name(&resize, "resize");
    grid_distance_bytes_size = method(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, &size, OGH_ARRAY_SIZE_HASH);
    grid_distance_ints_resize = method(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, &resize, OGH_BYTES_RESIZE_HASH);
    grid_distance_byte_index = reinterpret_cast<GDExtensionInterfacePackedByteArrayOperatorIndexConst>(api("packed_byte_array_operator_index_const"));
    grid_distance_int_index = reinterpret_cast<GDExtensionInterfacePackedInt32ArrayOperatorIndex>(api("packed_int32_array_operator_index"));
    destruct[GDEXTENSION_VARIANT_TYPE_STRING_NAME](&size); destruct[GDEXTENSION_VARIANT_TYPE_STRING_NAME](&resize);
}
