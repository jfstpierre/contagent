#!/bin/bash
# Tests for parse_ssh_config_hosts, _collect_wildcard_ssh_blocks (_ssh_config_select.sh)
# and _inject_ssh_config (common.sh).

set -uo pipefail

_LIB_SELECT_="$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../wrappers/lib/ssh_config_select.sh"
_LIB_COMMON_="$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../wrappers/lib/common.sh"
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

# Helper: write a temp ssh config file and return its path via a global
_tmpdir=""
_cfg=""

_make_config() {
  _tmpdir="$(mktemp -d)"
  _cfg="${_tmpdir}/ssh_config"
  cat > "${_cfg}"
}

_cleanup() {
  rm -rf "${_tmpdir:-}"
}

# ---------------------------------------------------------------------------
echo "=== parse_ssh_config_hosts: file edge cases ==="

describe "Non-existent config → empty array."

source "${_LIB_SELECT_}"

(
  source "${_LIB_SELECT_}"
  result=()
  parse_ssh_config_hosts "/nonexistent-path-xyzzy/config" result
  printf '%d\n' "${#result[@]}"
) > /tmp/_psch_out 2>&1
assert_eq "$(cat /tmp/_psch_out)" "0" "parse: non-existent config → empty array"

describe "Empty config file → empty array."

_make_config < /dev/null
(
  source "${_LIB_SELECT_}"
  result=()
  parse_ssh_config_hosts "${_cfg}" result
  printf '%d\n' "${#result[@]}"
) > /tmp/_psch_out 2>&1
assert_eq "$(cat /tmp/_psch_out)" "0" "parse: empty config → empty array"
_cleanup

describe "Config with only 'Host *' → empty array (wildcard-only block skipped)."

_make_config <<'EOF'
Host *
    ServerAliveInterval 60
EOF
(
  source "${_LIB_SELECT_}"
  result=()
  parse_ssh_config_hosts "${_cfg}" result
  printf '%d\n' "${#result[@]}"
) > /tmp/_psch_out 2>&1
assert_eq "$(cat /tmp/_psch_out)" "0" "parse: Host * only → empty array"
_cleanup

# ---------------------------------------------------------------------------
echo "=== parse_ssh_config_hosts: single named block ==="

describe \
  "One named block with HostName, IdentityFile, a comment, and blank line." \
  "Verify aliases, hostname, idfile, and that block text contains all lines."

_make_config <<'EOF'
Host foo
    HostName example.com
    IdentityFile ~/.ssh/id_foo
    # a comment
    User git

EOF
(
  source "${_LIB_SELECT_}"
  result=()
  parse_ssh_config_hosts "${_cfg}" result
  printf 'len=%d\n' "${#result[@]}"
  printf 'aliases=%s\n' "${result[0]}"
  printf 'hostname=%s\n' "${result[1]}"
  printf 'idfile=%s\n' "${result[2]}"
  printf 'block=%s\n' "${result[3]}"
) > /tmp/_psch_out 2>&1
_out="$(cat /tmp/_psch_out)"
assert_eq "$(printf '%s\n' "${_out}" | grep '^len=' | cut -d= -f2)" "4" "parse: single block → 4 elements"
assert_eq "$(printf '%s\n' "${_out}" | grep '^aliases=' | cut -d= -f2)" "foo" "parse: single block → aliases"
assert_eq "$(printf '%s\n' "${_out}" | grep '^hostname=' | cut -d= -f2)" "example.com" "parse: single block → hostname"
assert_eq "$(printf '%s\n' "${_out}" | grep '^idfile=' | cut -d= -f2)" "~/.ssh/id_foo" "parse: single block → idfile"
assert_contains "${_out}" "Host foo" "parse: single block → block contains Host line"
assert_contains "${_out}" "HostName example.com" "parse: single block → block contains HostName"
assert_contains "${_out}" "IdentityFile ~/.ssh/id_foo" "parse: single block → block contains IdentityFile"
assert_contains "${_out}" "# a comment" "parse: single block → block contains comment"
_cleanup

# ---------------------------------------------------------------------------
echo "=== parse_ssh_config_hosts: '='-separated keywords ==="

describe "IdentityFile=~/.ssh/id_eq and HostName=host.example (no spaces around =)."

_make_config <<'EOF'
Host eqtest
    HostName=host.example
    IdentityFile=~/.ssh/id_eq
EOF
(
  source "${_LIB_SELECT_}"
  result=()
  parse_ssh_config_hosts "${_cfg}" result
  printf 'hostname=%s\n' "${result[1]}"
  printf 'idfile=%s\n' "${result[2]}"
) > /tmp/_psch_out 2>&1
_out="$(cat /tmp/_psch_out)"
assert_eq "$(printf '%s\n' "${_out}" | grep '^hostname=' | cut -d= -f2-)" "host.example" "parse: = syntax → hostname parsed"
assert_eq "$(printf '%s\n' "${_out}" | grep '^idfile=' | cut -d= -f2-)" "~/.ssh/id_eq" "parse: = syntax → idfile parsed"
_cleanup

# ---------------------------------------------------------------------------
echo "=== parse_ssh_config_hosts: multiple named blocks ==="

describe "Three named Host blocks → array of length 12 (3×4), distinct aliases."

_make_config <<'EOF'
Host alpha
    HostName alpha.example.com

Host beta
    HostName beta.example.com
    IdentityFile ~/.ssh/id_beta

Host gamma
    HostName gamma.example.com
EOF
(
  source "${_LIB_SELECT_}"
  result=()
  parse_ssh_config_hosts "${_cfg}" result
  printf 'len=%d\n' "${#result[@]}"
  printf 'a0=%s\n' "${result[0]}"
  printf 'a1=%s\n' "${result[4]}"
  printf 'a2=%s\n' "${result[8]}"
) > /tmp/_psch_out 2>&1
_out="$(cat /tmp/_psch_out)"
assert_eq "$(printf '%s\n' "${_out}" | grep '^len=' | cut -d= -f2)" "12" "parse: 3 blocks → 12 elements"
assert_eq "$(printf '%s\n' "${_out}" | grep '^a0=' | cut -d= -f2)" "alpha" "parse: block 0 aliases = alpha"
assert_eq "$(printf '%s\n' "${_out}" | grep '^a1=' | cut -d= -f2)" "beta" "parse: block 1 aliases = beta"
assert_eq "$(printf '%s\n' "${_out}" | grep '^a2=' | cut -d= -f2)" "gamma" "parse: block 2 aliases = gamma"
_cleanup

# ---------------------------------------------------------------------------
echo "=== parse_ssh_config_hosts: mixed wildcards filtered ==="

describe "'Host myserver * !old' → aliases='myserver'; block still present."

_make_config <<'EOF'
Host myserver * !old
    HostName myserver.example.com
EOF
(
  source "${_LIB_SELECT_}"
  result=()
  parse_ssh_config_hosts "${_cfg}" result
  printf 'len=%d\n' "${#result[@]}"
  printf 'aliases=%s\n' "${result[0]}"
) > /tmp/_psch_out 2>&1
_out="$(cat /tmp/_psch_out)"
assert_eq "$(printf '%s\n' "${_out}" | grep '^len=' | cut -d= -f2)" "4" "parse: mixed aliases → block present"
assert_eq "$(printf '%s\n' "${_out}" | grep '^aliases=' | cut -d= -f2)" "myserver" "parse: mixed aliases → wildcards stripped"
_cleanup

# ---------------------------------------------------------------------------
echo "=== parse_ssh_config_hosts: Match block stops accumulation ==="

describe \
  "Host foo, then Match block, then Host bar." \
  "Only foo and bar in result; Match content not accumulated."

_make_config <<'EOF'
Host foo
    HostName foo.example.com

Match host bar.example.com
    IdentityFile ~/.ssh/id_match

Host bar
    HostName bar.example.com
EOF
(
  source "${_LIB_SELECT_}"
  result=()
  parse_ssh_config_hosts "${_cfg}" result
  printf 'len=%d\n' "${#result[@]}"
  printf 'a0=%s\n' "${result[0]}"
  printf 'a1=%s\n' "${result[4]}"
  printf 'b0=%s\n' "${result[3]}"
) > /tmp/_psch_out 2>&1
_out="$(cat /tmp/_psch_out)"
assert_eq "$(printf '%s\n' "${_out}" | grep '^len=' | cut -d= -f2)" "8" "parse: Match block → only 2 named blocks (8 elements)"
assert_eq "$(printf '%s\n' "${_out}" | grep '^a0=' | cut -d= -f2)" "foo" "parse: Match block → first block is foo"
assert_eq "$(printf '%s\n' "${_out}" | grep '^a1=' | cut -d= -f2)" "bar" "parse: Match block → second block is bar"
assert_not_contains "${_out}" "id_match" "parse: Match block → Match content not in foo block"
_cleanup

# ---------------------------------------------------------------------------
echo "=== parse_ssh_config_hosts: case-insensitive keywords ==="

describe "HOST, HOSTNAME, IDENTITYFILE in uppercase → parsed correctly."

_make_config <<'EOF'
HOST capshost
    HOSTNAME caps.example.com
    IDENTITYFILE ~/.ssh/id_caps
EOF
(
  source "${_LIB_SELECT_}"
  result=()
  parse_ssh_config_hosts "${_cfg}" result
  printf 'aliases=%s\n' "${result[0]}"
  printf 'hostname=%s\n' "${result[1]}"
  printf 'idfile=%s\n' "${result[2]}"
) > /tmp/_psch_out 2>&1
_out="$(cat /tmp/_psch_out)"
assert_eq "$(printf '%s\n' "${_out}" | grep '^aliases=' | cut -d= -f2)" "capshost" "parse: uppercase HOST → aliases"
assert_eq "$(printf '%s\n' "${_out}" | grep '^hostname=' | cut -d= -f2)" "caps.example.com" "parse: uppercase HOSTNAME"
assert_eq "$(printf '%s\n' "${_out}" | grep '^idfile=' | cut -d= -f2)" "~/.ssh/id_caps" "parse: uppercase IDENTITYFILE"
_cleanup

# ---------------------------------------------------------------------------
echo "=== _collect_wildcard_ssh_blocks: non-existent config ==="

describe "Non-existent config → dst file untouched (stays empty)."

_make_config < /dev/null
_dst="${_tmpdir}/dst"
: > "${_dst}"
(
  source "${_LIB_SELECT_}"
  _collect_wildcard_ssh_blocks "/nonexistent-path-xyzzy/config" "${_dst}"
)
assert_eq "$(cat "${_dst}")" "" "collect: non-existent config → dst empty"
_cleanup

# ---------------------------------------------------------------------------
echo "=== _collect_wildcard_ssh_blocks: global directives only ==="

describe "Lines before first Host/Match are written verbatim to dst."

_make_config <<'EOF'
ServerAliveInterval 60

# global comment
EOF
_dst="${_tmpdir}/dst"
: > "${_dst}"
(
  source "${_LIB_SELECT_}"
  _collect_wildcard_ssh_blocks "${_cfg}" "${_dst}"
)
_got="$(cat "${_dst}")"
assert_contains "${_got}" "ServerAliveInterval 60" "collect: global directive written"
assert_contains "${_got}" "# global comment" "collect: global comment written"
_cleanup

# ---------------------------------------------------------------------------
echo "=== _collect_wildcard_ssh_blocks: Host * block captured ==="

describe \
  "Config: global line, Host * block, named Host foo." \
  "dst gets global + Host * block; NOT the foo block."

_make_config <<'EOF'
ServerAliveInterval 30
Host *
    AddKeysToAgent yes
    StrictHostKeyChecking accept-new
Host foo
    HostName foo.example.com
    IdentityFile ~/.ssh/id_foo
EOF
_dst="${_tmpdir}/dst"
: > "${_dst}"
(
  source "${_LIB_SELECT_}"
  _collect_wildcard_ssh_blocks "${_cfg}" "${_dst}"
)
_got="$(cat "${_dst}")"
assert_contains "${_got}" "ServerAliveInterval 30" "collect: global line captured"
assert_contains "${_got}" "Host *" "collect: Host * line captured"
assert_contains "${_got}" "AddKeysToAgent yes" "collect: Host * body captured"
assert_not_contains "${_got}" "Host foo" "collect: named Host not captured"
assert_not_contains "${_got}" "id_foo" "collect: named Host body not captured"
_cleanup

# ---------------------------------------------------------------------------
echo "=== _collect_wildcard_ssh_blocks: named-only config ==="

describe "Config with only named Host blocks, no globals, no Host *. dst stays empty."

_make_config <<'EOF'
Host alpha
    HostName alpha.example.com
Host beta
    HostName beta.example.com
EOF
_dst="${_tmpdir}/dst"
: > "${_dst}"
(
  source "${_LIB_SELECT_}"
  _collect_wildcard_ssh_blocks "${_cfg}" "${_dst}"
)
assert_eq "$(cat "${_dst}")" "" "collect: named-only config → dst empty"
_cleanup

# ---------------------------------------------------------------------------
echo "=== _collect_wildcard_ssh_blocks: Match block not captured ==="

describe "Host * → captured; Match block body → not captured."

_make_config <<'EOF'
Host *
    ServerAliveInterval 60
Match exec "test -f /etc/mysite"
    IdentityFile ~/.ssh/id_site
Host real
    HostName real.example.com
EOF
_dst="${_tmpdir}/dst"
: > "${_dst}"
(
  source "${_LIB_SELECT_}"
  _collect_wildcard_ssh_blocks "${_cfg}" "${_dst}"
)
_got="$(cat "${_dst}")"
assert_contains "${_got}" "Host *" "collect: Match test → Host * captured"
assert_contains "${_got}" "ServerAliveInterval 60" "collect: Match test → Host * body captured"
assert_not_contains "${_got}" "id_site" "collect: Match block body not captured"
assert_not_contains "${_got}" "Host real" "collect: named Host not captured"
_cleanup

# ---------------------------------------------------------------------------
echo "=== _parse_ssh_catchall_blocks: edge cases ==="

describe "Non-existent config → empty array."

(
  source "${_LIB_SELECT_}"
  result=()
  _parse_ssh_catchall_blocks "/nonexistent-path-xyzzy/config" result
  printf '%d\n' "${#result[@]}"
) > /tmp/_pscb_out 2>&1
assert_eq "$(cat /tmp/_pscb_out)" "0" "catchall: non-existent config → empty array"

describe "Named-only config (no Host *) → empty array."

_make_config <<'EOF'
Host named
    HostName named.example.com
    IdentityFile ~/.ssh/id_named
EOF
(
  source "${_LIB_SELECT_}"
  result=()
  _parse_ssh_catchall_blocks "${_cfg}" result
  printf '%d\n' "${#result[@]}"
) > /tmp/_pscb_out 2>&1
assert_eq "$(cat /tmp/_pscb_out)" "0" "catchall: named-only config → empty array"
_cleanup

# ---------------------------------------------------------------------------
echo "=== _parse_ssh_catchall_blocks: Host * block captured ==="

describe "Config with Host * containing IdentityFile. Verify idfile and verbatim block."

_make_config <<'EOF'
Host named
    HostName named.example.com
Host *
    IdentityFile ~/.ssh/id_default
    ServerAliveInterval 60
EOF
(
  source "${_LIB_SELECT_}"
  result=()
  _parse_ssh_catchall_blocks "${_cfg}" result
  printf 'len=%d\n' "${#result[@]}"
  printf 'aliases=%s\n' "${result[0]}"
  printf 'idfile=%s\n' "${result[2]}"
  printf 'block=%s\n' "${result[3]}"
) > /tmp/_pscb_out 2>&1
_out="$(cat /tmp/_pscb_out)"
assert_eq "$(printf '%s\n' "${_out}" | grep '^len=' | cut -d= -f2)" "4" "catchall: Host * block → 4 elements"
assert_eq "$(printf '%s\n' "${_out}" | grep '^aliases=' | cut -d= -f2)" "*" "catchall: aliases = *"
assert_eq "$(printf '%s\n' "${_out}" | grep '^idfile=' | cut -d= -f2-)" "~/.ssh/id_default" "catchall: IdentityFile parsed"
assert_contains "${_out}" "Host *" "catchall: block contains Host * line"
assert_contains "${_out}" "ServerAliveInterval 60" "catchall: block body captured verbatim"
assert_not_contains "${_out}" "Host named" "catchall: named Host not captured"
_cleanup

# ---------------------------------------------------------------------------
echo "=== prompt_ssh_host_selection: IdentityFile injected into keyless host ==="

describe \
  "Config: Host * with IdentityFile, plus a keyless named host." \
  "Selecting the named host should inject the catchall IdentityFile into its block." \
  "Host * should NOT appear in ssh-config unless explicitly selected."

_make_config <<'EOF'
Host keyless
    HostName keyless.example.com
Host *
    IdentityFile ~/.ssh/id_catchall
EOF
_tmpdir_w="$(mktemp -d)"
mkdir -p "${_tmpdir_w}/.contagent"
# Option 2 = keyless (index 0), then Done (option 3 = 0 named + 1 catchall + 2)
(
  source "${_LIB_SELECT_}"
  HOME="${_tmpdir}"
  # Override HOME so the function reads our test config
  cp "${_cfg}" "${_tmpdir}/.ssh_test_config"
  # Monkey-patch: redirect HOME/.ssh/config to our test file
  mkdir -p "${_tmpdir}/.ssh"
  cp "${_cfg}" "${_tmpdir}/.ssh/config"
  HOME="${_tmpdir}" prompt_ssh_host_selection "${_tmpdir_w}" <<< $'2\n4\n'
) > /tmp/_psh_out 2>&1
_ssh_cfg="$(cat "${_tmpdir_w}/.contagent/ssh-config" 2>/dev/null || echo '')"
_allowed="$(cat "${_tmpdir_w}/.contagent/ssh-allowed-keys" 2>/dev/null || echo '')"
assert_contains "${_ssh_cfg}" "Host keyless" "inject: keyless host block present"
assert_contains "${_ssh_cfg}" "IdentityFile ~/.ssh/id_catchall" "inject: catchall key injected into keyless block"
assert_not_contains "${_ssh_cfg}" "Host *" "inject: Host * NOT auto-added"
assert_contains "${_allowed}" "~/.ssh/id_catchall" "inject: catchall key in allowed-keys"
rm -rf "${_tmpdir_w}"
_cleanup

# ---------------------------------------------------------------------------
echo "=== prompt_ssh_host_selection: keyed host keeps its own key ==="

describe \
  "Config: keyed named host + Host * with different key." \
  "Selecting the keyed host should NOT inject the catchall key."

_make_config <<'EOF'
Host keyed
    HostName keyed.example.com
    IdentityFile ~/.ssh/id_own
Host *
    IdentityFile ~/.ssh/id_catchall
EOF
_tmpdir_w="$(mktemp -d)"
mkdir -p "${_tmpdir_w}/.contagent"
(
  source "${_LIB_SELECT_}"
  mkdir -p "${_tmpdir}/.ssh"
  cp "${_cfg}" "${_tmpdir}/.ssh/config"
  HOME="${_tmpdir}" prompt_ssh_host_selection "${_tmpdir_w}" <<< $'2\n4\n'
) > /tmp/_psh_out 2>&1
_ssh_cfg="$(cat "${_tmpdir_w}/.contagent/ssh-config" 2>/dev/null || echo '')"
_allowed="$(cat "${_tmpdir_w}/.contagent/ssh-allowed-keys" 2>/dev/null || echo '')"
assert_contains "${_ssh_cfg}" "IdentityFile ~/.ssh/id_own" "keyed: own key present"
assert_not_contains "${_ssh_cfg}" "id_catchall" "keyed: catchall key NOT injected"
assert_contains "${_allowed}" "~/.ssh/id_own" "keyed: own key in allowed-keys"
assert_not_contains "${_allowed}" "id_catchall" "keyed: catchall NOT in allowed-keys"
rm -rf "${_tmpdir_w}"
_cleanup

# ---------------------------------------------------------------------------
echo "=== prompt_ssh_host_selection: explicit Host * selection ==="

describe \
  "User explicitly selects Host * via menu." \
  "Both named block AND Host * block appear in ssh-config."

_make_config <<'EOF'
Host myserver
    HostName myserver.example.com
    IdentityFile ~/.ssh/id_myserver
Host *
    ServerAliveInterval 30
    IdentityFile ~/.ssh/id_catchall
EOF
_tmpdir_w="$(mktemp -d)"
mkdir -p "${_tmpdir_w}/.contagent"
# 1 named + 1 catchall → Done is option 4 (1+1+1+1); catchall is option 3
(
  source "${_LIB_SELECT_}"
  mkdir -p "${_tmpdir}/.ssh"
  cp "${_cfg}" "${_tmpdir}/.ssh/config"
  HOME="${_tmpdir}" prompt_ssh_host_selection "${_tmpdir_w}" <<< $'2\n3\n4\n'
) > /tmp/_psh_out 2>&1
_ssh_cfg="$(cat "${_tmpdir_w}/.contagent/ssh-config" 2>/dev/null || echo '')"
assert_contains "${_ssh_cfg}" "Host myserver" "explicit *: named block present"
assert_contains "${_ssh_cfg}" "Host *" "explicit *: Host * block present"
assert_contains "${_ssh_cfg}" "ServerAliveInterval 30" "explicit *: Host * body present"
rm -rf "${_tmpdir_w}"
_cleanup

# ---------------------------------------------------------------------------
rm -f /tmp/_pscb_out /tmp/_psh_out

echo "=== _inject_ssh_config: no-op when ssh-config absent ==="

describe "No .contagent/ssh-config file → target home ~/.ssh/config not created."

_tmpdir="$(mktemp -d)"
_ws="${_tmpdir}/workspace"
_home="${_tmpdir}/home"
mkdir -p "${_ws}/.contagent"
mkdir -p "${_home}"

(
  source "${_LIB_COMMON_}"
  _inject_ssh_config "${_ws}" "${_home}"
)
if [ -f "${_home}/.ssh/config" ]; then
  fail "_inject: no ssh-config → config not created" "file was created unexpectedly"
else
  ok "_inject: no ssh-config → target config not created"
fi
rm -rf "${_tmpdir}"

# ---------------------------------------------------------------------------
echo "=== _inject_ssh_config: no-op when ssh-config empty ==="

describe "Empty .contagent/ssh-config → target config untouched."

_tmpdir="$(mktemp -d)"
_ws="${_tmpdir}/workspace"
_home="${_tmpdir}/home"
mkdir -p "${_ws}/.contagent"
mkdir -p "${_home}/.ssh"
: > "${_ws}/.contagent/ssh-config"
printf 'ExistingLine yes\n' > "${_home}/.ssh/config"

(
  source "${_LIB_COMMON_}"
  _inject_ssh_config "${_ws}" "${_home}"
)
assert_eq "$(cat "${_home}/.ssh/config")" "ExistingLine yes" "_inject: empty ssh-config → existing config unchanged"
rm -rf "${_tmpdir}"

# ---------------------------------------------------------------------------
echo "=== _inject_ssh_config: first injection into empty home ==="

describe \
  "Fresh home with no ~/.ssh/config." \
  "After inject: sentinels present, Host block between them, perms 700/600."

_tmpdir="$(mktemp -d)"
_ws="${_tmpdir}/workspace"
_home="${_tmpdir}/home"
mkdir -p "${_ws}/.contagent"
mkdir -p "${_home}"
printf 'Host injected\n    HostName injected.example.com\n' > "${_ws}/.contagent/ssh-config"

(
  source "${_LIB_COMMON_}"
  _inject_ssh_config "${_ws}" "${_home}"
)
_got="$(cat "${_home}/.ssh/config")"
assert_contains "${_got}" "# contagent-managed-hosts-begin" "_inject: fresh → begin sentinel present"
assert_contains "${_got}" "# contagent-managed-hosts-end" "_inject: fresh → end sentinel present"
assert_contains "${_got}" "Host injected" "_inject: fresh → Host block present"
assert_eq "$(stat -c '%a' "${_home}/.ssh")" "700" "_inject: .ssh/ has mode 700"
assert_eq "$(stat -c '%a' "${_home}/.ssh/config")" "600" "_inject: config has mode 600"
rm -rf "${_tmpdir}"

# ---------------------------------------------------------------------------
echo "=== _inject_ssh_config: appended after pre-existing content ==="

describe \
  "Target config has existing user content." \
  "After inject: existing content preserved, sentinel block appended below."

_tmpdir="$(mktemp -d)"
_ws="${_tmpdir}/workspace"
_home="${_tmpdir}/home"
mkdir -p "${_ws}/.contagent"
mkdir -p "${_home}/.ssh"
printf 'Host injected\n    HostName injected.example.com\n' > "${_ws}/.contagent/ssh-config"
printf 'Host existing\n    HostName existing.example.com\n' > "${_home}/.ssh/config"
chmod 600 "${_home}/.ssh/config"

(
  source "${_LIB_COMMON_}"
  _inject_ssh_config "${_ws}" "${_home}"
)
_got="$(cat "${_home}/.ssh/config")"
assert_contains "${_got}" "Host existing" "_inject: existing content preserved"
assert_contains "${_got}" "Host injected" "_inject: new block appended"
# existing content should appear before the sentinel
_existing_line="$(grep -n 'Host existing' "${_home}/.ssh/config" | cut -d: -f1)"
_sentinel_line="$(grep -n 'contagent-managed-hosts-begin' "${_home}/.ssh/config" | cut -d: -f1)"
if [ "${_existing_line}" -lt "${_sentinel_line}" ]; then
  ok "_inject: existing content is before sentinel block"
else
  fail "_inject: existing content is before sentinel block" \
    "existing on line ${_existing_line}, sentinel on line ${_sentinel_line}"
fi
rm -rf "${_tmpdir}"

# ---------------------------------------------------------------------------
echo "=== _inject_ssh_config: idempotent on second call ==="

describe "Run inject twice with same ssh-config. Sentinel appears exactly once."

_tmpdir="$(mktemp -d)"
_ws="${_tmpdir}/workspace"
_home="${_tmpdir}/home"
mkdir -p "${_ws}/.contagent"
mkdir -p "${_home}"
printf 'Host idempotent\n    HostName idem.example.com\n' > "${_ws}/.contagent/ssh-config"

(
  source "${_LIB_COMMON_}"
  _inject_ssh_config "${_ws}" "${_home}"
  _inject_ssh_config "${_ws}" "${_home}"
)
_count="$(grep -c 'contagent-managed-hosts-begin' "${_home}/.ssh/config")"
assert_eq "${_count}" "1" "_inject: idempotent → sentinel appears exactly once"
rm -rf "${_tmpdir}"

# ---------------------------------------------------------------------------
echo "=== _inject_ssh_config: updated config replaces old block ==="

describe \
  "Inject config-A, then inject config-B." \
  "config-A content gone; config-B content present; one sentinel block."

_tmpdir="$(mktemp -d)"
_ws="${_tmpdir}/workspace"
_home="${_tmpdir}/home"
mkdir -p "${_ws}/.contagent"
mkdir -p "${_home}"
printf 'Host config-a\n    HostName a.example.com\n' > "${_ws}/.contagent/ssh-config"

(
  source "${_LIB_COMMON_}"
  _inject_ssh_config "${_ws}" "${_home}"
)
printf 'Host config-b\n    HostName b.example.com\n' > "${_ws}/.contagent/ssh-config"
(
  source "${_LIB_COMMON_}"
  _inject_ssh_config "${_ws}" "${_home}"
)
_got="$(cat "${_home}/.ssh/config")"
assert_not_contains "${_got}" "Host config-a" "_inject: update → old block gone"
assert_contains "${_got}" "Host config-b" "_inject: update → new block present"
_count="$(grep -c 'contagent-managed-hosts-begin' "${_home}/.ssh/config")"
assert_eq "${_count}" "1" "_inject: update → single sentinel block"
rm -rf "${_tmpdir}"

# ---------------------------------------------------------------------------
rm -f /tmp/_psch_out
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
