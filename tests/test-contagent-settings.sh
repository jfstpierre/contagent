#!/bin/bash
# Tests for read_setting, set_setting, check_home_dir from contagent

set -uo pipefail

_CONTAGENT_="$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../contagent"
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

# Load contagent functions only (no dispatch).
# Sets HOME to homedir so contagent sets CONTAGENT_DIR="${homedir}/.contagent"
# and SETTINGS_FILE="${homedir}/.contagent/settings".
# Call AFTER this to read CONTAGENT_DIR and SETTINGS_FILE.
_load_contagent() {
  local homedir="$1"
  export HOME="${homedir}"
  mkdir -p "${homedir}/.contagent"
  _CONTAGENT_LIB_ONLY=1 source "${_CONTAGENT_}"
  # contagent sets CONTAGENT_DIR="${HOME}/.contagent" and SETTINGS_FILE="${CONTAGENT_DIR}/settings"
  # Those variables are now available in the current shell.
}

# ---------------------------------------------------------------------------
echo "=== read_setting / set_setting ==="

# Test 1: read_setting returns value for existing key
tmpdir="$(mktemp -d)"
(
  _load_contagent "${tmpdir}"
  printf 'FOO=bar\n' > "${SETTINGS_FILE}"
  VAL="$(read_setting FOO)"
  [ "$VAL" = "bar" ]
) && ok "read_setting returns value for existing key" \
  || fail "read_setting returns value for existing key" "unexpected value"
rm -rf "${tmpdir}"

# Test 2: read_setting returns empty for missing key
tmpdir="$(mktemp -d)"
(
  _load_contagent "${tmpdir}"
  printf 'FOO=bar\n' > "${SETTINGS_FILE}"
  VAL="$(read_setting MISSING)"
  [ -z "$VAL" ]
) && ok "read_setting returns empty for missing key" \
  || fail "read_setting returns empty for missing key" "non-empty value returned"
rm -rf "${tmpdir}"

# Test 3: read_setting handles multiple keys correctly
tmpdir="$(mktemp -d)"
(
  _load_contagent "${tmpdir}"
  printf 'A=1\nB=2\n' > "${SETTINGS_FILE}"
  [ "$(read_setting A)" = "1" ] && [ "$(read_setting B)" = "2" ]
) && ok "read_setting handles multiple keys" \
  || fail "read_setting handles multiple keys" "wrong value"
rm -rf "${tmpdir}"

# Test 4: set_setting creates new key
tmpdir="$(mktemp -d)"
(
  _load_contagent "${tmpdir}"
  touch "${SETTINGS_FILE}"
  set_setting X val
  [ "$(read_setting X)" = "val" ]
) && ok "set_setting creates new key" \
  || fail "set_setting creates new key" "key not found or wrong value"
rm -rf "${tmpdir}"

# Test 5: set_setting updates existing key
tmpdir="$(mktemp -d)"
(
  _load_contagent "${tmpdir}"
  printf 'X=old\n' > "${SETTINGS_FILE}"
  set_setting X new
  [ "$(read_setting X)" = "new" ]
) && ok "set_setting updates existing key" \
  || fail "set_setting updates existing key" "wrong value after update"
rm -rf "${tmpdir}"

# Test 6: set_setting preserves other keys
tmpdir="$(mktemp -d)"
(
  _load_contagent "${tmpdir}"
  printf 'A=1\nB=2\n' > "${SETTINGS_FILE}"
  set_setting A updated
  [ "$(read_setting B)" = "2" ]
) && ok "set_setting preserves other keys" \
  || fail "set_setting preserves other keys" "other key was modified"
rm -rf "${tmpdir}"

# Test 7: set_setting creates CONTAGENT_DIR if absent
tmpdir="$(mktemp -d)"
(
  _load_contagent "${tmpdir}"
  # Override to point at a non-existent subdir
  CONTAGENT_DIR="${tmpdir}/newdir"
  SETTINGS_FILE="${CONTAGENT_DIR}/settings"
  set_setting X val
  [ -d "${CONTAGENT_DIR}" ] && [ -f "${SETTINGS_FILE}" ]
) && ok "set_setting creates CONTAGENT_DIR if absent" \
  || fail "set_setting creates CONTAGENT_DIR if absent" "dir or file not created"
rm -rf "${tmpdir}"

# ---------------------------------------------------------------------------
echo "=== check_home_dir ==="

# Test 8: not in HOME → returns 0, no output
tmpdir="$(mktemp -d)"
RC=0
STDOUT="$(
  _load_contagent "${tmpdir}"
  # pwd is not HOME
  cd /tmp
  check_home_dir
)" || RC=$?
assert_eq "$RC" "0" "not in HOME → returns 0"
assert_eq "$STDOUT" "" "not in HOME → no output"
rm -rf "${tmpdir}"

# Test 9: in HOME, HOME_WARN=disabled → returns 0, no output
tmpdir="$(mktemp -d)"
RC=0
STDOUT="$(
  _load_contagent "${tmpdir}"
  printf 'HOME_WARN=disabled\n' > "${SETTINGS_FILE}"
  cd "${HOME}"
  check_home_dir
)" || RC=$?
assert_eq "$RC" "0" "HOME_WARN=disabled → returns 0"
assert_eq "$STDOUT" "" "HOME_WARN=disabled → no output"
rm -rf "${tmpdir}"

# Test 10: in HOME, user says y → returns 0
tmpdir="$(mktemp -d)"
RC=0
(
  _load_contagent "${tmpdir}"
  touch "${SETTINGS_FILE}"
  cd "${HOME}"
  printf 'y\n' | check_home_dir
) >/dev/null 2>&1 || RC=$?
assert_eq "$RC" "0" "user says y → returns 0"
rm -rf "${tmpdir}"

# Test 11: in HOME, user says n → exits 1, "Aborted" in output
tmpdir="$(mktemp -d)"
RC=0
STDOUT="$(
  (
    _load_contagent "${tmpdir}"
    touch "${SETTINGS_FILE}"
    cd "${HOME}"
    printf 'n\n' | check_home_dir
  )
)" || RC=$?
assert_eq "$RC" "1" "user says n → exits 1"
assert_contains "$STDOUT" "Aborted" "user says n → 'Aborted' in output"
rm -rf "${tmpdir}"

# Test 12: in HOME, user says d → sets HOME_WARN=disabled, returns 0
tmpdir="$(mktemp -d)"
RC=0
(
  _load_contagent "${tmpdir}"
  touch "${SETTINGS_FILE}"
  cd "${HOME}"
  printf 'd\n' | check_home_dir
) >/dev/null 2>&1 || RC=$?
assert_eq "$RC" "0" "user says d → returns 0"
WARN_VAL="$(
  _load_contagent "${tmpdir}"
  read_setting HOME_WARN
)"
assert_eq "$WARN_VAL" "disabled" "user says d → HOME_WARN=disabled in settings"
rm -rf "${tmpdir}"

# Test 13: in HOME, invalid input then y → proceeds normally
tmpdir="$(mktemp -d)"
RC=0
(
  _load_contagent "${tmpdir}"
  touch "${SETTINGS_FILE}"
  cd "${HOME}"
  printf 'x\ny\n' | check_home_dir
) >/dev/null 2>&1 || RC=$?
assert_eq "$RC" "0" "invalid input then y → returns 0"
rm -rf "${tmpdir}"

# ---------------------------------------------------------------------------
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
