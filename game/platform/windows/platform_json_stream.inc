// Include inside the existing bridge namespace, after V/A/D adapters.
constexpr size_t JSON_CHUNK = 32768, JSON_MAX_STRING = 65536, JSON_MAX_DEPTH = 64;
Builtin json_stream_class;
GDExtensionInterfaceVariantCall json_variant_call;
GDExtensionInterfaceStringNewWithUtf8CharsAndLen json_new_string;
GDExtensionInterfacePackedByteArrayOperatorIndex json_byte_index;
GDExtensionInterfacePackedByteArrayOperatorIndexConst json_byte_index_const;

V json_text(const char* text, size_t length) {
    Builtin string; json_new_string(&string, text, static_cast<int64_t>(length));
    V result = V::typed(GDEXTENSION_VARIANT_TYPE_STRING, &string);
    destruct[GDEXTENSION_VARIANT_TYPE_STRING](&string); return result;
}
V json_bool(bool flag) {
    GDExtensionBool value = flag; return V::typed(GDEXTENSION_VARIANT_TYPE_BOOL, &value);
}
bool json_is_true(const V& value) {
    if (type(&value.raw) != GDEXTENSION_VARIANT_TYPE_BOOL) return false;
    GDExtensionBool flag; to_type[GDEXTENSION_VARIANT_TYPE_BOOL](&flag, const_cast<Raw*>(&value.raw)); return flag;
}
V json_method(const V& target, const char* name, const std::vector<V>& arguments = {}) {
    Builtin method; new_name(&method, name);
    std::vector<GDExtensionConstVariantPtr> args;
    for (const auto& arg : arguments) args.push_back(&arg.raw);
    V returned; destroy(&returned.raw); GDExtensionCallError error{};
    json_variant_call(const_cast<Raw*>(&target.raw), &method, args.data(), static_cast<int64_t>(args.size()), &returned.raw, &error);
    destruct[GDEXTENSION_VARIANT_TYPE_STRING_NAME](&method);
    if (error.error != GDEXTENSION_CALL_OK) throw std::runtime_error("JSON流回调执行失败");
    return returned;
}
struct JsonBytes {
    alignas(8) unsigned char raw[OGH_PACKED_BYTE_ARRAY_SIZE];
    JsonBytes() { construct[GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY](raw, nullptr); }
    explicit JsonBytes(const V& value) { to_type[GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY](raw, const_cast<Raw*>(&value.raw)); }
    ~JsonBytes() { destruct[GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY](raw); }
    V value() const { return V::typed(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, raw); }
};
V json_chunk(const char* data, size_t length) {
    JsonBytes bytes;
    V value = bytes.value(); json_method(value, "resize", {V::number(static_cast<int64_t>(length))});
    JsonBytes resized(value);
    if (length) std::memcpy(json_byte_index(resized.raw, 0), data, length);
    return resized.value();
}
void json_callback_ok(const V& result) {
    if (type(&result.raw) != GDEXTENSION_VARIANT_TYPE_DICTIONARY) throw std::runtime_error("JSON流回调返回类型无效");
    D response(result);
    if (!json_is_true(response.get("ok"))) {
        V reason = response.get("error");
        throw std::runtime_error(reason.nil() ? "JSON流回调失败" : reason.text());
    }
}
struct JsonOutput {
    using Ch = char;
    V sink;
    std::array<char, JSON_CHUNK> buffer{};
    size_t used = 0;
    explicit JsonOutput(const V& callback) : sink(callback) {}
    void Put(char value) { buffer[used++] = value; if (used == buffer.size()) Flush(); }
    void Flush() {
        if (!used) return;
        V result = json_method(sink, "call", {json_chunk(buffer.data(), used)});
        json_callback_ok(result); used = 0;
    }
};
struct JsonHandler {
    static constexpr size_t max_array_size = std::numeric_limits<size_t>::max();
    static constexpr size_t max_object_size = std::numeric_limits<size_t>::max();
    static constexpr size_t max_string_size = JSON_MAX_STRING;
    static constexpr size_t max_key_size = JSON_MAX_STRING;
    struct Frame {
        V value;
        V key;
        std::set<std::string> keys;
        bool object;
        explicit Frame(bool is_object) : object(is_object) { if (object) value = D().value(); else value = A().value(); }
    };
    std::vector<Frame> frames;
    V decimal_decoder;
    V root;
    std::string string_parts, number_parts;
    bool complete = false;
    explicit JsonHandler(const V& decoder) : decimal_decoder(decoder) {}
    void depth() const { if (frames.size() > JSON_MAX_DEPTH) throw std::runtime_error("JSON嵌套深度超过64"); }
    bool accept(const V& value) {
        depth();
        if (frames.empty()) { root = value; complete = true; }
        else if (frames.back().object) {
            D object(frames.back().value); auto slot = dict_index(&object.raw, &frames.back().key.raw);
            destroy(slot); new_copy(slot, &value.raw);
        } else { A array(frames.back().value); array.append(value); }
        return true;
    }
    bool Null() { return accept(V()); }
    bool Bool(bool value) { return accept(json_bool(value)); }
    bool String(const char* text, rapidjson::SizeType length, bool) {
        if (length > JSON_MAX_STRING) throw std::runtime_error("JSON字符串超过64KiB");
        return accept(json_text(text, length));
    }
    bool Key(const char* text, rapidjson::SizeType length, bool) {
        // Keys occupy the same child depth as their values in the world codec.
        depth();
        if (length > JSON_MAX_STRING) throw std::runtime_error("JSON字符串超过64KiB");
        if (!frames.back().keys.emplace(text, length).second) throw std::runtime_error("JSON对象分隔符或重复键无效");
        frames.back().key = json_text(text, length); return true;
    }
    bool RawNumber(const char* text, rapidjson::SizeType length, bool) {
        if (length > 128) throw std::runtime_error("JSON标量格式无效");
        std::string token(text, length);
        if (token.find_first_of(".eE") == std::string::npos) {
            int64_t integer = 0; auto parsed = std::from_chars(text, text + length, integer);
            if (parsed.ec != std::errc() || parsed.ptr != text + length) throw std::runtime_error("JSON整数超出64位范围或格式无效");
            return accept(V::number(integer));
        }
        // Reuse the existing C-locale UCRT decimal decoder. Boost.JSON validates
        // grammar; the established adapter checks full consumption and finite
        // binary64 output without introducing another numeric algorithm.
        V decoded = json_method(decimal_decoder, "call", {json_text(text, length)}); json_callback_ok(decoded);
        V number = D(decoded).get("value");
        if (type(&number.raw) != GDEXTENSION_VARIANT_TYPE_FLOAT) throw std::runtime_error("JSON浮点解码器返回类型无效");
        return accept(number);
    }
    bool StartObject() { depth(); frames.emplace_back(true); return true; }
    bool StartArray() { depth(); frames.emplace_back(false); return true; }
    bool end() { V value = frames.back().value; frames.pop_back(); return accept(value); }
    bool EndObject(rapidjson::SizeType) { return end(); }
    bool EndArray(rapidjson::SizeType) { return end(); }
    bool on_document_begin(boost::system::error_code&) { return true; }
    bool on_document_end(boost::system::error_code&) { return true; }
    bool on_object_begin(boost::system::error_code&) { return StartObject(); }
    bool on_array_begin(boost::system::error_code&) { return StartArray(); }
    bool on_object_end(size_t, boost::system::error_code&) { return end(); }
    bool on_array_end(size_t, boost::system::error_code&) { return end(); }
    bool on_null(boost::system::error_code&) { return Null(); }
    bool on_bool(bool value, boost::system::error_code&) { return Bool(value); }
    bool on_string_part(boost::json::string_view part, size_t total, boost::system::error_code&) {
        if (total > JSON_MAX_STRING) throw std::runtime_error("JSON字符串超过64KiB");
        string_parts.append(part.data(), part.size()); return true;
    }
    bool on_key_part(boost::json::string_view part, size_t total, boost::system::error_code& error) { return on_string_part(part, total, error); }
    bool on_string(boost::json::string_view part, size_t total, boost::system::error_code& error) {
        on_string_part(part, total, error);
        bool accepted = String(string_parts.data(), static_cast<rapidjson::SizeType>(string_parts.size()), false);
        string_parts.clear(); return accepted;
    }
    bool on_key(boost::json::string_view part, size_t total, boost::system::error_code& error) {
        on_string_part(part, total, error);
        bool accepted = Key(string_parts.data(), static_cast<rapidjson::SizeType>(string_parts.size()), false);
        string_parts.clear(); return accepted;
    }
    bool on_number_part(boost::json::string_view part, boost::system::error_code&) {
        if (number_parts.size() + part.size() > 128) throw std::runtime_error("JSON标量格式无效");
        number_parts.append(part.data(), part.size()); return true;
    }
    bool finish_number(boost::json::string_view part, boost::system::error_code& error) {
        on_number_part(part, error);
        bool accepted = RawNumber(number_parts.data(), static_cast<rapidjson::SizeType>(number_parts.size()), false);
        number_parts.clear(); return accepted;
    }
    bool on_int64(int64_t, boost::json::string_view part, boost::system::error_code& error) { return finish_number(part, error); }
    bool on_uint64(uint64_t, boost::json::string_view part, boost::system::error_code& error) { return finish_number(part, error); }
    bool on_double(double, boost::json::string_view part, boost::system::error_code& error) { return finish_number(part, error); }
    bool on_comment_part(boost::json::string_view, boost::system::error_code&) { return false; }
    bool on_comment(boost::json::string_view, boost::system::error_code&) { return false; }
};
using JsonWriter = rapidjson::Writer<JsonOutput, rapidjson::UTF8<>, rapidjson::UTF8<>, rapidjson::CrtAllocator, rapidjson::kWriteValidateEncodingFlag>;
void json_write(JsonWriter& writer, const V& value, size_t depth, const V& float_format) {
    if (depth > JSON_MAX_DEPTH) throw std::runtime_error("JSON嵌套深度超过64");
    switch (type(&value.raw)) {
        case GDEXTENSION_VARIANT_TYPE_DICTIONARY: {
            D object(value); A keys(object.keys()); std::vector<std::pair<std::string, V>> ordered;
            for (int64_t i = 0; i < keys.size(); ++i) {
                V key = keys.at(i); auto kind = type(&key.raw);
                if (kind != GDEXTENSION_VARIANT_TYPE_STRING && kind != GDEXTENSION_VARIANT_TYPE_STRING_NAME) throw std::runtime_error("世界对象键必须是字符串");
                ordered.emplace_back(key.text(), key);
            }
            std::sort(ordered.begin(), ordered.end(), [](const auto& a, const auto& b) { return a.first < b.first; });
            writer.StartObject();
            for (const auto& key : ordered) {
                if (depth == JSON_MAX_DEPTH) throw std::runtime_error("JSON嵌套深度超过64");
                if (key.first.size() > JSON_MAX_STRING) throw std::runtime_error("JSON字符串超过64KiB");
                if (!writer.Key(key.first.data(), static_cast<rapidjson::SizeType>(key.first.size()))) throw std::runtime_error("JSON键不是有效UTF-8");
                json_write(writer, object.get(key.second), depth + 1, float_format);
            }
            writer.EndObject(); break;
        }
        case GDEXTENSION_VARIANT_TYPE_ARRAY: {
            A array(value); writer.StartArray();
            for (int64_t i = 0; i < array.size(); ++i) json_write(writer, array.at(i), depth + 1, float_format);
            writer.EndArray(); break;
        }
        case GDEXTENSION_VARIANT_TYPE_STRING:
        case GDEXTENSION_VARIANT_TYPE_STRING_NAME: {
            std::string text = value.text();
            if (text.size() > JSON_MAX_STRING) throw std::runtime_error("JSON字符串超过64KiB");
            if (!writer.String(text.data(), static_cast<rapidjson::SizeType>(text.size()))) throw std::runtime_error("JSON字符串不是有效UTF-8");
            break;
        }
        case GDEXTENSION_VARIANT_TYPE_NIL: writer.Null(); break;
        case GDEXTENSION_VARIANT_TYPE_BOOL: writer.Bool(json_is_true(value)); break;
        case GDEXTENSION_VARIANT_TYPE_INT: writer.Int64(value.number()); break;
        case GDEXTENSION_VARIANT_TYPE_FLOAT: {
            double number; to_type[GDEXTENSION_VARIANT_TYPE_FLOAT](&number, const_cast<Raw*>(&value.raw));
            if (!std::isfinite(number)) throw std::runtime_error("世界含有不能保存的值或平台句柄");
            // Godot's scalar formatter discards the sign of -0.0. RapidJSON's
            // mature formatter retains both its sign bit and float marker.
            if (number == 0.0) { writer.Double(number); break; }
            // Keep Godot's existing full-precision scalar spelling, including
            // the decimal marker that distinguishes float 1.0 from int 1.
            V formatted = json_method(float_format, "call", {value});
            if (type(&formatted.raw) != GDEXTENSION_VARIANT_TYPE_STRING) throw std::runtime_error("JSON浮点格式器返回类型无效");
            std::string token = formatted.text(); writer.RawValue(token.data(), token.size(), rapidjson::kNumberType); break;
        }
        default: throw std::runtime_error("世界含有不能保存的值或平台句柄");
    }
}
enum class JsonMethod { ENCODE, DECODE };
struct JsonMethodInfo { const char* name; JsonMethod method; std::vector<GDExtensionVariantType> arguments; };
JsonMethodInfo json_methods[] = {
    {"encode", JsonMethod::ENCODE, {GDEXTENSION_VARIANT_TYPE_DICTIONARY, GDEXTENSION_VARIANT_TYPE_CALLABLE, GDEXTENSION_VARIANT_TYPE_CALLABLE}},
    {"decode", JsonMethod::DECODE, {GDEXTENSION_VARIANT_TYPE_CALLABLE, GDEXTENSION_VARIANT_TYPE_CALLABLE}}
};
V json_invoke(JsonMethod method, const std::vector<V>& args) {
    D output;
    try {
        if (method == JsonMethod::ENCODE) {
            JsonOutput stream(args[1]); JsonWriter writer(stream); json_write(writer, args[0], 0, args[2]); stream.Flush();
        } else {
            // Unlike RapidJSON's NumbersAsStrings mode, Boost's public `none`
            // mode validates the original number without imposing binary64
            // exponent bounds. Valid finite inputs such as 0e999 are retained.
            boost::json::parse_options options;
            options.max_depth = JSON_MAX_DEPTH + 1;
            options.numbers = boost::json::number_precision::none;
            boost::json::basic_parser<JsonHandler> reader(options, args[1]);
            for (;;) {
                V result = json_method(args[0], "call"); json_callback_ok(result);
                V data = D(result).get("data");
                if (type(&data.raw) != GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY) throw std::runtime_error("世界分段读取类型无效");
                size_t length = static_cast<size_t>(json_method(data, "size").number());
                if (length > JSON_CHUNK) throw std::runtime_error("世界分段超出32KiB");
                JsonBytes bytes(data); boost::system::error_code error;
                const char* buffer = length ? reinterpret_cast<const char*>(json_byte_index_const(bytes.raw, 0)) : "";
                size_t used = reader.write_some(length != 0, buffer, length, error);
                if (error) throw std::runtime_error(std::string("JSON格式无效：") + error.message());
                if (used != length) throw std::runtime_error("JSON末尾存在额外数据");
                if (length == 0) break;
            }
            const auto& handler = reader.handler();
            if (!handler.complete || type(&handler.root.raw) != GDEXTENSION_VARIANT_TYPE_DICTIONARY) throw std::runtime_error("世界根对象无效");
            output.set("value", handler.root);
        }
        output.set("ok", json_bool(true));
    } catch (const std::exception& error) {
        output.set("ok", json_bool(false)); output.set("error", V::text(error.what())); output.set("value", D().value());
    }
    return output.value();
}
void json_call(void* userdata, GDExtensionClassInstancePtr, const GDExtensionConstVariantPtr* args, GDExtensionInt count,
               GDExtensionVariantPtr returned, GDExtensionCallError* error) {
    auto& method = *static_cast<JsonMethodInfo*>(userdata); error->error = GDEXTENSION_CALL_OK;
    if (count != static_cast<int64_t>(method.arguments.size())) { error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT; return; }
    std::vector<V> values;
    for (int64_t i = 0; i < count; ++i) {
        if (type(args[i]) != method.arguments[i]) { error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT; error->argument = static_cast<int32_t>(i); error->expected = method.arguments[i]; return; }
        values.emplace_back(args[i]);
    }
    V result = json_invoke(method.method, values); destroy(returned); new_copy(returned, &result.raw);
}
void json_ptrcall(void* userdata, GDExtensionClassInstancePtr, const GDExtensionConstTypePtr* args, GDExtensionTypePtr returned) {
    auto& method = *static_cast<JsonMethodInfo*>(userdata); std::vector<V> values;
    for (size_t i = 0; i < method.arguments.size(); ++i) values.push_back(V::typed(method.arguments[i], args[i]));
    V result = json_invoke(method.method, values);
    destruct[GDEXTENSION_VARIANT_TYPE_DICTIONARY](returned); to_type[GDEXTENSION_VARIANT_TYPE_DICTIONARY](returned, &result.raw);
}
void json_register(GDExtensionInterfaceGetProcAddress api) {
    json_variant_call = reinterpret_cast<GDExtensionInterfaceVariantCall>(api("variant_call"));
    json_new_string = reinterpret_cast<GDExtensionInterfaceStringNewWithUtf8CharsAndLen>(api("string_new_with_utf8_chars_and_len"));
    json_byte_index = reinterpret_cast<GDExtensionInterfacePackedByteArrayOperatorIndex>(api("packed_byte_array_operator_index"));
    json_byte_index_const = reinterpret_cast<GDExtensionInterfacePackedByteArrayOperatorIndexConst>(api("packed_byte_array_operator_index_const"));
    auto get_dtor = reinterpret_cast<GDExtensionInterfaceVariantGetPtrDestructor>(api("variant_get_ptr_destructor"));
    Builtin empty, hint; new_name(&empty, ""); new_string(&hint, ""); new_name(&json_stream_class, "PlatformJsonStream");
    GDExtensionClassCreationInfo6 info{}; info.is_exposed = 1; info.is_abstract = 1;
    register_class(library, &json_stream_class, &ref_class, &info);
    GDExtensionPropertyInfo output{}; output.type = GDEXTENSION_VARIANT_TYPE_DICTIONARY;
    output.name = &empty; output.class_name = &empty; output.hint_string = &hint; output.usage = 6;
    for (auto& entry : json_methods) {
        Builtin name; new_name(&name, entry.name);
        std::vector<GDExtensionPropertyInfo> args(entry.arguments.size(), output);
        std::vector<Builtin> names(entry.arguments.size());
        std::vector<GDExtensionClassMethodArgumentMetadata> metadata(entry.arguments.size(), GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE);
        const char* argument_names[] = {entry.method == JsonMethod::DECODE ? "source" : "value", entry.method == JsonMethod::DECODE ? "decimal_decoder" : "sink", "float_format"};
        for (size_t i = 0; i < args.size(); ++i) { new_name(&names[i], argument_names[i]); args[i].name = &names[i]; args[i].type = entry.arguments[i]; }
        GDExtensionClassMethodInfo method{}; method.name = &name; method.method_userdata = &entry;
        method.call_func = json_call; method.ptrcall_func = json_ptrcall; method.method_flags = GDEXTENSION_METHOD_FLAG_NORMAL | GDEXTENSION_METHOD_FLAG_STATIC;
        method.has_return_value = 1; method.return_value_info = &output; method.argument_count = static_cast<uint32_t>(args.size());
        method.arguments_info = args.data(); method.arguments_metadata = metadata.data(); register_method(library, &json_stream_class, &method);
        for (auto& arg : names) get_dtor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&arg);
        get_dtor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&name);
    }
    destruct[GDEXTENSION_VARIANT_TYPE_STRING](&hint); get_dtor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&empty);
}
void json_unregister(GDExtensionInterfaceGetProcAddress api) {
    unregister_class(library, &json_stream_class);
    auto get_dtor = reinterpret_cast<GDExtensionInterfaceVariantGetPtrDestructor>(api("variant_get_ptr_destructor"));
    get_dtor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&json_stream_class);
}
