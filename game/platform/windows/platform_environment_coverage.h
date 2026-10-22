// Environment owns these already prepared cell/edge sets. Only their immutable
// masks are retained by the script's existing eight-floor cache; Boost owns BFS.
namespace environment_coverage_backend {
using grid_distance_backend::Edge;
constexpr int SIDE = grid_distance_backend::SIDE, LIMIT = grid_distance_backend::LIMIT;
using Distances = std::unordered_map<int, int32_t>;
struct Graph;
struct Allowed {
    const Graph* graph;
    bool operator()(const Edge& edge) const;
};
struct Neighbour {
    int from;
    Edge operator()(int order) const {
        constexpr int directions[] = {1, 0, 3, 2}; // Original left/up/down/right.
        return grid_distance_backend::Neighbour{from}(directions[order]);
    }
};
struct Graph : grid_distance_backend::Graph {
    using RawIterator = boost::transform_iterator<Neighbour, boost::counting_iterator<int>>;
    using out_edge_iterator = boost::filter_iterator<Allowed, RawIterator>;
    const Distances* distances = nullptr;
    int64_t radius = 0;
};
bool Allowed::operator()(const Edge& edge) const {
    return graph->distances->at(edge.from) < graph->radius && grid_distance_backend::Allowed{graph}(edge);
}
std::pair<Graph::out_edge_iterator, Graph::out_edge_iterator> out_edges(int vertex, const Graph& graph) {
    auto first = boost::make_transform_iterator(boost::counting_iterator<int>(0), Neighbour{vertex});
    auto last = boost::make_transform_iterator(boost::counting_iterator<int>(4), Neighbour{vertex});
    return {Graph::out_edge_iterator(Allowed{&graph}, first, last), Graph::out_edge_iterator(Allowed{&graph}, last, last)};
}
[[maybe_unused]] size_t out_degree(int vertex, const Graph& graph) {
    auto edges = out_edges(vertex, graph); return static_cast<size_t>(std::distance(edges.first, edges.second));
}
struct Visitor : boost::default_bfs_visitor {
    Distances* distances;
    std::vector<int32_t>* cells;
    Visitor(Distances& values, std::vector<int32_t>& output) : distances(&values), cells(&output) {}
    void tree_edge(const Edge& edge, const Graph&) const { (*distances)[edge.to] = distances->at(edge.from) + 1; }
    void discover_vertex(int vertex, const Graph&) const {
        cells->insert(cells->end(), {vertex % SIDE, vertex / SIDE, distances->at(vertex)});
    }
};
void close_edge(uint8_t* edges, int axis, int line, int along) {
    if (axis == 0) {
        if (line > 0) edges[(line - 1) * SIDE + along] &= ~(1 << 3);
        if (line < SIDE) edges[line * SIDE + along] &= ~(1 << 0);
    } else {
        if (line > 0) edges[along * SIDE + line - 1] &= ~(1 << 2);
        if (line < SIDE) edges[along * SIDE + line] &= ~(1 << 1);
    }
}
V unsupported(const char* reason) {
    D result; GDExtensionBool ready = false;
    result.set("ready", V::typed(GDEXTENSION_VARIANT_TYPE_BOOL, &ready));
    result.set("reason", V::text(reason)); return result.value();
}
}

V build_environment_coverage_masks(const V& raw_input) {
    using namespace environment_coverage_backend;
    if (!unit_mask_bytes_resize || !unit_mask_byte_index || !entry_i32_size || !entry_i32_index)
        throw std::runtime_error("环境覆盖原生数组接口不可用");
    D input(raw_input);
    V raw_owned = input.get("owned"), raw_blocked = input.get("blocked"), raw_walls = input.get("walls"), raw_noise = input.get("noise");
    for (const V* value : {&raw_owned, &raw_blocked, &raw_walls, &raw_noise})
        if (type(&value->raw) != GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY) return unsupported("特殊环境格边沿完整脚本查询");
    EntryInt32s owned(raw_owned), blocked(raw_blocked), walls(raw_walls), noise(raw_noise);
    if (owned.size() % 2 || blocked.size() % 2 || walls.size() % 3 || noise.size() % 3)
        return unsupported("环境格点和格边分量不完整");
    std::array<uint8_t, LIMIT> passable{};
    for (int64_t i = 0; i < owned.size(); i += 2) {
        int x = owned.data()[i], y = owned.data()[i + 1];
        if (x < 0 || y < 0 || x >= SIDE / 32 || y >= SIDE / 32) return unsupported("域外环境地块沿完整脚本查询");
        for (int row = y * 32; row < (y + 1) * 32; ++row)
            std::fill(passable.begin() + row * SIDE + x * 32, passable.begin() + row * SIDE + (x + 1) * 32, 1);
    }
    for (int64_t i = 0; i < blocked.size(); i += 2) {
        int x = blocked.data()[i], y = blocked.data()[i + 1];
        if (x < 0 || y < 0 || x >= SIDE || y >= SIDE) return unsupported("域外环境阻挡沿完整脚本查询");
        passable[y * SIDE + x] = 0;
    }
    unit_static_masks::Bytes ordinary(LIMIT), screened(LIMIT);
    uint8_t* ordinary_data = ordinary.data(); uint8_t* screened_data = screened.data();
    for (int from = 0; from < LIMIT; ++from)
        for (int direction = 0; direction < 4; ++direction) {
            Edge edge = grid_distance_backend::Neighbour{from}(direction);
            // The original environment predicate checks the destination only.
            // A blocked/unowned root is still observed and can leave its cell.
            if (edge.to >= 0 && passable[edge.to]) ordinary_data[from] |= 1 << direction;
        }
    auto close = [](uint8_t* target, const EntryInt32s& edges) {
        const int32_t* values = edges.size() ? edges.data() : nullptr;
        for (int64_t i = 0; i < edges.size(); i += 3) {
            int axis = values[i], line = values[i + 1], along = values[i + 2];
            if ((axis != 0 && axis != 1) || line < 0 || line > SIDE || along < 0 || along >= SIDE) return false;
            close_edge(target, axis, line, along);
        }
        return true;
    };
    if (!close(ordinary_data, walls)) return unsupported("域外环境墙边沿完整脚本查询");
    std::copy(ordinary_data, ordinary_data + LIMIT, screened_data);
    if (!close(screened_data, noise)) return unsupported("域外环境屏风边沿完整脚本查询");
    D result; GDExtensionBool ready = true;
    result.set("ready", V::typed(GDEXTENSION_VARIANT_TYPE_BOOL, &ready));
    result.set("ordinary", ordinary.value()); result.set("noise", screened.value()); return result.value();
}

V solve_environment_coverage(const V& raw_edges, const V& raw_options) {
    using namespace environment_coverage_backend;
    if (!grid_distance_bytes_size || !grid_distance_byte_index || !grid_distance_ints_resize || !grid_distance_int_index)
        throw std::runtime_error("环境覆盖原生数组接口不可用");
    GridDistanceBytes edges(raw_edges); D options(raw_options);
    V raw_root = options.get("root"), raw_radius = options.get("radius");
    if (edges.size() != LIMIT || type(&raw_root.raw) != GDEXTENSION_VARIANT_TYPE_INT ||
        type(&raw_radius.raw) != GDEXTENSION_VARIANT_TYPE_INT || raw_root.number() < 0 || raw_root.number() >= LIMIT)
        return unsupported("特殊环境起点或掩码沿完整脚本查询");
    const int root = static_cast<int>(raw_root.number());
    const int64_t radius = raw_radius.number(), bound = std::clamp<int64_t>(radius, 0, SIDE * 2);
    const size_t estimate = static_cast<size_t>(std::min<int64_t>(LIMIT, 1 + 2 * bound * (bound + 1)));
    Distances distances; distances.reserve(estimate); distances[root] = 0;
    std::unordered_map<int, boost::default_color_type> colors; colors.reserve(estimate);
    static_assert(boost::white_color == 0, "Default sparse colors must be white");
    auto color = boost::make_assoc_property_map(colors);
    std::vector<int32_t> cells; cells.reserve(estimate * 3);
    static const std::array<uint8_t, LIMIT> enabled = [] { std::array<uint8_t, LIMIT> values; values.fill(1); return values; }();
    Graph graph; graph.enabled = enabled.data(); graph.edges = edges.data(); graph.distances = &distances; graph.radius = radius;
    boost::queue<int> frontier;
    // Unlike breadth_first_search, visit does not initialize every grid vertex.
    // Sparse maps and output contain only the radius-limited discovered cells.
    boost::breadth_first_visit(graph, root, frontier, Visitor(distances, cells), color);
    GridDistanceInts output(static_cast<int64_t>(cells.size()));
    std::copy(cells.begin(), cells.end(), output.data());
    D result; GDExtensionBool ready = true;
    result.set("ready", V::typed(GDEXTENSION_VARIANT_TYPE_BOOL, &ready));
    result.set("cells", output.value()); return result.value();
}
