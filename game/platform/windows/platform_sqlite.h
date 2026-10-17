/* Private SQLite binding. Included once by the platform extension. */
#include "sqlite3.h"

typedef struct { uint64_t words[OGH_ARRAY_SIZE / 8]; } SqlArray;
typedef struct { uint64_t words[OGH_PACKED_BYTE_ARRAY_SIZE / 8]; } SqlBytes;
typedef struct { sqlite3 *connection; DWORD owner_thread; sqlite3_stmt *chunk_read, *chunk_write; } PlatformSQLite;

static StringName sqlite_class;
static GDExtensionInterfaceArrayOperatorIndexConst sql_array_index;
static GDExtensionInterfacePackedByteArrayOperatorIndex sql_bytes_index;
static GDExtensionInterfacePackedByteArrayOperatorIndexConst sql_bytes_index_const;
static GDExtensionPtrConstructor sql_array_new, sql_bytes_new;
static GDExtensionPtrDestructor sql_array_destroy, sql_bytes_destroy;
static GDExtensionTypeFromVariantConstructorFunc sql_array_from, sql_bytes_from, sql_int_from, sql_float_from, sql_bool_from;
static GDExtensionVariantFromTypeConstructorFunc sql_variant_array, sql_variant_bytes;
static GDExtensionPtrBuiltInMethod sql_array_size, sql_array_append, sql_bytes_size, sql_bytes_resize;

static void sql_error(Dictionary *result, int code, const char *message) {
    switch (code & 0xff) {
        case SQLITE_BUSY: case SQLITE_LOCKED: message = "医院资料被其他程序占用，请关闭占用程序后重试"; break;
        case SQLITE_READONLY: message = "医院资料目录不可写，请检查权限"; break;
        case SQLITE_FULL: message = "医院资料磁盘空间不足，请释放空间后重试"; break;
        case SQLITE_CANTOPEN: message = "无法打开医院资料，请检查文件占用和目录权限"; break;
        case SQLITE_NOMEM: message = "医院资料读写所需内存不足，当前医院和旧保存点保留"; break;
        case SQLITE_CORRUPT: case SQLITE_NOTADB: message = "医院资料损坏，请使用有效保存点或备份恢复"; break;
        default: break;
    }
    set_bool(result, "ok", 0);
    set_int(result, "code", code);
    set_string(result, "error", message);
}

static char *sql_utf8(const String *source, int64_t *length) {
    *length = string_to_utf8(source, NULL, 0);
    if (*length < 0 || *length > 1048576) return NULL;
    char *text = HeapAlloc(GetProcessHeap(), 0, (size_t)*length + 1);
    if (!text) return NULL;
    string_to_utf8(source, text, *length);
    text[*length] = '\0';
    return text;
}

static void sql_close(PlatformSQLite *database) {
	if (database->chunk_read) sqlite3_finalize(database->chunk_read);
	if (database->chunk_write) sqlite3_finalize(database->chunk_write);
	database->chunk_read = database->chunk_write = NULL;
    if (database->connection) sqlite3_close_v2(database->connection);
    database->connection = NULL;
}

static void sql_open(PlatformSQLite *database, const String *hospital, GDExtensionBool create, Dictionary *result) {
    dictionary_new(result, NULL);
    if (!InterlockedCompareExchange(&active_guard_count, 0, 0)) {
        sql_error(result, SQLITE_MISUSE, "医院资料库尚未取得独占权限");
        return;
    }
    if (database->connection) {
        sql_error(result, SQLITE_MISUSE, "SQLite连接已经打开");
        return;
    }
    int64_t length = 0;
    char *id = sql_utf8(hospital, &length);
    int valid = id && length == 36;
    for (int i = 0; valid && i < 36; ++i) {
        valid = (i == 8 || i == 13 || i == 18 || i == 23) ? id[i] == '-' :
                (id[i] >= '0' && id[i] <= '9') || (id[i] >= 'a' && id[i] <= 'f');
    }
    if (!valid) {
        if (id) HeapFree(GetProcessHeap(), 0, id);
        sql_error(result, SQLITE_MISUSE, "医院数据库身份无效");
        return;
    }
    DWORD error = ERROR_SUCCESS;
    wchar_t *directory = actual_user_directory(&error);
    if (!directory) {
        HeapFree(GetProcessHeap(), 0, id);
        sql_error(result, SQLITE_CANTOPEN, "无法取得实际医院资料目录");
        return;
    }
    size_t directory_length = wcslen(directory);
    wchar_t *path = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, (directory_length + 80) * sizeof(wchar_t));
    if (!path) {
        HeapFree(GetProcessHeap(), 0, directory);
        HeapFree(GetProcessHeap(), 0, id);
        sql_error(result, SQLITE_NOMEM, "医院数据库路径所需内存不足");
        return;
    }
    wcscpy(path, directory);
    wcscat(path, L"\\hospitals\\");
    size_t prefix = wcslen(path);
    for (int i = 0; i < 36; ++i) path[prefix + (size_t)i] = (wchar_t)id[i];
    wcscat(path, L"\\hospital.sqlite3");
    int path_bytes = WideCharToMultiByte(CP_UTF8, 0, path, -1, NULL, 0, NULL, NULL);
    char *utf8_path = path_bytes > 0 ? HeapAlloc(GetProcessHeap(), 0, (size_t)path_bytes) : NULL;
    if (utf8_path) WideCharToMultiByte(CP_UTF8, 0, path, -1, utf8_path, path_bytes, NULL, NULL);
    HeapFree(GetProcessHeap(), 0, path);
    HeapFree(GetProcessHeap(), 0, directory);
    HeapFree(GetProcessHeap(), 0, id);
    if (!utf8_path) {
        sql_error(result, SQLITE_NOMEM, "无法编码医院数据库路径");
        return;
    }
    int flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX;
    if (create) flags |= SQLITE_OPEN_CREATE;
    int code = sqlite3_open_v2(utf8_path, &database->connection, flags, NULL);
    HeapFree(GetProcessHeap(), 0, utf8_path);
    if (code == SQLITE_OK) {
        sqlite3_extended_result_codes(database->connection, 1);
        sqlite3_busy_timeout(database->connection, 1000);
        sqlite3_db_config(database->connection, SQLITE_DBCONFIG_DEFENSIVE, 1, NULL);
        code = sqlite3_exec(database->connection,
                "PRAGMA foreign_keys=ON; PRAGMA trusted_schema=OFF; PRAGMA synchronous=EXTRA;"
                "PRAGMA cache_size=-4096; PRAGMA temp_store=FILE;", NULL, NULL, NULL);
    }
    if (code != SQLITE_OK) {
        sql_error(result, code, database->connection ? sqlite3_errmsg(database->connection) : "无法打开医院数据库");
        sql_close(database);
        return;
    }
    database->owner_thread = GetCurrentThreadId();
    set_bool(result, "ok", 1);
    set_string(result, "version", sqlite3_libversion());
    set_string(result, "error", "");
}

static int sql_bind(sqlite3_stmt *statement, int index, GDExtensionConstVariantPtr value) {
    GDExtensionVariantPtr source = (GDExtensionVariantPtr)value;
    switch (variant_get_type(value)) {
        case GDEXTENSION_VARIANT_TYPE_NIL: return sqlite3_bind_null(statement, index);
        case GDEXTENSION_VARIANT_TYPE_BOOL: {
            GDExtensionBool number; sql_bool_from(&number, source);
            return sqlite3_bind_int(statement, index, number != 0);
        }
        case GDEXTENSION_VARIANT_TYPE_INT: {
            int64_t number; sql_int_from(&number, source);
            return sqlite3_bind_int64(statement, index, number);
        }
        case GDEXTENSION_VARIANT_TYPE_FLOAT: {
            double number; sql_float_from(&number, source);
            return sqlite3_bind_double(statement, index, number);
        }
        case GDEXTENSION_VARIANT_TYPE_STRING: {
            String string; string_from_variant(&string, source);
            int64_t length; char *text = sql_utf8(&string, &length);
            string_destroy(&string);
            if (!text) return SQLITE_NOMEM;
            int code = sqlite3_bind_text64(statement, index, text, (sqlite3_uint64)length, SQLITE_TRANSIENT, SQLITE_UTF8);
            HeapFree(GetProcessHeap(), 0, text);
            return code;
        }
        case GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY: {
            SqlBytes bytes; sql_bytes_from(&bytes, source);
            int64_t length; sql_bytes_size(&bytes, NULL, &length, 0);
            int code = length ? sqlite3_bind_blob64(statement, index, sql_bytes_index_const(&bytes, 0), (sqlite3_uint64)length, SQLITE_TRANSIENT) :
                    sqlite3_bind_zeroblob(statement, index, 0);
            sql_bytes_destroy(&bytes);
            return code;
        }
        default: return SQLITE_MISMATCH;
    }
}

static int sql_column(sqlite3_stmt *statement, int index, Dictionary *row) {
    const char *key = sqlite3_column_name(statement, index);
    switch (sqlite3_column_type(statement, index)) {
        case SQLITE_INTEGER: set_int(row, key, sqlite3_column_int64(statement, index)); break;
        case SQLITE_FLOAT: {
            double number = sqlite3_column_double(statement, index);
            dictionary_set(row, key, variant_from_float, &number);
            break;
        }
        case SQLITE_TEXT: set_string(row, key, (const char *)sqlite3_column_text(statement, index)); break;
        case SQLITE_BLOB: {
            SqlBytes bytes; sql_bytes_new(&bytes, NULL);
            int64_t length = sqlite3_column_bytes(statement, index), resize_error = 0;
            const GDExtensionConstTypePtr arguments[] = { &length };
            sql_bytes_resize(&bytes, arguments, &resize_error, 1);
            if (resize_error) { sql_bytes_destroy(&bytes); return SQLITE_NOMEM; }
            if (length) memcpy(sql_bytes_index(&bytes, 0), sqlite3_column_blob(statement, index), (size_t)length);
            dictionary_set(row, key, sql_variant_bytes, &bytes);
            sql_bytes_destroy(&bytes);
            break;
        }
        default: {
            String source; string_new(&source, key);
            Variant name; variant_from_string(&name, &source);
            GDExtensionVariantPtr slot = dictionary_index(row, &name);
            variant_destroy(slot); variant_new_nil(slot);
            variant_destroy(&name); string_destroy(&source);
        }
    }
    return SQLITE_OK;
}

static void sql_execute(PlatformSQLite *database, const String *query, const SqlArray *parameters, Dictionary *result) {
    dictionary_new(result, NULL);
    if (!database->connection || database->owner_thread != GetCurrentThreadId()) {
        sql_error(result, SQLITE_MISUSE, "SQLite连接未打开或被跨线程使用");
        return;
    }
    int64_t length; char *text = sql_utf8(query, &length);
    if (!text) { sql_error(result, SQLITE_NOMEM, "SQL语句所需内存不足"); return; }
    sqlite3_stmt **slot = NULL;
    if (!strcmp(text, "SELECT chunk_index,CASE WHEN length(data)<=32768 THEN data END AS data FROM world_chunks WHERE snapshot_id=? AND chunk_index>=? ORDER BY chunk_index LIMIT 1")) slot = &database->chunk_read;
    else if (!strcmp(text, "INSERT INTO world_chunks VALUES(?,?,?)")) slot = &database->chunk_write;
    sqlite3_stmt *statement = slot ? *slot : NULL;
    const char *tail = NULL;
    int code = statement ? SQLITE_OK : sqlite3_prepare_v3(database->connection, text, (int)length, slot ? SQLITE_PREPARE_PERSISTENT : 0, &statement, &tail);
    if (code == SQLITE_OK) {
        while (tail && (*tail == ' ' || *tail == '\r' || *tail == '\n' || *tail == '\t')) ++tail;
        if (!statement || (tail && *tail)) code = SQLITE_MISUSE;
    }
    if (code == SQLITE_OK && slot) *slot = statement;
    int64_t count = 0;
    sql_array_size((void *)parameters, NULL, &count, 0);
    if (code == SQLITE_OK && count != sqlite3_bind_parameter_count(statement)) code = SQLITE_RANGE;
    for (int64_t i = 0; code == SQLITE_OK && i < count; ++i) code = sql_bind(statement, (int)i + 1, sql_array_index(parameters, i));
    SqlArray rows; sql_array_new(&rows, NULL);
    int rows_count = 0;
    while (code == SQLITE_OK && (code = sqlite3_step(statement)) == SQLITE_ROW) {
        /* Callers page metadata and fetch one bounded world chunk at a time. */
        if (++rows_count > 256) { code = SQLITE_TOOBIG; break; }
        Dictionary row; dictionary_new(&row, NULL);
        for (int i = 0; i < sqlite3_column_count(statement); ++i) {
            int column_code = sql_column(statement, i, &row);
            if (column_code != SQLITE_OK) { code = column_code; break; }
        }
        if (code != SQLITE_ROW) { dictionary_destroy(&row); break; }
        Variant item; variant_from_dictionary(&item, &row);
        const GDExtensionConstTypePtr arguments[] = { &item };
        sql_array_append(&rows, arguments, NULL, 1);
        variant_destroy(&item); dictionary_destroy(&row);
        code = SQLITE_OK;
    }
    if (code == SQLITE_DONE) {
        set_bool(result, "ok", 1);
        set_int(result, "changes", sqlite3_changes(database->connection));
        set_string(result, "error", "");
        dictionary_set(result, "rows", sql_variant_array, &rows);
    } else {
        sql_error(result, code, code == SQLITE_RANGE ? "SQL参数数量不符" :
                code == SQLITE_TOOBIG ? "SQLite结果需要分页读取" : sqlite3_errmsg(database->connection));
    }
    if (slot && code == SQLITE_DONE) {
        int reset_code = sqlite3_reset(statement);
        int clear_code = sqlite3_clear_bindings(statement);
        if (reset_code != SQLITE_OK || clear_code != SQLITE_OK) {
            sql_error(result, reset_code != SQLITE_OK ? reset_code : clear_code, "SQLite分段语句释放失败");
            sqlite3_finalize(statement); *slot = NULL;
        }
    } else {
        sqlite3_finalize(statement);
        if (slot) *slot = NULL;
    }
    sql_array_destroy(&rows);
    HeapFree(GetProcessHeap(), 0, text);
}

enum SqlMethod { SQL_OPEN, SQL_EXECUTE, SQL_CLOSE };

static void sql_dispatch(enum SqlMethod method, PlatformSQLite *database, const GDExtensionConstTypePtr *args, Dictionary *result) {
    if (method == SQL_OPEN) sql_open(database, args[0], *(const GDExtensionBool *)args[1], result);
    else if (method == SQL_EXECUTE) sql_execute(database, args[0], args[1], result);
    else { sql_close(database); dictionary_new(result, NULL); set_bool(result, "ok", 1); }
}

static void sql_call(void *userdata, GDExtensionClassInstancePtr instance, const GDExtensionConstVariantPtr *args,
        GDExtensionInt count, GDExtensionVariantPtr returned, GDExtensionCallError *error) {
    enum SqlMethod method = (enum SqlMethod)(uintptr_t)userdata;
    int required = method == SQL_CLOSE ? 0 : 2;
    error->error = count == required ? GDEXTENSION_CALL_OK :
            count < required ? GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS : GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS;
    error->argument = 0; error->expected = required;
    variant_destroy(returned);
    if (error->error != GDEXTENSION_CALL_OK) { variant_new_nil(returned); return; }
    if (required && (variant_get_type(args[0]) != GDEXTENSION_VARIANT_TYPE_STRING ||
            variant_get_type(args[1]) != (method == SQL_OPEN ? GDEXTENSION_VARIANT_TYPE_BOOL : GDEXTENSION_VARIANT_TYPE_ARRAY))) {
        error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;
        variant_new_nil(returned); return;
    }
    String query; SqlArray parameters; GDExtensionBool create = 0;
    GDExtensionConstTypePtr typed[2] = { &query, NULL };
    if (required) {
        string_from_variant(&query, (GDExtensionVariantPtr)args[0]);
        if (method == SQL_OPEN) { sql_bool_from(&create, (GDExtensionVariantPtr)args[1]); typed[1] = &create; }
        else { sql_array_from(&parameters, (GDExtensionVariantPtr)args[1]); typed[1] = &parameters; }
    }
    Dictionary result; sql_dispatch(method, instance, typed, &result);
    variant_from_dictionary(returned, &result); dictionary_destroy(&result);
    if (required) string_destroy(&query);
    if (method == SQL_EXECUTE) sql_array_destroy(&parameters);
}

static void sql_ptrcall(void *userdata, GDExtensionClassInstancePtr instance,
        const GDExtensionConstTypePtr *args, GDExtensionTypePtr returned) {
    Dictionary result; sql_dispatch((enum SqlMethod)(uintptr_t)userdata, instance, args, &result);
    const GDExtensionConstTypePtr copy[] = { &result };
    dictionary_destroy(returned); dictionary_copy(returned, copy); dictionary_destroy(&result);
}

static GDExtensionObjectPtr sql_create(void *userdata, GDExtensionBool notify) {
    (void)userdata;
    PlatformSQLite *database = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(*database));
    if (!database) return NULL;
    GDExtensionObjectPtr object = construct_object(&parent_class);
    if (!object) { HeapFree(GetProcessHeap(), 0, database); return NULL; }
    object_set_instance(object, &sqlite_class, database);
    if (notify) {
        int64_t notification = 0; GDExtensionBool reversed = 0;
        const GDExtensionConstTypePtr args[] = { &notification, &reversed };
        object_ptrcall(notification_method, object, args, NULL);
    }
    return object;
}

static void sql_free(void *userdata, GDExtensionClassInstancePtr instance) {
    (void)userdata; sql_close(instance); HeapFree(GetProcessHeap(), 0, instance);
}

static void bind_sqlite(void) {
    string_name_new(&sqlite_class, "PlatformSQLite");
    GDExtensionClassCreationInfo6 class_info = { .is_exposed = 1, .create_instance_func = sql_create, .free_instance_func = sql_free };
    register_class(library, &sqlite_class, &parent_class, &class_info);
    const char *names[] = { "open", "execute", "close" };
    for (int method = SQL_OPEN; method <= SQL_CLOSE; ++method) {
        StringName name, empty; String hint;
        string_name_new(&name, names[method]); string_name_new(&empty, ""); string_new(&hint, "");
        GDExtensionPropertyInfo returned = { .type = GDEXTENSION_VARIANT_TYPE_DICTIONARY,
                .name = &empty, .class_name = &empty, .hint_string = &hint, .usage = 6 };
        GDExtensionPropertyInfo arguments[2] = {
            { .type = GDEXTENSION_VARIANT_TYPE_STRING, .name = &empty, .class_name = &empty, .hint_string = &hint, .usage = 6 },
            { .type = method == SQL_OPEN ? GDEXTENSION_VARIANT_TYPE_BOOL : GDEXTENSION_VARIANT_TYPE_ARRAY,
                    .name = &empty, .class_name = &empty, .hint_string = &hint, .usage = 6 } };
        GDExtensionClassMethodArgumentMetadata metadata[2] = { 0, 0 };
        GDExtensionClassMethodInfo info = { .name = &name, .method_userdata = (void *)(uintptr_t)method,
                .call_func = sql_call, .ptrcall_func = sql_ptrcall, .method_flags = GDEXTENSION_METHOD_FLAG_NORMAL,
                .has_return_value = 1, .return_value_info = &returned, .argument_count = method == SQL_CLOSE ? 0 : 2,
                .arguments_info = arguments, .arguments_metadata = metadata };
        register_method(library, &sqlite_class, &info);
        string_destroy(&hint); string_name_destroy(&empty); string_name_destroy(&name);
    }
}

static int load_sqlite_api(GDExtensionInterfaceGetProcAddress get_proc,
        GDExtensionInterfaceVariantGetPtrConstructor constructors, GDExtensionInterfaceVariantGetPtrDestructor destructors,
        GDExtensionInterfaceGetVariantFromTypeConstructor from_type, GDExtensionInterfaceGetVariantToTypeConstructor to_type) {
#define SQL_LOAD(variable, name) do { GDExtensionInterfaceFunctionPtr raw = get_proc(name); \
    memcpy(&variable, &raw, sizeof(variable)); if (!variable) return 0; } while (0)
    SQL_LOAD(sql_array_index, "array_operator_index_const");
    SQL_LOAD(sql_bytes_index, "packed_byte_array_operator_index");
    SQL_LOAD(sql_bytes_index_const, "packed_byte_array_operator_index_const");
    GDExtensionInterfaceVariantGetPtrBuiltinMethod builtin;
    SQL_LOAD(builtin, "variant_get_ptr_builtin_method");
#undef SQL_LOAD
    sql_array_new = constructors(GDEXTENSION_VARIANT_TYPE_ARRAY, 0);
    sql_bytes_new = constructors(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, 0);
    sql_array_destroy = destructors(GDEXTENSION_VARIANT_TYPE_ARRAY);
    sql_bytes_destroy = destructors(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
    sql_array_from = to_type(GDEXTENSION_VARIANT_TYPE_ARRAY);
    sql_bytes_from = to_type(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
    sql_int_from = to_type(GDEXTENSION_VARIANT_TYPE_INT);
    sql_float_from = to_type(GDEXTENSION_VARIANT_TYPE_FLOAT);
    sql_bool_from = to_type(GDEXTENSION_VARIANT_TYPE_BOOL);
    sql_variant_array = from_type(GDEXTENSION_VARIANT_TYPE_ARRAY);
    sql_variant_bytes = from_type(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
    StringName name;
    string_name_new(&name, "size");
    sql_array_size = builtin(GDEXTENSION_VARIANT_TYPE_ARRAY, &name, OGH_ARRAY_SIZE_HASH);
    sql_bytes_size = builtin(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, &name, OGH_ARRAY_SIZE_HASH);
    string_name_destroy(&name); string_name_new(&name, "append");
    sql_array_append = builtin(GDEXTENSION_VARIANT_TYPE_ARRAY, &name, OGH_ARRAY_APPEND_HASH);
    string_name_destroy(&name); string_name_new(&name, "resize");
    sql_bytes_resize = builtin(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, &name, OGH_BYTES_RESIZE_HASH);
    string_name_destroy(&name);
    return sql_array_size && sql_array_append && sql_bytes_size && sql_bytes_resize;
}
