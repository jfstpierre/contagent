#!/bin/bash
# Tests for forward_ssh_agent_apptainer, forward_ssh_agent_docker,
# _prompt_ssh_allowed_keys, _start_workspace_ssh_agent, contagent_ssh_agent_cleanup

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

ok()   { echo "  PASS: $1"; PASS=$((PASS + 1)); }
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
# Helpers: run forward_ssh_agent_apptainer in a subshell, capture result/warn.

_RESULT_FILE="$(mktemp)"
_WARN_FILE="$(mktemp)"

_run_fwd_apptainer() {
  local workspace="$1"
  : > "${_RESULT_FILE}"; : > "${_WARN_FILE}"
  (
    unset BASH_ENV SSH_AUTH_SOCK SSH_AGENT_PID _CONTAGENT_SSH_AGENT_PID 2>/dev/null || true
    export _WS="${workspace}" _RESULT_FILE _WARN_FILE
    # shellcheck source=../wrappers/lib/common.sh
    source "${_LIB_}"
    ARGS=()
    forward_ssh_agent_apptainer "${_WS}" ARGS >"${_WARN_FILE}" 2>&1
    printf '%s\n' "${ARGS[@]+"${ARGS[@]}"}" > "${_RESULT_FILE}"
  )
}

_run_fwd_docker() {
  local workspace="$1"
  : > "${_RESULT_FILE}"; : > "${_WARN_FILE}"
  (
    unset BASH_ENV SSH_AUTH_SOCK SSH_AGENT_PID _CONTAGENT_SSH_AGENT_PID 2>/dev/null || true
    export _WS="${workspace}" _RESULT_FILE _WARN_FILE
    source "${_LIB_}"
    ARGS=()
    forward_ssh_agent_docker "${_WS}" ARGS >"${_WARN_FILE}" 2>&1
    printf '%s\n' "${ARGS[@]+"${ARGS[@]}"}" > "${_RESULT_FILE}"
  )
}

_result() { cat "${_RESULT_FILE}"; }
_warn()   { cat "${_WARN_FILE}"; }

# ---------------------------------------------------------------------------
echo "=== first run: no config files → silent no-op, no files created ==="

describe \
  "First-run: neither ssh-allowed-keys nor ssh-config exists." \
  "forward_ssh_agent_apptainer/docker silently return 0 without creating files." \
  "No mount args are added. Run 'contagent ssh add' to configure SSH."

tmpdir="$(mktemp -d)"
mkdir -p "${tmpdir}/.contagent"

_run_fwd_apptainer "${tmpdir}"
assert_eq "$(_result)" "" "first run apptainer: no config → no mount args"
assert_eq "$(_warn)" "" "first run apptainer: no config → no warning output"

_run_fwd_docker "${tmpdir}"
assert_eq "$(_result)" "" "first run docker: no config → no mount args"
assert_eq "$(_warn)" "" "first run docker: no config → no warning output"

if [ -f "${tmpdir}/.contagent/ssh-allowed-keys" ]; then
  fail "first run: no files created" "ssh-allowed-keys was created unexpectedly"
else
  ok "first run: ssh-allowed-keys not created"
fi
if [ -f "${tmpdir}/.contagent/ssh-config" ]; then
  fail "first run: no files created" "ssh-config was created unexpectedly"
else
  ok "first run: ssh-config not created"
fi

rm -rf "${tmpdir}"

# ---------------------------------------------------------------------------
echo "=== allowed-keys file absent or empty → no mount added ==="

describe \
  "Empty or absent allowed-keys file → no mount args added for apptainer or docker."

tmpdir="$(mktemp -d)"
mkdir -p "${tmpdir}/.contagent"
# Pre-create both files to bypass the interactive prompt
: > "${tmpdir}/.contagent/ssh-allowed-keys"
: > "${tmpdir}/.contagent/ssh-config"

_run_fwd_apptainer "${tmpdir}"
assert_eq "$(_result)" "" "apptainer: empty allowed-keys → no mount"

_run_fwd_docker "${tmpdir}"
assert_eq "$(_result)" "" "docker: empty allowed-keys → no mount"

rm -rf "${tmpdir}"

# ---------------------------------------------------------------------------
echo "=== allowed-keys with non-existent key file ==="

describe \
  "Key listed in allowed-keys does not exist on disk." \
  "Warning is printed; no mount args are added for either backend."

tmpdir="$(mktemp -d)"
mkdir -p "${tmpdir}/.contagent"
printf '%s\n' "/nonexistent-key-xyzzy" > "${tmpdir}/.contagent/ssh-allowed-keys"

_run_fwd_apptainer "${tmpdir}"
assert_eq "$(_result)" "" "apptainer: missing key → no mount"
assert_contains "$(_warn)" "Warning:" "apptainer: missing key → warning printed"

_run_fwd_docker "${tmpdir}"
assert_eq "$(_result)" "" "docker: missing key → no mount"
assert_contains "$(_warn)" "Warning:" "docker: missing key → warning printed"

rm -rf "${tmpdir}"

# ---------------------------------------------------------------------------
echo "=== _start_workspace_ssh_agent with a real (no-passphrase) key ==="

describe \
  "Real ed25519 key with no passphrase loaded successfully." \
  "apptainer backend gets --bind; docker backend gets -v and -e SSH_AUTH_SOCK." \
  "Each backend uses only its own flags, not the other's."

# Generate a temporary key pair for testing
_KEYDIR="$(mktemp -d)"
_KEYFILE="${_KEYDIR}/test_key"
if ssh-keygen -t ed25519 -N "" -f "${_KEYFILE}" >/dev/null 2>&1; then

  tmpdir="$(mktemp -d)"
  mkdir -p "${tmpdir}/.contagent"
  printf '%s\n' "${_KEYFILE}" > "${tmpdir}/.contagent/ssh-allowed-keys"

  _run_fwd_apptainer "${tmpdir}"
  assert_contains "$(_result)" "--bind" "apptainer: valid key → --bind added"
  assert_not_contains "$(_result)" "-v" "apptainer: valid key → no -v flag"

  _run_fwd_docker "${tmpdir}"
  assert_contains "$(_result)" "-v" "docker: valid key → -v added"
  assert_contains "$(_result)" "-e" "docker: valid key → SSH_AUTH_SOCK env set"
  assert_contains "$(_result)" "SSH_AUTH_SOCK=" "docker: valid key → SSH_AUTH_SOCK value present"
  assert_not_contains "$(_result)" "--bind" "docker: valid key → no --bind flag"

  rm -rf "${tmpdir}"
else
  echo "  SKIP: ssh-keygen not available; skipping real-key tests"
fi
rm -rf "${_KEYDIR}"

# ---------------------------------------------------------------------------
echo "=== contagent_ssh_agent_cleanup ==="

describe \
  "Cleanup is a no-op when _CONTAGENT_SSH_AGENT_PID is unset." \
  "Returns 0 and produces no error output."

# Cleanup is a no-op when no agent was started
CLEANUP_OUT="$(
  unset _CONTAGENT_SSH_AGENT_PID 2>/dev/null || true
  source "${_LIB_}"
  contagent_ssh_agent_cleanup
  echo "ok"
)"
assert_eq "${CLEANUP_OUT}" "ok" "cleanup: no-op when _CONTAGENT_SSH_AGENT_PID unset"

describe \
  "Cleanup kills the workspace SSH agent when _CONTAGENT_SSH_AGENT_PID is set." \
  "Verifies the process is gone after cleanup and the variable is cleared."

# Cleanup kills the agent when PID is set
if ssh-agent -s >/dev/null 2>&1; then
  # Start a real agent outside the subshell so we can check it afterward
  _TEST_AGENT_ENV="$(ssh-agent -s 2>/dev/null)"
  eval "${_TEST_AGENT_ENV}" >/dev/null
  _TEST_AGENT_PID="${SSH_AGENT_PID}"

  CLEANUP_PID_OUT="$(
    source "${_LIB_}"
    _CONTAGENT_SSH_AGENT_PID="${_TEST_AGENT_PID}"
    contagent_ssh_agent_cleanup
    echo "_pid=${_CONTAGENT_SSH_AGENT_PID}"
  )"
  # Give the process a moment to die
  sleep 0.1
  _PID_LINE="$(printf '%s\n' "${CLEANUP_PID_OUT}" | grep '^_pid=')"
  assert_eq "${_PID_LINE}" "_pid=" "cleanup: _CONTAGENT_SSH_AGENT_PID is empty after cleanup"
  if kill -0 "${_TEST_AGENT_PID}" 2>/dev/null; then
    fail "cleanup: kills the workspace agent" "process ${_TEST_AGENT_PID} is still running"
    kill "${_TEST_AGENT_PID}" 2>/dev/null || true  # tidy up
  else
    ok "cleanup: kills the workspace agent"
  fi
else
  echo "  SKIP: ssh-agent not available; skipping cleanup kill test"
fi

# ---------------------------------------------------------------------------
echo "=== comment and blank lines in allowed-keys are ignored ==="

describe \
  "Comment lines (# ...) and blank lines in allowed-keys are skipped." \
  "The real key path between comments is still loaded successfully."

_KEYDIR2="$(mktemp -d)"
_KEYFILE2="${_KEYDIR2}/test_key2"
if ssh-keygen -t ed25519 -N "" -f "${_KEYFILE2}" >/dev/null 2>&1; then
  tmpdir="$(mktemp -d)"
  mkdir -p "${tmpdir}/.contagent"
  printf '# this is a comment\n\n%s\n# another comment\n' "${_KEYFILE2}" \
    > "${tmpdir}/.contagent/ssh-allowed-keys"

  _run_fwd_apptainer "${tmpdir}"
  assert_contains "$(_result)" "--bind" "apptainer: comments/blanks ignored; key loaded"

  rm -rf "${tmpdir}"
else
  echo "  SKIP: ssh-keygen not available; skipping comment-ignore test"
fi
rm -rf "${_KEYDIR2}"

# ---------------------------------------------------------------------------
rm -f "${_RESULT_FILE}" "${_WARN_FILE}"
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
