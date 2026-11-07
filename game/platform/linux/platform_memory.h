#ifndef OGH_LINUX_PLATFORM_MEMORY_H
#define OGH_LINUX_PLATFORM_MEMORY_H
/* Linux-only, fail-closed memory budget. No environment/API capacity overrides.
 * A full-root mount in the initial cgroup namespace is required: namespace roots
 * can hide constraining ancestors. Linux reserves inode 0xeffffffb for its initial
 * cgroup namespace (include/linux/proc_ns.h). Unknown kernels are rejected.
 * Reads are samples, not a reservation: concurrent allocations remain possible.
 */
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>

#define OGH_MEM_TEXT_CAP (128u * 1024u)
#define OGH_MEM_PATH_CAP 4096u
/* Internal reader seam used only by native tests. It returns errno values and
 * must fail rather than truncate. The namespace pseudo-file returns readlink. */
typedef int (*ogh_mem_reader)(void *, const char *, char *, size_t);

static int ogh_mem_error(char *message, size_t size, int error, const char *what)
{
    if (message && size) snprintf(message, size, "Linux memory visibility incomplete: %s (errno %d)", what, error);
    return error ? error : EINVAL;
}

static int ogh_mem_real_read(void *unused, const char *path, char *out, size_t cap)
{
    FILE *file;
    size_t n;
    int error = 0;
    (void)unused;
    if (cap < 2) return EOVERFLOW;
    if (strcmp(path, "/proc/self/ns/cgroup") == 0) {
        ssize_t len = readlink(path, out, cap - 1);
        if (len < 0) return errno;
        if ((size_t)len == cap - 1) return EOVERFLOW;
        out[len] = 0;
        return 0;
    }
    file = fopen(path, "r");
    if (!file) return errno;
    n = fread(out, 1, cap - 1, file);
    if (ferror(file)) error = errno ? errno : EIO;
    else if (!feof(file)) error = EOVERFLOW;
    if (memchr(out, 0, n)) error = EINVAL;
    out[n] = 0;
    if (fclose(file) && !error) error = errno ? errno : EIO;
    return error;
}

static int ogh_mem_uint(const char *s, uint64_t *value)
{
    uint64_t n = 0;
    if (!s || *s < '0' || *s > '9') return EINVAL;
    while (*s >= '0' && *s <= '9') {
        unsigned d = (unsigned)(*s++ - '0');
        if (n > (UINT64_MAX - d) / 10) return EOVERFLOW;
        n = n * 10 + d;
    }
    while (*s == '\n' || *s == ' ' || *s == '\t') ++s;
    if (*s) return EINVAL;
    *value = n;
    return 0;
}

static int ogh_mem_path_ok(const char *s)
{
    const char *start;
    if (*s++ != '/') return 0;
    if (!*s) return 1;
    for (;;) {
        start = s;
        while (*s && *s != '/') {
            if ((unsigned char)*s < 32 || *s == '\\') return 0;
            ++s;
        }
        if (s == start || (s - start == 1 && start[0] == '.') ||
            (s - start == 2 && start[0] == '.' && start[1] == '.')) return 0;
        if (!*s) return 1;
        ++s;
    }
}

static int ogh_mem_contains(const char *list, const char *item)
{
    size_t n = strlen(item);
    while (*list) {
        const char *end = strchr(list, ',');
        size_t len = end ? (size_t)(end - list) : strlen(list);
        if (len == n && !memcmp(list, item, n)) return 1;
        if (!end) break;
        list = end + 1;
    }
    return 0;
}

static int ogh_mem_decode(char *s)
{
    char *out = s;
    while (*s) {
        if (*s == '\\') {
            if (!strncmp(s, "\\040", 4)) *out++ = ' ';
            else if (!strncmp(s, "\\011", 4)) *out++ = '\t';
            else if (!strncmp(s, "\\012", 4)) *out++ = '\n';
            else if (!strncmp(s, "\\134", 4)) *out++ = '\\';
            else return EINVAL;
            s += 4;
        } else *out++ = *s++;
    }
    *out = 0;
    return 0;
}

static int ogh_mem_membership(char *text, char *path, int *version)
{
    char *line = text;
    int v1 = 0, v2 = 0;
    char unified[OGH_MEM_PATH_CAP] = "";
    if (!*line) return EINVAL;
    while (*line) {
        char *end = strchr(line, '\n'), *a, *b;
        uint64_t id;
        if (!end) return EINVAL;
        *end = 0;
        a = strchr(line, ':');
        if (!a) return EINVAL;
        *a++ = 0;
        b = strchr(a, ':');
        if (!b) return EINVAL;
        *b++ = 0;
        if (ogh_mem_uint(line, &id) || !ogh_mem_path_ok(b) || strlen(b) >= OGH_MEM_PATH_CAP) return EINVAL;
        if (id == 0) {
            if (*a || v2++) return EINVAL;
            strcpy(unified, b);
        } else {
            if (!*a) return EINVAL;
            if (ogh_mem_contains(a, "memory")) {
                if (v1++) return EINVAL;
                strcpy(path, b);
            }
        }
        line = end + 1;
    }
    if (v1) *version = 1;
    else if (v2) { *version = 2; strcpy(path, unified); }
    else return ENOTSUP; /* No proven memory hierarchy, never assume host-only. */
    return 0;
}

/* Split a mountinfo record. Optional fields precede the literal '-' field. */
static int ogh_mem_mount_line(char *line, char **root, char **point,
                              char **type, char **superopts, uint64_t *mount_id,
                              uint64_t *parent_id)
{
    char *fields[128];
    unsigned count = 0, dash = 0, i;
    while (*line) {
        if (count == 128 || *line == ' ') return EINVAL;
        fields[count++] = line;
        while (*line && *line != ' ') ++line;
        if (*line) *line++ = 0;
    }
    for (i = 6; i < count; ++i) if (!strcmp(fields[i], "-")) { dash = i; break; }
    if (!dash || count != dash + 4) return EINVAL;
    {
        uint64_t id;
        char *colon = strchr(fields[2], ':');
        if (ogh_mem_uint(fields[0], mount_id) || !*mount_id ||
            ogh_mem_uint(fields[1], parent_id) || !colon) return EINVAL;
        *colon = 0;
        if (ogh_mem_uint(fields[2], &id) || ogh_mem_uint(colon + 1, &id)) return EINVAL;
    }
    *root = fields[3]; *point = fields[4]; *type = fields[dash + 1]; *superopts = fields[dash + 3];
    if (ogh_mem_decode(*root) || ogh_mem_decode(*point) || !ogh_mem_path_ok(*root) || !ogh_mem_path_ok(*point)) return EINVAL;
    return 0;
}

static int ogh_mem_below(const char *path, const char *root)
{
    size_t n = strlen(root);
    return !strcmp(root, "/") || (!strncmp(path, root, n) && (!path[n] || path[n] == '/'));
}

static int ogh_mem_mounts(const char *original, int version, char *mount)
{
    struct record {
        uint64_t id, parent;
        char *root, *point, *type, *opts;
        int in_chain;
    } *records = NULL;
    char *copy = NULL, *line;
    size_t count = 0, capacity = 0, i, j, selected = 0, current;
    int found = 0, result = 0;
    for (line = (char *)original; *line; ++line) if (*line == '\n') ++capacity;
    if (!capacity) return ENOENT;
    copy = malloc(strlen(original) + 1);
    records = calloc(capacity, sizeof(*records));
    if (!copy || !records) { result = ENOMEM; goto done; }
    strcpy(copy, original);
    line = copy;
    while (*line) {
        char *end = strchr(line, '\n');
        struct record *r;
        int relevant;
        if (!end || count == capacity) { result = EINVAL; goto done; }
        *end = 0;
        r = &records[count];
        result = ogh_mem_mount_line(line, &r->root, &r->point, &r->type,
                                    &r->opts, &r->id, &r->parent);
        if (result) goto done;
        for (i = 0; i < count; ++i) if (records[i].id == r->id) { result = EINVAL; goto done; }
        relevant = version == 2 ? !strcmp(r->type, "cgroup2") :
            (!strcmp(r->type, "cgroup") && ogh_mem_contains(r->opts, "memory"));
        if (relevant && !strcmp(r->root, "/")) {
            if (++found != 1 || strlen(r->point) >= OGH_MEM_PATH_CAP) { result = ENOTSUP; goto done; }
            selected = count;
            strcpy(mount, r->point);
        }
        ++count;
        line = end + 1;
    }
    if (!found) { result = ENOENT; goto done; }
    /* Mountinfo parent IDs, not record order or mountpoint prefixes, determine
     * the visible ancestry. A later /base mount can hide /base/cg without
     * appearing below /base/cg. Refuse every competing ancestor conservatively. */
    current = selected;
    for (;;) {
        struct record *r = &records[current];
        if (r->in_chain) { result = EINVAL; goto done; }
        r->in_chain = 1;
        if (r->parent == r->id && !strcmp(r->point, "/")) break;
        for (j = 0; j < count; ++j) if (records[j].id == r->parent) break;
        if (j == count) {
            /* A mount namespace's root parent can be outside the visible list.
             * Missing parents below '/' do not prove a complete path. */
            if (strcmp(r->point, "/")) { result = ENOTSUP; goto done; }
            break;
        }
        if (!ogh_mem_below(r->point, records[j].point)) { result = EINVAL; goto done; }
        current = j;
    }
    for (i = 0; i < count; ++i) {
        if (i == selected) continue;
        if (ogh_mem_below(records[i].point, mount)) { result = ENOTSUP; goto done; }
        if (ogh_mem_below(mount, records[i].point) && !records[i].in_chain) { result = ENOTSUP; goto done; }
    }
done:
    free(records);
    free(copy);
    return result;
}

static int ogh_mem_host(char *text, uint64_t *value)
{
    char *line = text;
    int found = 0;
    while (*line) {
        char *end = strchr(line, '\n');
        if (!end) return EINVAL;
        *end = 0;
        if (!strncmp(line, "MemAvailable:", 13)) {
            char *number = line + 13, *unit;
            uint64_t kb;
            while (*number == ' ' || *number == '\t') ++number;
            unit = number;
            while (*unit >= '0' && *unit <= '9') ++unit;
            if (*unit != ' ' && *unit != '\t') return EINVAL;
            *unit++ = 0;
            while (*unit == ' ' || *unit == '\t') ++unit;
            if (strcmp(unit, "kB") || ogh_mem_uint(number, &kb) || kb > UINT64_MAX / 1024 || found++) return EINVAL;
            *value = kb * 1024;
        }
        line = end + 1;
    }
    return found ? 0 : ENOENT;
}

static int ogh_mem_file(ogh_mem_reader read_file, void *ctx, const char *dir,
                        const char *name, char *out, size_t cap)
{
    char path[OGH_MEM_PATH_CAP];
    int n = snprintf(path, sizeof(path), "%s/%s", !strcmp(dir, "/") ? "" : dir, name);
    if (n < 0 || (size_t)n >= sizeof(path)) return ENAMETOOLONG;
    return read_file(ctx, path, out, cap);
}

static int ogh_linux_memory_query(ogh_mem_reader reader, void *ctx,
                                  uint64_t *available, char *message, size_t message_size)
{
    char *text = NULL, *membership = NULL, *mountinfo = NULL;
    char member[OGH_MEM_PATH_CAP], mount[OGH_MEM_PATH_CAP], dir[OGH_MEM_PATH_CAP];
    char small[256];
    uint64_t budget = 0, limit, used, hierarchy;
    int version = 0, error = EINVAL, n;
    const char *stage = "invalid arguments";
    if (available) *available = 0;
    if (message && message_size) *message = 0;
    if (!available || !reader) goto done;
    text = malloc(OGH_MEM_TEXT_CAP); membership = malloc(OGH_MEM_TEXT_CAP); mountinfo = malloc(OGH_MEM_TEXT_CAP);
    if (!text || !membership || !mountinfo) { error = ENOMEM; goto done; }
#define OGH_MEM_TRY(call, description) do { stage = description; error = (call); if (error) goto done; } while (0)
    OGH_MEM_TRY(reader(ctx, "/proc/self/ns/cgroup", small, sizeof(small)), "cgroup namespace");
    if (strcmp(small, "cgroup:[4026531835]")) { error = ENOTSUP; stage = "non-initial cgroup namespace may hide ancestor limits"; goto done; }
    OGH_MEM_TRY(reader(ctx, "/proc/meminfo", text, OGH_MEM_TEXT_CAP), "MemAvailable read");
    OGH_MEM_TRY(ogh_mem_host(text, &budget), "MemAvailable parse");
    OGH_MEM_TRY(reader(ctx, "/proc/self/cgroup", membership, OGH_MEM_TEXT_CAP), "cgroup membership read");
    strcpy(text, membership);
    OGH_MEM_TRY(ogh_mem_membership(text, member, &version), "cgroup membership parse");
    OGH_MEM_TRY(reader(ctx, "/proc/self/mountinfo", mountinfo, OGH_MEM_TEXT_CAP), "mountinfo read");
    OGH_MEM_TRY(ogh_mem_mounts(mountinfo, version, mount), "complete, unmasked cgroup mount");
    n = snprintf(dir, sizeof(dir), "%s%s", !strcmp(mount, "/") ? "" : mount, !strcmp(member, "/") ? "" : member);
    if (!*dir) strcpy(dir, "/");
    if (n < 0 || (size_t)n >= sizeof(dir)) { error = ENAMETOOLONG; goto done; }
    if (version == 2) {
        OGH_MEM_TRY(ogh_mem_file(reader, ctx, mount, "cgroup.controllers", small, sizeof(small)), "root memory controller visibility");
        /* Controllers are whitespace-separated, unlike mount options. */
        { size_t i; for (i = 0; small[i]; ++i) if (small[i] == ' ' || small[i] == '\n' || small[i] == '\t') small[i] = ','; }
        if (!ogh_mem_contains(small, "memory")) { error = ENOTSUP; goto done; }
    }
    for (;;) {
        int at_root = !strcmp(dir, mount);
        int unlimited = 0;
        if (version == 2 && at_root) break; /* v2 root has no memory.max. */
        if (version == 1) {
            OGH_MEM_TRY(ogh_mem_file(reader, ctx, dir, "memory.use_hierarchy", small, sizeof(small)), "v1 hierarchy visibility");
            OGH_MEM_TRY(ogh_mem_uint(small, &hierarchy), "v1 hierarchy parse");
            if (hierarchy != 1) { error = ENOTSUP; stage = "v1 non-hierarchical accounting is unsupported"; goto done; }
        }
        OGH_MEM_TRY(ogh_mem_file(reader, ctx, dir, version == 2 ? "memory.max" : "memory.limit_in_bytes", small, sizeof(small)), "cgroup limit read");
        if (version == 2 && (!strcmp(small, "max\n") || !strcmp(small, "max"))) { limit = UINT64_MAX; unlimited = 1; }
        else OGH_MEM_TRY(ogh_mem_uint(small, &limit), "cgroup limit parse");
        OGH_MEM_TRY(ogh_mem_file(reader, ctx, dir, version == 2 ? "memory.current" : "memory.usage_in_bytes", small, sizeof(small)), "cgroup usage read");
        OGH_MEM_TRY(ogh_mem_uint(small, &used), "cgroup usage parse");
        if (!unlimited) {
            uint64_t left = used >= limit ? 0 : limit - used;
            if (left < budget) budget = left;
        }
        if (at_root) break;
        { char *slash = strrchr(dir, '/'); if (!slash) { error = EINVAL; goto done; } if (slash == dir) slash[1] = 0; else *slash = 0; }
        if (!ogh_mem_below(dir, mount)) { error = EINVAL; goto done; }
    }
    OGH_MEM_TRY(reader(ctx, "/proc/self/cgroup", text, OGH_MEM_TEXT_CAP), "membership recheck");
    if (strcmp(text, membership)) { error = EAGAIN; stage = "membership changed during sample"; goto done; }
    OGH_MEM_TRY(reader(ctx, "/proc/self/mountinfo", text, OGH_MEM_TEXT_CAP), "mount recheck");
    if (strcmp(text, mountinfo)) { error = EAGAIN; stage = "mounts changed during sample"; goto done; }
    OGH_MEM_TRY(reader(ctx, "/proc/self/ns/cgroup", small, sizeof(small)), "namespace recheck");
    if (strcmp(small, "cgroup:[4026531835]")) { error = EAGAIN; goto done; }
    *available = budget;
    error = 0;
done:
    free(text); free(membership); free(mountinfo);
    if (error) return ogh_mem_error(message, message_size, error, stage);
    return 0;
#undef OGH_MEM_TRY
}

static int ogh_linux_available_memory(uint64_t *available, char *message, size_t message_size)
{
    return ogh_linux_memory_query(ogh_mem_real_read, NULL, available, message, message_size);
}
#endif
