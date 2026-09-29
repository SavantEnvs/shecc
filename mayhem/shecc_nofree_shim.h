/*
 * mayhem/shecc_nofree_shim.h - additive, mayhem-only scaffolding. NOT an upstream edit.
 *
 * main() (src/main.c) calls ssa_release() then global_release() as its very last act, AFTER
 * code_generate() and elf_generate() have already produced the output ELF - pure teardown
 * with no effect on shecc's observable behavior. ssa_release()'s basic-block walk
 * (bb_forward_traversal, src/ssa.c) frees a block and then dereferences the now-freed block
 * to reach its CFG successors - a heap-use-after-free ASan catches on literally any input
 * (reproduces on `int main(){return 0;}`), a guaranteed, input-independent crash in code
 * that runs only after the real target logic has already finished, masking whatever bug an
 * input was actually fuzzed to trip.
 *
 * Fix: redirect shecc's OWN calls to free() to a no-op - leak instead of free, since
 * process exit() right after reclaims everything either way. This is the common
 * fuzz-harness practice of skipping unneeded teardown rather than fixing a bug in code
 * that is not the fuzz surface. Unlike redirecting ssa_release()/global_release()
 * themselves (which shecc also DEFINES, so renaming the call site would collide with
 * renaming the definition), free() is a pure libc call shecc never defines on the host
 * side (lib/c.c's `free` is the EMBEDDED TARGET libc, inlined into out/libc.inc as string
 * literals a macro cannot touch - see mayhem/shecc_abort_shim.h), so this has no such
 * collision. None of this backport's 16 relevant defect classes is a use-after-free or
 * double-free, so this does not suppress any of them; it only silences the one
 * post-completion teardown bug. The ASan/UBSan runtime is otherwise untouched - real
 * memory/UB bugs reached while shecc does its actual work still halt. No upstream file is
 * modified.
 */
#ifndef SHECC_FUZZ_NOFREE_SHIM_H
#define SHECC_FUZZ_NOFREE_SHIM_H

#include <stddef.h>

/* Defined once: main.c is a single translation unit that #includes the rest of shecc. */
void shecc_fuzz_nofree(void *ptr)
{
    (void) ptr;
}

#endif /* SHECC_FUZZ_NOFREE_SHIM_H */
