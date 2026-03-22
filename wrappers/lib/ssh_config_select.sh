# ssh_config_select.sh - SSH host selection from ~/.ssh/config
# Source this file; do not execute directly.
# Requires bash 4.3+ (uses declare -n namerefs).

# Parse ~/.ssh/config into a stride-4 array.
# Each block occupies 4 consecutive elements:
#   [N*4+0] — space-separated non-wildcard aliases
#   [N*4+1] — first HostName value (or "")
#   [N*4+2] — first IdentityFile value (or "")
#   [N*4+3] — verbatim block lines joined by $'\x01'
# Blocks where all aliases contain '*' or start with '!' are skipped.
# Usage: parse_ssh_config_hosts <config_file> <result_nameref>
parse_ssh_config_hosts() {
  local config_file="$1"
  local -n _psch_result="$2"
  _psch_result=()

  [ -f "${config_file}" ] || return 0

  local _cur_aliases="" _cur_hostname="" _cur_idfile="" _cur_lines=""
  local _in_match=0
  local _line _keyword _rest _token _filtered _v

  while IFS= read -r _line || [ -n "${_line}" ]; do
    read -r _keyword _rest <<< "${_line}"

    # SSH config allows both 'Keyword value' and 'Keyword=value' syntax; normalise.
    if [[ "${_keyword}" == *=* ]]; then
      # 'Keyword=value' — split on first '='
      _rest="${_keyword#*=}"
      _keyword="${_keyword%%=*}"
    elif [[ "${_rest}" == =* ]]; then
      # 'Keyword = value' — strip leading '= '
      _rest="${_rest#=}"
      _rest="${_rest# }"
    fi

    case "${_keyword,,}" in
      host)
        # Flush previous block (skip if all aliases were wildcards → empty _cur_aliases)
        if [ -n "${_cur_aliases}" ]; then
          _psch_result+=("${_cur_aliases}" "${_cur_hostname}" "${_cur_idfile}" "${_cur_lines}")
        fi
        _in_match=0
        _cur_aliases="" _cur_hostname="" _cur_idfile="" _cur_lines=""
        # Filter out wildcard and negation aliases; keep only plain host aliases.
        # Use read -ra to avoid glob expansion of tokens like '*'.
        _filtered=""
        local -a _tokens=()
        read -ra _tokens <<< "${_rest}"
        for _token in "${_tokens[@]}"; do
          [[ "${_token}" == *'*'* || "${_token}" == '!'* ]] || \
            _filtered="${_filtered:+${_filtered} }${_token}"
        done
        _cur_aliases="${_filtered}"
        _cur_lines="${_line}"
        ;;
      match)
        # Match blocks are not selectable; flush and stop accumulating
        if [ -n "${_cur_aliases}" ]; then
          _psch_result+=("${_cur_aliases}" "${_cur_hostname}" "${_cur_idfile}" "${_cur_lines}")
        fi
        _cur_aliases="" _cur_hostname="" _cur_idfile="" _cur_lines=""
        _in_match=1
        ;;
      *)
        # Append to current block (includes blank lines and comments)
        if [ "${_in_match}" -eq 0 ] && [ -n "${_cur_aliases}" ]; then
          _cur_lines="${_cur_lines}"$'\x01'"${_line}"
          _v="${_rest}"
          case "${_keyword,,}" in
            hostname)
              [ -z "${_cur_hostname}" ] && _cur_hostname="${_v}"
              ;;
            identityfile)
              [ -z "${_cur_idfile}" ] && _cur_idfile="${_v}"
              ;;
          esac
        fi
        ;;
    esac
  done < "${config_file}"

  # Flush last block
  if [ -n "${_cur_aliases}" ]; then
    _psch_result+=("${_cur_aliases}" "${_cur_hostname}" "${_cur_idfile}" "${_cur_lines}")
  fi
}

# Collect global ssh-config content (pre-Host directives and wildcard Host blocks)
# from <config_file> and append it verbatim to <dst_file>.
# This captures:
#   - Any directives written before the first Host/Match block (global defaults)
#   - Any Host block whose aliases are ALL wildcards ('*') or negations ('!')
# Usage: _collect_wildcard_ssh_blocks <config_file> <dst_file>
_collect_wildcard_ssh_blocks() {
  local config_file="$1"
  local dst_file="$2"

  [ -f "${config_file}" ] || return 0

  local _in_wildcard=0 _seen_host=0
  local _line _keyword _rest

  while IFS= read -r _line || [ -n "${_line}" ]; do
    read -r _keyword _rest <<< "${_line}"

    # Normalise 'Keyword=value' and 'Keyword = value' separators
    if [[ "${_keyword}" == *=* ]]; then
      _rest="${_keyword#*=}"
      _keyword="${_keyword%%=*}"
    elif [[ "${_rest}" == =* ]]; then
      _rest="${_rest#=}"
      _rest="${_rest# }"
    fi

    case "${_keyword,,}" in
      host)
        _in_wildcard=0
        _seen_host=1
        # Check if every alias token is a wildcard or negation
        local -a _tokens=()
        read -ra _tokens <<< "${_rest}"
        local _all_wild=1
        local _tok
        for _tok in "${_tokens[@]}"; do
          [[ "${_tok}" == *'*'* || "${_tok}" == '!'* ]] || { _all_wild=0; break; }
        done
        if [ "${_all_wild}" -eq 1 ] && [ "${#_tokens[@]}" -gt 0 ]; then
          _in_wildcard=1
          printf '%s\n' "${_line}" >> "${dst_file}"
        fi
        ;;
      match)
        _in_wildcard=0
        _seen_host=1
        ;;
      *)
        if [ "${_in_wildcard}" -eq 1 ]; then
          # Inside a wildcard Host block
          printf '%s\n' "${_line}" >> "${dst_file}"
        elif [ "${_seen_host}" -eq 0 ]; then
          # Before the first Host/Match — global directives
          printf '%s\n' "${_line}" >> "${dst_file}"
        fi
        ;;
    esac
  done < "${config_file}"
}

# Parse wildcard-only Host blocks (e.g. 'Host *') from <config_file> into a
# stride-4 array (same format as parse_ssh_config_hosts).
# Element [N*4+0] is the raw alias pattern (e.g. "*"); [N*4+1] is always "".
# Named Host blocks, Match blocks, and pre-Host global lines are ignored.
# Usage: _parse_ssh_catchall_blocks <config_file> <result_nameref>
_parse_ssh_catchall_blocks() {
  local config_file="$1"
  local -n _pscb_result="$2"
  _pscb_result=()

  [ -f "${config_file}" ] || return 0

  local _cur_aliases="" _cur_idfile="" _cur_lines=""
  local _in_catchall=0
  local _line _keyword _rest _tok
  local -a _tokens=()

  while IFS= read -r _line || [ -n "${_line}" ]; do
    read -r _keyword _rest <<< "${_line}"

    if [[ "${_keyword}" == *=* ]]; then
      _rest="${_keyword#*=}"
      _keyword="${_keyword%%=*}"
    elif [[ "${_rest}" == =* ]]; then
      _rest="${_rest#=}"
      _rest="${_rest# }"
    fi

    case "${_keyword,,}" in
      host)
        if [ "${_in_catchall}" -eq 1 ] && [ -n "${_cur_aliases}" ]; then
          _pscb_result+=("${_cur_aliases}" "" "${_cur_idfile}" "${_cur_lines}")
        fi
        _in_catchall=0
        _cur_aliases="" _cur_idfile="" _cur_lines=""
        read -ra _tokens <<< "${_rest}"
        local _all_wild=1
        for _tok in "${_tokens[@]+"${_tokens[@]}"}"; do
          [[ "${_tok}" == *'*'* || "${_tok}" == '!'* ]] || { _all_wild=0; break; }
        done
        if [ "${_all_wild}" -eq 1 ] && [ "${#_tokens[@]}" -gt 0 ]; then
          _in_catchall=1
          _cur_aliases="${_rest}"
          _cur_lines="${_line}"
        fi
        ;;
      match)
        if [ "${_in_catchall}" -eq 1 ] && [ -n "${_cur_aliases}" ]; then
          _pscb_result+=("${_cur_aliases}" "" "${_cur_idfile}" "${_cur_lines}")
        fi
        _in_catchall=0
        _cur_aliases="" _cur_idfile="" _cur_lines=""
        ;;
      *)
        if [ "${_in_catchall}" -eq 1 ]; then
          _cur_lines="${_cur_lines}"$'\x01'"${_line}"
          case "${_keyword,,}" in
            identityfile)
              [ -z "${_cur_idfile}" ] && _cur_idfile="${_rest}"
              ;;
          esac
        fi
        ;;
    esac
  done < "${config_file}"

  if [ "${_in_catchall}" -eq 1 ] && [ -n "${_cur_aliases}" ]; then
    _pscb_result+=("${_cur_aliases}" "" "${_cur_idfile}" "${_cur_lines}")
  fi
}

# Interactively prompt the user to select SSH Host blocks from ~/.ssh/config.
# Writes selected Host blocks to <workspace>/.contagent/ssh-config and
# IdentityFile paths to <workspace>/.contagent/ssh-allowed-keys.
# Both files are always (over)written — safe to call repeatedly.
# Usage: prompt_ssh_host_selection <workspace>
prompt_ssh_host_selection() {
  local workspace="$1"
  local ssh_config_dst="${workspace}/.contagent/ssh-config"
  local allowed_keys_dst="${workspace}/.contagent/ssh-allowed-keys"
  mkdir -p "${workspace}/.contagent"

  local -a _hosts=()
  parse_ssh_config_hosts "${HOME}/.ssh/config" _hosts
  local _nhosts=$(( ${#_hosts[@]} / 4 ))

  # Wildcard / catch-all blocks (Host *, etc.) — shown as explicit menu items
  local -a _catchall=()
  _parse_ssh_catchall_blocks "${HOME}/.ssh/config" _catchall
  local _ncatchall=$(( ${#_catchall[@]} / 4 ))

  # First IdentityFile found in any catchall block — used for keyless injection
  local _catchall_idfile="" _ci
  for (( _ci = 0; _ci < _ncatchall; _ci++ )); do
    if [ -n "${_catchall[$(( _ci * 4 + 2 ))]}" ]; then
      _catchall_idfile="${_catchall[$(( _ci * 4 + 2 ))]}"
      break
    fi
  done

  echo ""
  echo "SSH Host Configuration"
  echo "Select SSH hosts to make available inside the container."
  echo "(Pick a number to toggle; pick Done when finished.)"
  echo ""

  local -a _selected=()
  local _done=0

  while [ "${_done}" -eq 0 ]; do
    local _i _aliases _hostname _idfile _idfile_display _is_sel _sel_mark _s
    echo "  1) Default key  (forward agent as-is, no host-specific config)"

    # Named hosts (indices 0..nhosts-1)
    for (( _i = 0; _i < _nhosts; _i++ )); do
      _aliases="${_hosts[$(( _i * 4 + 0 ))]}"
      _hostname="${_hosts[$(( _i * 4 + 1 ))]}"
      _idfile="${_hosts[$(( _i * 4 + 2 ))]}"
      if [ -n "${_idfile}" ]; then
        _idfile_display="${_idfile}"
      elif [ -n "${_catchall_idfile}" ]; then
        _idfile_display="${_catchall_idfile} (injected from Host *)"
      else
        _idfile_display="(uses any key in agent)"
      fi
      _is_sel=0
      for _s in "${_selected[@]+"${_selected[@]}"}"; do
        [ "${_s}" -eq "${_i}" ] && { _is_sel=1; break; }
      done
      _sel_mark=""
      [ "${_is_sel}" -eq 1 ] && _sel_mark=" [selected]"
      printf "  %d) %-20s HostName: %-30s IdentityFile: %s%s\n" \
        "$(( _i + 2 ))" "${_aliases}" "${_hostname:-(none)}" "${_idfile_display}" "${_sel_mark}"
    done

    # Catchall blocks (Host *, etc.) — indices nhosts..nhosts+ncatchall-1
    for (( _i = 0; _i < _ncatchall; _i++ )); do
      _aliases="${_catchall[$(( _i * 4 + 0 ))]}"
      _idfile="${_catchall[$(( _i * 4 + 2 ))]}"
      local _cidx=$(( _nhosts + _i ))
      _is_sel=0
      for _s in "${_selected[@]+"${_selected[@]}"}"; do
        [ "${_s}" -eq "${_cidx}" ] && { _is_sel=1; break; }
      done
      _sel_mark=""
      [ "${_is_sel}" -eq 1 ] && _sel_mark=" [selected]"
      printf "  %d) %-20s (Host *)                               IdentityFile: %s%s\n" \
        "$(( _nhosts + _i + 2 ))" "${_aliases}" "${_idfile:-(none)}" "${_sel_mark}"
    done

    echo "  $(( _nhosts + _ncatchall + 2 ))) Done / Skip"
    echo ""

    local _choice
    read -r -p "Choice: " _choice || { _done=1; continue; }

    if [ "${_choice}" = "1" ]; then
      printf '__default__\n' > "${allowed_keys_dst}"
      : > "${ssh_config_dst}"
      _collect_wildcard_ssh_blocks "${HOME}/.ssh/config" "${ssh_config_dst}"
      echo ""
      echo "Saved: SSH agent will be forwarded as-is (default key mode)."
      echo ""
      return 0
    elif [ "${_choice}" = "$(( _nhosts + _ncatchall + 2 ))" ]; then
      _done=1
    elif [[ "${_choice}" =~ ^[0-9]+$ ]] && \
         [ "${_choice}" -ge 2 ] && \
         [ "${_choice}" -le "$(( _nhosts + _ncatchall + 1 ))" ]; then
      local _idx=$(( _choice - 2 ))
      local -a _new_selected=()
      local _was_selected=0
      for _s in "${_selected[@]+"${_selected[@]}"}"; do
        if [ "${_s}" -eq "${_idx}" ]; then
          _was_selected=1
        else
          _new_selected+=("${_s}")
        fi
      done
      if [ "${_was_selected}" -eq 0 ]; then
        _new_selected+=("${_idx}")
      fi
      _selected=("${_new_selected[@]+"${_new_selected[@]}"}")
    else
      echo "Invalid choice. Please enter a number from the list."
    fi
    echo ""
  done

  # Write selected blocks and key paths
  : > "${ssh_config_dst}"
  : > "${allowed_keys_dst}"

  if [ "${#_selected[@]}" -eq 0 ]; then
    echo "No hosts selected. SSH host injection disabled."
    echo ""
    return 0
  fi

  local _block _idfile _named_count=0 _catchall_count=0
  for _s in "${_selected[@]}"; do
    if [ "${_s}" -lt "${_nhosts}" ]; then
      # Named host
      _block="${_hosts[$(( _s * 4 + 3 ))]}"
      _idfile="${_hosts[$(( _s * 4 + 2 ))]}"
      # Inject catchall IdentityFile if this host has no key of its own
      if [ -z "${_idfile}" ] && [ -n "${_catchall_idfile}" ]; then
        _block="${_block}"$'\x01'"    IdentityFile ${_catchall_idfile}"
        _idfile="${_catchall_idfile}"
      fi
      printf '%s\n' "${_block//$'\x01'/$'\n'}" >> "${ssh_config_dst}"
      [ -n "${_idfile}" ] && printf '%s\n' "${_idfile}" >> "${allowed_keys_dst}"
      _named_count=$(( _named_count + 1 ))
    else
      # Catchall block (Host *, etc.)
      local _cidx=$(( _s - _nhosts ))
      _block="${_catchall[$(( _cidx * 4 + 3 ))]}"
      _idfile="${_catchall[$(( _cidx * 4 + 2 ))]}"
      printf '%s\n' "${_block//$'\x01'/$'\n'}" >> "${ssh_config_dst}"
      [ -n "${_idfile}" ] && printf '%s\n' "${_idfile}" >> "${allowed_keys_dst}"
      _catchall_count=$(( _catchall_count + 1 ))
    fi
  done

  [ "${_named_count}" -gt 0 ] && \
    echo "Saved ${_named_count} host block(s) to .contagent/ssh-config"
  [ "${_catchall_count}" -gt 0 ] && \
    echo "Saved ${_catchall_count} Host * block(s) to .contagent/ssh-config"
  [ -s "${allowed_keys_dst}" ] && \
    echo "Saved key path(s) to .contagent/ssh-allowed-keys"
  echo ""
}

# Print a summary of the SSH configuration for a workspace.
# Usage: list_ssh_selection <workspace>
list_ssh_selection() {
  local workspace="$1"
  local ssh_config="${workspace}/.contagent/ssh-config"
  local allowed_keys="${workspace}/.contagent/ssh-allowed-keys"

  echo "SSH configuration for: ${workspace}"
  echo ""

  if [ ! -f "${allowed_keys}" ] && [ ! -f "${ssh_config}" ]; then
    echo "  Not configured. Run 'contagent ssh add' to set up."
    echo ""
    return 0
  fi

  if grep -qxF '__default__' "${allowed_keys}" 2>/dev/null; then
    echo "  Mode: Default key (host agent forwarded as-is, no key filtering)"
    echo ""
    return 0
  fi

  if [ -s "${ssh_config}" ]; then
    echo "  Mode: Selected hosts"
    echo ""
    echo "  Host blocks (.contagent/ssh-config):"
    local _line
    while IFS= read -r _line || [ -n "${_line}" ]; do
      [[ "${_line}" =~ ^[Hh][Oo][Ss][Tt][[:space:]] ]] && \
        printf '    %s\n' "${_line}"
    done < "${ssh_config}"
  else
    echo "  Mode: No hosts selected (SSH host injection disabled)"
  fi

  if [ -s "${allowed_keys}" ]; then
    echo ""
    echo "  Allowed keys (.contagent/ssh-allowed-keys):"
    while IFS= read -r _line || [ -n "${_line}" ]; do
      [[ -z "${_line}" || "${_line}" =~ ^[[:space:]]*# ]] && continue
      printf '    %s\n' "${_line}"
    done < "${allowed_keys}"
  fi

  echo ""
}
