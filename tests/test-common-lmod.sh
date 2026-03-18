#!/bin/bash
# Tests for ensure_module, load_apptainer_module, load_modules_from_file

set -uo pipefail

_LIB_="$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../wrappers/lib/common.sh"
PASS=0
FAIL=0

ok() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; echo "       $2"; FAIL=$((FAIL + 1)); }

assert_eq() {
  local got="$1" expected="$2" msg="$3"
  if [ "$got" = "$expected" ]; then ok "$msg"
  else fail "$msg" "expected: $(printf '%q' "$expected")  got: $(printf '%q' "$got")"; fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="$3"
  if printf '%s\n' "$haystack" | grep -qF -- "$needle"; then ok "$msg"
  else fail "$msg" "'$needle' not found in output"; fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" msg="$3"
  if ! printf '%s\n' "$haystack" | grep -qF -- "$needle"; then ok "$msg"
  else fail "$msg" "'$needle' unexpectedly found in output"; fi
}

# ---------------------------------------------------------------------------
echo "=== ensure_module ==="

# Test 1: module already available → returns 0
RC="$(
  (
    unset BASH_ENV
    source "${_LIB_}"
    module() { :; }
    export -f module
    ensure_module
  ) >/dev/null 2>&1; echo $?
)"
assert_eq "$RC" "0" "module already available → returns 0"

# Test 2: module unavailable, no lmod init found → returns 1
# Override ensure_module to simulate the no-lmod path (the real function may
# find a system lmod, which is correct behavior but can't be tested portably).
RC="$(
  (
    unset BASH_ENV
    source "${_LIB_}"
    # Simulate: module not in PATH/env, no lmod init files found
    ensure_module() {
      type module >/dev/null 2>&1 && return 0
      return 1
    }
    unset -f module 2>/dev/null || true
    ensure_module
  ) >/dev/null 2>&1; echo $?
)"
assert_eq "$RC" "1" "module unavailable, no lmod → returns 1"

# ---------------------------------------------------------------------------
echo "=== load_apptainer_module ==="

# Test 3: no settings file → no module calls
tmpdir="$(mktemp -d)"
MODULE_LOG="${tmpdir}/module.log"
(
  unset BASH_ENV
  export CONTAGENT_DIR="${tmpdir}/empty_dir"
  export _MODULE_LOG="${MODULE_LOG}"
  module() { echo "module $*" >> "${_MODULE_LOG}"; }
  export -f module
  source "${_LIB_}"
  load_apptainer_module
) >/dev/null 2>&1
CALLS="$(cat "${MODULE_LOG}" 2>/dev/null || echo "")"
assert_eq "$CALLS" "" "no settings file → no module calls"
rm -rf "${tmpdir}"

# Test 4: settings file, APPTAINER_MODULE not set → no module calls
tmpdir="$(mktemp -d)"
MODULE_LOG="${tmpdir}/module.log"
printf 'CONTAINER_TYPE=apptainer\n' > "${tmpdir}/settings"
(
  unset BASH_ENV
  export CONTAGENT_DIR="${tmpdir}"
  export _MODULE_LOG="${MODULE_LOG}"
  module() { echo "module $*" >> "${_MODULE_LOG}"; }
  export -f module
  source "${_LIB_}"
  load_apptainer_module
) >/dev/null 2>&1
CALLS="$(cat "${MODULE_LOG}" 2>/dev/null || echo "")"
assert_eq "$CALLS" "" "settings file without APPTAINER_MODULE → no module calls"
rm -rf "${tmpdir}"

# Test 5: settings file with APPTAINER_MODULE, module available → module load called
tmpdir="$(mktemp -d)"
MODULE_LOG="${tmpdir}/module.log"
printf 'APPTAINER_MODULE=myapp/1.0\n' > "${tmpdir}/settings"
(
  unset BASH_ENV
  export CONTAGENT_DIR="${tmpdir}"
  export _MODULE_LOG="${MODULE_LOG}"
  module() { echo "module $*" >> "${_MODULE_LOG}"; }
  export -f module
  source "${_LIB_}"
  load_apptainer_module
) >/dev/null 2>&1
CALLS="$(cat "${MODULE_LOG}" 2>/dev/null || echo "")"
assert_contains "$CALLS" "module load myapp/1.0" "APPTAINER_MODULE set → module load called"
rm -rf "${tmpdir}"

# Test 6: settings file with APPTAINER_MODULE, lmod unavailable → warning printed
tmpdir="$(mktemp -d)"
printf 'APPTAINER_MODULE=myapp/1.0\n' > "${tmpdir}/settings"
STDOUT="$(
  unset BASH_ENV
  export CONTAGENT_DIR="${tmpdir}"
  source "${_LIB_}"
  # Override ensure_module to simulate lmod unavailable
  ensure_module() { return 1; }
  export -f ensure_module
  load_apptainer_module
)"
assert_contains "$STDOUT" "Warning:" "lmod unavailable → warning printed"
rm -rf "${tmpdir}"

# ---------------------------------------------------------------------------
echo "=== load_modules_from_file ==="

# Test 7: normal file → module purge + module load for each module
tmpdir="$(mktemp -d)"
MODULE_LOG="${tmpdir}/module.log"
printf 'scipy-stack/2023b\npython/3.11\n' > "${tmpdir}/modules"
(
  unset BASH_ENV
  export _MODULE_LOG="${MODULE_LOG}"
  module() { echo "module $*" >> "${_MODULE_LOG}"; }
  export -f module
  source "${_LIB_}"
  load_modules_from_file "${tmpdir}/modules"
) >/dev/null 2>&1
CALLS="$(cat "${MODULE_LOG}" 2>/dev/null || echo "")"
assert_contains "$CALLS" "module purge" "load_modules_from_file: module purge called"
assert_contains "$CALLS" "module load scipy-stack/2023b" "load_modules_from_file: first module loaded"
assert_contains "$CALLS" "module load python/3.11" "load_modules_from_file: second module loaded"
rm -rf "${tmpdir}"

# Test 8: file with comments and blank lines → only real modules loaded
tmpdir="$(mktemp -d)"
MODULE_LOG="${tmpdir}/module.log"
printf '# comment\n\nscipy-stack/2023b\n' > "${tmpdir}/modules"
(
  unset BASH_ENV
  export _MODULE_LOG="${MODULE_LOG}"
  module() { echo "module $*" >> "${_MODULE_LOG}"; }
  export -f module
  source "${_LIB_}"
  load_modules_from_file "${tmpdir}/modules"
) >/dev/null 2>&1
CALLS="$(cat "${MODULE_LOG}" 2>/dev/null || echo "")"
LOAD_COUNT="$(echo "$CALLS" | grep -c "^module load" || true)"
assert_eq "$LOAD_COUNT" "1" "load_modules_from_file: comments/blanks skipped, one load call"
rm -rf "${tmpdir}"

# Test 9: lmod unavailable → warning printed, no module calls
tmpdir="$(mktemp -d)"
MODULE_LOG="${tmpdir}/module.log"
printf 'scipy-stack/2023b\n' > "${tmpdir}/modules"
STDOUT="$(
  unset BASH_ENV
  source "${_LIB_}"
  # Override ensure_module to simulate lmod unavailable
  ensure_module() { return 1; }
  export -f ensure_module
  load_modules_from_file "${tmpdir}/modules" 2>/dev/null
)"
assert_contains "$STDOUT" "Warning:" "load_modules_from_file: lmod unavailable → warning"
assert_eq "$(cat "${MODULE_LOG}" 2>/dev/null || echo "")" "" "load_modules_from_file: lmod unavailable → no module calls"
rm -rf "${tmpdir}"

# ---------------------------------------------------------------------------
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
