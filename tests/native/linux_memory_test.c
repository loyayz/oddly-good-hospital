#define _POSIX_C_SOURCE 200809L
#include "../../game/platform/linux/platform_memory.h"
#include <assert.h>

struct entry { const char *path; const char *data; int error; };
struct fixture { struct entry e[32]; int size; int membership_reads; int mutate; };
static void put(struct fixture *f, const char *path, const char *data, int error)
{
    int i;
    for (i = 0; i < f->size; ++i) if (!strcmp(path, f->e[i].path)) break;
    if (i == f->size) ++f->size;
    assert(f->size <= 32);
    f->e[i].path = path; f->e[i].data = data; f->e[i].error = error;
}
static int fixture_read(void *ctx, const char *path, char *out, size_t cap)
{
    struct fixture *f = ctx;
    int i;
    if (!strcmp(path, "/proc/self/cgroup") && ++f->membership_reads == 2 && f->mutate) return EAGAIN;
    for (i = 0; i < f->size; ++i) if (!strcmp(path, f->e[i].path)) {
        if (f->e[i].error) return f->e[i].error;
        if (strlen(f->e[i].data) >= cap) return EOVERFLOW;
        strcpy(out, f->e[i].data); return 0;
    }
    return ENOENT;
}
static struct fixture base(int v)
{
    struct fixture f = {0};
    put(&f, "/proc/self/ns/cgroup", "cgroup:[4026531835]", 0);
    put(&f, "/proc/meminfo", "MemTotal: 10000 kB\nMemAvailable: 10 kB\n", 0);
    put(&f, "/proc/self/cgroup", v == 2 ? "0::/a/b\n" : "4:cpu,cpuacct:/x\n5:memory:/a/b\n0::/elsewhere\n", 0);
    put(&f, "/proc/self/mountinfo", v == 2 ?
        "1 0 0:1 / / rw - overlay overlay rw\n2 1 0:2 / /cg rw - cgroup2 cgroup rw\n" :
        "1 0 0:1 / / rw - overlay overlay rw\n2 1 0:2 / /cg rw - cgroup cgroup rw,memory\n", 0);
    if (v == 2) {
        put(&f, "/cg/cgroup.controllers", "cpu memory io\n", 0);
        put(&f, "/cg/a/b/memory.max", "9000\n", 0);
        put(&f, "/cg/a/b/memory.current", "1000\n", 0);
        put(&f, "/cg/a/memory.max", "10000\n", 0);
        put(&f, "/cg/a/memory.current", "7000\n", 0);
    } else {
        put(&f, "/cg/a/b/memory.use_hierarchy", "1\n", 0);
        put(&f, "/cg/a/memory.use_hierarchy", "1\n", 0);
        put(&f, "/cg/memory.use_hierarchy", "1\n", 0);
        put(&f, "/cg/a/b/memory.limit_in_bytes", "9000\n", 0);
        put(&f, "/cg/a/b/memory.usage_in_bytes", "1000\n", 0);
        put(&f, "/cg/a/memory.limit_in_bytes", "10000\n", 0);
        put(&f, "/cg/a/memory.usage_in_bytes", "7000\n", 0);
        put(&f, "/cg/memory.limit_in_bytes", "9223372036854771712\n", 0);
        put(&f, "/cg/memory.usage_in_bytes", "1000000\n", 0);
    }
    return f;
}
static int count;
static void expect(struct fixture f, int error, uint64_t value, const char *name)
{
    uint64_t actual = 123;
    char message[256];
    int result = ogh_linux_memory_query(fixture_read, &f, &actual, message, sizeof(message));
    if ((error ? !result : result) || actual != value || (result && !*message)) {
        fprintf(stderr, "FAIL %s: errno=%d bytes=%llu message=%s\n", name, result, (unsigned long long)actual, message);
        exit(1);
    }
    ++count;
}
int main(void)
{
    struct fixture f;
    int v;
    for (v = 1; v <= 2; ++v) {
        f = base(v); expect(f, 0, 3000, "ancestor wins");
        put(&f, "/proc/meminfo", "MemAvailable: 1 kB\n", 0); expect(f, 0, 1024, "host minimum");
        f = base(v); put(&f, v == 2 ? "/cg/a/b/memory.current" : "/cg/a/b/memory.usage_in_bytes", "9000\n", 0); expect(f, 0, 0, "usage equals limit");
        f = base(v); put(&f, v == 2 ? "/cg/a/memory.current" : "/cg/a/memory.usage_in_bytes", "11000\n", 0); expect(f, 0, 0, "ancestor exceeds limit");
        f = base(v); put(&f, v == 2 ? "/cg/a/memory.max" : "/cg/a/memory.limit_in_bytes", NULL, ENOENT); expect(f, 1, 0, "missing ancestor limit");
        f = base(v); put(&f, v == 2 ? "/cg/a/memory.current" : "/cg/a/memory.usage_in_bytes", NULL, EACCES); expect(f, 1, 0, "unreadable ancestor usage");
        f = base(v); put(&f, v == 2 ? "/cg/a/memory.max" : "/cg/a/memory.limit_in_bytes", "-1\n", 0); expect(f, 1, 0, "negative limit");
        f = base(v); put(&f, v == 2 ? "/cg/a/memory.max" : "/cg/a/memory.limit_in_bytes", "18446744073709551616\n", 0); expect(f, 1, 0, "limit overflow");
        f = base(v); put(&f, v == 2 ? "/cg/a/memory.max" : "/cg/a/memory.limit_in_bytes", "18446744073709551615\n", 0);
        put(&f, v == 2 ? "/cg/a/memory.current" : "/cg/a/memory.usage_in_bytes", "18446744073709551615\n", 0); expect(f, 0, 0, "numeric max is finite");
    }
#define BAD(path, data, err, name) do { f = base(2); put(&f, path, data, err); expect(f, 1, 0, name); } while (0)
    BAD("/proc/self/ns/cgroup", "cgroup:[4026533000]", 0, "hidden namespace ancestors");
    BAD("/proc/self/ns/cgroup", NULL, EACCES, "namespace unreadable");
    BAD("/proc/self/cgroup", NULL, EACCES, "membership unreadable");
    BAD("/proc/self/cgroup", "", 0, "membership empty");
    BAD("/proc/self/cgroup", "0::/a/../b\n", 0, "path traversal");
    BAD("/proc/self/cgroup", "0::/a//b\n", 0, "empty component");
    BAD("/proc/self/cgroup", "0::/a/.\n", 0, "dot component");
    BAD("/proc/self/cgroup", "0::/a/b", 0, "membership truncated");
    BAD("/proc/self/cgroup", "0::/a/b\n0::/\n", 0, "duplicate unified membership");
    BAD("/proc/self/cgroup", "5:memory:/a\n6:memory:/b\n", 0, "duplicate memory membership");
    BAD("/proc/meminfo", "MemFree: 123 kB\n", 0, "no fallback to MemFree");
    BAD("/proc/meminfo", "MemAvailable: 18014398509481984 kB\n", 0, "host bytes overflow");
    BAD("/proc/meminfo", "MemAvailable: 1 MB\n", 0, "host invalid unit");
    BAD("/proc/meminfo", "MemAvailable: 1 kB\nMemAvailable: 1 kB\n", 0, "host duplicate");
    BAD("/proc/self/mountinfo", "", 0, "no mount");
    BAD("/proc/self/mountinfo", "1 0 0:1 / / rw - overlay overlay rw\n2 1 0:2 /hidden /cg rw - cgroup2 cgroup rw\n", 0, "subtree mount hides ancestors");
    BAD("/proc/self/mountinfo", "1 0 0:1 / / rw - overlay overlay rw\n2 1 0:2 / /cg rw - cgroup2 cgroup rw\n3 2 0:3 / /cg/a rw - tmpfs tmpfs rw\n", 0, "nested mount masks hierarchy");
    BAD("/proc/self/mountinfo", "1 0 0:1 / / rw - overlay overlay rw\n2 1 0:2 / /cg rw - cgroup2 cgroup rw\n3 2 0:3 / /cg rw - tmpfs tmpfs rw\n", 0, "same-point overmount");
    BAD("/proc/self/mountinfo", "garbage\n", 0, "malformed mount");
    BAD("/cg/cgroup.controllers", "cpu io\n", 0, "memory controller invisible");
    BAD("/cg/a/memory.current", "2garbage\n", 0, "malformed usage");
    BAD("/proc/self/mountinfo", "1 0 0:1 / / rw - overlay overlay rw\n2 1 0:2 / /cg rw - cgroup2 cgroup rw\n3 2 0:3 /sub /cg rw - cgroup2 cgroup rw\n", 0, "subtree overmount");
    BAD("/proc/self/mountinfo", "bad 1 0:2 / /cg rw - cgroup2 cgroup rw\n", 0, "malformed mount id");
    BAD("/proc/self/mountinfo", "1 0 0:1 / / rw - overlay overlay rw\n2 1 0:2 / /cg\\999 rw - cgroup2 cgroup rw\n", 0, "invalid escape");
    BAD("/proc/self/mountinfo", NULL, EACCES, "mountinfo unreadable");
    BAD("/proc/self/cgroup", "7:cpu:/x\n", 0, "no proven memory membership");
    BAD("/cg/a/memory.max", NULL, EACCES, "unreadable limit");
    BAD("/cg/a/memory.current", NULL, ENOENT, "missing usage");
    BAD("/cg/a/memory.max", "max garbage\n", 0, "malformed max");
    BAD("/cg/cgroup.controllers", NULL, ENOENT, "missing controllers");
    {
        char huge[OGH_MEM_PATH_CAP + 32];
        memset(huge, 'a', sizeof(huge)); memcpy(huge, "0::/", 4);
        huge[sizeof(huge) - 2] = '\n'; huge[sizeof(huge) - 1] = 0;
        BAD("/proc/self/cgroup", huge, 0, "membership exceeds path bound");
    }
    f = base(1); put(&f, "/cg/memory.use_hierarchy", NULL, ENOENT); expect(f, 1, 0, "missing v1 root hierarchy");
    f = base(2); f.mutate = 1; expect(f, 1, 0, "membership changed");
    f = base(1); put(&f, "/cg/a/memory.use_hierarchy", "0\n", 0); expect(f, 1, 0, "v1 disabled hierarchy");
    f = base(1); put(&f, "/cg/memory.limit_in_bytes", "1001000\n", 0); expect(f, 0, 1000, "v1 root constrains");
    f = base(2); put(&f, "/cg/a/memory.max", "max\n", 0); expect(f, 0, 8000, "v2 unlimited ancestor");
    put(&f, "/cg/a/b/memory.max", "max\n", 0); expect(f, 0, 10240, "v2 all unlimited");
    f = base(1); put(&f, "/cg/a/memory.limit_in_bytes", "9223372036854771712\n", 0);
    put(&f, "/cg/a/b/memory.limit_in_bytes", "9223372036854771712\n", 0); expect(f, 0, 10240, "v1 unlimited sentinels conservatively numeric");
    f = base(2); put(&f, "/proc/self/cgroup", "0::/\n", 0); expect(f, 0, 10240, "initial namespace root host");
    f = base(2); put(&f, "/proc/self/mountinfo", "1 0 0:1 / / rw - overlay overlay rw\n2 1 0:2 / /my\\040cg rw shared:1 - cgroup2 cgroup rw\n", 0);
    put(&f, "/my cg/cgroup.controllers", "memory\n", 0);
    put(&f, "/my cg/a/b/memory.max", "9000\n", 0); put(&f, "/my cg/a/b/memory.current", "1000\n", 0);
    put(&f, "/my cg/a/memory.max", "10000\n", 0); put(&f, "/my cg/a/memory.current", "7000\n", 0); expect(f, 0, 3000, "escaped mountpoint");
    {
        char selected[OGH_MEM_PATH_CAP];
        const char *shadow = "1 0 0:1 / / rw - overlay overlay rw\n"
            "2 1 0:2 / /base/cg rw - cgroup2 cgroup rw\n"
            "3 1 0:3 / /base rw - tmpfs tmpfs rw\n";
        assert(ogh_mem_mounts(shadow, 2, selected) != 0); ++count;
        /* Even readable fake cgroup files under the replacement /base cannot
         * turn the failed mount-topology proof into a successful budget. */
        f = base(2); put(&f, "/proc/self/mountinfo", shadow, 0);
        put(&f, "/base/cg/cgroup.controllers", "memory\n", 0);
        put(&f, "/base/cg/a/b/memory.max", "9000\n", 0);
        put(&f, "/base/cg/a/b/memory.current", "1000\n", 0);
        put(&f, "/base/cg/a/memory.max", "10000\n", 0);
        put(&f, "/base/cg/a/memory.current", "7000\n", 0);
        expect(f, 1, 0, "ancestor shadow with readable lookalikes");
        put(&f, "/proc/self/mountinfo", "1 0 0:1 / / rw - overlay overlay rw\n"
            "3 1 0:3 / /base rw - tmpfs tmpfs rw\n"
            "2 3 0:2 / /base/cg rw - cgroup2 cgroup rw\n", 0);
        expect(f, 0, 3000, "genuine mounted ancestor chain");
        put(&f, "/proc/self/mountinfo", "2 3 0:2 / /base/cg rw - cgroup2 cgroup rw\n"
            "3 1 0:3 / /base rw - tmpfs tmpfs rw\n"
            "1 0 0:1 / / rw - overlay overlay rw\n", 0);
        expect(f, 0, 3000, "parent chain independent of record order");
        put(&f, "/proc/self/mountinfo", "1 0 0:1 / / rw - overlay overlay rw\n"
            "2 3 0:2 / /base/cg rw - cgroup2 cgroup rw\n"
            "3 1 0:3 / /base rw - tmpfs tmpfs rw\n"
            "4 1 0:4 / /base rw - tmpfs tmpfs rw\n", 0);
        expect(f, 1, 0, "competing ancestor mount");
    }
    f = base(2); put(&f, "/proc/self/mountinfo", "1 1 0:1 / / rw - rootfs rootfs rw\n2 1 0:2 / /cg rw - cgroup2 cgroup rw\n", 0);
    expect(f, 0, 3000, "self-parented namespace root");
    BAD("/proc/self/mountinfo", "1 0 0:1 / / rw - overlay overlay rw\n2 1 0:2 / /cg rw - cgroup2 cgroup rw\n1 0 0:3 / /other rw - tmpfs tmpfs rw\n", 0, "duplicate mount IDs");
    BAD("/proc/self/mountinfo", "1 3 0:1 / / rw - overlay overlay rw\n3 1 0:3 / / rw - tmpfs tmpfs rw\n2 1 0:2 / /cg rw - cgroup2 cgroup rw\n", 0, "cyclic mount parent");
    BAD("/proc/self/mountinfo", "2 999 0:2 / /cg rw - cgroup2 cgroup rw\n", 0, "missing non-root parent");
    BAD("/proc/self/mountinfo", "1 0 0:1 / /other rw - tmpfs tmpfs rw\n2 1 0:2 / /cg rw - cgroup2 cgroup rw\n", 0, "parent not path ancestor");
    { char message[256]; uint64_t available; int e = ogh_linux_available_memory(&available, message, sizeof(message));
      printf("REAL QUERY: errno=%d bytes=%llu %s\n", e, (unsigned long long)available, message);
      if (e) assert(available == 0); }
    printf("PASS: %d memory fixture cases\n", count);
    return 0;
}
