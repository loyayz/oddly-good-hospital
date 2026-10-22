// Included inside the bridge namespace after the shared Variant adapters.
// Boost owns the spatial tree. The adapter only maps floor/identity/rectangles.
namespace bg = boost::geometry;
namespace bgi = boost::geometry::index;
using SpatialPoint = bg::model::d2::point_xy<double>;
using SpatialBox = bg::model::box<SpatialPoint>;
using SpatialValue = std::pair<SpatialBox, std::string>;
struct SpatialInstance {
    using Tree = bgi::rtree<SpatialValue, bgi::quadratic<16>>;
    std::map<int64_t, Tree> floors;
    std::map<std::string, std::pair<int64_t, SpatialBox>> records;
    void remove(const std::string& id) {
        auto found = records.find(id);
        if (found == records.end()) return;
        auto floor = floors.find(found->second.first);
        floor->second.remove({found->second.second, id});
        if (floor->second.empty()) floors.erase(floor);
        records.erase(found);
    }
};
Builtin spatial_class;
double spatial_number(const V& value) {
    double number;
    if (type(&value.raw) == GDEXTENSION_VARIANT_TYPE_INT) number = static_cast<double>(value.number());
    else if (type(&value.raw) == GDEXTENSION_VARIANT_TYPE_FLOAT)
        to_type[GDEXTENSION_VARIANT_TYPE_FLOAT](&number, const_cast<Raw*>(&value.raw));
    else throw std::runtime_error("Spatial coordinates must be numbers");
    if (!std::isfinite(number)) throw std::runtime_error("Spatial coordinates must be finite");
    return number;
}
SpatialBox spatial_box(const V& raw) {
    A values(raw);
    if (values.size() != 4) throw std::runtime_error("Spatial rectangle requires four coordinates");
    double x = spatial_number(values.at(0)), y = spatial_number(values.at(1));
    double width = spatial_number(values.at(2)), height = spatial_number(values.at(3));
    if (width < 0 || height < 0) throw std::runtime_error("Spatial rectangle has negative size");
    return {{x, y}, {x + width, y + height}};
}
enum class SpatialMethod { CLEAR, UPDATE, REMOVE, QUERY, QUERY_MANY };
struct SpatialMethodInfo { const char* name; SpatialMethod method; std::vector<GDExtensionVariantType> arguments; };
SpatialMethodInfo spatial_methods[] = {
    {"clear", SpatialMethod::CLEAR, {}},
    {"update", SpatialMethod::UPDATE, {GDEXTENSION_VARIANT_TYPE_STRING, GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_ARRAY}},
    {"remove", SpatialMethod::REMOVE, {GDEXTENSION_VARIANT_TYPE_STRING}},
    {"query", SpatialMethod::QUERY, {GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_ARRAY}},
    {"query_many", SpatialMethod::QUERY_MANY, {GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_ARRAY}}
};
V spatial_invoke(SpatialMethod method, SpatialInstance& instance, const std::vector<V>& args) {
    try {
        D output;
        if (method == SpatialMethod::CLEAR) { instance.floors.clear(); instance.records.clear(); }
        else if (method == SpatialMethod::REMOVE) instance.remove(args[0].text());
        else if (method == SpatialMethod::UPDATE) {
            auto id = args[0].text(); auto floor = args[1].number(); auto box = spatial_box(args[2]);
            instance.remove(id);
            instance.floors[floor].insert({box, id}); instance.records.emplace(id, std::make_pair(floor, box));
        } else {
            A ids;
            std::vector<SpatialBox> rectangles;
            if (method == SpatialMethod::QUERY_MANY) {
                A inputs(args[1]);
                rectangles.reserve(inputs.size());
                for (int64_t i = 0; i < inputs.size(); ++i) {
                    V rectangle = inputs.at(i);
                    if (type(&rectangle.raw) != GDEXTENSION_VARIANT_TYPE_ARRAY)
                        throw std::runtime_error("Spatial rectangle must be an array");
                    auto box = spatial_box(rectangle);
                    if (!std::isfinite(bg::get<bg::max_corner, 0>(box)) || !std::isfinite(bg::get<bg::max_corner, 1>(box)))
                        throw std::runtime_error("Spatial rectangle endpoint must be finite");
                    rectangles.push_back(box);
                }
            }
            auto floor = instance.floors.find(args[0].number());
            if (floor != instance.floors.end()) {
                if (method == SpatialMethod::QUERY) {
                    auto predicate = bgi::intersects(spatial_box(args[1]));
                    for (auto it = floor->second.qbegin(predicate); it != floor->second.qend(); ++it) ids.append(V::text(it->second));
                } else {
                    std::set<std::string> candidates;
                    for (const auto& box : rectangles) {
                        auto predicate = bgi::intersects(box);
                        for (auto it = floor->second.qbegin(predicate); it != floor->second.qend(); ++it) candidates.insert(it->second);
                    }
                    for (const auto& id : candidates) ids.append(V::text(id));
                }
            }
            output.set("ids", ids.value());
        }
        return output.value();
    } catch (const std::exception& error) { return failure(error.what()); }
}
void spatial_call(void* userdata, GDExtensionClassInstancePtr instance, const GDExtensionConstVariantPtr* args,
                  GDExtensionInt count, GDExtensionVariantPtr returned, GDExtensionCallError* error) {
    auto& method = *static_cast<SpatialMethodInfo*>(userdata); error->error = GDEXTENSION_CALL_OK;
    if (count != static_cast<int64_t>(method.arguments.size())) { error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT; return; }
    std::vector<V> values;
    for (int64_t i = 0; i < count; ++i) {
        if (type(args[i]) != method.arguments[i]) { error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT; error->argument = static_cast<int32_t>(i); error->expected = method.arguments[i]; return; }
        values.emplace_back(args[i]);
    }
    V result = spatial_invoke(method.method, *static_cast<SpatialInstance*>(instance), values);
    destroy(returned); new_copy(returned, &result.raw);
}
void spatial_ptrcall(void* userdata, GDExtensionClassInstancePtr instance, const GDExtensionConstTypePtr* args, GDExtensionTypePtr returned) {
    auto& method = *static_cast<SpatialMethodInfo*>(userdata); std::vector<V> values;
    for (size_t i = 0; i < method.arguments.size(); ++i) values.push_back(V::typed(method.arguments[i], args[i]));
    V result = spatial_invoke(method.method, *static_cast<SpatialInstance*>(instance), values);
    destruct[GDEXTENSION_VARIANT_TYPE_DICTIONARY](returned); to_type[GDEXTENSION_VARIANT_TYPE_DICTIONARY](returned, &result.raw);
}
GDExtensionObjectPtr spatial_create(void*, GDExtensionBool notify) {
    auto* instance = new SpatialInstance; auto object = construct_object(&ref_class);
    set_instance(object, &spatial_class, instance);
    if (notify) {
        int64_t postinitialize = 0; GDExtensionBool reversed = 0;
        const void* args[] = {&postinitialize, &reversed}; object_ptrcall(notification, object, args, nullptr);
    }
    return object;
}
void spatial_free(void*, GDExtensionClassInstancePtr instance) { delete static_cast<SpatialInstance*>(instance); }
void spatial_register(GDExtensionInterfaceGetProcAddress api) {
    auto get_dtor = reinterpret_cast<GDExtensionInterfaceVariantGetPtrDestructor>(api("variant_get_ptr_destructor"));
    Builtin empty, hint; new_name(&empty, ""); new_string(&hint, ""); new_name(&spatial_class, "PlatformSpatialIndex");
    GDExtensionClassCreationInfo6 info{}; info.is_exposed = 1; info.create_instance_func = spatial_create; info.free_instance_func = spatial_free;
    register_class(library, &spatial_class, &ref_class, &info);
    GDExtensionPropertyInfo output{}; output.type = GDEXTENSION_VARIANT_TYPE_DICTIONARY;
    output.name = &empty; output.class_name = &empty; output.hint_string = &hint; output.usage = 6;
    for (auto& entry : spatial_methods) {
        Builtin name; new_name(&name, entry.name);
        std::vector<GDExtensionPropertyInfo> args(entry.arguments.size(), output);
        std::vector<Builtin> names(entry.arguments.size());
        std::vector<GDExtensionClassMethodArgumentMetadata> metadata(entry.arguments.size(), GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE);
        bool query = entry.method == SpatialMethod::QUERY || entry.method == SpatialMethod::QUERY_MANY;
        const char* argument_names[] = {query ? "floor_id" : "id", entry.method == SpatialMethod::QUERY_MANY ? "rectangles" : query ? "rectangle" : "floor_id", "rectangle"};
        for (size_t i = 0; i < args.size(); ++i) { new_name(&names[i], argument_names[i]); args[i].name = &names[i]; args[i].type = entry.arguments[i]; }
        GDExtensionClassMethodInfo method{}; method.name = &name; method.method_userdata = &entry;
        method.call_func = spatial_call; method.ptrcall_func = spatial_ptrcall; method.method_flags = GDEXTENSION_METHOD_FLAG_NORMAL;
        method.has_return_value = 1; method.return_value_info = &output; method.argument_count = static_cast<uint32_t>(args.size());
        method.arguments_info = args.data(); method.arguments_metadata = metadata.data(); register_method(library, &spatial_class, &method);
        for (auto& arg : names) get_dtor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&arg);
        get_dtor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&name);
    }
    destruct[GDEXTENSION_VARIANT_TYPE_STRING](&hint); get_dtor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&empty);
}
