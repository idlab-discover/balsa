/* Linux/glibc diagnostic interposer. Never use its timings as latency evidence.
 * KGEN's ABI is (alignment, bytes); it bypasses libc through Mojo's TCMalloc.
 * Counters cover these exported call sites, not all internal allocator traffic.
 * Difference 1/11/21-iteration processes to remove setup and teardown costs.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdatomic.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>

extern void *__libc_malloc(size_t);
extern void *__libc_calloc(size_t, size_t);
extern void *__libc_realloc(void *, size_t);
extern void __libc_free(void *);
static _Atomic unsigned long long mc, cc, rc, fc, mb, kc, kf, kb;
static void *(*ka)(size_t, size_t);
static void (*kf_real)(void *);

void *malloc(size_t n) {
    atomic_fetch_add(&mc, 1);
    atomic_fetch_add(&mb, n);
    return __libc_malloc(n);
}
void *calloc(size_t n, size_t s) {
    atomic_fetch_add(&cc, 1);
    atomic_fetch_add(&mb, n * s);
    return __libc_calloc(n, s);
}
void *realloc(void *p, size_t n) {
    atomic_fetch_add(&rc, 1);
    atomic_fetch_add(&mb, n);
    return __libc_realloc(p, n);
}
void free(void *p) {
    if (p) atomic_fetch_add(&fc, 1);
    __libc_free(p);
}
__attribute__((constructor)) static void init(void) {
    /* The KGEN symbols are absent in the native Treelite process, which never
     * calls these two wrappers. Direct libc entry points avoid dlsym recursion.
     */
    ka = dlsym(RTLD_NEXT, "KGEN_CompilerRT_AlignedAlloc");
    kf_real = dlsym(RTLD_NEXT, "KGEN_CompilerRT_AlignedFree");
}
void *KGEN_CompilerRT_AlignedAlloc(size_t alignment, size_t bytes) {
    atomic_fetch_add(&kc, 1);
    atomic_fetch_add(&kb, bytes);
    return ka(alignment, bytes);
}
void KGEN_CompilerRT_AlignedFree(void *p) {
    if (p) atomic_fetch_add(&kf, 1);
    kf_real(p);
}
__attribute__((destructor)) static void report(void) {
    fprintf(stderr, "ALLOC {\"malloc\":%llu,\"calloc\":%llu,\"realloc\":%llu,"
        "\"free_nonnull\":%llu,\"libc_requested_bytes\":%llu,"
        "\"kgen_alloc\":%llu,\"kgen_free_nonnull\":%llu,\"kgen_requested_bytes\":%llu}\n",
        mc, cc, rc, fc, mb, kc, kf, kb);
}
