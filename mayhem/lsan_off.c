/*
 * mayhem/lsan_off.c - additive, mayhem-only scaffolding. NOT an upstream edit.
 *
 * Fleet policy: disable LeakSanitizer preventively (build-time only, ASan stays on) for
 * every ASan-built target, via a linked TU's __lsan_is_turned_off() hook, rather than
 * reacting to a specific known leak. Linked into the fuzz target only (mayhem/build.sh's
 * CC wrapper appends this object at link time); the clean test oracle is unaffected.
 */
int __lsan_is_turned_off(void)
{
    return 1;
}
