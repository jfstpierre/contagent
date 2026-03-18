#!/bin/bash
# Tests for applaude-cvmfs C/U/I module tracking options

set -uo pipefail

_LIB_="$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../wrappers/lib/common.sh"
PASS=0
FAIL=0


ok() {
  echo "  PASS: $1"
  PASS=$((PASS + 1))
}
fail() {
  echo "  FAIL: $1"
  echo "       $2"
  FAIL=$((FAIL + 1))
}

assert_eq() {
  local got="$1" expected="$2" msg="$3"
  if [ "$got" = "$expected" ]; then
    ok "$msg"
  else
    fail "$msg" "expected: $(printf '%q' "$expected")  got: $(printf '%q' "$got")"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    ok "$msg"
  else
    fail "$msg" "'$needle' not found in output"
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" msg="$3"
  if ! echo "$haystack" | grep -qF "$needle"; then
    ok "$msg"
  else
    fail "$msg" "'$needle' unexpectedly found in output"
  fi
}

# run_test LOADED_MODULES FILE_CONTENT CHOICES
#   LOADED_MODULES : colon-separated lmod format, or ""
#   FILE_CONTENT   : initial content for .contagent/applaude/modules, or "" to skip creation
#   CHOICES        : newline-separated answers for the prompt (e.g. $'C', $'x\nU')
# After the call, MODULES_AFTER and MODULE_CALLS are set.
run_test() {
  local loaded="$1" file_content="$2" choices="$3"

  local tmpdir
  tmpdir="$(mktemp -d)"
  local workspace="${tmpdir}/workspace"
  local module_log="${tmpdir}/module.log"

  mkdir -p "${workspace}/.contagent/applaude"

  local modules_file="${workspace}/.contagent/applaude/modules"

  # Write initial modules file if provided
  [ -n "$file_content" ] && printf '%s' "$file_content" >"${modules_file}"

  # Run reconcile_cvmfs_modules with a mocked module() function and controlled stdin.
  # Unset BASH_ENV to prevent lmod from re-sourcing its init file and
  # overwriting our mock module function in every child bash process.
  (
    unset BASH_ENV
    export _MODULE_LOG="${module_log}"
    module() { echo "module $*" >>"${_MODULE_LOG}"; }
    export -f module
    export LOADEDMODULES="${loaded}"
    # shellcheck source=../wrappers/lib/common.sh
    source "${_LIB_}"
    printf '%s\n' "$choices" | reconcile_cvmfs_modules "${modules_file}"
  ) >/dev/null 2>&1

  MODULES_AFTER="$(cat "${modules_file}" 2>/dev/null || echo "")"
  MODULE_CALLS="$(cat "${module_log}" 2>/dev/null || echo "")"

  rm -rf "${tmpdir}"
}

# ---------------------------------------------------------------------------
echo "=== First execution (no modules file) ==="

run_test "scipy-stack/2023b:python/3.11" "" ""
assert_contains "$MODULES_AFTER" "scipy-stack/2023b" "modules file created with first module"
assert_contains "$MODULES_AFTER" "python/3.11" "modules file created with second module"
assert_eq "$MODULE_CALLS" "" "no module commands run on first execution"

# ---------------------------------------------------------------------------
echo "=== Modules match — no prompt ==="

SAVED=$'scipy-stack/2023b\npython/3.11'
run_test "scipy-stack/2023b:python/3.11" "$SAVED" ""
assert_eq "$MODULES_AFTER" "$SAVED" "modules file unchanged when modules match"
assert_eq "$MODULE_CALLS" "" "no module commands run when modules match"

# Order-independent match (file order differs from lmod order)
SAVED_REVERSED=$'python/3.11\nscipy-stack/2023b'
run_test "scipy-stack/2023b:python/3.11" "$SAVED_REVERSED" ""
assert_eq "$MODULES_AFTER" "$SAVED_REVERSED" "modules file unchanged when order differs but content matches"
assert_eq "$MODULE_CALLS" "" "no module commands run when order differs but content matches"

# ---------------------------------------------------------------------------
echo "=== Option C: change loaded modules to match file ==="

FILE=$'scipy-stack/2023b\npython/3.11'
run_test "scipy-stack/2023b" "$FILE" "C"
assert_eq "$MODULES_AFTER" "$FILE" "modules file unchanged after C"
assert_contains "$MODULE_CALLS" "module purge" "module purge called after C"
assert_contains "$MODULE_CALLS" "module load scipy-stack/2023b" "scipy-stack loaded after C"
assert_contains "$MODULE_CALLS" "module load python/3.11" "python/3.11 loaded after C"

# ---------------------------------------------------------------------------
echo "=== Option U: update file with currently loaded modules ==="

FILE=$'scipy-stack/2023b\npython/3.11'
run_test "scipy-stack/2023b" "$FILE" "U"
assert_contains "$MODULES_AFTER" "scipy-stack/2023b" "file updated with current module after U"
assert_not_contains "$MODULES_AFTER" "python/3.11" "removed module not in file after U"
assert_eq "$MODULE_CALLS" "" "no module commands run after U"

# ---------------------------------------------------------------------------
echo "=== Option I: ignore — nothing changes ==="

FILE=$'scipy-stack/2023b\npython/3.11'
run_test "scipy-stack/2023b" "$FILE" "I"
assert_eq "$MODULES_AFTER" "$FILE" "modules file unchanged after I"
assert_eq "$MODULE_CALLS" "" "no module commands run after I"

# ---------------------------------------------------------------------------
echo "=== Invalid input then valid choice ==="

FILE=$'scipy-stack/2023b\npython/3.11'
run_test "scipy-stack/2023b" "$FILE" $'x\nI'
assert_eq "$MODULES_AFTER" "$FILE" "modules file unchanged after invalid then I"

FILE=$'scipy-stack/2023b\npython/3.11'
run_test "scipy-stack/2023b" "$FILE" $'?\nC'
assert_contains "$MODULE_CALLS" "module purge" "module purge called after invalid then C"

# ---------------------------------------------------------------------------
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
