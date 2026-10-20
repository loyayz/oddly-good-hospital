// Include <queue> globally, then include this file after V/A/D in the native
// bridge's anonymous namespace. Queue order is integer tick, then Unicode ID.
struct RouteQueueItem {
    int64_t tick;
    std::string id;
    int64_t sequence;
};
struct RouteQueueLater {
    bool operator()(const RouteQueueItem& first, const RouteQueueItem& second) const {
        return first.tick != second.tick ? first.tick > second.tick : first.id > second.id;
    }
};
struct RouteQueueInstance {
    std::priority_queue<RouteQueueItem, std::vector<RouteQueueItem>, RouteQueueLater> values;
};
Builtin route_queue_class;
enum RouteQueueOperation { ROUTE_QUEUE_PUSH, ROUTE_QUEUE_POP, ROUTE_QUEUE_SIZE };
struct RouteQueueMethod {
    const char* name;
    RouteQueueOperation operation;
    GDExtensionVariantType output;
    std::vector<GDExtensionVariantType> arguments;
};
RouteQueueMethod route_queue_methods[] = {
    {"push", ROUTE_QUEUE_PUSH, GDEXTENSION_VARIANT_TYPE_DICTIONARY, {GDEXTENSION_VARIANT_TYPE_DICTIONARY}},
    {"pop", ROUTE_QUEUE_POP, GDEXTENSION_VARIANT_TYPE_DICTIONARY, {}},
    {"size", ROUTE_QUEUE_SIZE, GDEXTENSION_VARIANT_TYPE_INT, {}}
};

V route_queue_invoke(RouteQueueOperation operation, const std::vector<V>& arguments, GDExtensionClassInstancePtr instance) {
    auto& queue = static_cast<RouteQueueInstance*>(instance)->values;
    if (operation == ROUTE_QUEUE_SIZE) return V::number(static_cast<int64_t>(queue.size()));
    D result;
    if (operation == ROUTE_QUEUE_PUSH) {
        D item(arguments[0]);
        V id = item.get("id"), tick = item.get("tick");
        if (type(&id.raw) != GDEXTENSION_VARIANT_TYPE_STRING || type(&tick.raw) != GDEXTENSION_VARIANT_TYPE_INT)
            throw std::runtime_error("路线队列需要字符串身份和整数时间");
        V sequence = item.get("sequence");
        queue.push({tick.number(), id.text(), type(&sequence.raw) == GDEXTENSION_VARIANT_TYPE_INT ? sequence.number() : -1});
    } else if (!queue.empty()) {
        const auto& item = queue.top();
        result.set("id", V::text(item.id)); result.set("tick", V::number(item.tick));
        result.set("sequence", V::number(item.sequence));
        queue.pop();
    }
    return result.value();
}

GDExtensionObjectPtr route_queue_create(void*, GDExtensionBool notify) {
    auto* instance = new RouteQueueInstance;
    auto object = construct_object(&ref_class);
    set_instance(object, &route_queue_class, instance);
    if (notify) {
        int64_t postinitialize = 0; GDExtensionBool reversed = 0;
        const void* arguments[] = {&postinitialize, &reversed}; object_ptrcall(notification, object, arguments, nullptr);
    }
    return object;
}
void route_queue_free(void*, GDExtensionClassInstancePtr instance) { delete static_cast<RouteQueueInstance*>(instance); }

void route_queue_call(void* userdata, GDExtensionClassInstancePtr instance, const GDExtensionConstVariantPtr* arguments,
                      GDExtensionInt count, GDExtensionVariantPtr returned, GDExtensionCallError* error) {
    auto& method = *static_cast<RouteQueueMethod*>(userdata); error->error = GDEXTENSION_CALL_OK;
    if (count != static_cast<int64_t>(method.arguments.size())) { error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT; return; }
    std::vector<V> values;
    for (int64_t i = 0; i < count; ++i) {
        if (type(arguments[i]) != method.arguments[i]) {
            error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT; error->argument = static_cast<int32_t>(i); error->expected = method.arguments[i]; return;
        }
        values.emplace_back(arguments[i]);
    }
    try {
        V result = route_queue_invoke(method.operation, values, instance);
        destroy(returned); new_copy(returned, &result.raw);
    } catch (const std::exception&) {
        error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;
    }
}
void route_queue_ptrcall(void* userdata, GDExtensionClassInstancePtr instance, const GDExtensionConstTypePtr* arguments,
                         GDExtensionTypePtr returned) {
    auto& method = *static_cast<RouteQueueMethod*>(userdata);
    std::vector<V> values;
    for (size_t i = 0; i < method.arguments.size(); ++i) values.push_back(V::typed(method.arguments[i], arguments[i]));
    // Typed GDScript calls have the same already-validated dictionary payload
    // contract as HospitalTransit._relax; exceptions never cross the C ABI.
    try {
        V result = route_queue_invoke(method.operation, values, instance);
        if (method.output == GDEXTENSION_VARIANT_TYPE_DICTIONARY) destruct[method.output](returned);
        to_type[method.output](returned, &result.raw);
    } catch (const std::exception&) {
        if (method.output == GDEXTENSION_VARIANT_TYPE_DICTIONARY) {
            D empty; destruct[method.output](returned); V result = empty.value(); to_type[method.output](returned, &result.raw);
        } else { *static_cast<int64_t*>(returned) = 0; }
    }
}

void route_queue_register(GDExtensionInterfaceGetProcAddress api) {
    new_name(&route_queue_class, "PlatformRouteQueue");
    GDExtensionClassCreationInfo6 info{}; info.is_exposed = 1;
    info.create_instance_func = route_queue_create; info.free_instance_func = route_queue_free;
    register_class(library, &route_queue_class, &ref_class, &info);
    Builtin empty_name, hint;
    new_name(&empty_name, ""); new_string(&hint, "");
    auto get_dtor = reinterpret_cast<GDExtensionInterfaceVariantGetPtrDestructor>(api("variant_get_ptr_destructor"));
    for (auto& entry : route_queue_methods) {
        Builtin name; new_name(&name, entry.name);
        GDExtensionPropertyInfo output{}; output.type = entry.output;
        output.name = &empty_name; output.class_name = &empty_name; output.hint_string = &hint; output.usage = 6;
        std::vector<GDExtensionPropertyInfo> arguments(entry.arguments.size(), output);
        std::vector<Builtin> argument_names(entry.arguments.size());
        std::vector<GDExtensionClassMethodArgumentMetadata> metadata(entry.arguments.size(), GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE);
        for (size_t i = 0; i < arguments.size(); ++i) {
            arguments[i].type = entry.arguments[i]; new_name(&argument_names[i], "item"); arguments[i].name = &argument_names[i];
        }
        GDExtensionClassMethodInfo method{}; method.name = &name; method.method_userdata = &entry;
        method.call_func = route_queue_call; method.ptrcall_func = route_queue_ptrcall; method.method_flags = GDEXTENSION_METHOD_FLAG_NORMAL;
        method.has_return_value = 1; method.return_value_info = &output;
        method.argument_count = static_cast<uint32_t>(arguments.size()); method.arguments_info = arguments.data(); method.arguments_metadata = metadata.data();
        register_method(library, &route_queue_class, &method);
        for (Builtin& argument_name : argument_names) get_dtor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&argument_name);
        get_dtor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&name);
    }
    get_dtor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&empty_name); destruct[GDEXTENSION_VARIANT_TYPE_STRING](&hint);
}
void route_queue_unregister(GDExtensionInterfaceGetProcAddress api) {
    unregister_class(library, &route_queue_class);
    auto get_dtor = reinterpret_cast<GDExtensionInterfaceVariantGetPtrDestructor>(api("variant_get_ptr_destructor"));
    get_dtor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&route_queue_class);
}
