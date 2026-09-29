/*
 * mayhem/shecc_zalloc_shim.h - additive, mayhem-only scaffolding. NOT an upstream edit.
 *
 * global_init() (src/globals.c) populates every one of shecc's arena-style globals
 * (FUNC_TRIES among them) with plain malloc(), relying on the root trie node's `next[]`
 * array reading back as zero. A vanilla (non-sanitized) build gets that for free: glibc
 * malloc() satisfies a first-touch allocation this large (MAX_FUNC_TRIES * sizeof(trie_t))
 * straight from a fresh mmap, which the kernel zero-fills. ASan's allocator does not give
 * the same guarantee - it can hand back memory carrying its own non-zero bookkeeping/fill
 * pattern - so under `-fsanitize=address` insert_trie() (src/globals.c:97) reads that
 * leftover byte, follows it as a trie-node index, and SEGVs on literally any input
 * containing a one-char function name: `int main(){return 0;}` included. Every one of the
 * original run's crashers lands on this single, build-dependent crash before the input
 * ever reaches the bug it originally tripped - one defect masks the other sixteen.
 *
 * Fix: redirect shecc's OWN calls to malloc() to a zero-filling allocator, restoring the
 * zero-initialized-arena behavior the original (unsanitized) binary had implicitly, via a
 * compile-time text substitution (-Dmalloc=shecc_fuzz_zalloc) applied ONLY to the sanitized
 * fuzz build. It modifies no upstream source file and leaves the ASan/UBSan runtime itself
 * untouched - real memory/undefined-behaviour bugs still halt via the sanitizer's own Die()
 * path; this only removes one build artifact that is not part of shecc's logic.
 */
#ifndef SHECC_FUZZ_ZALLOC_SHIM_H
#define SHECC_FUZZ_ZALLOC_SHIM_H

#include <stdlib.h>

/* Defined once: main.c is a single translation unit that #includes the rest of shecc. */
void *shecc_fuzz_zalloc(size_t size)
{
    return calloc(1, size);
}

#endif /* SHECC_FUZZ_ZALLOC_SHIM_H */
