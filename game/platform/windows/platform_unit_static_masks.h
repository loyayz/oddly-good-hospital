// A bounded adapter for the business-owned unit-body integer geometry. Godot
// still owns AStar2D and path search; Boost.Geometry owns interval containment.
// This only assembles masks from already quoted doors and immutable sources.
GDExtensionPtrBuiltInMethod unit_mask_bytes_resize;
GDExtensionInterfacePackedByteArrayOperatorIndex unit_mask_byte_index;

namespace unit_static_masks {
constexpr int SIDE = 96, LIMIT = SIDE * SIDE, COORDINATE_LIMIT = 100000;
struct Unsupported : std::runtime_error { using std::runtime_error::runtime_error; };
struct Point { int x, y; };
struct Rect { int x, y, width, height; };
struct Wall { std::string room; char axis; int line, low, high; };
struct Door { std::string room; char axis; Rect original, opening; bool ok; };
struct Scene {
    bool height_ok;
    std::vector<Point> plots, blocked;
    std::vector<Rect> facilities, connectors;
    std::vector<Wall> walls;
    std::vector<Door> doors;
};

D dictionary(const V& value) {
    if (type(&value.raw) != GDEXTENSION_VARIANT_TYPE_DICTIONARY) throw Unsupported("静态单格输入需要完整字典");
    return D(value);
}
A array(const V& value) {
    if (type(&value.raw) != GDEXTENSION_VARIANT_TYPE_ARRAY) throw Unsupported("静态单格输入需要完整数组");
    return A(value);
}
std::string text(const V& value) {
    if (type(&value.raw) != GDEXTENSION_VARIANT_TYPE_STRING) throw Unsupported("静态单格输入需要文字身份");
    return value.text();
}
int integer(const V& value, bool positive = false) {
    double number = 0;
    if (type(&value.raw) == GDEXTENSION_VARIANT_TYPE_INT) number = static_cast<double>(value.number());
    else if (type(&value.raw) == GDEXTENSION_VARIANT_TYPE_FLOAT)
        to_type[GDEXTENSION_VARIANT_TYPE_FLOAT](&number, const_cast<Raw*>(&value.raw));
    else throw Unsupported("静态单格坐标需要整数数值");
    if (!std::isfinite(number) || std::floor(number) != number || std::abs(number) > COORDINATE_LIMIT || (positive && number <= 0))
        throw Unsupported("特殊或非整数几何沿原完整通行谓词");
    return static_cast<int>(number);
}
bool boolean(const V& value) {
    if (type(&value.raw) != GDEXTENSION_VARIANT_TYPE_BOOL) throw Unsupported("静态单格输入需要明确布尔条件");
    GDExtensionBool result = false;
    to_type[GDEXTENSION_VARIANT_TYPE_BOOL](&result, const_cast<Raw*>(&value.raw));
    return result;
}
Point point(const V& value, bool extent = false) {
    A fields = array(value);
    if (fields.size() != 2) throw Unsupported("静态单格坐标需要两个完整分量");
    return {integer(fields.at(0), extent), integer(fields.at(1), extent)};
}
Rect rectangle(const V& value) {
    if (type(&value.raw) != GDEXTENSION_VARIANT_TYPE_RECT2) throw Unsupported("门几何需要原已报价Rect2");
    // The build pins single precision and Rect2's four float ABI. Integer
    // inputs <=100000 and their sums are exact in this float32 domain.
    struct RawRect { float x, y, width, height; } raw;
    to_type[GDEXTENSION_VARIANT_TYPE_RECT2](&raw, const_cast<Raw*>(&value.raw));
    auto coordinate = [](float number) {
        if (!std::isfinite(number) || std::floor(number) != number || std::abs(number) > COORDINATE_LIMIT)
            throw Unsupported("分数或特殊门矩形沿原完整通行谓词");
        return static_cast<int>(number);
    };
    Rect result{coordinate(raw.x), coordinate(raw.y), coordinate(raw.width), coordinate(raw.height)};
    if (result.width < 0 || result.height < 0) throw Unsupported("特殊门矩形沿原完整通行谓词");
    return result;
}
char axis(const V& value) {
    std::string result = text(value);
    if (result != "x" && result != "y") throw Unsupported("静态单格墙轴无效");
    return result[0];
}
void rooms(Scene& scene, const D& records) {
    A ids(records.keys());
    for (int64_t i = 0; i < ids.size(); ++i) {
        std::string id = text(ids.at(i));
        D room = dictionary(records.get(ids.at(i)));
        Point origin = point(room.get("origin")), size = point(room.get("size"), true);
        V raw_edges = room.get("wall_edges");
        if (!raw_edges.nil()) {
            A edges = array(raw_edges);
            for (int64_t j = 0; j < edges.size(); ++j) {
                D edge = dictionary(edges.at(j));
                Wall wall{id, axis(edge.get("axis")), integer(edge.get("line")), integer(edge.get("low")), integer(edge.get("high"))};
                if (wall.low >= wall.high) throw Unsupported("退化墙段沿原完整通行谓词");
                scene.walls.push_back(std::move(wall));
            }
        } else {
            scene.walls.push_back({id, 'x', origin.y, origin.x, origin.x + size.x});
            scene.walls.push_back({id, 'x', origin.y + size.y, origin.x, origin.x + size.x});
            scene.walls.push_back({id, 'y', origin.x, origin.y, origin.y + size.y});
            scene.walls.push_back({id, 'y', origin.x + size.x, origin.y, origin.y + size.y});
        }
    }
}
void obstacles(std::vector<Rect>& target, const D& records) {
    A ids(records.keys());
    for (int64_t i = 0; i < ids.size(); ++i) {
        text(ids.at(i));
        D record = dictionary(records.get(ids.at(i)));
        Point origin = point(record.get("cell")), size = point(record.get("footprint"), true);
        target.push_back({origin.x, origin.y, size.x, size.y});
    }
}
Scene parse(const V& raw_options) {
    D options = dictionary(raw_options), source = dictionary(options.get("source"));
    D layout = dictionary(source.get("layout"));
    Scene scene;
    scene.height_ok = boolean(options.get("height_ok"));
    V height = source.get("height");
    double actual_height = 0;
    if (type(&height.raw) == GDEXTENSION_VARIANT_TYPE_FLOAT)
        to_type[GDEXTENSION_VARIANT_TYPE_FLOAT](&actual_height, &height.raw);
    else if (type(&height.raw) == GDEXTENSION_VARIANT_TYPE_INT) actual_height = static_cast<double>(height.number());
    else throw Unsupported("特殊净高沿原完整通行谓词");
    if (!std::isfinite(actual_height)) throw Unsupported("特殊净高沿原完整通行谓词");
    A plots = array(layout.get("plots")), blocked = array(layout.get("blocked"));
    for (int64_t i = 0; i < plots.size(); ++i) {
        Point plot = point(plots.at(i));
        if (plot.x < 0 || plot.y < 0 || plot.x > 2 || plot.y > 2) throw Unsupported("院区外地块沿原完整通行谓词");
        scene.plots.push_back(plot);
    }
    for (int64_t i = 0; i < blocked.size(); ++i) scene.blocked.push_back(point(blocked.at(i)));
    rooms(scene, dictionary(source.get("rooms")));
    obstacles(scene.facilities, dictionary(source.get("facilities")));
    obstacles(scene.connectors, dictionary(source.get("connectors")));
    A raw_doors = array(layout.get("doors")), quoted_doors = array(options.get("doors"));
    if (raw_doors.size() != quoted_doors.size()) throw Unsupported("门源与已报价几何不对应");
    for (int64_t i = 0; i < raw_doors.size(); ++i) {
        D original = dictionary(raw_doors.at(i)), quoted = dictionary(quoted_doors.at(i));
        Point cell = point(original.get("cell"));
        int span = integer(original.get("span"), true);
        char direction = axis(original.get("axis"));
        Door door{text(original.get("room_id")), direction, rectangle(quoted.get("original")), rectangle(quoted.get("opening")), boolean(quoted.get("ok"))};
        if (text(quoted.get("room_id")) != door.room || axis(quoted.get("axis")) != direction ||
            door.original.x != cell.x || door.original.y != cell.y || door.original.width != (direction == 'x' ? span : 1) || door.original.height != (direction == 'x' ? 1 : span))
            throw Unsupported("门源与已报价矩形不对应");
        if (!door.ok && text(quoted.get("reason")).empty())
            throw Unsupported("空失败原因沿原完整通行谓词");
        if (door.ok && (door.opening.x != cell.x || door.opening.y != cell.y || door.opening.width < 1 || door.opening.height < 1 ||
            (direction == 'x' ? door.opening.height != 1 : door.opening.width != 1)))
            throw Unsupported("特殊已报价门沿原完整通行谓词");
        scene.doors.push_back(std::move(door));
    }
    return scene;
}
void fill(uint8_t* target, const Rect& rect, uint8_t value) {
    const int left = std::max(0, rect.x), right = std::min(SIDE, rect.x + rect.width);
    const int top = std::max(0, rect.y), bottom = std::min(SIDE, rect.y + rect.height);
    if (left >= right || top >= bottom) return;
    for (int y = top; y < bottom; ++y) std::fill(target + y * SIDE + left, target + y * SIDE + right, value);
}
struct Bytes {
    alignas(8) unsigned char raw[OGH_PACKED_BYTE_ARRAY_SIZE];
    explicit Bytes(int64_t size) {
        construct[GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY](raw, nullptr);
        const void* args[] = {&size}; int64_t error = 0;
        unit_mask_bytes_resize(raw, args, &error, 1);
        if (error) { destruct[GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY](raw); throw std::runtime_error("静态单格掩码内存不足"); }
        if (size) std::fill(data(), data() + size, 0);
    }
    ~Bytes() { destruct[GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY](raw); }
    uint8_t* data() { return unit_mask_byte_index(raw, 0); }
    V value() const { return V::typed(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, raw); }
};
}

V build_unit_static_masks(const V& raw_options) {
    using namespace unit_static_masks;
    if (!to_type[GDEXTENSION_VARIANT_TYPE_RECT2] || !unit_mask_bytes_resize || !unit_mask_byte_index || !grid_distance_ints_resize || !grid_distance_int_index)
        throw std::runtime_error("静态单格掩码原生数组接口不可用");
    Scene scene;
    try { scene = parse(raw_options); }
    catch (const Unsupported& error) {
        D fallback; GDExtensionBool ready = false;
        fallback.set("ready", V::typed(GDEXTENSION_VARIANT_TYPE_BOOL, &ready));
        fallback.set("reason", V::text(error.what())); return fallback.value();
    }
    // Parse and validate the complete input before allocating output or touching
    // any engine graph. The caller continues the original builder on fallback.
    Bytes present(LIMIT), enabled(LIMIT), edges(LIMIT);
    auto* points = present.data(); auto* available = enabled.data(); auto* links = edges.data();
    for (const Point& plot : scene.plots) fill(points, {plot.x * 32, plot.y * 32, 32, 32}, 1);
    if (scene.height_ok) std::copy(points, points + LIMIT, available);
    std::vector<uint8_t> openings(LIMIT, 0);
    for (const Door& door : scene.doors) if (door.ok) fill(openings.data(), door.opening, 1);
    for (const Point& point : scene.blocked)
        if (point.x >= 0 && point.x < SIDE && point.y >= 0 && point.y < SIDE && !openings[point.y * SIDE + point.x])
            available[point.y * SIDE + point.x] = 0;
    for (const Door& door : scene.doors) if (!door.ok) fill(available, door.original, 0);
    for (const Rect& rect : scene.facilities) fill(available, rect, 0);
    for (const Rect& rect : scene.connectors) fill(available, rect, 0);
    for (int id = 0; id < LIMIT; ++id) {
        if (!available[id]) continue;
        if (id % SIDE + 1 < SIDE && available[id + 1]) { links[id] |= 4; links[id + 1] |= 2; }
        if (id + SIDE < LIMIT && available[id + SIDE]) { links[id] |= 8; links[id + SIDE] |= 1; }
    }
    // Keep every room's independent wall: another room's opening cannot remove
    // it. A single matching approved opening must cover the entire cross-cut;
    // combining two partial door openings would change the original predicate.
    using OpeningKey = std::tuple<std::string, char, int>;
    std::map<OpeningKey, std::vector<SpatialBox>> by_wall;
    for (const Door& door : scene.doors) {
        if (!door.ok) continue;
        const bool horizontal = door.axis == 'x';
        const int line = horizontal ? door.opening.y : door.opening.x;
        const int low = horizontal ? door.opening.x : door.opening.y;
        const int high = low + (horizontal ? door.opening.width : door.opening.height);
        by_wall[{door.room, door.axis, line}].push_back({{double(low), 0.0}, {double(high), 1.0}});
    }
    for (const Wall& wall : scene.walls) {
        if (wall.line <= 0 || wall.line >= SIDE) continue;
        const auto found = by_wall.find({wall.room, wall.axis, wall.line});
        for (int along = std::max(0, wall.low); along < std::min(SIDE, wall.high); ++along) {
            const SpatialBox cut{{double(along), 0.0}, {double(along + 1), 1.0}};
            bool open = found != by_wall.end() && std::any_of(found->second.begin(), found->second.end(),
                [&](const SpatialBox& opening) { return bg::covered_by(cut, opening); });
            if (open) continue;
            const int from = wall.axis == 'x' ? (wall.line - 1) * SIDE + along : along * SIDE + wall.line - 1;
            const int to = from + (wall.axis == 'x' ? SIDE : 1);
            links[from] &= uint8_t(wall.axis == 'x' ? ~8 : ~4);
            links[to] &= uint8_t(wall.axis == 'x' ? ~1 : ~2);
        }
    }
    int count = static_cast<int>(std::count(points, points + LIMIT, uint8_t(1)));
    GridDistanceInts ids(count);
    int index = 0;
    for (int id = 0; id < LIMIT; ++id) if (points[id]) ids.data()[index++] = id;
    D result; GDExtensionBool ready = true;
    result.set("ready", V::typed(GDEXTENSION_VARIANT_TYPE_BOOL, &ready));
    result.set("present", present.value()); result.set("enabled", enabled.value()); result.set("edges", edges.value()); result.set("ids", ids.value());
    return result.value();
}

void unit_static_masks_initialize(GDExtensionInterfaceGetProcAddress api) {
    auto method = reinterpret_cast<GDExtensionInterfaceVariantGetPtrBuiltinMethod>(api("variant_get_ptr_builtin_method"));
    Builtin resize; new_name(&resize, "resize");
    unit_mask_bytes_resize = method(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, &resize, OGH_BYTES_RESIZE_HASH);
    unit_mask_byte_index = reinterpret_cast<GDExtensionInterfacePackedByteArrayOperatorIndex>(api("packed_byte_array_operator_index"));
    destruct[GDEXTENSION_VARIANT_TYPE_STRING_NAME](&resize);
}
