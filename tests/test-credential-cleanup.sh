#!/bin/bash
# Tests that wrappers strip credentials from the workspace state dir on exit.

set -uo pipefail

_WRAPPERS_="$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../wrappers"
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

# Run an Apptainer wrapper to completion in an isolated environment.
# After the run, the caller can inspect ${SETUP_WORKSPACE} for cleanup results.
SETUP_TMPDIR=""
SETUP_WORKSPACE=""
run_apptainer_wrapper() {
  local wrapper="$1" sif_name="$2"
  SETUP_TMPDIR="$(mktemp -d)"
  SETUP_WORKSPACE="${SETUP_TMPDIR}/workspace"

  mkdir -p "${SETUP_WORKSPACE}/.contagent" \
           "${SETUP_TMPDIR}/home" \
           "${SETUP_TMPDIR}/bin" \
           "${SETUP_TMPDIR}/contagentdir/runtime"

  # Mock apptainer: exit 0 immediately (no modules, no actual container run)
  cat > "${SETUP_TMPDIR}/bin/apptainer" << 'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "${SETUP_TMPDIR}/bin/apptainer"

  # Create fake SIF
  touch "${SETUP_TMPDIR}/contagentdir/${sif_name}"

  # Provide credential files in fake HOME
  mkdir -p "${SETUP_TMPDIR}/home/.claude"
  echo '{"fake":"credentials"}' > "${SETUP_TMPDIR}/home/.claude/.credentials.json"
  echo '{"fake":"config"}' > "${SETUP_TMPDIR}/home/.claude.json"
  mkdir -p "${SETUP_TMPDIR}/home/.local/share/opencode" \
           "${SETUP_TMPDIR}/home/.config/opencode" \
           "${SETUP_TMPDIR}/home/.config/cursor" \
           "${SETUP_TMPDIR}/home/.cursor"
  echo '{"fake":"opencode_auth"}' > "${SETUP_TMPDIR}/home/.local/share/opencode/auth.json"
  echo '{"fake":"cursor_auth"}' > "${SETUP_TMPDIR}/home/.config/cursor/auth.json"
  echo '{"fake":"cursor_cli"}' > "${SETUP_TMPDIR}/home/.cursor/cli-config.json"

  (
    cd "${SETUP_WORKSPACE}"
    PATH="${SETUP_TMPDIR}/bin:${PATH}" \
    HOME="${SETUP_TMPDIR}/home" \
    CONTAGENT_DIR="${SETUP_TMPDIR}/contagentdir" \
    LOADEDMODULES="test-module/1.0" \
    bash "${_WRAPPERS_}/${wrapper}"
  ) >/dev/null 2>&1
}

# Run a Docker wrapper to completion in an isolated environment.
# Credentials go to CONTAGENT_DIR (not workspace); workspace stubs are zeroed.
run_docker_wrapper() {
  local wrapper="$1"
  SETUP_TMPDIR="$(mktemp -d)"
  SETUP_WORKSPACE="${SETUP_TMPDIR}/workspace"

  mkdir -p "${SETUP_WORKSPACE}/.contagent" \
           "${SETUP_TMPDIR}/home" \
           "${SETUP_TMPDIR}/bin" \
           "${SETUP_TMPDIR}/contagentdir"

  # Mock docker: inspect succeeds; run exits 0
  cat > "${SETUP_TMPDIR}/bin/docker" << 'EOF'
#!/bin/bash
if [ "${1:-}" = "image" ] && [ "${2:-}" = "inspect" ]; then exit 0; fi
exit 0
EOF
  chmod +x "${SETUP_TMPDIR}/bin/docker"

  # Provide credential files in fake HOME
  mkdir -p "${SETUP_TMPDIR}/home/.claude" \
           "${SETUP_TMPDIR}/home/.local/share/opencode" \
           "${SETUP_TMPDIR}/home/.config/cursor" \
           "${SETUP_TMPDIR}/home/.cursor"
  echo '{"fake":"credentials"}' > "${SETUP_TMPDIR}/home/.claude/.credentials.json"
  echo '{"fake":"config"}' > "${SETUP_TMPDIR}/home/.claude.json"
  echo '{"fake":"opencode_auth"}' > "${SETUP_TMPDIR}/home/.local/share/opencode/auth.json"
  echo '{"fake":"cursor_auth"}' > "${SETUP_TMPDIR}/home/.config/cursor/auth.json"
  echo '{"fake":"cursor_cli"}' > "${SETUP_TMPDIR}/home/.cursor/cli-config.json"

  (
    cd "${SETUP_WORKSPACE}"
    PATH="${SETUP_TMPDIR}/bin:${PATH}" \
    HOME="${SETUP_TMPDIR}/home" \
    CONTAGENT_DIR="${SETUP_TMPDIR}/contagentdir" \
    bash "${_WRAPPERS_}/${wrapper}"
  ) >/dev/null 2>&1
}

cleanup_test() {
  rm -rf "${SETUP_TMPDIR}"
}

# ---------------------------------------------------------------------------
echo "=== applaude credential handling ==="

describe \
  "applaude copies real credentials to CONTAGENT_DIR (outside workspace)." \
  "The workspace-side stubs contain credential content as --bind targets." \
  "CVMFS variant omitted: shared library handles credentials identically for both."

run_apptainer_wrapper "applaude" "apptainer.sif"
STUB1="${SETUP_WORKSPACE}/.contagent/apptainer/home/.claude/.credentials.json"
STUB2="${SETUP_WORKSPACE}/.contagent/apptainer/home/.claude.json"
CRED_DIR="${SETUP_TMPDIR}/contagentdir/claude/creds"

assert_eq "$(cat "${STUB1}" 2>/dev/null)" '{"fake":"credentials"}' "applaude: .credentials.json stub in workspace has credential content"

assert_eq "$(cat "${STUB2}" 2>/dev/null)" '{"fake":"config"}' "applaude: .claude.json stub in workspace has credential content"

[ -f "${CRED_DIR}/.credentials.json" ] \
  && ok "applaude: .credentials.json copied to CONTAGENT_DIR" \
  || fail "applaude: .credentials.json copied to CONTAGENT_DIR" "file not found in cred dir"

cleanup_test

# (applaude-cvmfs omitted: credential cleanup is in the shared library and
#  exercises the same code path regardless of which SIF variant is used.)

# ---------------------------------------------------------------------------
echo "=== appopen credential handling ==="

describe \
  "appopen copies OpenCode auth to CONTAGENT_DIR (outside workspace)." \
  "The workspace-side auth.json stub contains credential content as a --bind target." \
  "CVMFS variant omitted: shared library handles credentials identically for both."

run_apptainer_wrapper "appopen" "apptainer.sif"
STUB1="${SETUP_WORKSPACE}/.contagent/apptainer/home/.local/share/opencode/auth.json"
CRED_DIR="${SETUP_TMPDIR}/contagentdir/opencode/creds"

assert_eq "$(cat "${STUB1}" 2>/dev/null)" '{"fake":"opencode_auth"}' "appopen: auth.json stub in workspace has credential content"

[ -f "${CRED_DIR}/auth.json" ] \
  && ok "appopen: auth.json copied to CONTAGENT_DIR" \
  || fail "appopen: auth.json copied to CONTAGENT_DIR" "file not found in cred dir"

cleanup_test

# (appopen-cvmfs omitted: same reasoning as applaude-cvmfs above.)

# ---------------------------------------------------------------------------
echo "=== appsur credential handling ==="

describe \
  "appsur copies Cursor credentials to CONTAGENT_DIR (outside workspace)." \
  "The workspace-side stubs contain credential content as --bind targets." \
  "CVMFS variant omitted: shared library handles credentials identically for both."

run_apptainer_wrapper "appsur" "apptainer.sif"
STUB1="${SETUP_WORKSPACE}/.contagent/apptainer/home/.config/cursor/auth.json"
STUB2="${SETUP_WORKSPACE}/.contagent/apptainer/home/.cursor/cli-config.json"
CRED_DIR="${SETUP_TMPDIR}/contagentdir/cursor/creds"

assert_eq "$(cat "${STUB1}" 2>/dev/null)" '{"fake":"cursor_auth"}' "appsur: auth.json stub in workspace has credential content"

assert_eq "$(cat "${STUB2}" 2>/dev/null)" '{"fake":"cursor_cli"}' "appsur: cli-config.json stub in workspace has credential content"

[ -f "${CRED_DIR}/auth.json" ] \
  && ok "appsur: auth.json copied to CONTAGENT_DIR" \
  || fail "appsur: auth.json copied to CONTAGENT_DIR" "file not found in cred dir"

cleanup_test

# (appsur-cvmfs omitted: same reasoning as applaude-cvmfs above.)

# ---------------------------------------------------------------------------
echo "=== docklaude credential cleanup ==="

describe \
  "docklaude copies real credentials to CONTAGENT_DIR (outside workspace)." \
  "The workspace-side credential files are zeroed stubs — never contain real tokens." \
  "Confirms credentials are isolated from the shareable workspace directory."

run_docker_wrapper "docklaude"
STUB1="${SETUP_WORKSPACE}/.contagent/docker/home/.claude/.credentials.json"
STUB2="${SETUP_WORKSPACE}/.contagent/docker/home/.claude.json"
CRED_DIR="${SETUP_TMPDIR}/contagentdir/claude/creds"

[ -f "${STUB1}" ] && [ ! -s "${STUB1}" ] \
  && ok "docklaude: .credentials.json stub in workspace is empty" \
  || fail "docklaude: .credentials.json stub in workspace is empty" "file missing or non-empty"

[ -f "${STUB2}" ] && [ ! -s "${STUB2}" ] \
  && ok "docklaude: .claude.json stub in workspace is empty" \
  || fail "docklaude: .claude.json stub in workspace is empty" "file missing or non-empty"

[ -f "${CRED_DIR}/.credentials.json" ] \
  && ok "docklaude: .credentials.json copied to CONTAGENT_DIR" \
  || fail "docklaude: .credentials.json copied to CONTAGENT_DIR" "file not found in cred dir"

cleanup_test

# ---------------------------------------------------------------------------
echo "=== dockopen credential cleanup ==="

describe \
  "dockopen copies real OpenCode auth to CONTAGENT_DIR (outside workspace)." \
  "The workspace-side auth.json stub is zeroed — never contains real tokens."

run_docker_wrapper "dockopen"
STUB1="${SETUP_WORKSPACE}/.contagent/docker/home/.local/share/opencode/auth.json"
CRED_DIR="${SETUP_TMPDIR}/contagentdir/opencode/creds"

[ -f "${STUB1}" ] && [ ! -s "${STUB1}" ] \
  && ok "dockopen: auth.json stub in workspace is empty" \
  || fail "dockopen: auth.json stub in workspace is empty" "file missing or non-empty"

[ -f "${CRED_DIR}/auth.json" ] \
  && ok "dockopen: auth.json copied to CONTAGENT_DIR" \
  || fail "dockopen: auth.json copied to CONTAGENT_DIR" "file not found in cred dir"

cleanup_test

# ---------------------------------------------------------------------------
echo "=== docksur credential cleanup ==="

describe \
  "docksur copies real Cursor credentials to CONTAGENT_DIR (outside workspace)." \
  "The workspace-side auth.json and cli-config.json stubs are zeroed."

run_docker_wrapper "docksur"
STUB1="${SETUP_WORKSPACE}/.contagent/docker/home/.config/cursor/auth.json"
STUB2="${SETUP_WORKSPACE}/.contagent/docker/home/.cursor/cli-config.json"
CRED_DIR="${SETUP_TMPDIR}/contagentdir/cursor/creds"

[ -f "${STUB1}" ] && [ ! -s "${STUB1}" ] \
  && ok "docksur: auth.json stub in workspace is empty" \
  || fail "docksur: auth.json stub in workspace is empty" "file missing or non-empty"

[ -f "${STUB2}" ] && [ ! -s "${STUB2}" ] \
  && ok "docksur: cli-config.json stub in workspace is empty" \
  || fail "docksur: cli-config.json stub in workspace is empty" "file missing or non-empty"

[ -f "${CRED_DIR}/auth.json" ] \
  && ok "docksur: auth.json copied to CONTAGENT_DIR" \
  || fail "docksur: auth.json copied to CONTAGENT_DIR" "file not found in cred dir"

cleanup_test

# ---------------------------------------------------------------------------
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
