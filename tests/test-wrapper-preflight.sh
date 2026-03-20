#!/bin/bash
# Tests that wrapper scripts fail with useful errors when required files are missing,
# and succeed when all required files are present (with mocked container commands).

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

assert_contains() {
  local haystack="$1" needle="$2" msg="$3"
  if echo "$haystack" | grep -qF "$needle"; then ok "$msg"
  else fail "$msg" "'$needle' not found in output"; fi
}

# Run a wrapper script with the given environment setup.
# Prints stdout+stderr. Returns the exit code via global RUN_RC.
RUN_RC=0
run_wrapper() {
  local wrapper="$1" env_dir="$2"
  RUN_RC=0
  OUTPUT="$(
    cd "${env_dir}/workspace"
    PATH="${env_dir}/bin:${PATH}" \
    HOME="${env_dir}/home" \
    CONTAGENT_DIR="${env_dir}/contagentdir" \
    LOADEDMODULES="test-module/1.0" \
    bash "${_WRAPPERS_}/${wrapper}" 2>&1
  )" || RUN_RC=$?
}

# Set up a minimal Apptainer environment in tmpdir.
# Creates: home, workspace, bin/apptainer (mock), contagentdir
setup_apptainer_env() {
  local tmpdir="$1" sif_name="$2"
  mkdir -p "${tmpdir}/home" \
           "${tmpdir}/workspace/.contagent" \
           "${tmpdir}/bin" \
           "${tmpdir}/contagentdir/runtime"
  # Mock apptainer: exit 0 for any command
  cat > "${tmpdir}/bin/apptainer" << 'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "${tmpdir}/bin/apptainer"
  # Create the SIF image
  touch "${tmpdir}/contagentdir/${sif_name}"
}

# Set up a minimal Docker environment in tmpdir.
setup_docker_env() {
  local tmpdir="$1"
  mkdir -p "${tmpdir}/home" \
           "${tmpdir}/workspace/.contagent" \
           "${tmpdir}/bin" \
           "${tmpdir}/contagentdir"
  # Mock docker: inspect succeeds; run exits 0
  cat > "${tmpdir}/bin/docker" << 'EOF'
#!/bin/bash
if [ "${1:-}" = "image" ] && [ "${2:-}" = "inspect" ]; then
  exit 0
fi
exit 0
EOF
  chmod +x "${tmpdir}/bin/docker"
}

# ---------------------------------------------------------------------------
echo "=== appbash / appbash-cvmfs (SIF only) ==="

describe \
  "SIF not found → exits 1 with error mentioning 'SIF not found'." \
  "Tested for both appbash and appbash-cvmfs."

for wrapper in appbash appbash-cvmfs; do
  sif="apptainer.sif"
  [ "$wrapper" = "appbash-cvmfs" ] && sif="apptainer-cvmfs.sif"

  # Test: missing SIF → exits non-zero, message contains "SIF not found"
  tmpdir="$(mktemp -d)"
  setup_apptainer_env "${tmpdir}" "${sif}"
  rm -f "${tmpdir}/contagentdir/${sif}"
  run_wrapper "${wrapper}" "${tmpdir}"
  assert_eq "$RUN_RC" "1" "${wrapper}: missing SIF → exits non-zero"
  assert_contains "$OUTPUT" "SIF not found" "${wrapper}: missing SIF → error message"
  rm -rf "${tmpdir}"
done

describe \
  "All present → exits 0." \
  "CVMFS variant omitted: both variants call check_sif from the shared library."

# Happy path only for appbash. CVMFS variant uses identical preflight logic
# (check_sif from the shared library), so success is implied by the test above.
tmpdir="$(mktemp -d)"
setup_apptainer_env "${tmpdir}" "apptainer.sif"
run_wrapper "appbash" "${tmpdir}"
assert_eq "$RUN_RC" "0" "appbash: all present → exits 0"
rm -rf "${tmpdir}"

# ---------------------------------------------------------------------------
echo "=== applaude / applaude-cvmfs ==="

describe \
  "~/.claude directory missing → exits 1 with error mentioning .claude." \
  "~/.claude.json missing → exits 1 with error mentioning .claude.json." \
  "Credentials present but SIF missing → exits 1. Tested for both variants."

for wrapper in applaude applaude-cvmfs; do
  sif="apptainer.sif"
  [ "$wrapper" = "applaude-cvmfs" ] && sif="apptainer-cvmfs.sif"

  # Test: missing ~/.claude dir → exits non-zero, message mentions directory
  tmpdir="$(mktemp -d)"
  setup_apptainer_env "${tmpdir}" "${sif}"
  # home has no .claude dir
  run_wrapper "${wrapper}" "${tmpdir}"
  assert_eq "$RUN_RC" "1" "${wrapper}: missing ~/.claude → exits non-zero"
  assert_contains "$OUTPUT" ".claude" "${wrapper}: missing ~/.claude → error message"
  rm -rf "${tmpdir}"

  # Test: ~/.claude present but ~/.claude.json missing → exits non-zero
  tmpdir="$(mktemp -d)"
  setup_apptainer_env "${tmpdir}" "${sif}"
  mkdir -p "${tmpdir}/home/.claude"
  touch "${tmpdir}/home/.claude/.credentials.json"
  run_wrapper "${wrapper}" "${tmpdir}"
  assert_eq "$RUN_RC" "1" "${wrapper}: missing ~/.claude.json → exits non-zero"
  assert_contains "$OUTPUT" ".claude.json" "${wrapper}: missing ~/.claude.json → error message"
  rm -rf "${tmpdir}"

  # Test: credentials present, SIF missing → exits non-zero
  tmpdir="$(mktemp -d)"
  setup_apptainer_env "${tmpdir}" "${sif}"
  mkdir -p "${tmpdir}/home/.claude"
  touch "${tmpdir}/home/.claude/.credentials.json"
  touch "${tmpdir}/home/.claude.json"
  rm -f "${tmpdir}/contagentdir/${sif}"
  run_wrapper "${wrapper}" "${tmpdir}"
  assert_eq "$RUN_RC" "1" "${wrapper}: credentials present, SIF missing → exits non-zero"
  assert_contains "$OUTPUT" "SIF not found" "${wrapper}: missing SIF → error message"
  rm -rf "${tmpdir}"
done

describe \
  "All credentials and SIF present → exits 0." \
  "CVMFS variant omitted: both variants use the same preflight checks."

# Happy path only for applaude. CVMFS variant uses identical preflight logic
# (shared library functions), so success is implied by the failure tests above.
tmpdir="$(mktemp -d)"
setup_apptainer_env "${tmpdir}" "apptainer.sif"
mkdir -p "${tmpdir}/home/.claude"
touch "${tmpdir}/home/.claude/.credentials.json"
touch "${tmpdir}/home/.claude.json"
run_wrapper "applaude" "${tmpdir}"
assert_eq "$RUN_RC" "0" "applaude: all present → exits 0"
rm -rf "${tmpdir}"

# ---------------------------------------------------------------------------
echo "=== appopen / appopen-cvmfs ==="

describe \
  "auth.json missing → exits 1 with error mentioning auth.json." \
  "auth.json present but SIF missing → exits 1. Tested for both variants."

for wrapper in appopen appopen-cvmfs; do
  sif="apptainer.sif"
  [ "$wrapper" = "appopen-cvmfs" ] && sif="apptainer-cvmfs.sif"

  # Test: missing auth.json → exits non-zero
  tmpdir="$(mktemp -d)"
  setup_apptainer_env "${tmpdir}" "${sif}"
  run_wrapper "${wrapper}" "${tmpdir}"
  assert_eq "$RUN_RC" "1" "${wrapper}: missing auth.json → exits non-zero"
  assert_contains "$OUTPUT" "auth.json" "${wrapper}: missing auth.json → error message"
  rm -rf "${tmpdir}"

  # Test: auth.json present, SIF missing → exits non-zero
  tmpdir="$(mktemp -d)"
  setup_apptainer_env "${tmpdir}" "${sif}"
  mkdir -p "${tmpdir}/home/.local/share/opencode"
  touch "${tmpdir}/home/.local/share/opencode/auth.json"
  rm -f "${tmpdir}/contagentdir/${sif}"
  run_wrapper "${wrapper}" "${tmpdir}"
  assert_eq "$RUN_RC" "1" "${wrapper}: auth.json present, SIF missing → exits non-zero"
  assert_contains "$OUTPUT" "SIF not found" "${wrapper}: missing SIF → error message"
  rm -rf "${tmpdir}"
done

describe \
  "All present → exits 0." \
  "CVMFS variant omitted: both variants use the same preflight checks."

# Happy path only for appopen. CVMFS variant uses identical preflight logic.
tmpdir="$(mktemp -d)"
setup_apptainer_env "${tmpdir}" "apptainer.sif"
mkdir -p "${tmpdir}/home/.local/share/opencode"
touch "${tmpdir}/home/.local/share/opencode/auth.json"
run_wrapper "appopen" "${tmpdir}"
assert_eq "$RUN_RC" "0" "appopen: all present → exits 0"
rm -rf "${tmpdir}"

# ---------------------------------------------------------------------------
echo "=== appsur / appsur-cvmfs ==="

describe \
  "auth.json missing → exits 1. cli-config.json missing → exits 1." \
  "Both credentials present but SIF missing → exits 1. Tested for both variants."

for wrapper in appsur appsur-cvmfs; do
  sif="apptainer.sif"
  [ "$wrapper" = "appsur-cvmfs" ] && sif="apptainer-cvmfs.sif"

  # Test: missing auth.json → exits non-zero
  tmpdir="$(mktemp -d)"
  setup_apptainer_env "${tmpdir}" "${sif}"
  run_wrapper "${wrapper}" "${tmpdir}"
  assert_eq "$RUN_RC" "1" "${wrapper}: missing auth.json → exits non-zero"
  assert_contains "$OUTPUT" "auth.json" "${wrapper}: missing auth.json → error message"
  rm -rf "${tmpdir}"

  # Test: auth.json present, cli-config.json missing → exits non-zero
  tmpdir="$(mktemp -d)"
  setup_apptainer_env "${tmpdir}" "${sif}"
  mkdir -p "${tmpdir}/home/.config/cursor"
  touch "${tmpdir}/home/.config/cursor/auth.json"
  run_wrapper "${wrapper}" "${tmpdir}"
  assert_eq "$RUN_RC" "1" "${wrapper}: missing cli-config.json → exits non-zero"
  assert_contains "$OUTPUT" "cli-config.json" "${wrapper}: missing cli-config.json → error message"
  rm -rf "${tmpdir}"

  # Test: both credentials present, SIF missing → exits non-zero
  tmpdir="$(mktemp -d)"
  setup_apptainer_env "${tmpdir}" "${sif}"
  mkdir -p "${tmpdir}/home/.config/cursor" "${tmpdir}/home/.cursor"
  touch "${tmpdir}/home/.config/cursor/auth.json"
  touch "${tmpdir}/home/.cursor/cli-config.json"
  rm -f "${tmpdir}/contagentdir/${sif}"
  run_wrapper "${wrapper}" "${tmpdir}"
  assert_eq "$RUN_RC" "1" "${wrapper}: credentials present, SIF missing → exits non-zero"
  assert_contains "$OUTPUT" "SIF not found" "${wrapper}: missing SIF → error message"
  rm -rf "${tmpdir}"
done

describe \
  "All present → exits 0." \
  "CVMFS variant omitted: both variants use the same preflight checks."

# Happy path only for appsur. CVMFS variant uses identical preflight logic.
tmpdir="$(mktemp -d)"
setup_apptainer_env "${tmpdir}" "apptainer.sif"
mkdir -p "${tmpdir}/home/.config/cursor" "${tmpdir}/home/.cursor"
touch "${tmpdir}/home/.config/cursor/auth.json"
touch "${tmpdir}/home/.cursor/cli-config.json"
run_wrapper "appsur" "${tmpdir}"
assert_eq "$RUN_RC" "0" "appsur: all present → exits 0"
rm -rf "${tmpdir}"

# ---------------------------------------------------------------------------
echo "=== dockbash ==="

describe \
  "Docker image not found → exits 1 with 'not found' in error message." \
  "Image present (mocked inspect succeeds) → exits 0."

# Test: docker image inspect fails → exits non-zero, message mentions image
tmpdir="$(mktemp -d)"
setup_docker_env "${tmpdir}"
# Override docker to make inspect fail
cat > "${tmpdir}/bin/docker" << 'EOF'
#!/bin/bash
if [ "${1:-}" = "image" ] && [ "${2:-}" = "inspect" ]; then
  exit 1
fi
exit 0
EOF
chmod +x "${tmpdir}/bin/docker"
run_wrapper "dockbash" "${tmpdir}"
assert_eq "$RUN_RC" "1" "dockbash: image not found → exits non-zero"
assert_contains "$OUTPUT" "not found" "dockbash: image not found → error message"
rm -rf "${tmpdir}"

# Test: image present + mocked docker → exits 0
tmpdir="$(mktemp -d)"
setup_docker_env "${tmpdir}"
run_wrapper "dockbash" "${tmpdir}"
assert_eq "$RUN_RC" "0" "dockbash: all present → exits 0"
rm -rf "${tmpdir}"

# ---------------------------------------------------------------------------
echo "=== docklaude ==="

describe \
  "~/.claude missing → exits 1. ~/.claude.json missing → exits 1." \
  "Docker image missing (inspect + build both fail) → exits 1." \
  "All present → exits 0."

# Test: missing ~/.claude dir → exits non-zero
tmpdir="$(mktemp -d)"
setup_docker_env "${tmpdir}"
run_wrapper "docklaude" "${tmpdir}"
assert_eq "$RUN_RC" "1" "docklaude: missing ~/.claude → exits non-zero"
assert_contains "$OUTPUT" ".claude" "docklaude: missing ~/.claude → error message"
rm -rf "${tmpdir}"

# Test: missing ~/.claude.json → exits non-zero
tmpdir="$(mktemp -d)"
setup_docker_env "${tmpdir}"
mkdir -p "${tmpdir}/home/.claude"
touch "${tmpdir}/home/.claude/.credentials.json"
run_wrapper "docklaude" "${tmpdir}"
assert_eq "$RUN_RC" "1" "docklaude: missing ~/.claude.json → exits non-zero"
assert_contains "$OUTPUT" ".claude.json" "docklaude: missing ~/.claude.json → error message"
rm -rf "${tmpdir}"

# Test: credentials present, docker image not found → exits non-zero
# docklaude auto-builds on missing image; mock both inspect and build as failing.
tmpdir="$(mktemp -d)"
setup_docker_env "${tmpdir}"
mkdir -p "${tmpdir}/home/.claude"
touch "${tmpdir}/home/.claude/.credentials.json"
touch "${tmpdir}/home/.claude.json"
cat > "${tmpdir}/bin/docker" << 'EOF'
#!/bin/bash
if [ "${1:-}" = "image" ] && [ "${2:-}" = "inspect" ]; then exit 1; fi
if [ "${1:-}" = "build" ]; then exit 1; fi
exit 0
EOF
chmod +x "${tmpdir}/bin/docker"
run_wrapper "docklaude" "${tmpdir}"
assert_eq "$RUN_RC" "1" "docklaude: image not found → exits non-zero"
assert_contains "$OUTPUT" "not found" "docklaude: image not found → error message"
rm -rf "${tmpdir}"

# Test: all present → exits 0
tmpdir="$(mktemp -d)"
setup_docker_env "${tmpdir}"
mkdir -p "${tmpdir}/home/.claude"
touch "${tmpdir}/home/.claude/.credentials.json"
touch "${tmpdir}/home/.claude.json"
run_wrapper "docklaude" "${tmpdir}"
assert_eq "$RUN_RC" "0" "docklaude: all present → exits 0"
rm -rf "${tmpdir}"

# ---------------------------------------------------------------------------
echo "=== dockopen ==="

describe \
  "auth.json missing → exits 1. Image not found → exits 1. All present → exits 0."

# Test: missing auth.json → exits non-zero
tmpdir="$(mktemp -d)"
setup_docker_env "${tmpdir}"
run_wrapper "dockopen" "${tmpdir}"
assert_eq "$RUN_RC" "1" "dockopen: missing auth.json → exits non-zero"
assert_contains "$OUTPUT" "auth.json" "dockopen: missing auth.json → error message"
rm -rf "${tmpdir}"

# Test: auth.json present, image not found → exits non-zero
tmpdir="$(mktemp -d)"
setup_docker_env "${tmpdir}"
mkdir -p "${tmpdir}/home/.local/share/opencode"
touch "${tmpdir}/home/.local/share/opencode/auth.json"
cat > "${tmpdir}/bin/docker" << 'EOF'
#!/bin/bash
if [ "${1:-}" = "image" ] && [ "${2:-}" = "inspect" ]; then exit 1; fi
exit 0
EOF
chmod +x "${tmpdir}/bin/docker"
run_wrapper "dockopen" "${tmpdir}"
assert_eq "$RUN_RC" "1" "dockopen: image not found → exits non-zero"
rm -rf "${tmpdir}"

# Test: all present → exits 0
tmpdir="$(mktemp -d)"
setup_docker_env "${tmpdir}"
mkdir -p "${tmpdir}/home/.local/share/opencode"
touch "${tmpdir}/home/.local/share/opencode/auth.json"
run_wrapper "dockopen" "${tmpdir}"
assert_eq "$RUN_RC" "0" "dockopen: all present → exits 0"
rm -rf "${tmpdir}"

# ---------------------------------------------------------------------------
echo "=== docksur ==="

describe \
  "auth.json missing → exits 1. cli-config.json missing → exits 1." \
  "Image not found → exits 1. All present → exits 0."

# Test: missing auth.json → exits non-zero
tmpdir="$(mktemp -d)"
setup_docker_env "${tmpdir}"
run_wrapper "docksur" "${tmpdir}"
assert_eq "$RUN_RC" "1" "docksur: missing auth.json → exits non-zero"
assert_contains "$OUTPUT" "auth.json" "docksur: missing auth.json → error message"
rm -rf "${tmpdir}"

# Test: missing cli-config.json → exits non-zero
tmpdir="$(mktemp -d)"
setup_docker_env "${tmpdir}"
mkdir -p "${tmpdir}/home/.config/cursor"
touch "${tmpdir}/home/.config/cursor/auth.json"
run_wrapper "docksur" "${tmpdir}"
assert_eq "$RUN_RC" "1" "docksur: missing cli-config.json → exits non-zero"
assert_contains "$OUTPUT" "cli-config.json" "docksur: missing cli-config.json → error message"
rm -rf "${tmpdir}"

# Test: credentials present, image not found → exits non-zero
tmpdir="$(mktemp -d)"
setup_docker_env "${tmpdir}"
mkdir -p "${tmpdir}/home/.config/cursor" "${tmpdir}/home/.cursor"
touch "${tmpdir}/home/.config/cursor/auth.json"
touch "${tmpdir}/home/.cursor/cli-config.json"
cat > "${tmpdir}/bin/docker" << 'EOF'
#!/bin/bash
if [ "${1:-}" = "image" ] && [ "${2:-}" = "inspect" ]; then exit 1; fi
exit 0
EOF
chmod +x "${tmpdir}/bin/docker"
run_wrapper "docksur" "${tmpdir}"
assert_eq "$RUN_RC" "1" "docksur: image not found → exits non-zero"
rm -rf "${tmpdir}"

# Test: all present → exits 0
tmpdir="$(mktemp -d)"
setup_docker_env "${tmpdir}"
mkdir -p "${tmpdir}/home/.config/cursor" "${tmpdir}/home/.cursor"
touch "${tmpdir}/home/.config/cursor/auth.json"
touch "${tmpdir}/home/.cursor/cli-config.json"
run_wrapper "docksur" "${tmpdir}"
assert_eq "$RUN_RC" "0" "docksur: all present → exits 0"
rm -rf "${tmpdir}"

# ---------------------------------------------------------------------------
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
