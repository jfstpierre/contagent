# context.sh - Context generation for contagent agent containers
# Source this file; do not execute directly.

# Determine the directory of this file so we can find sibling assets.
_CONTEXT_LIB_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
_CONTEXT_SKILLS_SRC="${_CONTEXT_LIB_DIR}/../context/claude/skills"

# Generate /workspace/.contagent/context.md describing the container environment.
# Usage: generate_context_file <workspace> <variant> [modules_file]
generate_context_file() {
  local workspace="$1"
  local variant="$2"
  local modules_file="${3:-}"
  local context_file="${workspace}/.contagent/context.md"

  mkdir -p "${workspace}/.contagent"

  {
    cat << EOF
# Contagent Container Environment

You are running inside a **contagent container** (variant: \`${variant}\`).

## Filesystem Access
Only the following paths are accessible inside this container:
- \`/workspace\` (read-write) — maps to \`${workspace}\` on the host
EOF

    # Parse .contagent/mounts and list active mounts
    local mounts_file="${workspace}/.contagent/mounts"
    if [ -f "${mounts_file}" ]; then
      while IFS= read -r line || [ -n "$line" ]; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        IFS=: read -r host_path container_path mode <<< "$line"
        if [ -z "${host_path}" ] || [ -z "${container_path}" ]; then
          continue
        fi
        host_path="${host_path/#\~/$HOME}"
        [ -e "${host_path}" ] || continue
        mode="${mode:-ro}"
        local mode_label
        case "${mode}" in
          rw) mode_label="read-write" ;;
          *)  mode_label="read-only" ;;
        esac
        printf -- '- `%s` (%s) — maps to `%s` on the host\n' \
          "${container_path}" "${mode_label}" "${host_path}"
      done < "${mounts_file}"
    fi

    cat << 'EOF'

Paths NOT listed above do not exist from this container's perspective.

## To access additional host paths
Edit `/workspace/.contagent/mounts` and add a line:
  `host_path:container_path[:mode]`  (mode: `ro` or `rw`, default `ro`)
**Ask the user before modifying this file. A session restart is required.**
EOF

    # Note SSH agent forwarding if active
    if [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "${SSH_AUTH_SOCK}" ]; then
      cat << 'EOF'

## SSH Agent
An SSH agent is forwarded into this container (`SSH_AUTH_SOCK` is set). Only
the specific keys listed in `.contagent/ssh-allowed-keys` are loaded — private
keys never enter the container.

You can perform authenticated git operations (push, fetch from private repos)
using these pre-approved keys.

**IMPORTANT:** Do NOT modify `.contagent/ssh-allowed-keys` without explicit
user permission. If you need access to an additional key, ask the user first
and explain why — only edit the file after they confirm. A contagent restart is
required for changes to take effect.
EOF
    fi

    if [ -n "${modules_file}" ] && [ -f "${modules_file}" ]; then
      local loaded_modules
      loaded_modules="$(grep -v '^[[:space:]]*#' "${modules_file}" \
        | grep -v '^[[:space:]]*$' | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
      local rel_modules_file="${modules_file#${workspace}/}"
      cat << EOF

## Loaded modules
Currently loaded: ${loaded_modules}
Saved in: \`/workspace/${rel_modules_file}\`
To change: edit the modules file, then ask the user to \`module load <name>\` on the host and restart.
**Ask the user before modifying this file. A session restart is required.**
EOF
    fi
  } > "${context_file}"
}

# Inject /workspace/.contagent/context.md into an OpenCode config file.
# Usage: generate_opencode_config <merged_home_or_cred_dir> <workspace>
#
# For Apptainer wrappers, pass the merged home directory; the function writes to
# <merged_home>/.config/opencode/opencode.json.  For Docker wrappers, pass the
# credentials directory; the function writes to <cred_dir>/opencode.json.
generate_opencode_config() {
  local base_dir="$1"
  local workspace="$2"
  local target_file

  if [ -d "${base_dir}/.config/opencode" ]; then
    # Apptainer: merged home already has .config/opencode/ set up
    target_file="${base_dir}/.config/opencode/opencode.json"
  else
    # Docker: credentials directory — opencode.json sits directly inside
    target_file="${base_dir}/opencode.json"
    mkdir -p "${base_dir}"
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    echo "Warning: python3 unavailable — skipping OpenCode context injection."
    return 0
  fi

  python3 -c "
import json, sys
try:
    cfg = json.load(open(sys.argv[1]))
except (FileNotFoundError, ValueError):
    cfg = {}
entry = '/workspace/.contagent/context.md'
instrs = cfg.get('instructions', [])
if entry not in instrs:
    instrs.append(entry)
cfg['instructions'] = instrs
with open(sys.argv[1], 'w') as f:
    json.dump(cfg, f, indent=2)
" "${target_file}"
}

# Write a Cursor rules file embedding the context markdown.
# Usage: install_cursor_rules <workspace> <context_md>
install_cursor_rules() {
  local workspace="$1"
  local context_md="$2"
  local rules_file="${workspace}/.cursor/rules/contagent.mdc"
  local gitignore_file="${workspace}/.gitignore"

  mkdir -p "${workspace}/.cursor/rules"

  {
    printf -- '---\n'
    printf 'description: contagent container environment (auto-generated, do not commit)\n'
    printf 'alwaysApply: true\n'
    printf -- '---\n\n'
    cat "${context_md}"
  } > "${rules_file}"

  # Add to .gitignore if not already present
  if ! grep -qF '.cursor/rules/contagent.mdc' "${gitignore_file}" 2>/dev/null; then
    echo '.cursor/rules/contagent.mdc' >> "${gitignore_file}"
  fi
}

# Copy Claude skill files into a container home directory.
# Guarded by a version sentinel in the first line of each SKILL.md.
# Usage: install_claude_skills <container_home>
install_claude_skills() {
  local container_home="$1"
  local skills_src="${_CONTEXT_SKILLS_SRC}"
  local skills_dst="${container_home}/.claude/skills"

  [ -d "${skills_src}" ] || return 0

  mkdir -p "${skills_dst}"

  local skill_dir skill_name src_skill dst_skill src_version dst_version
  for skill_dir in "${skills_src}"/*/; do
    skill_name="$(basename "${skill_dir}")"
    src_skill="${skill_dir}SKILL.md"
    dst_skill="${skills_dst}/${skill_name}/SKILL.md"

    [ -f "${src_skill}" ] || continue

    src_version="$(head -1 "${src_skill}")"

    # Skip if the installed version already matches
    if [ -f "${dst_skill}" ]; then
      dst_version="$(head -1 "${dst_skill}")"
      [ "${src_version}" = "${dst_version}" ] && continue
    fi

    mkdir -p "${skills_dst}/${skill_name}"
    cp "${src_skill}" "${dst_skill}"
  done
}
