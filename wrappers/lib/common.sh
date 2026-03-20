# common.sh - Shared library for contagent wrapper scripts
# Source this file; do not execute directly.
# Requires bash 4.3+ (uses declare -n namerefs).

# Ensure lmod's module function is available.
# Returns 0 if module is (or becomes) available, 1 otherwise.
ensure_module() {
  if ! type module >/dev/null 2>&1; then
    for lmod_init in \
      /cvmfs/soft.computecanada.ca/nix/var/nix/profiles/16.09/lmod/lmod/init/bash \
      /etc/profile.d/lmod.sh \
      /usr/share/lmod/lmod/init/bash; do
      [ -f "$lmod_init" ] && { source "$lmod_init"; return 0; }
    done
    return 1
  fi
}

# Load the Apptainer module recorded by contagent, if any.
# Reads APPTAINER_MODULE from ~/.contagent/settings (or $CONTAGENT_DIR/settings).
load_apptainer_module() {
  local settings_file="${CONTAGENT_DIR:-${HOME}/.contagent}/settings"
  if [ -f "${settings_file}" ]; then
    local apptainer_module
    apptainer_module="$(grep '^APPTAINER_MODULE=' "${settings_file}" | cut -d= -f2-)"
    if [ -n "${apptainer_module:-}" ]; then
      if ensure_module; then
        module load "${apptainer_module}"
      else
        echo "Warning: lmod unavailable — could not load Apptainer module '${apptainer_module}'."
      fi
    fi
  fi
}

# Create .contagent/mounts with a template and first-run notice if absent.
# Usage: init_mounts_file <workspace>
init_mounts_file() {
  local workspace="$1"
  local mounts_file="${workspace}/.contagent/mounts"
  if [ ! -f "${mounts_file}" ]; then
    mkdir -p "${workspace}/.contagent"
    cat > "${mounts_file}" << 'MOUNTS_TEMPLATE'
# Extra bind mounts for contagent containers
#
# To mount additional host paths into the container, add entries below, one per line:
#   host_path:container_path[:mode]
#
# mode is optional; defaults to "ro" (read-only). Use "rw" for read-write access.
# Tilde (~) is expanded to your home directory ($HOME).
# Paths that do not exist on the host are skipped with a warning.
# Lines starting with # are comments and are ignored.
#
# Examples:
#   /data/shared:/data:ro
#   ~/models:/models:ro
#   /scratch/myproject:/scratch:rw
MOUNTS_TEMPLATE
    echo "Note: .contagent/mounts created."
    echo "  Add extra bind mounts for the container by editing:"
    echo "    ${mounts_file}"
    echo "  Format: host_path:container_path[:mode]  (mode: ro or rw, default: ro)"
    echo "  Example: /data/shared:/data:ro"
    echo ""
  fi
}

# Parse .contagent/mounts and append --bind args to a named array.
# Usage: parse_mounts_apptainer <workspace> <array_name>
parse_mounts_apptainer() {
  local workspace="$1"
  local -n _pmapp_arr="$2"
  local mounts_file="${workspace}/.contagent/mounts"
  if [ -f "${mounts_file}" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
      IFS=: read -r host_path container_path mode <<< "$line"
      if [ -z "${host_path}" ] || [ -z "${container_path}" ]; then
        echo "Warning: invalid entry in ${mounts_file}: ${line}"
        continue
      fi
      mode="${mode:-ro}"
      if [[ "${mode}" != "ro" && "${mode}" != "rw" ]]; then
        echo "Warning: unknown mode '${mode}' in ${mounts_file} (use ro or rw), defaulting to ro"
        mode="ro"
      fi
      host_path="${host_path/#\~/$HOME}"
      if [ ! -e "${host_path}" ]; then
        echo "Warning: mount source does not exist: ${host_path} (skipping)"
        continue
      fi
      _pmapp_arr+=("--bind" "${host_path}:${container_path}:${mode}")
    done < "${mounts_file}"
  fi
}

# Parse .contagent/mounts and append -v args to a named array (Docker format).
# Usage: parse_mounts_docker <workspace> <array_name>
parse_mounts_docker() {
  local workspace="$1"
  local -n _pmdock_arr="$2"
  local mounts_file="${workspace}/.contagent/mounts"
  if [ -f "${mounts_file}" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
      IFS=: read -r host_path container_path mode <<< "$line"
      if [ -z "${host_path}" ] || [ -z "${container_path}" ]; then
        echo "Warning: invalid entry in ${mounts_file}: ${line}"
        continue
      fi
      mode="${mode:-ro}"
      if [[ "${mode}" != "ro" && "${mode}" != "rw" ]]; then
        echo "Warning: unknown mode '${mode}' in ${mounts_file} (use ro or rw), defaulting to ro"
        mode="ro"
      fi
      host_path="${host_path/#\~/$HOME}"
      if [ ! -e "${host_path}" ]; then
        echo "Warning: mount source does not exist: ${host_path} (skipping)"
        continue
      fi
      _pmdock_arr+=("-v" "${host_path}:${container_path}:${mode}")
    done < "${mounts_file}"
  fi
}

# Interactively prompt the user to select SSH key file paths to allow in this workspace.
# Creates (or truncates) <allowed_keys_file> with the user's choices.
# Usage: _prompt_ssh_allowed_keys <allowed_keys_file>
_prompt_ssh_allowed_keys() {
  local allowed_keys_file="$1"
  mkdir -p "$(dirname "${allowed_keys_file}")"

  echo ""
  echo "Setting up SSH key access for this workspace."
  echo "To push/fetch from private repos inside the container, enter the SSH private"
  echo "key file path(s) you want to allow. Leave blank and press Enter to skip."
  echo ""

  # Show keys currently loaded in the host agent as a reference
  if [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "${SSH_AUTH_SOCK}" ]; then
    local _al
    if _al="$(ssh-add -l 2>/dev/null)"; then
      echo "Keys currently in your SSH agent:"
      printf '%s\n' "${_al}" | sed 's/^/  /'
      echo ""
    fi
  fi

  echo "Enter key file path(s), one per line. Press Enter on a blank line when done."
  echo "Type 'none' to disable SSH forwarding for this workspace."
  echo ""

  : > "${allowed_keys_file}"
  local _line _count=0
  while IFS= read -r -p "  Key path: " _line; do
    _line="${_line#"${_line%%[![:space:]]*}"}"   # ltrim
    _line="${_line%"${_line##*[![:space:]]}"}"   # rtrim
    [ -z "${_line}" ] && break
    if [ "${_line}" = "none" ]; then
      _count=0; break
    fi
    printf '%s\n' "${_line}" >> "${allowed_keys_file}"
    _count=$((_count + 1))
  done

  if [ "${_count}" -gt 0 ]; then
    echo ""
    echo "Saved ${_count} key path(s) to .contagent/ssh-allowed-keys."
  else
    : > "${allowed_keys_file}"   # ensure file exists but is empty (= disabled)
    echo ""
    echo "No keys specified. SSH forwarding disabled for this workspace."
  fi
  echo ""
}

# Start an isolated per-workspace ssh-agent loaded with only the allowed key files.
# On success: exports SSH_AUTH_SOCK, SSH_AGENT_PID; sets _CONTAGENT_SSH_AGENT_PID.
# Returns 0 when the agent is running with ≥1 key, 1 otherwise.
# Usage: _start_workspace_ssh_agent <workspace>
_start_workspace_ssh_agent() {
  local workspace="$1"
  local allowed_keys_file="${workspace}/.contagent/ssh-allowed-keys"

  [ -f "${allowed_keys_file}" ] || return 1

  # Skip if file has no actionable entries
  local _has=0 _l
  while IFS= read -r _l || [ -n "${_l}" ]; do
    [[ -z "${_l}" || "${_l}" =~ ^[[:space:]]*# ]] && continue
    _has=1; break
  done < "${allowed_keys_file}"
  [ "${_has}" -eq 0 ] && return 1

  # Launch an isolated ssh-agent
  local _aenv
  _aenv="$(ssh-agent -s 2>/dev/null)" || {
    echo "Warning: ssh-agent unavailable; SSH forwarding disabled."
    return 1
  }
  eval "${_aenv}" >/dev/null
  export SSH_AUTH_SOCK SSH_AGENT_PID
  _CONTAGENT_SSH_AGENT_PID="${SSH_AGENT_PID}"

  # Add each allowed key to the workspace agent
  local _key _exp _added=0
  while IFS= read -r _key || [ -n "${_key}" ]; do
    [[ -z "${_key}" || "${_key}" =~ ^[[:space:]]*# ]] && continue
    _exp="${_key/#\~/$HOME}"
    if [ ! -f "${_exp}" ]; then
      echo "Warning: SSH key file not found: ${_exp} (skipping)"
      continue
    fi
    if ssh-add "${_exp}" 2>/dev/null; then
      _added=$((_added + 1))
    else
      echo "Warning: could not add SSH key: ${_exp}"
      echo "  If the key has a passphrase, run 'ssh-add ${_exp}' first, then retry."
    fi
  done < "${allowed_keys_file}"

  if [ "${_added}" -eq 0 ]; then
    echo "Warning: no SSH keys were loaded; disabling SSH forwarding for this session."
    kill "${_CONTAGENT_SSH_AGENT_PID}" 2>/dev/null || true
    _CONTAGENT_SSH_AGENT_PID=""
    return 1
  fi

  return 0
}

# Kill the per-workspace ssh-agent if one is running.
# Safe to call unconditionally (no-op if no agent was started).
contagent_ssh_agent_cleanup() {
  if [ -n "${_CONTAGENT_SSH_AGENT_PID:-}" ]; then
    kill "${_CONTAGENT_SSH_AGENT_PID}" 2>/dev/null || true
    _CONTAGENT_SSH_AGENT_PID=""
  fi
}

# Append --bind args for SSH agent forwarding to an Apptainer args array.
# On first use (no ssh-allowed-keys file yet) prompts the user to select keys.
# Starts an isolated per-workspace agent with only the approved keys.
# Usage: forward_ssh_agent_apptainer <workspace> <array_name>
forward_ssh_agent_apptainer() {
  local workspace="$1"
  local -n _fwdssa_arr="$2"

  local _akeys="${workspace}/.contagent/ssh-allowed-keys"
  [ -f "${_akeys}" ] || _prompt_ssh_allowed_keys "${_akeys}"

  _start_workspace_ssh_agent "${workspace}" || return 0

  # SSH_AUTH_SOCK now points to the isolated workspace agent.
  # Apptainer inherits env vars automatically; only the bind mount is needed.
  _fwdssa_arr+=("--bind" "${SSH_AUTH_SOCK}:${SSH_AUTH_SOCK}")
}

# Append -v/-e args for SSH agent forwarding to a Docker args array.
# On first use (no ssh-allowed-keys file yet) prompts the user to select keys.
# Starts an isolated per-workspace agent with only the approved keys.
# Usage: forward_ssh_agent_docker <workspace> <array_name>
forward_ssh_agent_docker() {
  local workspace="$1"
  local -n _fwdssad_arr="$2"

  local _akeys="${workspace}/.contagent/ssh-allowed-keys"
  [ -f "${_akeys}" ] || _prompt_ssh_allowed_keys "${_akeys}"

  _start_workspace_ssh_agent "${workspace}" || return 0

  # Docker does not inherit host env; pass the socket path explicitly.
  _fwdssad_arr+=("-v" "${SSH_AUTH_SOCK}:${SSH_AUTH_SOCK}")
  _fwdssad_arr+=("-e" "SSH_AUTH_SOCK=${SSH_AUTH_SOCK}")
}

# Print LOADEDMODULES (colon-separated) as one module per line.
get_loaded_modules() {
  echo "${LOADEDMODULES:-}" | tr ':' '\n' | grep -v '^$'
}

# Purge all modules and reload each module listed in a file.
# Usage: load_modules_from_file <file>
load_modules_from_file() {
  local file="$1"
  if ! ensure_module; then
    echo "Warning: 'module' unavailable — skipping module loading."
    echo "Ensure lmod is initialized before running this script."
    return
  fi
  module purge
  while IFS= read -r mod || [ -n "$mod" ]; do
    [[ -z "$mod" || "$mod" =~ ^[[:space:]]*# ]] && continue
    echo "Loading module: $mod"
    module load "$mod"
  done < "$file"
}

# Reconcile loaded modules against a saved modules file.
# On first run: creates the file from currently loaded modules.
# On subsequent runs: prompts with C/U/I if loaded modules differ from saved.
# Usage: reconcile_cvmfs_modules <modules_file>
reconcile_cvmfs_modules() {
  local modules_file="$1"
  local current_modules
  current_modules="$(get_loaded_modules)"

  if [ ! -f "${modules_file}" ]; then
    mkdir -p "$(dirname "${modules_file}")"
    echo "${current_modules}" > "${modules_file}"
    echo "Saved loaded modules to ${modules_file}"
  else
    local saved_modules current_sorted saved_sorted
    saved_modules="$(cat "${modules_file}")"
    current_sorted="$(echo "${current_modules}" | sort)"
    saved_sorted="$(echo "${saved_modules}" | sort)"

    if [ "${current_sorted}" != "${saved_sorted}" ]; then
      echo "Loaded modules differ from ${modules_file}:"
      echo "  Currently loaded: $(echo "${current_modules}" | tr '\n' ' ')"
      echo "  In modules file:  $(echo "${saved_modules}" | tr '\n' ' ')"
      while true; do
        read -r -p "(C)hange loaded modules to match file, (U)pdate file with current modules, (I)gnore? [C/U/I]: " choice
        case "${choice}" in
          [Cc])
            load_modules_from_file "${modules_file}"
            break
            ;;
          [Uu])
            echo "${current_modules}" > "${modules_file}"
            echo "Updated ${modules_file}"
            break
            ;;
          [Ii])
            break
            ;;
          *)
            echo "Please enter C, U, or I."
            ;;
        esac
      done
    fi
  fi
}
