#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#include <stdio.h>
#include <string.h>

static SYSTEM_CPU_SET_INFORMATION rows[4];
static DWORD caller = 100;
static GROUP_AFFINITY allowed;
static int unavailable, set_failure, query_calls, set_calls;
static KAFFINITY applied_mask;
static DWORD WINAPI fake_thread_id(void) { return caller; }
static BOOL WINAPI fake_group(HANDLE thread, PGROUP_AFFINITY group) {
    (void)thread; *group = allowed; return TRUE;
}
static BOOL WINAPI fake_sets(PSYSTEM_CPU_SET_INFORMATION buffer, ULONG size,
        PULONG returned, HANDLE process, ULONG flags) {
    (void)process; (void)flags; ++query_calls;
    if (unavailable) { *returned = 0; SetLastError(ERROR_CALL_NOT_IMPLEMENTED); return FALSE; }
    *returned = sizeof(rows);
    if (size < sizeof(rows)) { SetLastError(ERROR_INSUFFICIENT_BUFFER); return FALSE; }
    memcpy(buffer, rows, sizeof(rows)); return TRUE;
}
static DWORD_PTR WINAPI fake_affinity(HANDLE thread, DWORD_PTR mask) {
    (void)thread; ++set_calls;
    if (set_failure) { SetLastError(ERROR_ACCESS_DENIED); return 0; }
    applied_mask = mask; return allowed.Mask;
}
#define GetCurrentThreadId fake_thread_id
#define GetThreadGroupAffinity fake_group
#define GetSystemCpuSetInformation fake_sets
#define SetThreadAffinityMask fake_affinity
#include "../../game/platform/windows/platform_thread_policy.h"

static void reset(void) {
    memset(rows, 0, sizeof(rows)); memset(&allowed, 0, sizeof(allowed));
    allowed.Mask = 15; caller = 100; unavailable = set_failure = query_calls = set_calls = 0; applied_mask = 0;
    for (int i = 0; i < 4; ++i) {
        rows[i].Size = sizeof(rows[i]); rows[i].Type = CpuSetInformation;
        rows[i].CpuSet.Id = (DWORD)(256+i); rows[i].CpuSet.CoreIndex = (BYTE)i;
        rows[i].CpuSet.LogicalProcessorIndex = (BYTE)i;
        rows[i].CpuSet.EfficiencyClass = i < 2 ? 1 : 0;
    }
}
int main(void) {
    OghThreadPolicyResult result;
    reset(); result = ogh_apply_main_thread_policy(100);
    assert(result.applied && result.hybrid && result.mask == 3 && applied_mask == 3 && set_calls == 1);
    reset(); for (int i = 0; i < 4; ++i) rows[i].CpuSet.EfficiencyClass = 0;
    result = ogh_apply_main_thread_policy(100);
    assert(!result.applied && !result.hybrid && !strcmp(result.reason,"homogeneous_cpu") && !set_calls);
    reset(); allowed.Mask = 12; result = ogh_apply_main_thread_policy(100);
    assert(!result.applied && !strcmp(result.reason,"no_performance_cpu_in_allowed_group") && !set_calls);
    reset(); allowed.Mask = 3; result = ogh_apply_main_thread_policy(100);
    assert(result.applied && !strcmp(result.reason,"already_performance") && !set_calls);
    reset(); rows[0].CpuSet.AllFlags = 2; result = ogh_apply_main_thread_policy(100);
    assert(result.applied && result.mask == 2 && applied_mask == 2);
    reset(); rows[0].CpuSet.AllFlags = 6; result = ogh_apply_main_thread_policy(100);
    assert(result.applied && result.mask == 3);
    reset(); allowed.Group = 1; allowed.Mask = 3;
    rows[2].CpuSet.Group = rows[3].CpuSet.Group = 1;
    rows[2].CpuSet.LogicalProcessorIndex = 0; rows[3].CpuSet.LogicalProcessorIndex = 1;
    result = ogh_apply_main_thread_policy(100);
    assert(!result.applied && !strcmp(result.reason,"no_performance_cpu_in_allowed_group") && !set_calls);
    reset(); unavailable = 1; result = ogh_apply_main_thread_policy(100);
    assert(!result.applied && result.error == ERROR_CALL_NOT_IMPLEMENTED && !set_calls);
    reset(); set_failure = 1; result = ogh_apply_main_thread_policy(100);
    assert(!result.applied && result.error == ERROR_ACCESS_DENIED && !applied_mask);
    reset(); result = ogh_apply_main_thread_policy(999);
    assert(!result.applied && !strcmp(result.reason,"not_main_thread") && !query_calls && !set_calls);
    reset(); rows[1].Size = 0; result = ogh_apply_main_thread_policy(100);
    assert(!result.applied && !strcmp(result.reason,"invalid_cpu_set_information") && !set_calls);
    puts("{\"cases\":11,\"failed\":0}");
    return 0;
}
