#!/bin/bash
# Tests that Apptainer wrappers strip credentials from workspace state dir on exit.

set -uo pipefail

_WRAPPERS_="$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../wrappers"
PASS=0
FAIL=0

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

cleanup_test() {
  rm -rf "${SETUP_TMPDIR}"
}

# ---------------------------------------------------------------------------
echo "=== applaude credential cleanup ==="

run_apptainer_wrapper "applaude" "apptainer.sif"
CRED1="${SETUP_WORKSPACE}/.contagent/applaude/home/.claude/.credentials.json"
CRED2="${SETUP_WORKSPACE}/.contagent/applaude/home/.claude.json"
RUNTIME="${SETUP_TMPDIR}/contagentdir/runtime"

[ ! -f "${CRED1}" ] \
  && ok "applaude: .credentials.json absent from workspace after exit" \
  || fail "applaude: .credentials.json absent from workspace after exit" "file still exists: ${CRED1}"

[ ! -f "${CRED2}" ] \
  && ok "applaude: .claude.json absent from workspace after exit" \
  || fail "applaude: .claude.json absent from workspace after exit" "file still exists: ${CRED2}"

LEFTOVER_MERGED="$(find "${RUNTIME}" -maxdepth 1 -name 'contagent-*' -type d 2>/dev/null || true)"
assert_eq "$LEFTOVER_MERGED" "" "applaude: MERGED_HOME deleted after exit"
cleanup_test

# ---------------------------------------------------------------------------
echo "=== applaude-cvmfs credential cleanup ==="

run_apptainer_wrapper "applaude-cvmfs" "apptainer-cvmfs.sif"
CRED1="${SETUP_WORKSPACE}/.contagent/applaude/home/.claude/.credentials.json"
CRED2="${SETUP_WORKSPACE}/.contagent/applaude/home/.claude.json"
RUNTIME="${SETUP_TMPDIR}/contagentdir/runtime"

[ ! -f "${CRED1}" ] \
  && ok "applaude-cvmfs: .credentials.json absent from workspace after exit" \
  || fail "applaude-cvmfs: .credentials.json absent from workspace after exit" "file still exists: ${CRED1}"

[ ! -f "${CRED2}" ] \
  && ok "applaude-cvmfs: .claude.json absent from workspace after exit" \
  || fail "applaude-cvmfs: .claude.json absent from workspace after exit" "file still exists: ${CRED2}"

LEFTOVER_MERGED="$(find "${RUNTIME}" -maxdepth 1 -name 'contagent-*' -type d 2>/dev/null || true)"
assert_eq "$LEFTOVER_MERGED" "" "applaude-cvmfs: MERGED_HOME deleted after exit"
cleanup_test

# ---------------------------------------------------------------------------
echo "=== appopen credential cleanup ==="

run_apptainer_wrapper "appopen" "apptainer.sif"
CRED1="${SETUP_WORKSPACE}/.contagent/appopen/home/.local/share/opencode/auth.json"
RUNTIME="${SETUP_TMPDIR}/contagentdir/runtime"

[ ! -f "${CRED1}" ] \
  && ok "appopen: auth.json absent from workspace after exit" \
  || fail "appopen: auth.json absent from workspace after exit" "file still exists: ${CRED1}"

LEFTOVER_MERGED="$(find "${RUNTIME}" -maxdepth 1 -name 'contagent-*' -type d 2>/dev/null || true)"
assert_eq "$LEFTOVER_MERGED" "" "appopen: MERGED_HOME deleted after exit"
cleanup_test

# ---------------------------------------------------------------------------
echo "=== appopen-cvmfs credential cleanup ==="

run_apptainer_wrapper "appopen-cvmfs" "apptainer-cvmfs.sif"
CRED1="${SETUP_WORKSPACE}/.contagent/appopen/home/.local/share/opencode/auth.json"
RUNTIME="${SETUP_TMPDIR}/contagentdir/runtime"

[ ! -f "${CRED1}" ] \
  && ok "appopen-cvmfs: auth.json absent from workspace after exit" \
  || fail "appopen-cvmfs: auth.json absent from workspace after exit" "file still exists: ${CRED1}"

LEFTOVER_MERGED="$(find "${RUNTIME}" -maxdepth 1 -name 'contagent-*' -type d 2>/dev/null || true)"
assert_eq "$LEFTOVER_MERGED" "" "appopen-cvmfs: MERGED_HOME deleted after exit"
cleanup_test

# ---------------------------------------------------------------------------
echo "=== appsur credential cleanup ==="

run_apptainer_wrapper "appsur" "apptainer.sif"
CRED1="${SETUP_WORKSPACE}/.contagent/appsur/home/.config/cursor/auth.json"
CRED2="${SETUP_WORKSPACE}/.contagent/appsur/home/.cursor/cli-config.json"
RUNTIME="${SETUP_TMPDIR}/contagentdir/runtime"

[ ! -f "${CRED1}" ] \
  && ok "appsur: auth.json absent from workspace after exit" \
  || fail "appsur: auth.json absent from workspace after exit" "file still exists: ${CRED1}"

[ ! -f "${CRED2}" ] \
  && ok "appsur: cli-config.json absent from workspace after exit" \
  || fail "appsur: cli-config.json absent from workspace after exit" "file still exists: ${CRED2}"

LEFTOVER_MERGED="$(find "${RUNTIME}" -maxdepth 1 -name 'contagent-*' -type d 2>/dev/null || true)"
assert_eq "$LEFTOVER_MERGED" "" "appsur: MERGED_HOME deleted after exit"
cleanup_test

# ---------------------------------------------------------------------------
echo "=== appsur-cvmfs credential cleanup ==="

run_apptainer_wrapper "appsur-cvmfs" "apptainer-cvmfs.sif"
CRED1="${SETUP_WORKSPACE}/.contagent/appsur/home/.config/cursor/auth.json"
CRED2="${SETUP_WORKSPACE}/.contagent/appsur/home/.cursor/cli-config.json"
RUNTIME="${SETUP_TMPDIR}/contagentdir/runtime"

[ ! -f "${CRED1}" ] \
  && ok "appsur-cvmfs: auth.json absent from workspace after exit" \
  || fail "appsur-cvmfs: auth.json absent from workspace after exit" "file still exists: ${CRED1}"

[ ! -f "${CRED2}" ] \
  && ok "appsur-cvmfs: cli-config.json absent from workspace after exit" \
  || fail "appsur-cvmfs: cli-config.json absent from workspace after exit" "file still exists: ${CRED2}"

LEFTOVER_MERGED="$(find "${RUNTIME}" -maxdepth 1 -name 'contagent-*' -type d 2>/dev/null || true)"
assert_eq "$LEFTOVER_MERGED" "" "appsur-cvmfs: MERGED_HOME deleted after exit"
cleanup_test

# ---------------------------------------------------------------------------
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
