#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>
#include <locale.h>
#include <math.h>
#include "gdextension_interface.h"
#include "platform_guard_abi.h"

/* Sizes and method hashes come from this build's engine-generated API. */
typedef struct { uint64_t words[OGH_VARIANT_SIZE / 8]; } Variant;
typedef struct { uint64_t words[OGH_STRING_SIZE / 8]; } String;
typedef struct { uint64_t words[OGH_STRING_NAME_SIZE / 8]; } StringName;
typedef struct { uint64_t words[OGH_DICTIONARY_SIZE / 8]; } Dictionary;

typedef struct {
    HANDLE handle;
} PlatformSessionGuard;

static GDExtensionClassLibraryPtr library;
static GDExtensionInterfaceGetProcAddress platform_api;
void ogh_math_initialize(GDExtensionInterfaceGetProcAddress api, GDExtensionClassLibraryPtr owner);
void ogh_math_deinitialize(GDExtensionInterfaceGetProcAddress api);
static volatile LONG active_guard_count;
static StringName guard_class;
static StringName parent_class;
static StringName numbers_class;
static GDExtensionObjectPtr os_singleton;
static GDExtensionMethodBindPtr user_dir_method;
static GDExtensionMethodBindPtr notification_method;

static GDExtensionInterfaceStringNameNewWithUtf8Chars string_name_new;
static GDExtensionInterfaceStringNewWithUtf8Chars string_new;
static GDExtensionInterfaceStringToUtf16Chars string_to_utf16;
static GDExtensionInterfaceStringToUtf8Chars string_to_utf8;
static GDExtensionInterfaceVariantGetType variant_get_type;
static GDExtensionInterfaceVariantDestroy variant_destroy;
static GDExtensionInterfaceVariantNewNil variant_new_nil;
static GDExtensionInterfaceDictionaryOperatorIndex dictionary_index;
static GDExtensionInterfaceObjectSetInstance object_set_instance;
static GDExtensionInterfaceObjectMethodBindPtrcall object_ptrcall;
static GDExtensionInterfaceClassdbConstructObject3 construct_object;
static GDExtensionInterfaceClassdbRegisterExtensionClass6 register_class;
static GDExtensionInterfaceClassdbRegisterExtensionClassMethod register_method;
static GDExtensionInterfaceClassdbUnregisterExtensionClass unregister_class;
static GDExtensionInterfaceClassdbGetMethodBind get_method_bind;
static GDExtensionInterfaceGlobalGetSingleton get_singleton;
static GDExtensionPtrConstructor dictionary_new;
static GDExtensionPtrConstructor dictionary_copy;
static GDExtensionPtrConstructor string_default;
static GDExtensionPtrDestructor dictionary_destroy;
static GDExtensionPtrDestructor string_destroy;
static GDExtensionPtrDestructor string_name_destroy;
static GDExtensionVariantFromTypeConstructorFunc variant_from_bool;
static GDExtensionVariantFromTypeConstructorFunc variant_from_int;
static GDExtensionVariantFromTypeConstructorFunc variant_from_string;
static GDExtensionVariantFromTypeConstructorFunc variant_from_dictionary;
static GDExtensionVariantFromTypeConstructorFunc variant_from_float;
static GDExtensionTypeFromVariantConstructorFunc string_from_variant;

/* A private C numeric locale makes decimal decoding independent of Windows locale.
 * UCRT is supplied by Windows 10/11; no process-wide locale is changed. */
typedef void *(__cdecl *CreateLocale)(int, const char *);
typedef void (__cdecl *FreeLocale)(void *);
typedef double (__cdecl *StrtodLocale)(const char *, char **, void *);
static HMODULE numeric_runtime;
static void *numeric_locale;
static FreeLocale free_numeric_locale;
static StrtodLocale decode_numeric_decimal;

static void dictionary_set(Dictionary *dictionary, const char *key,
        GDExtensionVariantFromTypeConstructorFunc constructor, void *value) {
    String key_string;
    Variant key_variant;
    string_new(&key_string, key);
    variant_from_string(&key_variant, &key_string);
    GDExtensionVariantPtr slot = dictionary_index(dictionary, &key_variant);
    variant_destroy(slot);
    constructor(slot, value);
    variant_destroy(&key_variant);
    string_destroy(&key_string);
}

static void set_bool(Dictionary *dictionary, const char *key, GDExtensionBool value) {
    dictionary_set(dictionary, key, variant_from_bool, &value);
}

static void set_int(Dictionary *dictionary, const char *key, int64_t value) {
    dictionary_set(dictionary, key, variant_from_int, &value);
}

static void set_string(Dictionary *dictionary, const char *key, const char *value) {
    String string;
    string_new(&string, value);
    dictionary_set(dictionary, key, variant_from_string, &string);
    string_destroy(&string);
}

static void set_error(Dictionary *result, DWORD error, const char *operation) {
    wchar_t system_message[512];
    char utf8_message[1536];
    char message[2048];
    DWORD length = FormatMessageW(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
            NULL, error, 0, system_message, 512, NULL);
    while (length && (system_message[length - 1] == L'\r' || system_message[length - 1] == L'\n')) {
        --length;
    }
    int utf8_length = length ? WideCharToMultiByte(CP_UTF8, 0, system_message, (int)length,
            utf8_message, (int)sizeof(utf8_message) - 1, NULL, NULL) : 0;
    utf8_message[utf8_length] = '\0';
    snprintf(message, sizeof(message), "%s (Windows error %lu): %s", operation,
            (unsigned long)error, utf8_message);
    set_bool(result, "ok", 0);
    set_int(result, "error", error);
    set_string(result, "message", message);
}

/* Only OS.get_user_data_dir() supplies a path. Script cannot choose a directory. */
static wchar_t *actual_user_directory(DWORD *error) {
    String godot_directory;
    string_default(&godot_directory, NULL);
    object_ptrcall(user_dir_method, os_singleton, NULL, &godot_directory);
    int64_t length = string_to_utf16(&godot_directory, NULL, 0);
    if (length <= 0 || length > 32740) {
        string_destroy(&godot_directory);
        *error = length > 32740 ? ERROR_FILENAME_EXCED_RANGE : ERROR_BAD_PATHNAME;
        return NULL;
    }
    wchar_t *path = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY,
            ((size_t)length + 32) * sizeof(wchar_t));
    if (!path) {
        string_destroy(&godot_directory);
        *error = ERROR_NOT_ENOUGH_MEMORY;
        return NULL;
    }
    string_to_utf16(&godot_directory, (char16_t *)path, length);
    string_destroy(&godot_directory);
    for (int64_t i = 0; i < length; ++i) {
        if (path[i] == L'/') path[i] = L'\\';
    }
    /* Extended paths preserve Unicode and avoid the legacy MAX_PATH boundary. */
    if (wcsncmp(path, L"\\\\?\\", 4) != 0) {
        if (length >= 3 && path[1] == L':' && path[2] == L'\\') {
            memmove(path + 4, path, ((size_t)length + 1) * sizeof(wchar_t));
            memcpy(path, L"\\\\?\\", 4 * sizeof(wchar_t));
        } else if (length >= 3 && path[0] == L'\\' && path[1] == L'\\') {
            memmove(path + 8, path + 2, ((size_t)length - 1) * sizeof(wchar_t));
            memcpy(path, L"\\\\?\\UNC\\", 8 * sizeof(wchar_t));
        } else {
            HeapFree(GetProcessHeap(), 0, path);
            *error = ERROR_BAD_PATHNAME;
            return NULL;
        }
    }
    length = (int64_t)wcslen(path);
    while (length > 7 && path[length - 1] == L'\\') path[--length] = L'\0';
    return path;
}

static DWORD create_directory(wchar_t *path) {
    if (CreateDirectoryW(path, NULL)) return ERROR_SUCCESS;
    DWORD error = GetLastError();
    if (error != ERROR_ALREADY_EXISTS) return error;
    DWORD attributes = GetFileAttributesW(path);
    if (attributes == INVALID_FILE_ATTRIBUTES) return GetLastError();
    return (attributes & FILE_ATTRIBUTE_DIRECTORY) ? ERROR_SUCCESS : ERROR_DIRECTORY;
}

static DWORD ensure_user_directory(wchar_t *path) {
    size_t start = 7; /* \\?\C:\ */
    if (wcsncmp(path, L"\\\\?\\UNC\\", 8) == 0) {
        start = 8;
        for (int component = 0; component < 2; ++component) {
            while (path[start] && path[start] != L'\\') ++start;
            if (!path[start]) return ERROR_BAD_PATHNAME;
            ++start;
        }
    }
    for (size_t i = start; path[i]; ++i) {
        if (path[i] != L'\\') continue;
        path[i] = L'\0';
        DWORD error = create_directory(path);
        path[i] = L'\\';
        if (error != ERROR_SUCCESS) return error;
    }
    return create_directory(path);
}

static void acquire_guard(PlatformSessionGuard *guard, Dictionary *result) {
    dictionary_new(result, NULL);
    set_bool(result, "busy", 0);
    if (guard->handle != INVALID_HANDLE_VALUE) {
        set_bool(result, "ok", 1);
        set_int(result, "error", ERROR_SUCCESS);
        set_string(result, "message", "");
        return;
    }
    DWORD error = ERROR_SUCCESS;
    wchar_t *path = actual_user_directory(&error);
    if (!path) {
        set_error(result, error, "Unable to resolve the hospital data directory");
        return;
    }
    error = ensure_user_directory(path);
    if (error != ERROR_SUCCESS) {
        HeapFree(GetProcessHeap(), 0, path);
        set_error(result, error, "Unable to create the hospital data directory");
        return;
    }
    wcscat(path, L"\\.session.guard");
    /* NULL security attributes produce a non-inheritable handle. */
    guard->handle = CreateFileW(path, GENERIC_READ | GENERIC_WRITE, 0, NULL,
            OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    error = guard->handle == INVALID_HANDLE_VALUE ? GetLastError() : ERROR_SUCCESS;
    HeapFree(GetProcessHeap(), 0, path);
    if (error == ERROR_SUCCESS) {
        InterlockedIncrement(&active_guard_count);
        set_bool(result, "ok", 1);
        set_int(result, "error", ERROR_SUCCESS);
        set_string(result, "message", "");
    } else if (error == ERROR_SHARING_VIOLATION) {
        set_bool(result, "ok", 0);
        set_bool(result, "busy", 1);
        set_int(result, "error", error);
        set_string(result, "message", "医院资料正在被占用，请回到已打开的游戏或稍后重试");
    } else {
        set_error(result, error, "Unable to open the hospital data guard");
    }
}

static void release_guard(PlatformSessionGuard *guard) {
    if (guard->handle == INVALID_HANDLE_VALUE) return;
    CloseHandle(guard->handle);
    guard->handle = INVALID_HANDLE_VALUE;
    InterlockedDecrement(&active_guard_count);
}

static void resource_status(PlatformSessionGuard *guard, Dictionary *result) {
    dictionary_new(result, NULL);
    set_int(result, "available_physical_bytes", 0);
    set_int(result, "available_disk_bytes", 0);
    if (guard->handle == INVALID_HANDLE_VALUE) {
        set_error(result, ERROR_INVALID_HANDLE, "Hospital data ownership has not been acquired");
        return;
    }
    MEMORYSTATUSEX memory = { .dwLength = sizeof(MEMORYSTATUSEX) };
    if (!GlobalMemoryStatusEx(&memory)) {
        set_error(result, GetLastError(), "Unable to query available physical memory");
        return;
    }
    DWORD error = ERROR_SUCCESS;
    wchar_t *path = actual_user_directory(&error);
    if (!path) {
        set_error(result, error, "Unable to resolve the hospital data volume");
        return;
    }
    ULARGE_INTEGER disk;
    BOOL disk_ok = GetDiskFreeSpaceExW(path, &disk, NULL, NULL);
    error = disk_ok ? ERROR_SUCCESS : GetLastError();
    HeapFree(GetProcessHeap(), 0, path);
    if (error != ERROR_SUCCESS) {
        set_error(result, error, "Unable to query available hospital data volume space");
        return;
    }
    if (memory.ullAvailPhys > INT64_MAX || disk.QuadPart > INT64_MAX) {
        set_error(result, ERROR_ARITHMETIC_OVERFLOW, "Available resource bytes exceed the supported integer range");
        return;
    }
    set_bool(result, "ok", 1);
    set_int(result, "error", ERROR_SUCCESS);
    set_string(result, "message", "");
    set_int(result, "available_physical_bytes", (int64_t)memory.ullAvailPhys);
    set_int(result, "available_disk_bytes", (int64_t)disk.QuadPart);
}

enum GuardMethod { METHOD_ACQUIRE, METHOD_RELEASE, METHOD_IS_HELD, METHOD_RESOURCES };

static void method_call(void *method_userdata, GDExtensionClassInstancePtr instance,
        const GDExtensionConstVariantPtr *args, GDExtensionInt count,
        GDExtensionVariantPtr returned, GDExtensionCallError *call_error) {
    (void)args;
    PlatformSessionGuard *guard = instance;
    call_error->error = count ? GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS : GDEXTENSION_CALL_OK;
    call_error->argument = 0;
    call_error->expected = 0;
    variant_destroy(returned);
    if (count) {
        variant_new_nil(returned);
        return;
    }
    enum GuardMethod method = (enum GuardMethod)(uintptr_t)method_userdata;
    if (method == METHOD_RELEASE) {
        release_guard(guard);
        variant_new_nil(returned);
    } else if (method == METHOD_IS_HELD) {
        GDExtensionBool held = guard->handle != INVALID_HANDLE_VALUE;
        variant_from_bool(returned, &held);
    } else {
        Dictionary result;
        if (method == METHOD_ACQUIRE) acquire_guard(guard, &result);
        else resource_status(guard, &result);
        variant_from_dictionary(returned, &result);
        dictionary_destroy(&result);
    }
}

static void method_ptrcall(void *method_userdata, GDExtensionClassInstancePtr instance,
        const GDExtensionConstTypePtr *args, GDExtensionTypePtr returned) {
    (void)args;
    PlatformSessionGuard *guard = instance;
    enum GuardMethod method = (enum GuardMethod)(uintptr_t)method_userdata;
    if (method == METHOD_RELEASE) {
        release_guard(guard);
    } else if (method == METHOD_IS_HELD) {
        *(GDExtensionBool *)returned = guard->handle != INVALID_HANDLE_VALUE;
    } else {
        Dictionary result;
        if (method == METHOD_ACQUIRE) acquire_guard(guard, &result);
        else resource_status(guard, &result);
        const GDExtensionConstTypePtr copy_args[] = { &result };
        dictionary_destroy(returned);
        dictionary_copy(returned, copy_args);
        dictionary_destroy(&result);
    }
}

static GDExtensionObjectPtr guard_create(void *userdata, GDExtensionBool notify) {
    (void)userdata;
    PlatformSessionGuard *guard = HeapAlloc(GetProcessHeap(), 0, sizeof(*guard));
    if (!guard) return NULL;
    guard->handle = INVALID_HANDLE_VALUE;
    GDExtensionObjectPtr object = construct_object(&parent_class);
    if (!object) {
        HeapFree(GetProcessHeap(), 0, guard);
        return NULL;
    }
    object_set_instance(object, &guard_class, guard);
    if (notify) {
        int64_t postinitialize = 0;
        GDExtensionBool reversed = 0;
        const GDExtensionConstTypePtr args[] = { &postinitialize, &reversed };
        object_ptrcall(notification_method, object, args, NULL);
    }
    return object;
}

static void guard_free(void *userdata, GDExtensionClassInstancePtr instance) {
    (void)userdata;
    release_guard(instance);
    HeapFree(GetProcessHeap(), 0, instance);
}

static void bind_method(const char *name, enum GuardMethod method, GDExtensionVariantType returned_type) {
    StringName method_name, empty_name;
    String empty_hint;
    string_name_new(&method_name, name);
    string_name_new(&empty_name, "");
    string_new(&empty_hint, "");
    GDExtensionPropertyInfo returned = {
        .type = returned_type, .name = &empty_name, .class_name = &empty_name,
        .hint_string = &empty_hint, .usage = 6,
    };
    GDExtensionClassMethodInfo info = {
        .name = &method_name, .method_userdata = (void *)(uintptr_t)method,
        .call_func = method_call, .ptrcall_func = method_ptrcall,
        .method_flags = GDEXTENSION_METHOD_FLAG_NORMAL,
        .has_return_value = returned_type != GDEXTENSION_VARIANT_TYPE_NIL,
        .return_value_info = &returned,
    };
    if (method == METHOD_IS_HELD || method == METHOD_RESOURCES) {
        info.method_flags |= GDEXTENSION_METHOD_FLAG_CONST;
    }
    register_method(library, &guard_class, &info);
    string_destroy(&empty_hint);
    string_name_destroy(&empty_name);
    string_name_destroy(&method_name);
}

static void decode_decimal(const String *source, Dictionary *result) {
    dictionary_new(result, NULL);
    set_bool(result, "ok", 0);
    int64_t length = string_to_utf8(source, NULL, 0);
    if (!numeric_locale || !decode_numeric_decimal || length <= 0 || length > 128) {
        set_string(result, "error", "Decimal decoder unavailable or token out of bounds");
        return;
    }
    char token[129];
    string_to_utf8(source, token, length);
    token[length] = '\0';
    char *end = NULL;
    double value = decode_numeric_decimal(token, &end, numeric_locale);
    if (end != token + length || !isfinite(value)) {
        set_string(result, "error", "Decimal token is not a finite number");
        return;
    }
    dictionary_set(result, "value", variant_from_float, &value);
    set_bool(result, "ok", 1);
}

static void decimal_call(void *userdata, GDExtensionClassInstancePtr instance,
        const GDExtensionConstVariantPtr *args, GDExtensionInt count,
        GDExtensionVariantPtr returned, GDExtensionCallError *call_error) {
    (void)userdata;
    (void)instance;
    call_error->error = GDEXTENSION_CALL_OK;
    call_error->argument = 0;
    call_error->expected = GDEXTENSION_VARIANT_TYPE_STRING;
    variant_destroy(returned);
    if (count != 1 || variant_get_type(args[0]) != GDEXTENSION_VARIANT_TYPE_STRING) {
        call_error->error = count < 1 ? GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS :
                count > 1 ? GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS : GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;
        variant_new_nil(returned);
        return;
    }
    String source;
    string_from_variant(&source, (GDExtensionVariantPtr)args[0]);
    Dictionary result;
    decode_decimal(&source, &result);
    variant_from_dictionary(returned, &result);
    dictionary_destroy(&result);
    string_destroy(&source);
}

static void decimal_ptrcall(void *userdata, GDExtensionClassInstancePtr instance,
        const GDExtensionConstTypePtr *args, GDExtensionTypePtr returned) {
    (void)userdata;
    (void)instance;
    Dictionary result;
    decode_decimal(args[0], &result);
    const GDExtensionConstTypePtr copy_args[] = { &result };
    dictionary_destroy(returned);
    dictionary_copy(returned, copy_args);
    dictionary_destroy(&result);
}

static void bind_decimal_decoder(void) {
    numeric_runtime = LoadLibraryExW(L"ucrtbase.dll", NULL, LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (numeric_runtime) {
        FARPROC raw_create = GetProcAddress(numeric_runtime, "_create_locale");
        FARPROC raw_free = GetProcAddress(numeric_runtime, "_free_locale");
        FARPROC raw_decode = GetProcAddress(numeric_runtime, "_strtod_l");
        CreateLocale create_locale;
        memcpy(&create_locale, &raw_create, sizeof(create_locale));
        memcpy(&free_numeric_locale, &raw_free, sizeof(free_numeric_locale));
        memcpy(&decode_numeric_decimal, &raw_decode, sizeof(decode_numeric_decimal));
        if (create_locale && free_numeric_locale && decode_numeric_decimal) {
            numeric_locale = create_locale(LC_NUMERIC, "C");
        }
    }
    string_name_new(&numbers_class, "PlatformJsonNumbers");
    GDExtensionClassCreationInfo6 class_info = { .is_exposed = 1, .is_abstract = 1 };
    register_class(library, &numbers_class, &parent_class, &class_info);
    StringName method_name, argument_name, empty_name;
    String empty_hint;
    string_name_new(&method_name, "decode_decimal");
    string_name_new(&argument_name, "source");
    string_name_new(&empty_name, "");
    string_new(&empty_hint, "");
    GDExtensionPropertyInfo returned = { .type = GDEXTENSION_VARIANT_TYPE_DICTIONARY,
        .name = &empty_name, .class_name = &empty_name, .hint_string = &empty_hint, .usage = 6 };
    GDExtensionPropertyInfo argument = { .type = GDEXTENSION_VARIANT_TYPE_STRING,
        .name = &argument_name, .class_name = &empty_name, .hint_string = &empty_hint, .usage = 6 };
    GDExtensionClassMethodArgumentMetadata metadata = GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
    GDExtensionClassMethodInfo method = { .name = &method_name,
        .call_func = decimal_call, .ptrcall_func = decimal_ptrcall,
        .method_flags = GDEXTENSION_METHOD_FLAG_NORMAL | GDEXTENSION_METHOD_FLAG_STATIC,
        .has_return_value = 1, .return_value_info = &returned,
        .argument_count = 1, .arguments_info = &argument, .arguments_metadata = &metadata };
    register_method(library, &numbers_class, &method);
    string_destroy(&empty_hint);
    string_name_destroy(&empty_name);
    string_name_destroy(&argument_name);
    string_name_destroy(&method_name);
}

#include "platform_sqlite.h"

static void initialize(void *userdata, GDExtensionInitializationLevel level) {
    (void)userdata;
    if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
    StringName os_class, directory_name, object_class, notification_name;
    string_name_new(&guard_class, "PlatformSessionGuard");
    string_name_new(&parent_class, "RefCounted");
    string_name_new(&os_class, "OS");
    string_name_new(&directory_name, "get_user_data_dir");
    string_name_new(&object_class, "Object");
    string_name_new(&notification_name, "notification");
    os_singleton = get_singleton(&os_class);
    user_dir_method = (GDExtensionMethodBindPtr)get_method_bind(&os_class, &directory_name, OGH_USER_DIR_HASH);
    notification_method = (GDExtensionMethodBindPtr)get_method_bind(&object_class, &notification_name, OGH_NOTIFICATION_HASH);
    GDExtensionClassCreationInfo6 info = {
        .is_exposed = 1, .create_instance_func = guard_create, .free_instance_func = guard_free,
    };
    register_class(library, &guard_class, &parent_class, &info);
    bind_method("acquire", METHOD_ACQUIRE, GDEXTENSION_VARIANT_TYPE_DICTIONARY);
    bind_method("release", METHOD_RELEASE, GDEXTENSION_VARIANT_TYPE_NIL);
    bind_method("is_held", METHOD_IS_HELD, GDEXTENSION_VARIANT_TYPE_BOOL);
    bind_method("get_resource_status", METHOD_RESOURCES, GDEXTENSION_VARIANT_TYPE_DICTIONARY);
    bind_decimal_decoder();
    bind_sqlite();
    ogh_math_initialize(platform_api, library);
    string_name_destroy(&notification_name);
    string_name_destroy(&object_class);
    string_name_destroy(&directory_name);
    string_name_destroy(&os_class);
}

static void deinitialize(void *userdata, GDExtensionInitializationLevel level) {
    (void)userdata;
    if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
    ogh_math_deinitialize(platform_api);
    unregister_class(library, &guard_class);
    unregister_class(library, &numbers_class);
    unregister_class(library, &sqlite_class);
    string_name_destroy(&sqlite_class);
    string_name_destroy(&numbers_class);
    if (numeric_locale) free_numeric_locale(numeric_locale);
    if (numeric_runtime) FreeLibrary(numeric_runtime);
    numeric_locale = NULL;
    numeric_runtime = NULL;
    string_name_destroy(&parent_class);
    string_name_destroy(&guard_class);
}

#define LOAD_INTERFACE(type, variable, name) do { \
    GDExtensionInterfaceFunctionPtr raw = get_proc_address(name); \
    _Static_assert(sizeof(type) == sizeof(raw), "Windows x86_64 function pointer ABI"); \
    memcpy(&variable, &raw, sizeof(variable)); \
    if (!variable) return 0; \
} while (0)

__declspec(dllexport) GDExtensionBool oddly_good_platform_init(
        GDExtensionInterfaceGetProcAddress get_proc_address,
        GDExtensionClassLibraryPtr class_library, GDExtensionInitialization *initialization) {
    library = class_library;
    platform_api = get_proc_address;
    GDExtensionInterfaceGetGodotVersion2 get_version;
    LOAD_INTERFACE(GDExtensionInterfaceGetGodotVersion2, get_version, "get_godot_version2");
    GDExtensionGodotVersion2 version;
    get_version(&version);
    if (version.major != 4 || version.minor != 7 || version.patch != 2) return 0;
    LOAD_INTERFACE(GDExtensionInterfaceStringNameNewWithUtf8Chars, string_name_new, "string_name_new_with_utf8_chars");
    LOAD_INTERFACE(GDExtensionInterfaceStringNewWithUtf8Chars, string_new, "string_new_with_utf8_chars");
    LOAD_INTERFACE(GDExtensionInterfaceStringToUtf16Chars, string_to_utf16, "string_to_utf16_chars");
    LOAD_INTERFACE(GDExtensionInterfaceStringToUtf8Chars, string_to_utf8, "string_to_utf8_chars");
    LOAD_INTERFACE(GDExtensionInterfaceVariantGetType, variant_get_type, "variant_get_type");
    LOAD_INTERFACE(GDExtensionInterfaceVariantDestroy, variant_destroy, "variant_destroy");
    LOAD_INTERFACE(GDExtensionInterfaceVariantNewNil, variant_new_nil, "variant_new_nil");
    LOAD_INTERFACE(GDExtensionInterfaceDictionaryOperatorIndex, dictionary_index, "dictionary_operator_index");
    LOAD_INTERFACE(GDExtensionInterfaceObjectSetInstance, object_set_instance, "object_set_instance");
    LOAD_INTERFACE(GDExtensionInterfaceObjectMethodBindPtrcall, object_ptrcall, "object_method_bind_ptrcall");
    LOAD_INTERFACE(GDExtensionInterfaceClassdbConstructObject3, construct_object, "classdb_construct_object3");
    LOAD_INTERFACE(GDExtensionInterfaceClassdbRegisterExtensionClass6, register_class, "classdb_register_extension_class6");
    LOAD_INTERFACE(GDExtensionInterfaceClassdbRegisterExtensionClassMethod, register_method, "classdb_register_extension_class_method");
    LOAD_INTERFACE(GDExtensionInterfaceClassdbUnregisterExtensionClass, unregister_class, "classdb_unregister_extension_class");
    LOAD_INTERFACE(GDExtensionInterfaceClassdbGetMethodBind, get_method_bind, "classdb_get_method_bind");
    LOAD_INTERFACE(GDExtensionInterfaceGlobalGetSingleton, get_singleton, "global_get_singleton");
    GDExtensionInterfaceVariantGetPtrConstructor get_constructor;
    GDExtensionInterfaceVariantGetPtrDestructor get_destructor;
    GDExtensionInterfaceGetVariantFromTypeConstructor get_from_type;
    GDExtensionInterfaceGetVariantToTypeConstructor get_to_type;
    LOAD_INTERFACE(GDExtensionInterfaceVariantGetPtrConstructor, get_constructor, "variant_get_ptr_constructor");
    LOAD_INTERFACE(GDExtensionInterfaceVariantGetPtrDestructor, get_destructor, "variant_get_ptr_destructor");
    LOAD_INTERFACE(GDExtensionInterfaceGetVariantFromTypeConstructor, get_from_type, "get_variant_from_type_constructor");
    LOAD_INTERFACE(GDExtensionInterfaceGetVariantToTypeConstructor, get_to_type, "get_variant_to_type_constructor");
    dictionary_new = get_constructor(GDEXTENSION_VARIANT_TYPE_DICTIONARY, 0);
    dictionary_copy = get_constructor(GDEXTENSION_VARIANT_TYPE_DICTIONARY, 1);
    string_default = get_constructor(GDEXTENSION_VARIANT_TYPE_STRING, 0);
    dictionary_destroy = get_destructor(GDEXTENSION_VARIANT_TYPE_DICTIONARY);
    string_destroy = get_destructor(GDEXTENSION_VARIANT_TYPE_STRING);
    string_name_destroy = get_destructor(GDEXTENSION_VARIANT_TYPE_STRING_NAME);
    variant_from_bool = get_from_type(GDEXTENSION_VARIANT_TYPE_BOOL);
    variant_from_int = get_from_type(GDEXTENSION_VARIANT_TYPE_INT);
    variant_from_string = get_from_type(GDEXTENSION_VARIANT_TYPE_STRING);
    variant_from_dictionary = get_from_type(GDEXTENSION_VARIANT_TYPE_DICTIONARY);
    variant_from_float = get_from_type(GDEXTENSION_VARIANT_TYPE_FLOAT);
    string_from_variant = get_to_type(GDEXTENSION_VARIANT_TYPE_STRING);
    if (!load_sqlite_api(get_proc_address, get_constructor, get_destructor, get_from_type, get_to_type)) return 0;
    initialization->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
    initialization->userdata = NULL;
    initialization->initialize = initialize;
    initialization->deinitialize = deinitialize;
    return 1;
}
