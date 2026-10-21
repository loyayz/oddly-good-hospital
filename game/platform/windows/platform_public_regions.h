// Included after platform_entry_order.h. Boost owns the complete component
// traversal; this adapter only projects the hospital's bounded integer cells.
namespace public_region_backend {
constexpr int SIDE = 96, LIMIT = SIDE * SIDE, COORDINATE_LIMIT = 100000;
struct Unsupported : std::runtime_error { using std::runtime_error::runtime_error; };
struct Point { int x, y; };
struct Rect { Point cell, size; };
struct Room { std::string id; std::vector<Point> cells; };
struct Source {
    std::vector<Point> plots, blocked;
    std::vector<Room> rooms;
    std::vector<Rect> obstacles;
};
D dictionary(const V& value) {
    if (type(&value.raw) != GDEXTENSION_VARIANT_TYPE_DICTIONARY) throw Unsupported("区域输入需要完整字典");
    return D(value);
}
A array(const V& value) {
    if (type(&value.raw) != GDEXTENSION_VARIANT_TYPE_ARRAY) throw Unsupported("区域输入需要完整数组");
    return A(value);
}
int integer(const V& value) {
    double number = 0;
    if (type(&value.raw) == GDEXTENSION_VARIANT_TYPE_INT) number = static_cast<double>(value.number());
    else if (type(&value.raw) == GDEXTENSION_VARIANT_TYPE_FLOAT)
        to_type[GDEXTENSION_VARIANT_TYPE_FLOAT](&number, const_cast<Raw*>(&value.raw));
    else throw Unsupported("特殊区域坐标沿完整脚本计算");
    if (!std::isfinite(number) || std::floor(number) != number || std::abs(number) > COORDINATE_LIMIT)
        throw Unsupported("分数或特殊区域坐标沿完整脚本计算");
    return static_cast<int>(number);
}
Point point(const V& value) {
    A parts = array(value);
    if (parts.size() != 2) throw Unsupported("区域坐标需要两个完整分量");
    return {integer(parts.at(0)), integer(parts.at(1))};
}
bool inside(const Point& point) { return point.x >= 0 && point.y >= 0 && point.x < SIDE && point.y < SIDE; }
void room_cell(Room& room, Point cell) {
    if (!inside(cell)) throw Unsupported("院区外区域格点沿完整脚本计算");
    room.cells.push_back(cell);
}
Source parse(const V& raw) {
    D input = dictionary(raw);
    A plots = array(input.get("plots")), blocked = array(input.get("blocked"));
    A rooms = array(input.get("rooms")), obstacles = array(input.get("obstacles"));
    Source source;
    for (int64_t i = 0; i < plots.size(); ++i) {
        Point plot = point(plots.at(i));
        if (plot.x < 0 || plot.y < 0 || plot.x > 2 || plot.y > 2)
            throw Unsupported("院区外地块沿完整脚本计算");
        source.plots.push_back(plot);
    }
    for (int64_t i = 0; i < blocked.size(); ++i) source.blocked.push_back(point(blocked.at(i)));
    for (int64_t i = 0; i < rooms.size(); ++i) {
        D record = dictionary(rooms.at(i));
        V raw_id = record.get("id");
        if (type(&raw_id.raw) != GDEXTENSION_VARIANT_TYPE_STRING)
            throw Unsupported("特殊房间身份沿完整脚本计算");
        Room room{raw_id.text(), {}};
        if (room.id.find('\0') != std::string::npos)
            throw Unsupported("含空字符的房间身份沿完整脚本计算");
        // An explicitly empty cells array overrides the rectangular shorthand,
        // just as BuildGeometry.cells does. Nil is distinct from absence.
        V raw_cells = record.get("cells");
        V raw_keys = record.keys(); A keys(raw_keys);
        bool explicit_cells = false;
        for (int64_t k = 0; k < keys.size(); ++k) {
            V key = keys.at(k);
            if (type(&key.raw) != GDEXTENSION_VARIANT_TYPE_STRING)
                throw Unsupported("特殊房间字段键沿完整脚本计算");
            if (key.text() == "cells") {
                explicit_cells = true; break;
            }
        }
        if (explicit_cells) {
            A cells = array(raw_cells);
            if (cells.size() > LIMIT) throw Unsupported("特殊房间格点集合沿完整脚本计算");
            for (int64_t j = 0; j < cells.size(); ++j) room_cell(room, point(cells.at(j)));
        } else {
            Point origin = point(record.get("origin")), size = point(record.get("size"));
            if (size.x < 0 || size.y < 0) throw Unsupported("特殊房间范围沿完整脚本计算");
            if (size.x && size.y) {
                if (!inside(origin) || size.x > SIDE - origin.x || size.y > SIDE - origin.y)
                    throw Unsupported("院区外房间范围沿完整脚本计算");
                for (int y = origin.y; y < origin.y + size.y; ++y)
                    for (int x = origin.x; x < origin.x + size.x; ++x) room.cells.push_back({x,y});
            }
        }
        source.rooms.push_back(std::move(room));
    }
    for (int64_t i = 0; i < obstacles.size(); ++i) {
        D record = dictionary(obstacles.at(i));
        source.obstacles.push_back({point(record.get("cell")),point(record.get("footprint"))});
    }
    return source;
}
struct Component {
    std::string room;
    int low_x, low_y, high_x, high_y;
    std::vector<int> ids;
};
}

V solve_public_region_components(const V& raw) {
    using namespace public_region_backend;
    if (!entry_i64_resize || !entry_i64_index || !construct[GDEXTENSION_VARIANT_TYPE_PACKED_INT64_ARRAY] ||
        !destruct[GDEXTENSION_VARIANT_TYPE_PACKED_INT64_ARRAY] || !from_type[GDEXTENSION_VARIANT_TYPE_PACKED_INT64_ARRAY])
        throw std::runtime_error("公共区域原生整数数组接口不可用");
    Source source;
    try { source = parse(raw); }
    catch (const Unsupported& error) {
        D fallback; GDExtensionBool ready = false;
        fallback.set("ready", V::typed(GDEXTENSION_VARIANT_TYPE_BOOL, &ready));
        fallback.set("reason", V::text(error.what())); return fallback.value();
    }
    // Validate the entire projection before constructing any returned objects.
    // Plots establish public space; later room records overwrite earlier ones.
    std::vector<int> zones(LIMIT, -1);
    std::vector<std::string> room_ids{std::string()};
    std::map<std::string,int> room_numbers{{std::string(),0}};
    for (const Point& plot : source.plots)
        for (int y = plot.y * 32; y < (plot.y + 1) * 32; ++y)
            for (int x = plot.x * 32; x < (plot.x + 1) * 32; ++x) zones[y * SIDE + x] = 0;
    for (const Room& room : source.rooms) {
        auto found = room_numbers.find(room.id);
        if (found == room_numbers.end()) {
            int number = static_cast<int>(room_ids.size());
            room_ids.push_back(room.id); found = room_numbers.emplace(room.id,number).first;
        }
        for (const Point& cell : room.cells) zones[cell.y * SIDE + cell.x] = found->second;
    }
    std::vector<uint8_t> free(LIMIT);
    for (int id = 0; id < LIMIT; ++id) free[id] = zones[id] >= 0;
    for (const Point& cell : source.blocked) if (inside(cell)) free[cell.y * SIDE + cell.x] = 0;
    for (const Rect& obstacle : source.obstacles) {
        // Outside obstacle portions erase nothing. Nonpositive extents retain
        // the original range loop's empty deletion rather than creating cells.
        if (obstacle.size.x <= 0 || obstacle.size.y <= 0) continue;
        const int left = std::max(0,obstacle.cell.x), right = std::min(SIDE,obstacle.cell.x + obstacle.size.x);
        const int top = std::max(0,obstacle.cell.y), bottom = std::min(SIDE,obstacle.cell.y + obstacle.size.y);
        for (int y = top; y < bottom; ++y)
            if (left < right) std::fill(free.begin() + y * SIDE + left,free.begin() + y * SIDE + right,uint8_t(0));
    }
    using Graph = boost::adjacency_list<boost::vecS,boost::vecS,boost::undirectedS>;
    Graph graph(LIMIT);
    for (int id = 0; id < LIMIT; ++id) {
        if (!free[id]) continue;
        if (id % SIDE + 1 < SIDE && free[id + 1] && zones[id] == zones[id + 1]) boost::add_edge(id,id + 1,graph);
        if (id + SIDE < LIMIT && free[id + SIDE] && zones[id] == zones[id + SIDE]) boost::add_edge(id,id + SIDE,graph);
    }
    std::vector<int> labels(LIMIT), positions(LIMIT,-1);
    boost::connected_components(graph,labels.data());
    std::vector<Component> components;
    for (int id = 0; id < LIMIT; ++id) {
        if (!free[id]) continue;
        const int x = id % SIDE, y = id / SIDE, label = labels[id];
        if (positions[label] < 0) {
            positions[label] = static_cast<int>(components.size());
            components.push_back({room_ids[zones[id]],x,y,x,y,{}});
        }
        Component& component = components[positions[label]];
        component.low_x = std::min(component.low_x,x); component.high_x = std::max(component.high_x,x);
        component.low_y = std::min(component.low_y,y); component.high_y = std::max(component.high_y,y);
        component.ids.push_back(id);
    }
    // Component order is minimum y/x anchor; members are canonical row-major
    // XY pairs. Boost's DFS visit order is neither exported nor hashed.
    A records;
    for (const Component& component : components) {
        EntryInt64s cells(static_cast<int64_t>(component.ids.size()) * 2);
        int64_t* coordinates = cells.mutable_data();
        for (size_t i = 0; i < component.ids.size(); ++i) {
            coordinates[i * 2] = component.ids[i] % SIDE;
            coordinates[i * 2 + 1] = component.ids[i] / SIDE;
        }
        A bounds;
        for (int value : {component.low_x,component.low_y,component.high_x - component.low_x + 1,component.high_y - component.low_y + 1})
            bounds.append(V::number(value));
        D record; record.set("room_id",V::text(component.room));
        record.set("cells",cells.value()); record.set("bounds",bounds.value()); records.append(record.value());
    }
    D result; GDExtensionBool ready = true;
    result.set("ready",V::typed(GDEXTENSION_VARIANT_TYPE_BOOL,&ready)); result.set("components",records.value()); return result.value();
}
