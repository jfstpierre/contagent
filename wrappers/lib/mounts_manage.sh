# mounts_manage.sh - Interactive mount management for contagent workspaces
# Source this file; do not execute directly.
# Requires common.sh to be sourced first (provides init_mounts_file).

# List entries in .contagent/mounts in a human-readable format.
# Usage: list_mounts <workspace>
list_mounts() {
  local workspace="$1"
  local mounts_file="${workspace}/.contagent/mounts"

  echo "Mounts for: ${workspace}"
  echo ""

  if [ ! -f "${mounts_file}" ]; then
    echo "  No mounts configured (.contagent/mounts not found)."
    echo "  Run 'contagent mount add' to add a mount."
    echo ""
    return 0
  fi

  local _count=0 _line host_path container_path mode _status
  while IFS= read -r _line || [ -n "${_line}" ]; do
    [[ -z "${_line}" || "${_line}" =~ ^[[:space:]]*# ]] && continue
    IFS=: read -r host_path container_path mode <<< "${_line}"
    if [ -z "${host_path}" ] || [ -z "${container_path}" ]; then
      continue
    fi
    local _display_path="${host_path}"
    host_path="${host_path/#\~/$HOME}"
    mode="${mode:-ro}"
    _status=""
    [ ! -e "${host_path}" ] && _status=" (missing on host)"
    _count=$((_count + 1))
    printf '  %-40s → %-25s [%s]%s\n' \
      "${_display_path}" "${container_path}" "${mode}" "${_status}"
  done < "${mounts_file}"

  if [ "${_count}" -eq 0 ]; then
    echo "  No mount entries yet."
    echo "  Run 'contagent mount add' to add a mount."
  fi
  echo ""
}

# Interactively add a mount entry to .contagent/mounts.
# Usage: add_mount <workspace>
add_mount() {
  local workspace="$1"
  local mounts_file="${workspace}/.contagent/mounts"

  init_mounts_file "${workspace}"

  echo ""
  echo "Add a mount for: ${workspace}"
  echo ""

  local host_path container_path mode _expanded

  while true; do
    read -r -p "Host path (absolute or ~/...): " host_path
    if [ -z "${host_path}" ]; then
      echo "Aborted."
      echo ""
      return 0
    fi
    _expanded="${host_path/#\~/$HOME}"
    if [ ! -e "${_expanded}" ]; then
      read -r -p "Warning: '${_expanded}' does not exist on the host. Add anyway? [y/N]: " _confirm
      [[ "${_confirm}" =~ ^[Yy]$ ]] || continue
    fi
    break
  done

  read -r -p "Container path (absolute, e.g. /data): " container_path
  if [ -z "${container_path}" ]; then
    echo "Aborted."
    echo ""
    return 0
  fi

  read -r -p "Mode [ro/rw, default ro]: " mode
  mode="${mode:-ro}"
  if [[ "${mode}" != "ro" && "${mode}" != "rw" ]]; then
    echo "Invalid mode '${mode}'; defaulting to ro."
    mode="ro"
  fi

  printf '%s:%s:%s\n' "${host_path}" "${container_path}" "${mode}" >> "${mounts_file}"

  echo ""
  echo "Added: ${host_path}:${container_path}:${mode}"
  echo "A session restart is required for the change to take effect."
  echo ""
}
