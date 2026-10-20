// Included after V/A/D in platform_arrivals.cpp's bridge namespace.
// Boost.Graph owns connected-component traversal; this adapter maps the
// hospital's bounded four-neighbour grid and returns the requested component.
std::pair<int64_t, int64_t> grid_point(const V& value) {
    if (type(&value.raw) != GDEXTENSION_VARIANT_TYPE_ARRAY) throw std::runtime_error("Grid coordinate must be an array");
    A point(value);
    if (point.size() != 2) throw std::runtime_error("Grid coordinate requires two integers");
    V x = point.at(0), y = point.at(1);
    if (type(&x.raw) != GDEXTENSION_VARIANT_TYPE_INT || type(&y.raw) != GDEXTENSION_VARIANT_TYPE_INT)
        throw std::runtime_error("Grid coordinate requires two integers");
    return {x.number(), y.number()};
}
V solve_grid_component(const V& raw_occupied, const V& raw_bounds, const V& raw_start, const V& raw_filled) {
    A occupied(raw_occupied), bounds(raw_bounds);
    if (bounds.size() != 4) throw std::runtime_error("Grid component requires four inclusive bounds");
    int64_t limits[4];
    for (int64_t i = 0; i < 4; ++i) {
        V limit = bounds.at(i);
        if (type(&limit.raw) != GDEXTENSION_VARIANT_TYPE_INT) throw std::runtime_error("Grid component bounds must be integers");
        limits[i] = limit.number();
    }
    const int64_t low_x = limits[0], low_y = limits[1], high_x = limits[2], high_y = limits[3];
    if (low_x < -1 || low_y < -1 || high_x > 96 || high_y > 96 || high_x < low_x || high_y < low_y)
        throw std::runtime_error("Grid component exceeds the hospital's 98 by 98 validation envelope");
    const size_t width = static_cast<size_t>(high_x - low_x + 1), height = static_cast<size_t>(high_y - low_y + 1);
    const auto start = grid_point(raw_start);
    if (start.first < low_x || start.first > high_x || start.second < low_y || start.second > high_y)
        throw std::runtime_error("Grid component start lies outside its bounds");
    GDExtensionBool filled = false;
    to_type[GDEXTENSION_VARIANT_TYPE_BOOL](&filled, const_cast<Raw*>(&raw_filled.raw));
    std::vector<unsigned char> eligible(width * height, filled ? 0 : 1);
    for (int64_t i = 0; i < occupied.size(); ++i) {
        auto point = grid_point(occupied.at(i));
        if (point.first < low_x || point.first > high_x || point.second < low_y || point.second > high_y) continue;
        size_t id = static_cast<size_t>(point.second - low_y) * width + static_cast<size_t>(point.first - low_x);
        eligible[id] = filled ? 1 : 0;
    }
    const size_t start_id = static_cast<size_t>(start.second - low_y) * width + static_cast<size_t>(start.first - low_x);
    if (!eligible[start_id]) throw std::runtime_error("Grid component start has the wrong occupancy kind");
    using Graph = boost::adjacency_list<boost::vecS, boost::vecS, boost::undirectedS>;
    Graph graph(width * height);
    for (size_t y = 0; y < height; ++y) {
        for (size_t x = 0; x < width; ++x) {
            size_t id = y * width + x;
            if (!eligible[id]) continue;
            if (x + 1 < width && eligible[id + 1]) boost::add_edge(id, id + 1, graph);
            if (y + 1 < height && eligible[id + width]) boost::add_edge(id, id + width, graph);
        }
    }
    std::vector<int> components(width * height);
    boost::connected_components(graph, components.data());
    A cells;
    for (size_t id = 0; id < eligible.size(); ++id) {
        if (!eligible[id] || components[id] != components[start_id]) continue;
        A point; point.append(V::number(low_x + static_cast<int64_t>(id % width)));
        point.append(V::number(low_y + static_cast<int64_t>(id / width))); cells.append(point.value());
    }
    D result; result.set("cells", cells.value()); return result.value();
}
