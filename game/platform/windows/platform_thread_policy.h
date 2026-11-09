#ifndef OGH_PLATFORM_THREAD_POLICY_H
#define OGH_PLATFORM_THREAD_POLICY_H

#include <stdint.h>
#include <stddef.h>
#include <limits.h>

typedef struct {
    int applied;
    int hybrid;
    uint32_t error;
    uint16_t group;
    uint64_t mask;
    const char *reason;
} OghThreadPolicyResult;

/* Only the calling main thread is changed. Process and worker affinities stay
 * owned by Windows. An unavailable performance subset leaves the original mask. */
static inline OghThreadPolicyResult ogh_apply_main_thread_policy(uint32_t main_thread_id) {
    OghThreadPolicyResult result = {0, 0, 0, 0, 0, "platform_default"};
#if defined(_WIN32)
    if (GetCurrentThreadId() != main_thread_id) {
        result.reason = "not_main_thread";
        return result;
    }
    GROUP_AFFINITY allowed;
    if (!GetThreadGroupAffinity(GetCurrentThread(), &allowed)) {
        result.reason = "thread_affinity_unavailable";
        result.error = GetLastError();
        return result;
    }
    result.group = allowed.Group;
    ULONG bytes = 0;
    GetSystemCpuSetInformation(NULL, 0, &bytes, GetCurrentProcess(), 0);
    if (!bytes) {
        result.reason = "cpu_sets_unavailable";
        result.error = GetLastError();
        return result;
    }
    BYTE *buffer = HeapAlloc(GetProcessHeap(), 0, bytes);
    if (!buffer) {
        result.reason = "allocation_failed";
        result.error = ERROR_NOT_ENOUGH_MEMORY;
        return result;
    }
    ULONG capacity = bytes;
    if (!GetSystemCpuSetInformation((PSYSTEM_CPU_SET_INFORMATION)buffer, capacity, &bytes, GetCurrentProcess(), 0)) {
        result.reason = "cpu_sets_unavailable";
        result.error = GetLastError();
        HeapFree(GetProcessHeap(), 0, buffer);
        return result;
    }
    BYTE lowest = UINT8_MAX, highest = 0;
    KAFFINITY selected = 0;
    unsigned records = 0;
    for (ULONG offset = 0; offset < bytes;) {
        if (bytes-offset < sizeof(DWORD)*2) { records = 0; break; }
        PSYSTEM_CPU_SET_INFORMATION info = (PSYSTEM_CPU_SET_INFORMATION)(buffer+offset);
        if (info->Size < sizeof(DWORD)*2 || info->Size > bytes-offset) { records = 0; break; }
        if (info->Type == CpuSetInformation) {
            if (info->Size < offsetof(SYSTEM_CPU_SET_INFORMATION, CpuSet.AllFlags)+sizeof(BYTE)) { records = 0; break; }
            BYTE efficiency = info->CpuSet.EfficiencyClass;
            if (efficiency < lowest) lowest = efficiency;
            if (efficiency > highest) { highest = efficiency; selected = 0; }
            ++records;
            BYTE logical = info->CpuSet.LogicalProcessorIndex;
            int allocated_elsewhere = (info->CpuSet.AllFlags & 2) && !(info->CpuSet.AllFlags & 4);
            if (efficiency == highest && info->CpuSet.Group == allowed.Group &&
                    logical < sizeof(KAFFINITY)*CHAR_BIT && !allocated_elsewhere) {
                KAFFINITY bit = (KAFFINITY)1 << logical;
                if (allowed.Mask & bit) selected |= bit;
            }
        }
        offset += info->Size;
    }
    HeapFree(GetProcessHeap(), 0, buffer);
    if (!records) { result.reason = "invalid_cpu_set_information"; return result; }
    result.hybrid = lowest != highest;
    if (!result.hybrid) { result.reason = "homogeneous_cpu"; return result; }
    if (!selected) { result.reason = "no_performance_cpu_in_allowed_group"; return result; }
    if (selected != allowed.Mask && !SetThreadAffinityMask(GetCurrentThread(), selected)) {
        result.reason = "set_affinity_failed";
        result.error = GetLastError();
        return result;
    }
    result.applied = 1;
    result.mask = (uint64_t)selected;
    result.reason = selected == allowed.Mask ? "already_performance" : "performance_cores";
#else
    (void)main_thread_id;
#endif
    return result;
}

#endif
