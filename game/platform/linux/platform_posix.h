/* Linux-only system boundary for the shared GDExtension C binding.
 * Windows branches keep the original Win32 implementation. These local aliases
 * preserve the shared binding's allocation/thread contracts, not Win32 errors. */
#ifndef OGH_PLATFORM_POSIX_H
#define OGH_PLATFORM_POSIX_H
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <locale.h>
#include <unistd.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <sys/syscall.h>
#include <time.h>
#include "platform_memory.h"
typedef int HANDLE;
typedef int DWORD;
typedef int LONG;
#define INVALID_HANDLE_VALUE (-1)
#define HEAP_ZERO_MEMORY 1
#define HeapAlloc(heap, flags, bytes) ((flags) ? calloc(1, (bytes)) : malloc(bytes))
#define HeapFree(heap, flags, ptr) free(ptr)
#define GetCurrentThreadId() ((DWORD)syscall(SYS_gettid))
#define InterlockedIncrement(ptr) __atomic_add_fetch((ptr), 1, __ATOMIC_SEQ_CST)
#define InterlockedDecrement(ptr) __atomic_sub_fetch((ptr), 1, __ATOMIC_SEQ_CST)
#define InterlockedCompareExchange(ptr, exchange, comparand) __atomic_load_n((ptr), __ATOMIC_SEQ_CST)
#define __cdecl
static void ogh_free_numeric_locale(void *value) { freelocale((locale_t)value); }
static double ogh_decode_numeric_decimal(const char *source, char **end, void *value) {
    return strtod_l(source, end, (locale_t)value);
}
#endif
