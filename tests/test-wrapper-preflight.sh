#!/bin/bash
# Tests that wrapper scripts fail with useful errors when required files are missing,
# and succeed when all required files are present (with mocked container commands).

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

  # Test: SIF present + mocked apptainer → exits 0
  tmpdir="$(mktemp -d)"
  setup_apptainer_env "${tmpdir}" "${sif}"
  run_wrapper "${wrapper}" "${tmpdir}"
  assert_eq "$RUN_RC" "0" "${wrapper}: all present → exits 0"
  rm -rf "${tmpdir}"
done

# ---------------------------------------------------------------------------
echo "=== applaude / applaude-cvmfs ==="

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

  # Test: all present + mocked apptainer → exits 0
  tmpdir="$(mktemp -d)"
  setup_apptainer_env "${tmpdir}" "${sif}"
  mkdir -p "${tmpdir}/home/.claude"
  touch "${tmpdir}/home/.claude/.credentials.json"
  touch "${tmpdir}/home/.claude.json"
  run_wrapper "${wrapper}" "${tmpdir}"
  assert_eq "$RUN_RC" "0" "${wrapper}: all present → exits 0"
  rm -rf "${tmpdir}"
done

# ---------------------------------------------------------------------------
echo "=== appopen / appopen-cvmfs ==="

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

  # Test: all present → exits 0
  tmpdir="$(mktemp -d)"
  setup_apptainer_env "${tmpdir}" "${sif}"
  mkdir -p "${tmpdir}/home/.local/share/opencode"
  touch "${tmpdir}/home/.local/share/opencode/auth.json"
  run_wrapper "${wrapper}" "${tmpdir}"
  assert_eq "$RUN_RC" "0" "${wrapper}: all present → exits 0"
  rm -rf "${tmpdir}"
done

# ---------------------------------------------------------------------------
echo "=== appsur / appsur-cvmfs ==="

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

  # Test: all present → exits 0
  tmpdir="$(mktemp -d)"
  setup_apptainer_env "${tmpdir}" "${sif}"
  mkdir -p "${tmpdir}/home/.config/cursor" "${tmpdir}/home/.cursor"
  touch "${tmpdir}/home/.config/cursor/auth.json"
  touch "${tmpdir}/home/.cursor/cli-config.json"
  run_wrapper "${wrapper}" "${tmpdir}"
  assert_eq "$RUN_RC" "0" "${wrapper}: all present → exits 0"
  rm -rf "${tmpdir}"
done

# ---------------------------------------------------------------------------
echo "=== dockbash ==="

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
