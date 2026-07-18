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
cat > /tmp/shecc-cc <<EOF
#!/bin/sh
exec ${CC} ${SANITIZER_FLAGS} ${DEBUG_FLAGS} "\$@"
EOF
chmod +x /tmp/shecc-cc

make distclean >/dev/null 2>&1 || true
make config ARCH=arm
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
make bootstrap -j"${MAYHEM_JOBS}"
test -x out/shecc && test -f out/shecc-stage2.elf
cd "$SRC"

echo "build.sh: fuzz target ($SRC/out/shecc) and test oracle ($ORACLE) built OK"
