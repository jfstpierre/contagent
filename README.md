# Contagent

Container wrappers for agentic coding tools that sandbox execution to the selected workspace directory.

## Supported tools
- Claude Code
- Cursor CLI
- OpenCode

## Supported containers
- Apptainer with/without CVMFS support (DRAC/Alliance clusters)
- Docker

## Prerequisites

- The target agentic tool configured on the host (the initial configuration and credentials are copied to each local workspace of the coding agent, but `claude login`, `agent login`, or `opencode auth login` must first be executed on the host)
- Docker (for Docker variants) or Apptainer (for Apptainer variants)
- `python3` (for OpenCode variants — used to merge context into `opencode.json`; available by default on all supported platforms)

---

## Quick start

### 1. Build the container image

```bash
cd /path/to/contagent
./contagent build
```

`contagent build` shows the current container state and prompts you to select a variant:

| Choice | Type | Image |
|--------|------|-------|
| 1 (default) | `apptainer-cvmfs` | `~/.contagent/apptainer-cvmfs.sif` |
| 2 | `apptainer` | `~/.contagent/apptainer.sif` |
| 3 | `docker` | `docklaude` Docker image |

The selected type is saved to `~/.contagent/settings` and used by all subsequent `contagent` commands.

### 2. (Optional) Configure SSH and mounts for a workspace

```bash
cd /path/to/project
contagent ssh add       # select SSH hosts to forward into the container
contagent mount add     # add extra bind mounts (e.g. /data, ~/models)
```

These are optional and workspace-local. SSH and mounts can be configured at any time; a session restart is required for changes to take effect.

### 3. Run an agent

```bash
cd /path/to/project
/path/to/contagent/contagent claude [...]     # Claude Code
/path/to/contagent/contagent agent [...]      # Cursor CLI
/path/to/contagent/contagent opencode [...]   # OpenCode
/path/to/contagent/contagent bash             # Interactive shell
```

All arguments are passed through to the underlying tool.

---

## Agent variants

Each tool maps to a wrapper script selected automatically based on the container type set during `contagent build`:

| Command | Docker | Apptainer | Apptainer + CVMFS |
|---------|--------|-----------|-------------------|
| `contagent claude` | `docklaude` | `applaude` | `applaude-cvmfs` |
| `contagent agent` | `docksur` | `appsur` | `appsur-cvmfs` |
| `contagent opencode` | `dockopen` | `appopen` | `appopen-cvmfs` |
| `contagent bash` | `dockbash` | `appbash` | `appbash-cvmfs` |

Workspace state is stored under `.contagent/<variant>/` in the project directory. Credentials are copied from the host on first run; host files are never modified.

`contagent bash` launches an interactive shell in the same container, with the same workspace mount and state isolation as the agent commands. This is useful for debugging or running one-off commands in the container environment.

---

## Agent container awareness

Before each run, contagent writes `.contagent/context.md` in the workspace describing the container's filesystem layout, and injects it into the agent's session:

| Agent | Injection mechanism |
|-------|---------------------|
| Claude Code | `--append-system-prompt-file /workspace/.contagent/context.md` |
| OpenCode | Added to the `instructions` array in `opencode.json` |
| Cursor | Embedded in `.cursor/rules/contagent.mdc` (`alwaysApply: true`) |

The context file lists every mounted path the agent can see, with host↔container mappings and access modes. It also explains how to request additional mounts (via `.contagent/mounts`) and, for CVMFS variants, which modules are loaded.

**Claude Code** additionally receives two skills installed into the container home on first run (upgraded automatically when the skill version changes):

- `add-mount` — guides Claude to propose and write a new `.contagent/mounts` entry with user consent
- `contagent-status` — invokable as `/contagent-status`; summarises current mounts, modules, and how to expand access

`.cursor/rules/contagent.mdc` is automatically added to `.gitignore` so it is not committed.

---

## Extra bind mounts

```bash
contagent mount add    # interactively add a mount
contagent mount list   # show current mounts for this workspace
```

`contagent mount add` prompts for a host path (absolute or `~/…`), a container
path, and an access mode (`ro`/`rw`). The entry is appended to
`.contagent/mounts`.

You can also edit `.contagent/mounts` directly:

```
# host_path:container_path[:mode]   (mode: ro or rw, default: ro)
/data/shared:/data:ro
~/models:/models:ro
```

Lines starting with `#` are ignored. Tilde (`~`) is expanded to `$HOME`.
Paths that do not exist on the host are skipped with a warning. A session
restart is required for mount changes to take effect.

---

## Module tracking (CVMFS variants)

The `-cvmfs` variants track which lmod modules are loaded in your shell, storing them in `.contagent/<variant>/modules` and prompting you to reconcile on subsequent runs.

Load the modules you need before invoking the agent:

```bash
module load python/3.11.5 scipy-stack/2023b
cd /path/to/project
/path/to/contagent/contagent claude   # or agent, or opencode
```

**First run:** the currently loaded modules are saved to the modules file automatically.

**Subsequent runs:** if the loaded modules differ from the saved list, you are prompted:

```
Loaded modules differ from .contagent/applaude/modules:
  Currently loaded: python/3.11.5
  In modules file:  python/3.11.5 scipy-stack/2023b
(C)hange loaded modules to match file, (U)pdate file with current modules, (I)gnore? [C/U/I]:
```

| Choice | Effect |
|--------|--------|
| `C`hange | Purge current modules and reload from the modules file |
| `U`pdate | Overwrite the modules file with the currently loaded modules |
| `I`gnore | Proceed as-is, leaving both the environment and the file unchanged |

The CVMFS variants also bind `/cvmfs:/cvmfs` into the container and propagate the full post-load environment (PATH, LD_LIBRARY_PATH, PYTHONPATH, etc.).

---

## SSH access

Contagent can forward an SSH agent into the container so agents can push to
private repos or authenticate against remote hosts — without exposing your
private keys.

**Private keys never enter the container.** An isolated per-workspace
`ssh-agent` is started on the host with only the approved key(s) loaded; the
container only receives the agent socket. Selected `Host` blocks from
`~/.ssh/config` are injected into the container's `~/.ssh/config` so SSH
aliases work inside the container without any manual setup.

### Setup

```bash
cd /path/to/project
contagent ssh add
```

An interactive menu lists every named `Host` block from your `~/.ssh/config`
plus a "Default key" option that forwards your existing agent as-is. Toggle
entries by number; press Enter on a blank line when done.

```
SSH host configuration for: /path/to/project

  1) Default key  (forward agent as-is)
  2) github         github.com              IdentityFile: ~/.ssh/id_github
  3) work-server    work.example.com        (uses any key in agent)
  4) *              (Host *)                IdentityFile: ~/.ssh/id_default
  5) Done / Skip

Choice (toggle number, blank = done):
```

The selected `Host` blocks are written to `.contagent/ssh-config` and injected
into the container's `~/.ssh/config` before each run. The private key paths are
recorded in `.contagent/ssh-allowed-keys` and loaded into an isolated
per-workspace `ssh-agent` at launch time.

**IdentityFile injection for keyless hosts:** if you select a named host that
has no `IdentityFile` in its block, and your `~/.ssh/config` contains a
`Host *` block with an `IdentityFile`, that key is automatically injected into
the written host block. This gives precise control without relying on SSH's
implicit `Host *` fallback inside the container.

### Viewing the current configuration

```bash
contagent ssh list
```

### Inside the container

`SSH_AUTH_SOCK` is set; test with:

```bash
ssh -T git@github.com
```

### Passphrase-protected keys

If a key has a passphrase, load it into the host agent once before launching:

```bash
ssh-add ~/.ssh/id_yourkey   # enter passphrase once
```

Contagent detects that all configured keys are already in the host agent and
forwards it directly, without starting a new agent or prompting for the
passphrase again.

### Modifying SSH config from inside the container

SSH config is managed on the host via `contagent ssh add`. An agent inside the
container cannot modify it — a restart is required for any changes to take effect.

---

## Common behaviour

All variants:

- Copy credentials from the host into a per-workspace state directory on first run — host credential files are **never modified**
- Mount the current directory as `/workspace`
- Isolate container HOME to prevent host config leaking in
- Pass all command-line arguments through to the underlying tool

> **Warning**: Do not run `contagent` from your home directory (`~/`). This mounts your entire home as the workspace. If you do, you will be prompted to confirm, with the option to disable the warning permanently.

## Security model

- Host credential files are never mounted into the container
- Credentials are copied to the workspace state directory before the container starts
- Container cannot modify host credential files
- All container state is confined to `.contagent/` in each workspace

---

## Running tests

The test suite requires only bash — no Docker or Apptainer installation needed.

```bash
bash tests/run-all.sh
```

Pass `--verbose` (or `-v`) to print a 2–3 line description of each test scenario:

```bash
bash tests/run-all.sh --verbose
bash tests/test-context-generation.sh -v
```

Individual test files can be run directly:

```bash
bash tests/test-common-mounts.sh
bash tests/test-common-lmod.sh
bash tests/test-contagent-settings.sh
bash tests/test-wrapper-preflight.sh
bash tests/test-credential-cleanup.sh
bash tests/test-context-generation.sh
bash tests/test-ssh-config-select.sh
bash tests/test-ssh-agent.sh
```

| File | What it covers |
|------|----------------|
| `tests/test-applaude-cvmfs-modules.sh` | `reconcile_cvmfs_modules()` |
| `tests/test-common-mounts.sh` | `init_mounts_file`, `parse_mounts_apptainer`, `parse_mounts_docker` |
| `tests/test-common-lmod.sh` | `ensure_module`, `load_apptainer_module`, `load_modules_from_file` |
| `tests/test-contagent-settings.sh` | `read_setting`, `set_setting`, `check_home_dir` |
| `tests/test-wrapper-preflight.sh` | Pre-flight checks for all 12 wrapper scripts |
| `tests/test-credential-cleanup.sh` | Credential isolation for all Apptainer and Docker wrappers |
| `tests/test-context-generation.sh` | `generate_context_file`, `generate_opencode_config`, `install_cursor_rules`, `install_claude_skills` |
| `tests/test-ssh-config-select.sh` | `parse_ssh_config_hosts`, `_parse_ssh_catchall_blocks`, `_collect_wildcard_ssh_blocks`, `prompt_ssh_host_selection`, `_inject_ssh_config` |
| `tests/test-ssh-agent.sh` | `forward_ssh_agent_apptainer`, `forward_ssh_agent_docker`, `_start_workspace_ssh_agent`, `contagent_ssh_agent_cleanup` |
