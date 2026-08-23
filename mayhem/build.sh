#!/usr/bin/env bash
#
# mayhem/build.sh — build shecc's Mayhem fuzz target AND its upstream test oracle.
#
# shecc is a self-hosting C compiler. The Mayhem target is the stage-0 compiler itself,
# `out/shecc`, fed an arbitrary C source file (the classic file-input CLI target — it exercises
# the whole lexer/preprocessor/parser/SSA/codegen/ELF pipeline).
#
#   (1) FUZZ TARGET  — the project built with $SANITIZER_FLAGS + $DEBUG_FLAGS so the fuzzed
#                      compiler is instrumented (ASan+UBSan, halting) and carries DWARF < 4.
#                      Lands at $SRC/out/shecc (referenced by mayhem/Mayhemfile).
#   (2) TEST ORACLE  — a separate CLEAN build (upstream's normal flags) in $SRC/.oracle so
#                      mayhem/test.sh only RUNS `make check` (the full upstream suite). It is
#                      built with normal flags because shecc has benign UB during self-bootstrap
#                      that upstream's non-halting check-sanitizer tolerates but our halting
#                      UBSan aborts on — so the oracle must not use the sanitized binary.
set -euo pipefail

# clang rejects an empty SOURCE_DATE_EPOCH — unset it if blank.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}"
: "${MAYHEM_JOBS:=$(nproc)}"
export CC MAYHEM_JOBS

cd "$SRC"

# --- (1) FUZZ TARGET: sanitized + DWARF<4 stage-0 compiler ------------------------------------
# shecc's Makefile computes CFLAGS internally (it appends a curated set of -W flags), so we inject
# the sanitizer + DWARF flags through a CC wrapper instead of overriding CFLAGS on the make line
# (which would wipe the project's own flags). LDFLAGS carries the sanitizer runtime to the link.
#
# ABORT SHIM (additive, fuzz build only): shecc reports every invalid/unsupported C input via
# fatal()/error_at()/internal-invariant checks that call abort() -> SIGABRT. Under Mayhem that
# reads as "crashes on basic inputs" (has_critical_errors) and turns every malformed fuzz input
# into noise. We redirect shecc's OWN abort() call-sites to a clean exit(1) with a compile-time
# macro + a tiny shim TU (mayhem/shecc_abort_shim.h). This touches neither the ASan/UBSan runtime
# (real memory/UB bugs still halt via the sanitizer's own Die()) nor shecc's embedded target libc
# (inlined as __c("...") string literals), and valid C still compiles to an ELF. No upstream file
# is modified. Applied ONLY to this fuzz build; the clean test oracle below is unaffected.
ABORT_SHIM="${SRC}/mayhem/shecc_abort_shim.h"
FUZZ_REJECT_FLAGS="-include ${ABORT_SHIM} -Dabort=shecc_fuzz_reject"
cat > /tmp/shecc-cc <<EOF
#!/bin/sh
exec ${CC} ${SANITIZER_FLAGS} ${DEBUG_FLAGS} ${FUZZ_REJECT_FLAGS} "\$@"
EOF
chmod +x /tmp/shecc-cc

# GENERATED-HEADER ORDERING (race fix): src/main.c does `#include "../out/libc.inc"`, a file the
# Makefile generates (tools/norm-lf + tools/inliner over lib/c.c, lib/c.h). Before upstream eb947f5
# ("State the generated files an object compile needs", which gives `$(OUT)/%.o: %.c` the
# order-only prerequisites `| config $(OUT)/libc.inc`) the object rule had no prerequisite on it —
# out/libc.inc was only a sibling prerequisite of the stage-0 link — and the only other edge (the
# -MMD .d files) is deleted by `make distclean` / `git clean -ffdX`. A cold `make -jN` (N>=2) then
# lets the main.o compile race the generator, and on a slow/loaded host it fails with
# "src/main.c:50:10: fatal error: '../out/libc.inc' file not found" — a charged build error for a
# patch that cannot touch the Makefile. So the layer does not depend on which side of eb947f5 the
# base is on, we generate out/libc.inc in its own make invocation (with the same CC/LDFLAGS as the
# build that follows, so the outputs are identical) BEFORE each parallel make. It is still an
# ordinary make target, so an edit to lib/c.c or lib/c.h regenerates it. On a base that already
# carries eb947f5 the step only makes explicit the order the Makefile itself declares.
make distclean >/dev/null 2>&1 || true
make config ARCH=arm
make out/libc.inc CC=/tmp/shecc-cc LDFLAGS="${SANITIZER_FLAGS}" -j"${MAYHEM_JOBS}"
make out/shecc CC=/tmp/shecc-cc LDFLAGS="${SANITIZER_FLAGS}" -j"${MAYHEM_JOBS}"
test -x out/shecc

# --- (2) TEST ORACLE: clean upstream build for the functional suite ---------------------------
ORACLE="$SRC/.oracle"
rm -rf "$ORACLE"
mkdir -p "$ORACLE"
# Copy the source tree (minus .git / out / the oracle itself) into a sibling build dir.
tar --exclude=./.git --exclude=./out --exclude=./.oracle -cf - . | ( cd "$ORACLE" && tar -xf - )
cd "$ORACLE"
make config ARCH=arm
# Build stage0 + stage1 + stage2 with the project's NORMAL flags (upstream default: clang -O -g).
# `make check` in test.sh then just compiles+runs the test programs against these prebuilt stages.
# out/libc.inc first, in its own make invocation — same race fix as the fuzz build above.
make out/libc.inc -j"${MAYHEM_JOBS}"
make bootstrap -j"${MAYHEM_JOBS}"
test -x out/shecc && test -f out/shecc-stage2.elf
cd "$SRC"

echo "build.sh: fuzz target ($SRC/out/shecc) and test oracle ($ORACLE) built OK"
