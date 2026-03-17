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

Workspace state is stored under `.contagent/<variant>/` in the project directory. Credentials are copied from the host on first run; host files are never modified.

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

## Common behaviour

All variants:

- Copy credentials from the host into a per-workspace state directory on first run — host credential files are **never modified**
- Mount the current directory as `/workspace`
- Isolate container HOME to prevent host config leaking in
- Pass all command-line arguments through to the underlying tool

> **Warning**: Do not run any of these scripts from your home directory (`~/`). This mounts your entire home as the workspace.

## Security model

- Host credential files are never mounted into the container
- Credentials are copied to the workspace state directory before the container starts
- Container cannot modify host credential files
- All container state is confined to `.contagent/` in each workspace
