// Included after the bridge's shared Variant adapters. minizip-ng owns ZIP
// structure/ZIP64/DEFLATE; zlib owns CRC. This layer enforces backup policy.
#include "mz.h"
#include "mz_strm.h"
#include "mz_strm_os.h"
#include "mz_zip.h"
#include "zlib.h"
extern "C" int32_t ogh_zip_layout(void*, int64_t, int64_t*);
extern "C" int32_t ogh_zip_descriptor(void*, int64_t, uint8_t, uint32_t*, int64_t*, int64_t*, int64_t*);
extern "C" int32_t ogh_zip_extra(const mz_zip_file*, int64_t, void*, uint8_t);
extern "C" int64_t ogh_zip_directory_end(void*);

struct ZipBytes { alignas(8) unsigned char raw[OGH_PACKED_BYTE_ARRAY_SIZE]; };
Builtin backup_zip_class;
GDExtensionTypeFromVariantConstructorFunc zip_bytes_from;
GDExtensionVariantFromTypeConstructorFunc zip_bytes_to, zip_bool_to;
GDExtensionPtrConstructor zip_bytes_new;
GDExtensionPtrDestructor zip_bytes_destroy;
GDExtensionPtrBuiltInMethod zip_bytes_size, zip_bytes_resize;
GDExtensionInterfacePackedByteArrayOperatorIndex zip_bytes_index;
GDExtensionInterfacePackedByteArrayOperatorIndexConst zip_bytes_index_const;
struct ZipInputBytes {
    ZipBytes bytes;
    explicit ZipInputBytes(const V& source) { zip_bytes_from(&bytes, const_cast<Raw*>(&source.raw)); }
    ~ZipInputBytes() { zip_bytes_destroy(&bytes); }
};
V zip_bool(bool value) {
    GDExtensionBool boolean = value; V result; destroy(&result.raw); zip_bool_to(&result.raw, &boolean); return result;
}
V zip_result() { D result; result.set("ok", zip_bool(true)); return result.value(); }
V zip_failure(const std::string& reason) {
    D result; result.set("ok", zip_bool(false)); result.set("error", V::text(reason)); return result.value();
}
void zip_check(int32_t code, const char* reason) { if (code != MZ_OK) throw std::runtime_error(reason); }
struct BackupZipInstance {
    void* stream = nullptr;
    void* zip = nullptr;
    bool writing = false, entry = false;
    int64_t expected = 0, transferred = 0;
    ~BackupZipInstance() { close(); }
    void close() {
        if (zip) { mz_zip_close(zip); mz_zip_delete(&zip); }
        if (stream) { mz_stream_close(stream); mz_stream_os_delete(&stream); }
        entry = false; writing = false;
    }
    void open(const std::string& path, bool write) {
        close(); stream = mz_stream_os_create(); zip = mz_zip_create();
        if (!stream || !zip) throw std::runtime_error("备份所需内存不足");
        int mode = write ? MZ_OPEN_MODE_WRITE | MZ_OPEN_MODE_CREATE : MZ_OPEN_MODE_READ;
        zip_check(mz_stream_open(stream, path.c_str(), mode), "无法打开备份文件");
        zip_check(mz_zip_open(zip, stream, mode), "备份ZIP目录或ZIP64结构无效"); writing = write;
        if (write) zip_check(mz_zip_set_data_descriptor(zip, 0), "无法初始化备份写入器");
    }
    int64_t length() {
        auto saved = mz_stream_tell(stream);
        zip_check(mz_stream_seek(stream, 0, MZ_SEEK_END), "无法读取备份文件长度");
        auto size = mz_stream_tell(stream);
        zip_check(mz_stream_seek(stream, saved, MZ_SEEK_SET), "无法恢复备份读取位置"); return size;
    }
};
bool zip_allowed(const std::string& name) {
    return name == "manifest.json" || name == "hospital.sqlite3" || name == "thumbnail.png";
}
V zip_entry_value(const mz_zip_file& entry, int64_t data_offset) {
    D value; value.set("name", V::text(std::string(entry.filename, entry.filename_size)));
    for (const auto& pair : std::vector<std::pair<const char*, int64_t>>{
        {"flags", entry.flag}, {"method", entry.compression_method}, {"crc", entry.crc},
        {"compressed", entry.compressed_size}, {"unpacked", entry.uncompressed_size},
        {"offset", entry.disk_offset}, {"data_offset", data_offset}}) value.set(pair.first, V::number(pair.second));
    return value.value();
}
V zip_inspect(const std::string& path) {
    BackupZipInstance archive; archive.open(path, false);
    int64_t length = archive.length(), directory = 0;
    zip_check(ogh_zip_layout(archive.zip, length, &directory), "备份条目数量、目录范围或分卷信息无效");
    uint64_t count = 0; mz_zip_get_number_entry(archive.zip, &count);
    D entries; std::set<std::string> names;
    struct Layout { mz_zip_file entry; int64_t data; int64_t end; };
    std::vector<Layout> layouts;
    zip_check(mz_zip_goto_first_entry(archive.zip), "备份必需条目缺失");
    for (uint64_t index = 0; index < count; ++index) {
        mz_zip_file* info = nullptr; zip_check(mz_zip_entry_get_info(archive.zip, &info), "备份条目目录无效");
        mz_zip_file central = *info;
        std::string name(central.filename, central.filename_size);
        if (!zip_allowed(name) || name.size() > 64 || !names.insert(name).second || central.disk_number ||
            (central.flag & ~0x080e) || (central.compression_method != 0 && central.compression_method != 8) ||
            ((central.external_fa >> 16) & 61440) == 40960 ||
            central.uncompressed_size < 0 || central.compressed_size < 0 || central.disk_offset < 0 ||
            central.disk_offset >= directory ||
            (central.uncompressed_size > 0 && (central.compressed_size == 0 ||
             static_cast<long double>(central.uncompressed_size) / central.compressed_size > 200.0L)) ||
            (central.compression_method == 0 && central.compressed_size != central.uncompressed_size) ||
            (name == "manifest.json" && central.uncompressed_size > 65536) ||
            (name == "thumbnail.png" && central.uncompressed_size > 262144))
            throw std::runtime_error("备份包含未知、重复、加密、符号链接或不安全条目");
        auto central_position = mz_zip_get_entry(archive.zip);
        auto central_end = central_position + 46 + central.filename_size + central.extrafield_size + central.comment_size;
        if (central_position < directory || central_end > ogh_zip_directory_end(archive.zip) ||
            (index + 1 == count && central_end != ogh_zip_directory_end(archive.zip)))
            throw std::runtime_error("备份条目目录范围或实际大小不符");
        zip_check(ogh_zip_extra(info, central_position, archive.stream, 0), "备份ZIP附加字段格式无效");
        zip_check(mz_zip_entry_read_open(archive.zip, 1, nullptr), "备份本地条目头无效");
        archive.entry = true;
        mz_zip_file* local = nullptr; zip_check(mz_zip_entry_get_local_info(archive.zip, &local), "备份本地条目信息无效");
        int64_t data = mz_stream_tell(archive.stream);
        if (local->filename_size != name.size() || std::string(local->filename, local->filename_size) != name ||
            local->flag != central.flag || local->compression_method != central.compression_method ||
            (!(central.flag & 8) && (local->crc != central.crc || local->compressed_size != central.compressed_size ||
             local->uncompressed_size != central.uncompressed_size)) || data < 0 ||
            data > directory || central.compressed_size > directory - data)
            throw std::runtime_error("备份本地条目路径、类型、长度或CRC与目录不符");
        zip_check(ogh_zip_extra(local, central.disk_offset, archive.stream, 1), "备份本地ZIP附加字段格式无效");
        int64_t end = data + central.compressed_size;
        if (central.flag & 8) {
            uint32_t crc = 0; int64_t compressed = 0, unpacked = 0;
            zip_check(ogh_zip_descriptor(archive.zip, end,
                central.compressed_size >= UINT32_MAX || central.uncompressed_size >= UINT32_MAX,
                &crc, &compressed, &unpacked, &end), "备份流式条目描述无效");
            if (crc != central.crc || compressed != central.compressed_size || unpacked != central.uncompressed_size)
                throw std::runtime_error("备份流式条目描述不符");
        }
        // Raw entry is intentionally not consumed during metadata inspection.
        mz_zip_entry_read_close(archive.zip, nullptr, nullptr, nullptr); archive.entry = false;
        layouts.push_back({central, data, end}); entries.set(name.c_str(), zip_entry_value(central, data));
        int32_t next = mz_zip_goto_next_entry(archive.zip);
        if (index + 1 < count) zip_check(next, "备份条目目录未完整写入");
        else if (next != MZ_END_OF_LIST) throw std::runtime_error("备份目录包含未登记条目");
    }
    if (!names.count("manifest.json") || !names.count("hospital.sqlite3")) throw std::runtime_error("备份必需条目缺失");
    std::sort(layouts.begin(), layouts.end(), [](const Layout& a, const Layout& b) { return a.entry.disk_offset < b.entry.disk_offset; });
    int64_t end = 0;
    for (const auto& layout : layouts) {
        if (layout.entry.disk_offset != end || layout.end > directory)
            throw std::runtime_error("备份包含未登记条目、重复区域或前置数据");
        end = layout.end;
    }
    if (end != directory) throw std::runtime_error("备份目录前存在未登记数据");
    D result; result.set("ok", zip_bool(true)); result.set("entries", entries.value());
    result.set("bytes", V::number(length)); result.set("path", V::text(path)); return result.value();
}
enum class BackupZipMethod { INSPECT, OPEN_READ, READ, OPEN_WRITE, BEGIN, WRITE, END, FINISH, CLOSE, CRC };
struct BackupZipMethodInfo { const char* name; BackupZipMethod method; std::vector<GDExtensionVariantType> arguments; };
BackupZipMethodInfo backup_zip_methods[] = {
    {"inspect", BackupZipMethod::INSPECT, {GDEXTENSION_VARIANT_TYPE_STRING}},
    {"open_read", BackupZipMethod::OPEN_READ, {GDEXTENSION_VARIANT_TYPE_STRING, GDEXTENSION_VARIANT_TYPE_STRING, GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_DICTIONARY}},
    {"read_chunk", BackupZipMethod::READ, {}},
    {"open_write", BackupZipMethod::OPEN_WRITE, {GDEXTENSION_VARIANT_TYPE_STRING}},
    {"begin_entry", BackupZipMethod::BEGIN, {GDEXTENSION_VARIANT_TYPE_STRING, GDEXTENSION_VARIANT_TYPE_INT}},
    {"write_chunk", BackupZipMethod::WRITE, {GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY}},
    {"end_entry", BackupZipMethod::END, {GDEXTENSION_VARIANT_TYPE_INT}},
    {"finish_write", BackupZipMethod::FINISH, {}},
    {"close", BackupZipMethod::CLOSE, {}},
    {"crc32", BackupZipMethod::CRC, {GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, GDEXTENSION_VARIANT_TYPE_INT}}
};
V backup_zip_invoke(BackupZipMethod method, BackupZipInstance& instance, const std::vector<V>& args) {
    try {
        if (method == BackupZipMethod::INSPECT) return zip_inspect(args[0].text());
        if (method == BackupZipMethod::CLOSE) { instance.close(); return zip_result(); }
        if (method == BackupZipMethod::OPEN_WRITE) { instance.open(args[0].text(), true); return zip_result(); }
        if (method == BackupZipMethod::OPEN_READ) {
            instance.open(args[0].text(), false);
            if (instance.length() != args[2].number()) throw std::runtime_error("备份在读取前已改变");
            zip_check(mz_zip_locate_entry(instance.zip, args[1].text().c_str(), 0), "备份条目不存在");
            mz_zip_file* info = nullptr; zip_check(mz_zip_entry_get_info(instance.zip, &info), "备份条目目录无效");
            D expected(args[3]), actual(zip_entry_value(*info, 0));
            for (const char* key : {"flags", "method", "crc", "compressed", "unpacked", "offset"})
                if (actual.get(key).number() != expected.get(key).number()) throw std::runtime_error("备份在读取前已改变");
            instance.expected = info->uncompressed_size; instance.transferred = 0;
            zip_check(mz_zip_entry_read_open(instance.zip, 0, nullptr), "无法创建ZIP解压器"); instance.entry = true;
            void* compressed = nullptr;
            zip_check(mz_zip_entry_get_compress_stream(instance.zip, &compressed), "无法读取ZIP解压流");
            zip_check(mz_stream_set_prop_int64(compressed, MZ_STREAM_PROP_TOTAL_IN_MAX, info->compressed_size), "无法限制ZIP解压流");
            return zip_result();
        }
        if (method == BackupZipMethod::BEGIN) {
            if (!instance.zip || !instance.writing || instance.entry || !zip_allowed(args[0].text()) || args[1].number() < 0)
                throw std::runtime_error("备份写入状态或条目信息无效");
            std::string name = args[0].text(); mz_zip_file info{};
            info.filename = name.c_str(); info.filename_size = static_cast<uint16_t>(name.size());
            info.uncompressed_size = args[1].number(); info.compression_method = MZ_COMPRESS_METHOD_STORE;
            info.zip64 = MZ_ZIP64_AUTO; info.modified_date = 315532800;
            zip_check(mz_zip_entry_write_open(instance.zip, &info, 0, 0, nullptr), "备份条目写入失败");
            instance.entry = true; instance.expected = args[1].number(); instance.transferred = 0; return zip_result();
        }
        if (method == BackupZipMethod::WRITE || method == BackupZipMethod::CRC) {
            ZipInputBytes source(args[0]);
            int64_t length = 0; zip_bytes_size(&source.bytes, nullptr, &length, 0);
            const uint8_t* raw = length ? zip_bytes_index_const(&source.bytes, 0) : nullptr;
            if (method == BackupZipMethod::CRC) {
                if (length > 65536) throw std::runtime_error("备份CRC分块超过上限");
                auto crc = length ? crc32(static_cast<uLong>(args[1].number()), raw, static_cast<uInt>(length))
                                  : static_cast<uint32_t>(args[1].number());
                D result; result.set("ok", zip_bool(true)); result.set("crc", V::number(crc)); return result.value();
            }
            if (!instance.zip || !instance.writing || !instance.entry || length > 32768 || length > instance.expected - instance.transferred)
                throw std::runtime_error("备份写入超过声明长度或分块上限");
            if (length && mz_zip_entry_write(instance.zip, raw, static_cast<int32_t>(length)) != length)
                throw std::runtime_error("备份条目写入失败");
            instance.transferred += length; return zip_result();
        }
        if (method == BackupZipMethod::END) {
            if (!instance.zip || !instance.writing || !instance.entry || instance.transferred != instance.expected)
                throw std::runtime_error("备份源文件实际长度已改变");
            zip_check(mz_zip_entry_write_close(instance.zip, 0, -1, -1), "备份条目写入未完整结束"); instance.entry = false;
            mz_zip_file* info = nullptr; zip_check(mz_zip_entry_get_info(instance.zip, &info), "无法核对备份写入结果");
            if (info->crc != static_cast<uint32_t>(args[0].number()) || info->uncompressed_size != instance.expected)
                throw std::runtime_error("备份源文件实际长度或CRC已改变");
            return zip_result();
        }
        if (method == BackupZipMethod::FINISH) {
            if (!instance.zip || !instance.writing || instance.entry) throw std::runtime_error("备份写入状态无效");
            int32_t code = mz_zip_close(instance.zip); mz_zip_delete(&instance.zip);
            int32_t closed = mz_stream_close(instance.stream); mz_stream_os_delete(&instance.stream); instance.writing = false;
            zip_check(code, "备份ZIP目录写入失败"); zip_check(closed, "备份目标磁盘写入失败"); return zip_result();
        }
        if (!instance.zip || instance.writing || !instance.entry) throw std::runtime_error("备份读取状态无效");
        mz_zip_file* current = nullptr;
        zip_check(mz_zip_entry_get_info(instance.zip, &current), "无法读取ZIP条目信息");
        uint8_t data[32768];
        int32_t read = current->compression_method == MZ_COMPRESS_METHOD_STORE && !current->compressed_size
            ? 0 : mz_zip_entry_read(instance.zip, data, sizeof(data));
        if (read < 0) throw std::runtime_error("备份DEFLATE数据损坏或未完整结束");
        if (read > instance.expected - instance.transferred) throw std::runtime_error("备份解压超过声明长度");
        instance.transferred += read;
        if (!read) {
            void* compressed = nullptr; int64_t consumed = 0; mz_zip_file* info = nullptr;
            zip_check(mz_zip_entry_get_compress_stream(instance.zip, &compressed), "无法读取ZIP解压结果");
            zip_check(mz_stream_get_prop_int64(compressed, MZ_STREAM_PROP_TOTAL_IN, &consumed), "无法核对ZIP解压长度");
            zip_check(mz_zip_entry_get_info(instance.zip, &info), "无法读取ZIP条目长度");
            if (consumed != info->compressed_size || instance.transferred != instance.expected)
                throw std::runtime_error("备份DEFLATE流含额外数据或实际长度不符");
            // inspect already validates the descriptor under the restricted
            // protocol's size-based ZIP64 rule. Requesting descriptor outputs
            // here would let minizip's extra-field heuristic choose a different
            // width for an otherwise legal small entry with a ZIP64 extra.
            zip_check(mz_zip_entry_read_close(instance.zip, nullptr, nullptr, nullptr), "备份条目CRC不符"); instance.entry = false;
        }
        ZipBytes bytes; zip_bytes_new(&bytes, nullptr);
        int64_t size64 = read, resize_error = 0; const void* resize_args[] = {&size64};
        zip_bytes_resize(&bytes, resize_args, &resize_error, 1);
        if (resize_error) { zip_bytes_destroy(&bytes); throw std::runtime_error("备份读取所需内存不足"); }
        if (read) std::copy(data, data + read, zip_bytes_index(&bytes, 0));
        V raw; destroy(&raw.raw); zip_bytes_to(&raw.raw, &bytes); zip_bytes_destroy(&bytes);
        D result; result.set("ok", zip_bool(true)); result.set("raw", raw); result.set("done", zip_bool(!read)); return result.value();
    } catch (const std::exception& error) { instance.close(); return zip_failure(error.what()); }
}
void backup_zip_call(void* userdata, GDExtensionClassInstancePtr instance, const GDExtensionConstVariantPtr* args,
                     GDExtensionInt count, GDExtensionVariantPtr returned, GDExtensionCallError* error) {
    auto& method = *static_cast<BackupZipMethodInfo*>(userdata); error->error = GDEXTENSION_CALL_OK;
    if (count != static_cast<int64_t>(method.arguments.size())) { error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT; return; }
    std::vector<V> values;
    for (int64_t i = 0; i < count; ++i) {
        if (type(args[i]) != method.arguments[i]) { error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT; error->argument = static_cast<int32_t>(i); error->expected = method.arguments[i]; return; }
        values.emplace_back(args[i]);
    }
    V result = backup_zip_invoke(method.method, *static_cast<BackupZipInstance*>(instance), values);
    destroy(returned); new_copy(returned, &result.raw);
}
void backup_zip_ptrcall(void* userdata, GDExtensionClassInstancePtr instance, const GDExtensionConstTypePtr* args, GDExtensionTypePtr returned) {
    auto& method = *static_cast<BackupZipMethodInfo*>(userdata); std::vector<V> values;
    for (size_t i = 0; i < method.arguments.size(); ++i) values.push_back(V::typed(method.arguments[i], args[i]));
    V result = backup_zip_invoke(method.method, *static_cast<BackupZipInstance*>(instance), values);
    destruct[GDEXTENSION_VARIANT_TYPE_DICTIONARY](returned); to_type[GDEXTENSION_VARIANT_TYPE_DICTIONARY](returned, &result.raw);
}
GDExtensionObjectPtr backup_zip_create(void*, GDExtensionBool notify) {
    auto* instance = new BackupZipInstance; auto object = construct_object(&ref_class);
    set_instance(object, &backup_zip_class, instance);
    if (notify) { int64_t postinitialize = 0; GDExtensionBool reversed = 0; const void* args[] = {&postinitialize, &reversed}; object_ptrcall(notification, object, args, nullptr); }
    return object;
}
void backup_zip_free(void*, GDExtensionClassInstancePtr instance) { delete static_cast<BackupZipInstance*>(instance); }
void backup_zip_register(GDExtensionInterfaceGetProcAddress api) {
    auto get_from = reinterpret_cast<GDExtensionInterfaceGetVariantFromTypeConstructor>(api("get_variant_from_type_constructor"));
    auto get_to = reinterpret_cast<GDExtensionInterfaceGetVariantToTypeConstructor>(api("get_variant_to_type_constructor"));
    auto get_ctor = reinterpret_cast<GDExtensionInterfaceVariantGetPtrConstructor>(api("variant_get_ptr_constructor"));
    auto get_dtor = reinterpret_cast<GDExtensionInterfaceVariantGetPtrDestructor>(api("variant_get_ptr_destructor"));
    auto get_method = reinterpret_cast<GDExtensionInterfaceVariantGetPtrBuiltinMethod>(api("variant_get_ptr_builtin_method"));
    zip_bytes_from = get_to(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY); zip_bytes_to = get_from(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
    zip_bool_to = get_from(GDEXTENSION_VARIANT_TYPE_BOOL); zip_bytes_new = get_ctor(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, 0);
    zip_bytes_destroy = get_dtor(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
    from_type[GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY] = zip_bytes_to;
    zip_bytes_index = reinterpret_cast<GDExtensionInterfacePackedByteArrayOperatorIndex>(api("packed_byte_array_operator_index"));
    zip_bytes_index_const = reinterpret_cast<GDExtensionInterfacePackedByteArrayOperatorIndexConst>(api("packed_byte_array_operator_index_const"));
    Builtin size, resize; new_name(&size, "size"); new_name(&resize, "resize");
    zip_bytes_size = get_method(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, &size, OGH_ARRAY_SIZE_HASH);
    zip_bytes_resize = get_method(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, &resize, OGH_BYTES_RESIZE_HASH);
    get_dtor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&size); get_dtor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&resize);
    Builtin empty, hint; new_name(&empty, ""); new_string(&hint, ""); new_name(&backup_zip_class, "PlatformBackupZip");
    GDExtensionClassCreationInfo6 info{}; info.is_exposed = 1; info.create_instance_func = backup_zip_create; info.free_instance_func = backup_zip_free;
    register_class(library, &backup_zip_class, &ref_class, &info);
    GDExtensionPropertyInfo output{}; output.type = GDEXTENSION_VARIANT_TYPE_DICTIONARY; output.name = &empty; output.class_name = &empty; output.hint_string = &hint; output.usage = 6;
    for (auto& entry : backup_zip_methods) {
        Builtin name; new_name(&name, entry.name);
        std::vector<GDExtensionPropertyInfo> arguments(entry.arguments.size(), output);
        std::vector<Builtin> names(entry.arguments.size());
        std::vector<GDExtensionClassMethodArgumentMetadata> metadata(entry.arguments.size(), GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE);
        for (size_t i = 0; i < arguments.size(); ++i) { auto label = "arg" + std::to_string(i); new_name(&names[i], label.c_str()); arguments[i].name = &names[i]; arguments[i].type = entry.arguments[i]; }
        GDExtensionClassMethodInfo method{}; method.name = &name; method.method_userdata = &entry;
        method.call_func = backup_zip_call; method.ptrcall_func = backup_zip_ptrcall; method.method_flags = GDEXTENSION_METHOD_FLAG_NORMAL;
        method.has_return_value = 1; method.return_value_info = &output; method.argument_count = static_cast<uint32_t>(arguments.size());
        method.arguments_info = arguments.data(); method.arguments_metadata = metadata.data(); register_method(library, &backup_zip_class, &method);
        for (auto& arg : names) get_dtor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&arg);
        get_dtor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&name);
    }
    destruct[GDEXTENSION_VARIANT_TYPE_STRING](&hint); get_dtor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&empty);
}
