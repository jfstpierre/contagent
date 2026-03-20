#!/bin/bash
# Tests for context.sh: generate_context_file, generate_opencode_config,
# install_cursor_rules, install_claude_skills

set -uo pipefail

_LIB_="$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../wrappers/lib/context.sh"
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
echo "=== generate_context_file ==="

tmpdir="$(mktemp -d)"

describe \
  "Basic generation: no mounts file, no modules." \
  "Verifies context.md is created with the header, variant name, and /workspace path." \
  "Also confirms the Loaded modules section is absent when no modules_file is given."

# Basic generation: no mounts file, no modules
(
  # shellcheck source=../wrappers/lib/context.sh
  source "${_LIB_}"
  mkdir -p "${tmpdir}/ws1/.contagent"
  # Create an empty mounts file so the template init message doesn't fire
  touch "${tmpdir}/ws1/.contagent/mounts"
  generate_context_file "${tmpdir}/ws1" "applaude"
) >/dev/null 2>&1

[ -f "${tmpdir}/ws1/.contagent/context.md" ] \
  && ok "creates context.md" \
  || fail "creates context.md" "file not created"

CONTENT="$(cat "${tmpdir}/ws1/.contagent/context.md" 2>/dev/null)"
assert_contains "$CONTENT" "contagent container" "context.md contains header"
assert_contains "$CONTENT" "variant: \`applaude\`" "context.md contains variant"
assert_contains "$CONTENT" "/workspace" "context.md lists /workspace"
assert_contains "$CONTENT" "${tmpdir}/ws1" "context.md contains workspace host path"
assert_contains "$CONTENT" "To access additional host paths" "context.md contains mount instructions"
assert_not_contains "$CONTENT" "Loaded modules" "no modules section without modules_file"

describe \
  "Mounts listing: valid paths appear in context.md; non-existent paths are skipped." \
  "Uses a real tmpdir as host path and a bogus path to confirm filtering."

# Mounts listing: valid mounts appear; non-existent paths are skipped
mkdir -p "${tmpdir}/ws2/.contagent"
mkdir -p "${tmpdir}/realdir"
cat > "${tmpdir}/ws2/.contagent/mounts" << EOF
${tmpdir}/realdir:/data:ro
/this/does/not/exist:/nope:ro
EOF

(
  source "${_LIB_}"
  generate_context_file "${tmpdir}/ws2" "applaude"
) >/dev/null 2>&1

CONTENT2="$(cat "${tmpdir}/ws2/.contagent/context.md" 2>/dev/null)"
assert_contains "$CONTENT2" "/data" "context.md lists valid mount container path"
assert_contains "$CONTENT2" "${tmpdir}/realdir" "context.md lists valid mount host path"
assert_not_contains "$CONTENT2" "/nope" "context.md skips non-existent mount"

describe \
  "Mode labels: rw entries show 'read-write', ro entries show 'read-only'." \
  "Ensures the human-readable label matches the mount mode."

# Mode label: rw shows read-write, ro shows read-only
mkdir -p "${tmpdir}/ws3/.contagent"
cat > "${tmpdir}/ws3/.contagent/mounts" << EOF
${tmpdir}/realdir:/rw-mount:rw
${tmpdir}/realdir:/ro-mount:ro
EOF

(
  source "${_LIB_}"
  generate_context_file "${tmpdir}/ws3" "applaude"
) >/dev/null 2>&1

CONTENT3="$(cat "${tmpdir}/ws3/.contagent/context.md" 2>/dev/null)"
assert_contains "$CONTENT3" "read-write" "context.md shows read-write for rw mounts"
assert_contains "$CONTENT3" "read-only" "context.md shows read-only for ro mounts"

describe \
  "Modules section appears when a modules_file path is provided." \
  "Lists each module from the file and includes the file path in the section."

# Modules section: present when modules_file given
mkdir -p "${tmpdir}/ws4/.contagent/applaude"
touch "${tmpdir}/ws4/.contagent/mounts"
cat > "${tmpdir}/ws4/.contagent/applaude/modules" << EOF
python/3.11
scipy-stack/2023b
EOF

(
  source "${_LIB_}"
  generate_context_file "${tmpdir}/ws4" "applaude-cvmfs" \
    "${tmpdir}/ws4/.contagent/applaude/modules"
) >/dev/null 2>&1

CONTENT4="$(cat "${tmpdir}/ws4/.contagent/context.md" 2>/dev/null)"
assert_contains "$CONTENT4" "Loaded modules" "modules section present when modules_file given"
assert_contains "$CONTENT4" "python/3.11" "modules section lists first module"
assert_contains "$CONTENT4" "scipy-stack/2023b" "modules section lists second module"
assert_contains "$CONTENT4" ".contagent/applaude/modules" "modules section shows file path"

describe \
  "generate_context_file overwrites the file on every run." \
  "Re-running with a different variant name replaces all prior content."

# Overwrites on every run
(
  source "${_LIB_}"
  generate_context_file "${tmpdir}/ws1" "newvariant"
) >/dev/null 2>&1
CONTENT_NEW="$(cat "${tmpdir}/ws1/.contagent/context.md" 2>/dev/null)"
assert_contains "$CONTENT_NEW" "newvariant" "generate_context_file overwrites on every run"

rm -rf "${tmpdir}"

# ---------------------------------------------------------------------------
echo "=== generate_opencode_config ==="

tmpdir="$(mktemp -d)"

describe \
  "Apptainer mode: .config/opencode/ exists → writes opencode.json inside it." \
  "Idempotent: a second call does not duplicate the context.md entry."

# Apptainer mode: .config/opencode/ exists → writes to opencode.json inside it
mkdir -p "${tmpdir}/merged/.config/opencode"
(
  source "${_LIB_}"
  generate_opencode_config "${tmpdir}/merged" "${tmpdir}/ws"
) >/dev/null 2>&1

[ -f "${tmpdir}/merged/.config/opencode/opencode.json" ] \
  && ok "apptainer mode creates opencode.json" \
  || fail "apptainer mode creates opencode.json" "file not created"

OCFG="$(cat "${tmpdir}/merged/.config/opencode/opencode.json" 2>/dev/null)"
assert_contains "$OCFG" "/workspace/.contagent/context.md" \
  "apptainer opencode.json contains context.md path"

# Idempotent: running again does not duplicate the entry
(
  source "${_LIB_}"
  generate_opencode_config "${tmpdir}/merged" "${tmpdir}/ws"
) >/dev/null 2>&1

OCFG2="$(cat "${tmpdir}/merged/.config/opencode/opencode.json" 2>/dev/null)"
COUNT="$(printf '%s\n' "$OCFG2" | grep -c 'context.md' || true)"
assert_eq "$COUNT" "1" "context.md appears exactly once (idempotent)"

describe \
  "Merges with an existing opencode.json: preserves prior instructions and other keys."

# Merges with existing config
mkdir -p "${tmpdir}/merged2/.config/opencode"
printf '{"instructions":["/other/file.md"],"theme":"dark"}' \
  > "${tmpdir}/merged2/.config/opencode/opencode.json"

(
  source "${_LIB_}"
  generate_opencode_config "${tmpdir}/merged2" "${tmpdir}/ws"
) >/dev/null 2>&1

OCFG3="$(cat "${tmpdir}/merged2/.config/opencode/opencode.json" 2>/dev/null)"
assert_contains "$OCFG3" "/other/file.md" "merge preserves existing instructions entry"
assert_contains "$OCFG3" "/workspace/.contagent/context.md" "merge adds context.md"
assert_contains "$OCFG3" "dark" "merge preserves other config keys"

describe \
  "Docker mode: no .config/opencode/ directory → writes opencode.json directly to the cred dir." \
  "Also tests merging with a pre-existing opencode.json in the cred dir."

# Docker mode: no .config/opencode/ → writes to opencode.json directly in dir
mkdir -p "${tmpdir}/creds"
(
  source "${_LIB_}"
  generate_opencode_config "${tmpdir}/creds" "${tmpdir}/ws"
) >/dev/null 2>&1

[ -f "${tmpdir}/creds/opencode.json" ] \
  && ok "docker mode creates opencode.json in cred dir" \
  || fail "docker mode creates opencode.json in cred dir" "file not created"

OCFG4="$(cat "${tmpdir}/creds/opencode.json" 2>/dev/null)"
assert_contains "$OCFG4" "/workspace/.contagent/context.md" \
  "docker opencode.json contains context.md path"

# Docker mode: merges with pre-existing opencode.json in cred dir
printf '{"instructions":["/existing.md"]}' > "${tmpdir}/creds/opencode.json"
(
  source "${_LIB_}"
  generate_opencode_config "${tmpdir}/creds" "${tmpdir}/ws"
) >/dev/null 2>&1

OCFG5="$(cat "${tmpdir}/creds/opencode.json" 2>/dev/null)"
assert_contains "$OCFG5" "/existing.md" "docker mode preserves existing instruction"
assert_contains "$OCFG5" "/workspace/.contagent/context.md" "docker mode adds context.md"

rm -rf "${tmpdir}"

# ---------------------------------------------------------------------------
echo "=== install_cursor_rules ==="

tmpdir="$(mktemp -d)"

describe \
  "install_cursor_rules creates contagent.mdc in .cursor/rules/ with frontmatter." \
  "Embeds the full context.md content and adds a .gitignore entry."

# Set up a context.md to embed
mkdir -p "${tmpdir}/ws/.contagent"
printf '# Test Context\nSome content here.\n' > "${tmpdir}/ws/.contagent/context.md"

(
  source "${_LIB_}"
  install_cursor_rules "${tmpdir}/ws" "${tmpdir}/ws/.contagent/context.md"
) >/dev/null 2>&1

[ -f "${tmpdir}/ws/.cursor/rules/contagent.mdc" ] \
  && ok "install_cursor_rules creates contagent.mdc" \
  || fail "install_cursor_rules creates contagent.mdc" "file not created"

MDC="$(cat "${tmpdir}/ws/.cursor/rules/contagent.mdc" 2>/dev/null)"
assert_contains "$MDC" "---" "contagent.mdc has frontmatter delimiters"
assert_contains "$MDC" "alwaysApply: true" "contagent.mdc has alwaysApply"
assert_contains "$MDC" "auto-generated" "contagent.mdc has do-not-commit note"
assert_contains "$MDC" "# Test Context" "contagent.mdc embeds context.md content"
assert_contains "$MDC" "Some content here." "contagent.mdc embeds full context.md body"

# .gitignore entry added
[ -f "${tmpdir}/ws/.gitignore" ] \
  && ok ".gitignore created" \
  || fail ".gitignore created" "file not created"

GITIGNORE="$(cat "${tmpdir}/ws/.gitignore" 2>/dev/null)"
assert_contains "$GITIGNORE" ".cursor/rules/contagent.mdc" ".gitignore contains mdc entry"

describe \
  "Idempotent: running again does not duplicate the .gitignore entry."

# Idempotent: running again does not add a duplicate .gitignore entry
(
  source "${_LIB_}"
  install_cursor_rules "${tmpdir}/ws" "${tmpdir}/ws/.contagent/context.md"
) >/dev/null 2>&1

COUNT="$(grep -c 'contagent.mdc' "${tmpdir}/ws/.gitignore" || true)"
assert_eq "$COUNT" "1" ".gitignore entry not duplicated"

describe \
  "Appends to an existing .gitignore without removing previous entries."

# Appends to existing .gitignore
mkdir -p "${tmpdir}/ws2/.contagent"
printf '*.log\n' > "${tmpdir}/ws2/.gitignore"
cp "${tmpdir}/ws/.contagent/context.md" "${tmpdir}/ws2/.contagent/context.md"

(
  source "${_LIB_}"
  install_cursor_rules "${tmpdir}/ws2" "${tmpdir}/ws2/.contagent/context.md"
) >/dev/null 2>&1

GITIGNORE2="$(cat "${tmpdir}/ws2/.gitignore" 2>/dev/null)"
assert_contains "$GITIGNORE2" "*.log" "existing .gitignore entries preserved"
assert_contains "$GITIGNORE2" ".cursor/rules/contagent.mdc" "new entry appended to existing .gitignore"

rm -rf "${tmpdir}"

# ---------------------------------------------------------------------------
echo "=== install_claude_skills ==="

tmpdir="$(mktemp -d)"

# Create a fake skills source tree next to the lib dir
_FAKE_WRAPPERS="${tmpdir}/wrappers"
mkdir -p "${_FAKE_WRAPPERS}/lib"
mkdir -p "${_FAKE_WRAPPERS}/context/claude/skills/test-skill"
printf '<!-- contagent-skill-version: 1 -->\n# Test Skill\nContent.\n' \
  > "${_FAKE_WRAPPERS}/context/claude/skills/test-skill/SKILL.md"

# Point _CONTEXT_SKILLS_SRC at the fake tree
CONTAINER_HOME="${tmpdir}/home"
mkdir -p "${CONTAINER_HOME}"

describe \
  "install_claude_skills copies SKILL.md from the source tree into the container home."

(
  # shellcheck source=../wrappers/lib/context.sh
  source "${_LIB_}"
  _CONTEXT_SKILLS_SRC="${_FAKE_WRAPPERS}/context/claude/skills"
  install_claude_skills "${CONTAINER_HOME}"
) >/dev/null 2>&1

[ -f "${CONTAINER_HOME}/.claude/skills/test-skill/SKILL.md" ] \
  && ok "install_claude_skills copies SKILL.md" \
  || fail "install_claude_skills copies SKILL.md" "file not found"

SKILL_CONTENT="$(cat "${CONTAINER_HOME}/.claude/skills/test-skill/SKILL.md" 2>/dev/null)"
assert_contains "$SKILL_CONTENT" "contagent-skill-version: 1" "copied SKILL.md has version sentinel"

describe \
  "Same version sentinel in the installed file → skill not overwritten."

# Version sentinel: same version → skip (file unchanged)
printf '<!-- contagent-skill-version: 1 -->\n# MODIFIED\n' \
  > "${CONTAINER_HOME}/.claude/skills/test-skill/SKILL.md"

(
  source "${_LIB_}"
  _CONTEXT_SKILLS_SRC="${_FAKE_WRAPPERS}/context/claude/skills"
  install_claude_skills "${CONTAINER_HOME}"
) >/dev/null 2>&1

SKILL_AFTER="$(cat "${CONTAINER_HOME}/.claude/skills/test-skill/SKILL.md" 2>/dev/null)"
assert_contains "$SKILL_AFTER" "MODIFIED" "same version → skill not overwritten"

describe \
  "Different version sentinel in the source → skill file is overwritten."

# Version sentinel: different version → overwrite
printf '<!-- contagent-skill-version: 2 -->\n# Updated Skill\n' \
  > "${_FAKE_WRAPPERS}/context/claude/skills/test-skill/SKILL.md"

(
  source "${_LIB_}"
  _CONTEXT_SKILLS_SRC="${_FAKE_WRAPPERS}/context/claude/skills"
  install_claude_skills "${CONTAINER_HOME}"
) >/dev/null 2>&1

SKILL_NEW="$(cat "${CONTAINER_HOME}/.claude/skills/test-skill/SKILL.md" 2>/dev/null)"
assert_contains "$SKILL_NEW" "Updated Skill" "new version → skill overwritten"
assert_contains "$SKILL_NEW" "contagent-skill-version: 2" "new version sentinel written"

describe \
  "install_claude_skills is a no-op when the source directory does not exist."

# No-op when skills source directory does not exist
(
  source "${_LIB_}"
  _CONTEXT_SKILLS_SRC="${tmpdir}/nonexistent"
  install_claude_skills "${CONTAINER_HOME}"
) >/dev/null 2>&1
ok "install_claude_skills no-ops when source dir absent"

rm -rf "${tmpdir}"

# ---------------------------------------------------------------------------
echo "=== generate_context_file SSH agent block ==="

tmpdir="$(mktemp -d)"
mkdir -p "${tmpdir}/ws/.contagent"
touch "${tmpdir}/ws/.contagent/mounts"

describe \
  "SSH_AUTH_SOCK pointing to a real Unix socket → SSH Agent section present in context.md."

# With SSH_AUTH_SOCK pointing to a real socket: SSH Agent section present
sock_path="${tmpdir}/test.sock"
python3 -c "import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])" "$sock_path"

(
  source "${_LIB_}"
  SSH_AUTH_SOCK="$sock_path"
  generate_context_file "${tmpdir}/ws" "applaude"
) >/dev/null 2>&1

CONTENT_SSH="$(cat "${tmpdir}/ws/.contagent/context.md" 2>/dev/null)"
assert_contains "$CONTENT_SSH" "## SSH Agent" "real socket SSH_AUTH_SOCK → SSH Agent section present"

describe \
  "SSH_AUTH_SOCK pointing to a non-existent path → SSH Agent section absent." \
  "The code checks that the path is actually a socket, not just that the variable is set."

# With SSH_AUTH_SOCK pointing to a non-existent path: SSH Agent section absent
(
  source "${_LIB_}"
  SSH_AUTH_SOCK="/nonexistent/path/agent.sock"
  generate_context_file "${tmpdir}/ws" "applaude"
) >/dev/null 2>&1

CONTENT_NOSSH="$(cat "${tmpdir}/ws/.contagent/context.md" 2>/dev/null)"
assert_not_contains "$CONTENT_NOSSH" "## SSH Agent" "non-existent SSH_AUTH_SOCK path → SSH Agent section absent"

rm -rf "${tmpdir}"

# ---------------------------------------------------------------------------
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[ "${FAIL}" -eq 0 ]
