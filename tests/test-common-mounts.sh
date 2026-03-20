#!/bin/bash
# Tests for init_mounts_file, parse_mounts_apptainer, parse_mounts_docker

set -uo pipefail

_LIB_="$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../wrappers/lib/common.sh"
PASS=0
FAIL=0

VERBOSE=0
for _arg in "$@"; do
  case "$_arg" in -v|--verbose) VERBOSE=1 ;; esac
done

describe() {
  [ "$VERBOSE" -eq 1 ] || return 0
  local prefix="    "
  echo "  >"
  for _line in "$@"; do echo "${prefix}${_line}"; done
}

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
echo "=== init_mounts_file ==="

describe \
  "init_mounts_file creates the file with a template header when it does not exist." \
  "Prints a first-run notice to stdout on creation."

tmpdir="$(mktemp -d)"
(
  # shellcheck source=../wrappers/lib/common.sh
  source "${_LIB_}"
  init_mounts_file "${tmpdir}/ws1"
) >/dev/null 2>&1
[ -f "${tmpdir}/ws1/.contagent/mounts" ] && ok "creates file when absent" \
  || fail "creates file when absent" "file not created"

CONTENT="$(cat "${tmpdir}/ws1/.contagent/mounts" 2>/dev/null)"
assert_contains "$CONTENT" "# Extra bind mounts" "created file contains template header"

STDOUT="$(
  source "${_LIB_}"
  init_mounts_file "${tmpdir}/ws2"
)"
assert_contains "$STDOUT" "Note: .contagent/mounts created" "prints first-run notice to stdout"

describe \
  "init_mounts_file is a no-op when the file already exists." \
  "Existing content is preserved and no first-run notice is printed."

# Pre-create file with custom content
mkdir -p "${tmpdir}/ws3/.contagent"
echo "custom_content_xyz" > "${tmpdir}/ws3/.contagent/mounts"
(
  source "${_LIB_}"
  init_mounts_file "${tmpdir}/ws3"
) >/dev/null 2>&1
CONTENT3="$(cat "${tmpdir}/ws3/.contagent/mounts")"
assert_eq "$CONTENT3" "custom_content_xyz" "no-op when file already exists"

STDOUT3="$(
  source "${_LIB_}"
  init_mounts_file "${tmpdir}/ws3"
)"
assert_not_contains "$STDOUT3" "Note:" "first-run notice NOT printed when file exists"

rm -rf "${tmpdir}"

# ---------------------------------------------------------------------------
echo "=== parse_mounts_apptainer ==="

# Persistent files for capturing output — survive subshell boundaries.
# Warnings go to stdout in parse_mounts_*; we redirect that to _PARSE_WARN_FILE,
# and write array content to _PARSE_RESULT_FILE.
_PARSE_WARN_FILE="$(mktemp)"
_PARSE_RESULT_FILE="$(mktemp)"

run_parse_apptainer() {
  local file_content="$1"
  local td
  td="$(mktemp -d)"
  mkdir -p "${td}/.contagent"
  printf '%s\n' "$file_content" > "${td}/.contagent/mounts"
  : > "${_PARSE_WARN_FILE}"
  : > "${_PARSE_RESULT_FILE}"
  (
    unset BASH_ENV
    export _TD="${td}" _PARSE_WARN_FILE _PARSE_RESULT_FILE
    # shellcheck source=../wrappers/lib/common.sh
    source "${_LIB_}"
    MOUNTS_ARR=()
    # Redirect stdout (warnings) to warn file; write array to result file.
    parse_mounts_apptainer "${_TD}" MOUNTS_ARR >"${_PARSE_WARN_FILE}" 2>&1
    printf '%s\n' "${MOUNTS_ARR[@]+"${MOUNTS_ARR[@]}"}" > "${_PARSE_RESULT_FILE}"
  )
  rm -rf "${td}"
}

_read_parse_result() { cat "${_PARSE_RESULT_FILE}"; }
_read_parse_warn()   { cat "${_PARSE_WARN_FILE}"; }

describe \
  "Empty or comment-only mounts file → array unchanged (no --bind args added)."

# Test 6: empty/comment-only file
run_parse_apptainer "# just a comment"
assert_eq "$(_read_parse_result)" "" "empty/comment-only file → array unchanged"

describe \
  "Valid entry with explicit ro mode → --bind added with correct path and mode."

# Test 7: valid entry with explicit ro mode
tmpdir_host="$(mktemp -d)"
run_parse_apptainer "${tmpdir_host}:/container:ro"
assert_contains "$(_read_parse_result)" "--bind" "valid ro entry → --bind flag"
assert_contains "$(_read_parse_result)" "${tmpdir_host}:/container:ro" "valid ro entry → correct path and mode"
rm -rf "${tmpdir_host}"

describe \
  "No mode specified → entry defaults to ro."

# Test 8: valid entry without mode → defaults to ro
tmpdir_host="$(mktemp -d)"
run_parse_apptainer "${tmpdir_host}:/container"
assert_contains "$(_read_parse_result)" "${tmpdir_host}:/container:ro" "no mode → defaults to ro"
rm -rf "${tmpdir_host}"

describe \
  "rw mode is preserved as-is in the --bind argument."

# Test 9: valid entry with rw mode
tmpdir_host="$(mktemp -d)"
run_parse_apptainer "${tmpdir_host}:/container:rw"
assert_contains "$(_read_parse_result)" "${tmpdir_host}:/container:rw" "rw mode → rw preserved"
rm -rf "${tmpdir_host}"

describe \
  "Tilde in host path is expanded using \$HOME."

# Test 10: tilde expansion
tmpdir2="$(mktemp -d)"
mkdir -p "${tmpdir2}/foo" "${tmpdir2}/.contagent"
printf '%s\n' "~/foo:/bar:ro" > "${tmpdir2}/.contagent/mounts"
TILDE_RESULT="$(
  export HOME="${tmpdir2}"
  source "${_LIB_}"
  MOUNTS_ARR=()
  parse_mounts_apptainer "${tmpdir2}" MOUNTS_ARR 2>/dev/null
  printf '%s\n' "${MOUNTS_ARR[@]+"${MOUNTS_ARR[@]}"}"
)"
assert_contains "$TILDE_RESULT" "${tmpdir2}/foo:/bar:ro" "tilde expansion resolves to HOME/foo"
rm -rf "${tmpdir2}"

describe \
  "Non-existent host path → entry skipped and a warning is printed."

# Test 11: non-existent host path → warning + skipped
run_parse_apptainer "/nonexistent-path-xyzzy-test:/container:ro"
assert_eq "$(_read_parse_result)" "" "non-existent host path → entry skipped"
assert_contains "$(_read_parse_warn)" "Warning:" "non-existent host path → warning in output"

describe \
  "Invalid mode → defaults to ro and a warning is printed."

# Test 12: invalid mode → warning + defaults to ro
tmpdir_host="$(mktemp -d)"
run_parse_apptainer "${tmpdir_host}:/container:bad"
assert_contains "$(_read_parse_result)" ":ro" "invalid mode → defaults to ro"
assert_contains "$(_read_parse_warn)" "Warning:" "invalid mode → warning in output"
rm -rf "${tmpdir_host}"

describe \
  "Missing container_path (entry ends with ':') → entry skipped, warning printed."

# Test 13: missing container_path → warning + skipped
tmpdir_host="$(mktemp -d)"
run_parse_apptainer "${tmpdir_host}:"
assert_eq "$(_read_parse_result)" "" "missing container_path → entry skipped"
assert_contains "$(_read_parse_warn)" "Warning:" "missing container_path → warning in output"
rm -rf "${tmpdir_host}"

describe \
  "Comment and blank lines in the mounts file are ignored." \
  "Exactly one --bind is added for the one valid entry."

# Test 14: comment and blank lines ignored; one valid entry
tmpdir_host="$(mktemp -d)"
tmpd="$(mktemp -d)"
mkdir -p "${tmpd}/.contagent"
printf '# comment\n\n%s:/container:ro\n# another comment\n' "${tmpdir_host}" > "${tmpd}/.contagent/mounts"
(
  unset BASH_ENV
  export _TMPD="${tmpd}" _PARSE_RESULT_FILE
  source "${_LIB_}"
  MOUNTS_ARR=()
  parse_mounts_apptainer "${_TMPD}" MOUNTS_ARR 2>/dev/null
  printf '%s\n' "${MOUNTS_ARR[@]+"${MOUNTS_ARR[@]}"}" > "${_PARSE_RESULT_FILE}"
)
rm -rf "${tmpd}"
BIND_COUNT="$(grep -c "^--bind$" "${_PARSE_RESULT_FILE}" || true)"
assert_eq "$BIND_COUNT" "1" "comment and blank lines ignored; exactly one --bind"
rm -rf "${tmpdir_host}"

describe \
  "Multiple valid entries → one --bind per entry (two total)."

# Test 15: multiple valid entries
tmpdir_host1="$(mktemp -d)"
tmpdir_host2="$(mktemp -d)"
tmpd="$(mktemp -d)"
mkdir -p "${tmpd}/.contagent"
printf '%s:/c1:ro\n%s:/c2:rw\n' "${tmpdir_host1}" "${tmpdir_host2}" > "${tmpd}/.contagent/mounts"
(
  unset BASH_ENV
  export _TMPD="${tmpd}" _PARSE_RESULT_FILE
  source "${_LIB_}"
  MOUNTS_ARR=()
  parse_mounts_apptainer "${_TMPD}" MOUNTS_ARR 2>/dev/null
  printf '%s\n' "${MOUNTS_ARR[@]+"${MOUNTS_ARR[@]}"}" > "${_PARSE_RESULT_FILE}"
)
rm -rf "${tmpd}"
BIND_COUNT="$(grep -c "^--bind$" "${_PARSE_RESULT_FILE}" || true)"
assert_eq "$BIND_COUNT" "2" "multiple valid entries → two --bind flags"
rm -rf "${tmpdir_host1}" "${tmpdir_host2}"

# ---------------------------------------------------------------------------
echo "=== parse_mounts_docker ==="

run_parse_docker() {
  local file_content="$1"
  local td
  td="$(mktemp -d)"
  mkdir -p "${td}/.contagent"
  printf '%s\n' "$file_content" > "${td}/.contagent/mounts"
  : > "${_PARSE_WARN_FILE}"
  : > "${_PARSE_RESULT_FILE}"
  (
    unset BASH_ENV
    export _TD="${td}" _PARSE_WARN_FILE _PARSE_RESULT_FILE
    source "${_LIB_}"
    MOUNTS_ARR=()
    parse_mounts_docker "${_TD}" MOUNTS_ARR >"${_PARSE_WARN_FILE}" 2>&1
    printf '%s\n' "${MOUNTS_ARR[@]+"${MOUNTS_ARR[@]}"}" > "${_PARSE_RESULT_FILE}"
  )
  rm -rf "${td}"
}

describe \
  "Docker: valid entry uses -v flag (not --bind) with correct path and mode."

# Test 16: valid entry → -v flag (not --bind)
tmpdir_host="$(mktemp -d)"
run_parse_docker "${tmpdir_host}:/container:ro"
assert_contains "$(_read_parse_result)" "-v" "docker: uses -v flag"
assert_not_contains "$(_read_parse_result)" "--bind" "docker: does not use --bind"
assert_contains "$(_read_parse_result)" "${tmpdir_host}:/container:ro" "docker: correct path and mode"
rm -rf "${tmpdir_host}"

describe \
  "Docker: invalid mode → defaults to ro and a warning is printed."

# Test 17a: invalid mode → warning + defaults to ro (docker)
tmpdir_host="$(mktemp -d)"
run_parse_docker "${tmpdir_host}:/container:bad"
assert_contains "$(_read_parse_result)" ":ro" "docker: invalid mode → defaults to ro"
assert_contains "$(_read_parse_warn)" "Warning:" "docker: invalid mode → warning in output"
rm -rf "${tmpdir_host}"

describe \
  "Docker: non-existent host path → entry skipped."

# Test 17b: non-existent host path → skipped (docker)
run_parse_docker "/nonexistent-path-xyzzy-docker:/container:ro"
assert_eq "$(_read_parse_result)" "" "docker: non-existent host path → entry skipped"

describe \
  "Docker: multiple valid entries → one -v flag per entry (two total)."

# Test 18: multiple valid entries → two -v flags (docker)
tmpdir_host1="$(mktemp -d)"
tmpdir_host2="$(mktemp -d)"
tmpd="$(mktemp -d)"
mkdir -p "${tmpd}/.contagent"
printf '%s:/c1:ro\n%s:/c2:rw\n' "${tmpdir_host1}" "${tmpdir_host2}" > "${tmpd}/.contagent/mounts"
(
  unset BASH_ENV
  export _TMPD="${tmpd}" _PARSE_RESULT_FILE
  source "${_LIB_}"
  MOUNTS_ARR=()
  parse_mounts_docker "${_TMPD}" MOUNTS_ARR 2>/dev/null
  printf '%s\n' "${MOUNTS_ARR[@]+"${MOUNTS_ARR[@]}"}" > "${_PARSE_RESULT_FILE}"
)
rm -rf "${tmpd}"
V_COUNT="$(grep -c "^-v$" "${_PARSE_RESULT_FILE}" || true)"
assert_eq "$V_COUNT" "2" "docker: multiple valid entries → two -v flags"
rm -rf "${tmpdir_host1}" "${tmpdir_host2}"

describe \
  "Docker: comment and blank lines in the mounts file are ignored." \
  "Exactly one -v is added for the one valid entry."

# Test 19: comment and blank lines ignored; one valid entry (docker)
tmpdir_host="$(mktemp -d)"
tmpd="$(mktemp -d)"
mkdir -p "${tmpd}/.contagent"
printf '# comment\n\n%s:/container:ro\n# another comment\n' "${tmpdir_host}" > "${tmpd}/.contagent/mounts"
(
  unset BASH_ENV
  export _TMPD="${tmpd}" _PARSE_RESULT_FILE
  source "${_LIB_}"
  MOUNTS_ARR=()
  parse_mounts_docker "${_TMPD}" MOUNTS_ARR 2>/dev/null
  printf '%s\n' "${MOUNTS_ARR[@]+"${MOUNTS_ARR[@]}"}" > "${_PARSE_RESULT_FILE}"
)
rm -rf "${tmpd}"
V_COUNT="$(grep -c "^-v$" "${_PARSE_RESULT_FILE}" || true)"
assert_eq "$V_COUNT" "1" "docker: comment and blank lines ignored; exactly one -v"
rm -rf "${tmpdir_host}"

# ---------------------------------------------------------------------------
rm -f "${_PARSE_WARN_FILE}" "${_PARSE_RESULT_FILE}"
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
