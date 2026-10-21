// This is only an engine adapter, not another graph or search implementation.
// Complete hospital predicates are evaluated in RouteClearance. AStar2D owns
// allocation, point state, adjacency order and every subsequent path search.
GDExtensionMethodBindPtr floor_graph_reserve, floor_graph_add, floor_graph_disable;
GDExtensionMethodBindPtr floor_graph_connect, floor_graph_count;
GDExtensionInterfaceObjectCastTo floor_graph_cast;
void* floor_graph_tag = nullptr;

V build_floor_graph(const V& raw_graph, const V& raw_present, const V& raw_enabled, const V& raw_edges) {
    constexpr int SIDE = 96, LIMIT = SIDE * SIDE;
    if (!floor_graph_reserve || !floor_graph_add || !floor_graph_disable || !floor_graph_connect || !floor_graph_count ||
        !floor_graph_cast || !floor_graph_tag || !grid_distance_bytes_size || !grid_distance_byte_index)
        throw std::runtime_error("AStar2D 批量装配原生接口不可用");
    GDExtensionObjectPtr graph = nullptr;
    to_type[GDEXTENSION_VARIANT_TYPE_OBJECT](&graph, const_cast<Raw*>(&raw_graph.raw));
    if (!graph || !floor_graph_cast(graph, floor_graph_tag))
        throw std::runtime_error("层内导航批量装配需要 AStar2D");
    GridDistanceBytes present(raw_present), enabled(raw_enabled), edges(raw_edges);
    if (present.size() != LIMIT || enabled.size() != LIMIT || edges.size() != LIMIT)
        throw std::runtime_error("层内导航批量装配需要完整96×96点与边掩码");
    const uint8_t* points = present.data();
    const uint8_t* available = enabled.data();
    const uint8_t* links = edges.data();
    int64_t count = 0, connection_count = 0;
    // Validate before mutating the engine, including reciprocal edges and
    // horizontal boundaries. Malformed input must leave the graph unchanged.
    for (int id = 0; id < LIMIT; ++id) {
        if (points[id] > 1 || available[id] > 1 || links[id] > 15 || (!points[id] && available[id]) || (!available[id] && links[id]))
            throw std::runtime_error("层内导航点与边掩码不一致");
        count += points[id];
        for (int direction = 0; direction < 4; ++direction) {
            if (!(links[id] & (1 << direction))) continue;
            const int other = id + (direction == 0 ? -SIDE : direction == 1 ? -1 : direction == 2 ? 1 : SIDE);
            if (other < 0 || other >= LIMIT || ((direction == 1 || direction == 2) && id / SIDE != other / SIDE) ||
                !available[other] || !(links[other] & (1 << (3 - direction))))
                throw std::runtime_error("层内导航静态边必须完整且双向");
        }
    }
    int64_t existing = 0;
    object_ptrcall(floor_graph_count, graph, nullptr, &existing);
    if (existing != 0) throw std::runtime_error("层内导航批量装配仅接受空图");
    const void* reserve_args[] = {&count};
    object_ptrcall(floor_graph_reserve, graph, reserve_args, nullptr);
    const double weight = 1.0; // Godot ptrcall encodes scalar float as double.
    const GDExtensionBool yes = true;
    struct Point { float x, y; }; // The build pins the engine's single precision ABI.
    for (int64_t id = 0; id < LIMIT; ++id) {
        if (!points[id]) continue;
        const Point point{static_cast<float>(id % SIDE), static_cast<float>(id / SIDE)};
        const void* add_args[] = {&id, &point, &weight};
        object_ptrcall(floor_graph_add, graph, add_args, nullptr);
        if (!available[id]) {
            const void* disable_args[] = {&id, &yes};
            object_ptrcall(floor_graph_disable, graph, disable_args, nullptr);
        }
    }
    // Sorted IDs plus RIGHT/DOWN insert UP/LEFT before a node's own outgoing
    // additions, exactly matching the original engine neighbour insertion order.
    for (int64_t id = 0; id < LIMIT; ++id) {
        for (int direction : {2, 3}) {
            if (!(links[id] & (1 << direction))) continue;
            const int64_t other = id + (direction == 2 ? 1 : SIDE);
            const void* connect_args[] = {&id, &other, &yes};
            object_ptrcall(floor_graph_connect, graph, connect_args, nullptr);
            ++connection_count;
        }
    }
    D result;
    result.set("ok", V::typed(GDEXTENSION_VARIANT_TYPE_BOOL, &yes));
    result.set("points", V::number(count)); result.set("connections", V::number(connection_count));
    return result.value();
}

void floor_graph_initialize(GDExtensionInterfaceGetProcAddress api) {
    auto get_bind = reinterpret_cast<GDExtensionInterfaceClassdbGetMethodBind>(api("classdb_get_method_bind"));
    auto get_tag = reinterpret_cast<GDExtensionInterfaceClassdbGetClassTag>(api("classdb_get_class_tag"));
    floor_graph_cast = reinterpret_cast<GDExtensionInterfaceObjectCastTo>(api("object_cast_to"));
    Builtin owner; new_name(&owner, "AStar2D");
    floor_graph_tag = get_tag(&owner);
    auto bind = [&](const char* name, int64_t hash) {
        Builtin method; new_name(&method, name);
        GDExtensionMethodBindPtr result = get_bind(&owner, &method, hash);
        destruct[GDEXTENSION_VARIANT_TYPE_STRING_NAME](&method); return result;
    };
    floor_graph_reserve = bind("reserve_space", OGH_ASTAR_RESERVE_HASH);
    floor_graph_add = bind("add_point", OGH_ASTAR_ADD_HASH);
    floor_graph_disable = bind("set_point_disabled", OGH_ASTAR_DISABLE_HASH);
    floor_graph_connect = bind("connect_points", OGH_ASTAR_CONNECT_HASH);
    floor_graph_count = bind("get_point_count", OGH_ASTAR_COUNT_HASH);
    destruct[GDEXTENSION_VARIANT_TYPE_STRING_NAME](&owner);
}
