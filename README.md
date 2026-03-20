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

### 2. Run an agent

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

To mount additional host paths into the container, create a `.contagent/mounts` file in the project directory:

```
# host_path:container_path[:mode]   (mode: ro or rw, default: ro)
/data/shared:/data:ro
~/models:/models:ro
```

Lines starting with `#` are ignored. Each entry mounts `host_path` at `container_path` inside the container. Tilde (`~`) is expanded to `$HOME`. Paths that do not exist on the host are skipped with a warning.

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

## SSH key access

Contagent can forward an SSH agent into the container so agents can push to
private repos or authenticate against remote hosts — without exposing your
private keys.

**Private keys never enter the container.** An isolated per-workspace
`ssh-agent` is started on the host with only the approved key(s) loaded; the
container only receives the agent socket.

### Setup

1. **First launch** — contagent automatically asks which SSH key file(s) to
   allow and saves the answer to `.contagent/ssh-allowed-keys`:

   ```
   Setting up SSH key access for this workspace.
   To push/fetch from private repos inside the container, enter the SSH private
   key file path(s) you want to allow. Leave blank and press Enter to skip.

   Keys currently in your SSH agent:
     256 SHA256:xxxx /home/user/.ssh/id_grappes_githubcq (ED25519)

   Enter key file path(s), one per line. Press Enter on a blank line when done.
   Type 'none' to disable SSH forwarding for this workspace.

     Key path: ~/.ssh/id_grappes_githubcq
     Key path:
   Saved 1 key path(s) to .contagent/ssh-allowed-keys.
   ```

2. **Subsequent launches** — the saved key list is reused automatically.

3. **Inside the container** — `SSH_AUTH_SOCK` is set; test with:

   ```bash
   ssh -T git@github.com
   ```

### Key file format

`.contagent/ssh-allowed-keys` contains one key file path per line.
Tilde (`~`) is expanded. Lines starting with `#` are ignored.

```
# Allow only the cluster GitHub key
~/.ssh/id_grappes_githubcq
```

If the file is empty, SSH forwarding is silently skipped for that session.

### Passphrase-protected keys

If a key has a passphrase and it is not already loaded in a running
`ssh-agent` on the host, run:

```bash
ssh-add ~/.ssh/id_yourkey   # enter passphrase once
```

Then launch contagent; the key will be added to the per-workspace agent
without prompting again.

### Adding keys from inside the container

If an agent needs an additional key, it must **ask user permission first**
before editing `.contagent/ssh-allowed-keys`. Editing the file alone is not
sufficient — a contagent restart is required for changes to take effect.

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
| `tests/test-ssh-agent.sh` | `forward_ssh_agent_apptainer`, `forward_ssh_agent_docker`, `_start_workspace_ssh_agent`, `contagent_ssh_agent_cleanup` |
