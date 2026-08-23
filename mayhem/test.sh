#!/usr/bin/env bash
#
# mayhem/test.sh — RUN shecc's full upstream functional test suite (built by mayhem/build.sh).
#
# The suite is upstream's `make check`: it exercises the CLEAN oracle compiler ($SRC/.oracle,
# stage0 + bootstrapped stage2) over the project's ~1100 unit/functional test programs and the
# AAPCS ABI conformance tests, running each emitted ARM binary under qemu-arm and asserting its
# exit code / output. This is a genuine behavioral oracle: if the compiler is neutered to exit(0)
# (the verify-repo sabotage check) it emits no valid binary and the suite FAILS.
#
#   make check = check-stage0 + check-stage2 + check-abi-stage0 + check-abi-stage2
#
# We do NOT compile the compiler here (build.sh already did); `make check` only compiles the test
# programs with the prebuilt shecc — which is exactly what "running the suite" means for a compiler.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"

ORACLE="${SRC:-/mayhem}/.oracle"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-${SRC:-/mayhem}/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

if [ ! -x "$ORACLE/out/shecc" ]; then
  echo "test.sh: oracle compiler $ORACLE/out/shecc missing — build.sh did not run" >&2
  emit_ctrf "shecc-make-check" 0 1 0
  exit 1
fi

cd "$ORACLE"
LOG="$(mktemp)"
# ARCH=arm, static linking (DYNLINK=0). Dynamic-linking ABI cases self-skip (no arm cross-libc).
SHOW_PROGRESS=0 SHOW_SUMMARY=1 COLOR_OUTPUT=0 make check ARCH=arm DYNLINK=0 >"$LOG" 2>&1
rc=$?

# Sum the per-stage "Total/Passed/Failed/Skipped" summaries printed by driver.sh & arm-abi.sh.
read -r P F S < <(awk '
  /^[[:space:]]*Passed:/  { p += $2 }
  /^[[:space:]]*Failed:/  { f += $2 }
  /^[[:space:]]*Skipped:/ { s += $2 }
  END { printf "%d %d %d", p, f, s }
' "$LOG")

cat "$LOG"
echo "test.sh: make check rc=$rc  passed=$P failed=$F skipped=$S"

# Treat a nonzero make rc as at least one failure even if parsing found none (e.g. build/setup break).
if [ "$rc" -ne 0 ] && [ "${F:-0}" -eq 0 ]; then F=1; fi
rm -f "$LOG"

emit_ctrf "shecc-make-check" "${P:-0}" "${F:-0}" "${S:-0}"
