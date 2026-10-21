// Pure entry-bound keys; no world, candidate selection or occupancy is owned
// here. The original GDScript solver handles noncompact/int64 fallback inputs.
GDExtensionPtrBuiltInMethod entry_i32_size, entry_i64_size, entry_i64_resize;
GDExtensionInterfacePackedInt32ArrayOperatorIndexConst entry_i32_index;
GDExtensionInterfacePackedInt64ArrayOperatorIndexConst entry_i64_const_index;
GDExtensionInterfacePackedInt64ArrayOperatorIndex entry_i64_index;

struct EntryInt32s {
    alignas(8) unsigned char raw[OGH_PACKED_INT32_ARRAY_SIZE];
    explicit EntryInt32s(const V& value) { to_type[GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY](raw, const_cast<Raw*>(&value.raw)); }
    ~EntryInt32s() { destruct[GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY](raw); }
    int64_t size() const { int64_t count; entry_i32_size(const_cast<unsigned char*>(raw), nullptr, &count, 0); return count; }
    const int32_t* data() const { return entry_i32_index(raw, 0); }
};
struct EntryInt64s {
    alignas(8) unsigned char raw[OGH_PACKED_INT64_ARRAY_SIZE];
    explicit EntryInt64s(const V& value) { to_type[GDEXTENSION_VARIANT_TYPE_PACKED_INT64_ARRAY](raw, const_cast<Raw*>(&value.raw)); }
    explicit EntryInt64s(int64_t count) {
        construct[GDEXTENSION_VARIANT_TYPE_PACKED_INT64_ARRAY](raw, nullptr);
        const void* arguments[] = {&count}; int64_t error = 0;
        entry_i64_resize(raw, arguments, &error, 1);
        if (error) { destruct[GDEXTENSION_VARIANT_TYPE_PACKED_INT64_ARRAY](raw); throw std::runtime_error("入口顺序数组所需内存不足"); }
    }
    ~EntryInt64s() { destruct[GDEXTENSION_VARIANT_TYPE_PACKED_INT64_ARRAY](raw); }
    int64_t size() const { int64_t count; entry_i64_size(const_cast<unsigned char*>(raw), nullptr, &count, 0); return count; }
    const int64_t* data() const { return entry_i64_const_index(raw, 0); }
    int64_t* mutable_data() { return entry_i64_index(raw, 0); }
    V value() const { return V::typed(GDEXTENSION_VARIANT_TYPE_PACKED_INT64_ARRAY, raw); }
};

V solve_entry_order(const V& raw_cells, const V& raw_config) {
    constexpr int64_t SIDE = 96, CELLS = SIDE * SIDE, MAX_TICK = 9223372036854775807LL;
    constexpr int64_t SORT_LIMIT = (MAX_TICK - (CELLS - 1)) / CELLS;
    D result; GDExtensionBool ready = false;
    result.set("ready", V::typed(GDEXTENSION_VARIANT_TYPE_BOOL, &ready));
    if (!entry_i32_size || !entry_i64_size || !entry_i64_resize || !entry_i32_index || !entry_i64_const_index || !entry_i64_index)
        return result.value();
    D config(raw_config);
    V raw_start = config.get("start"), raw_walking = config.get("walking"), raw_sources = config.get("sources"),
        raw_excluded = config.get("excluded"), raw_stub = config.get("stub_ticks"), raw_maximum = config.get("maximum_ticks");
    if (type(&raw_start.raw) != GDEXTENSION_VARIANT_TYPE_ARRAY ||
        type(&raw_walking.raw) != GDEXTENSION_VARIANT_TYPE_PACKED_INT64_ARRAY ||
        type(&raw_sources.raw) != GDEXTENSION_VARIANT_TYPE_PACKED_INT64_ARRAY ||
        type(&raw_excluded.raw) != GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY ||
        type(&raw_stub.raw) != GDEXTENSION_VARIANT_TYPE_INT || type(&raw_maximum.raw) != GDEXTENSION_VARIANT_TYPE_INT)
        return result.value();
    A start(raw_start);
    if (start.size() != 2) return result.value();
    V raw_x = start.at(0), raw_y = start.at(1);
    if (type(&raw_x.raw) != GDEXTENSION_VARIANT_TYPE_INT || type(&raw_y.raw) != GDEXTENSION_VARIANT_TYPE_INT) return result.value();
    const int64_t x = raw_x.number(), y = raw_y.number(), stub = raw_stub.number(), maximum = raw_maximum.number();
    if (x < 0 || x >= SIDE || y < 0 || y >= SIDE || stub < 0) return result.value();
    EntryInt32s cells(raw_cells), excluded(raw_excluded);
    EntryInt64s walking(raw_walking), sources(raw_sources);
    if (walking.size() != (SIDE - 1) * 2 + 1 || sources.size() % 3 != 0) return result.value();
    const int64_t cell_count = cells.size(), source_count = sources.size(), excluded_count = excluded.size();
    const int64_t* distances = walking.data();
    const int64_t* arrivals = source_count ? sources.data() : nullptr;
    for (int64_t index = 0; index < source_count; index += 3)
        if (arrivals[index] < 0 || arrivals[index] >= SIDE || arrivals[index + 1] < 0 || arrivals[index + 1] >= SIDE || arrivals[index + 2] < 0)
            return result.value();
    std::vector<uint8_t> skipped(static_cast<size_t>(CELLS), 0);
    if (excluded_count) {
        const int32_t* ids = excluded.data();
        for (int64_t index = 0; index < excluded_count; ++index)
            if (ids[index] >= 0 && ids[index] < CELLS) skipped[ids[index]] = 1;
    }
    std::vector<int64_t> keys;
    keys.reserve(static_cast<size_t>(cell_count));
    const int32_t* ids = cell_count ? cells.data() : nullptr;
    for (int64_t index = 0; index < cell_count; ++index) {
        const int64_t id = ids[index];
        if (id < 0 || id >= CELLS) return result.value();
        if (skipped[id]) continue;
        const int64_t px = id % SIDE, py = id / SIDE;
        int64_t lower = MAX_TICK;
        if (!source_count) {
            const int64_t distance = (x > px ? x - px : px - x) + (y > py ? y - py : py - y);
            const int64_t ticks = distances[distance];
            if (ticks < 0 || stub > MAX_TICK - ticks) return result.value();
            lower = stub + ticks;
        } else {
            for (int64_t source = 0; source < source_count; source += 3) {
                const int64_t sx = arrivals[source], sy = arrivals[source + 1];
                const int64_t distance = (sx > px ? sx - px : px - sx) + (sy > py ? sy - py : py - sy);
                const int64_t ticks = distances[distance];
                if (ticks < 0 || arrivals[source + 2] > MAX_TICK - ticks) return result.value();
                lower = std::min(lower, arrivals[source + 2] + ticks);
            }
        }
        if (lower > maximum) continue;
        if (lower < 0 || lower > SORT_LIMIT) return result.value();
        keys.push_back(lower * CELLS + id);
    }
    // Standard-library numeric ordering is exactly the existing lower/y/x key.
    std::sort(keys.begin(), keys.end());
    EntryInt64s packed(static_cast<int64_t>(keys.size()));
    if (!keys.empty()) std::copy(keys.begin(), keys.end(), packed.mutable_data());
    ready = true;
    result.set("ready", V::typed(GDEXTENSION_VARIANT_TYPE_BOOL, &ready));
    result.set("compact", V::typed(GDEXTENSION_VARIANT_TYPE_BOOL, &ready));
    result.set("packed", packed.value()); A fallback; result.set("fallback", fallback.value());
    return result.value();
}

void entry_order_initialize(GDExtensionInterfaceGetProcAddress api) {
    auto method = reinterpret_cast<GDExtensionInterfaceVariantGetPtrBuiltinMethod>(api("variant_get_ptr_builtin_method"));
    Builtin size, resize; new_name(&size, "size"); new_name(&resize, "resize");
    entry_i32_size = method(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, &size, OGH_ARRAY_SIZE_HASH);
    entry_i64_size = method(GDEXTENSION_VARIANT_TYPE_PACKED_INT64_ARRAY, &size, OGH_ARRAY_SIZE_HASH);
    entry_i64_resize = method(GDEXTENSION_VARIANT_TYPE_PACKED_INT64_ARRAY, &resize, OGH_BYTES_RESIZE_HASH);
    entry_i32_index = reinterpret_cast<GDExtensionInterfacePackedInt32ArrayOperatorIndexConst>(api("packed_int32_array_operator_index_const"));
    entry_i64_const_index = reinterpret_cast<GDExtensionInterfacePackedInt64ArrayOperatorIndexConst>(api("packed_int64_array_operator_index_const"));
    entry_i64_index = reinterpret_cast<GDExtensionInterfacePackedInt64ArrayOperatorIndex>(api("packed_int64_array_operator_index"));
    destruct[GDEXTENSION_VARIANT_TYPE_STRING_NAME](&size); destruct[GDEXTENSION_VARIANT_TYPE_STRING_NAME](&resize);
}
