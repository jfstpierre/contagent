# Contagent

Container wrappers for agentic coding tools that sandbox execution to the selected workspace directory.

## Supported tools
- Claude Code
- Cursor CLI
- OpenCode

## Supported container 
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

## Claude Code

### docklaude (Docker)

#### Build

```bash
/path/to/contagent/contagent build
# Select option 3 (Docker)
```

#### Usage

```bash
cd /path/to/project
/path/to/contagent/contagent claude
```

Workspace state is stored in `.contagent/docklaude/` inside the project directory.

---

### applaude (Apptainer, generic HPC)

#### Build

```bash
/path/to/contagent/contagent build
# Select option 2 (Apptainer)
```

#### Usage

```bash
cd /path/to/project
/path/to/contagent/contagent claude
```

Workspace state is stored in `.contagent/applaude/home/` inside the project directory.

---

### applaude-cvmfs (Apptainer, DRAC/Alliance clusters)

Variant for clusters that use a CVMFS-mounted software stack (`/cvmfs/soft.computecanada.ca/`) managed by **lmod**. Software comes from `module load` rather than the SIF image.

#### Build (once on a login node)

```bash
/path/to/contagent/contagent build
# Select option 1 (apptainer-cvmfs, default)
```

#### Module tracking

`applaude-cvmfs` keeps track of the lmod modules loaded in your shell, storing them in `.contagent/applaude/modules` in the project directory and reloading them on your next session. Load the modules you will need for the session before invoking the script:

```bash
module load python/3.11.5 scipy-stack/2023b
cd /path/to/project
/path/to/contagent/contagent claude
```

**First run:** the currently loaded modules are saved to `.contagent/applaude/modules` automatically.

**Subsequent runs:** the loaded modules are compared against `.contagent/applaude/modules`. If they differ, you are prompted:

```
Loaded modules differ from .contagent/applaude/modules:
  Currently loaded: python/3.11.5
  In modules file:  python/3.11.5 scipy-stack/2023b
(C)hange loaded modules to match file, (U)pdate file with current modules, (I)gnore? [C/U/I]:
```

| Choice | Effect |
|--------|--------|
| `C`hange | Purge current modules and reload from `.contagent/applaude/modules` |
| `U`pdate | Overwrite `.contagent/applaude/modules` with the currently loaded modules |
| `I`gnore | Proceed as-is, leaving both the environment and the file unchanged |

#### Usage

```bash
cd /path/to/project
/path/to/contagent/contagent claude
```

What the script does:
1. Compares loaded modules against `.contagent/applaude/modules` (creating it on first run)
2. Binds `/cvmfs:/cvmfs` into the container (if `/cvmfs` exists on the host)
3. Propagates the post-load environment (PATH, LD_LIBRARY_PATH, PYTHONPATH, etc.) into the container
4. Runs Claude scoped to the workspace

Workspace state is stored in `.contagent/applaude/home/` (shared with `applaude`).

---

## Cursor CLI

Requires `cursor login` on the host before first use.

### docksur (Docker)

#### Build

```bash
/path/to/contagent/contagent build
# Select option 3 (Docker)
```

#### Usage

```bash
cd /path/to/project
/path/to/contagent/contagent agent
```

Workspace state is stored in `.contagent/docksur/home/` inside the project directory.

---

### appsur (Apptainer, generic HPC)

#### Build

```bash
/path/to/contagent/contagent build
# Select option 2 (Apptainer)
```

#### Usage

```bash
cd /path/to/project
/path/to/contagent/contagent agent
```

Workspace state is stored in `.contagent/appsur/home/` inside the project directory.

---

### appsur-cvmfs (Apptainer, DRAC/Alliance clusters)

#### Build

```bash
/path/to/contagent/contagent build
# Select option 1 (apptainer-cvmfs, default)
```

#### Usage

```bash
cd /path/to/project
/path/to/contagent/contagent agent
```

Workspace state is stored in `.contagent/appsur/home/` inside the project directory.

Module tracking works the same as `applaude-cvmfs` (see above), using `.contagent/appsur/modules`.

---

## OpenCode

Requires OpenCode to be configured with API keys on the host first (run `opencode` and set up your provider credentials).

### dockopen (Docker)

#### Build

```bash
/path/to/contagent/contagent build
# Select option 3 (Docker)
```

#### Usage

```bash
cd /path/to/project
/path/to/contagent/contagent opencode
```

Workspace state is stored in `.contagent/dockopen/home/` inside the project directory.

---

### appopen (Apptainer, generic HPC)

#### Build

```bash
/path/to/contagent/contagent build
# Select option 2 (Apptainer)
```

#### Usage

```bash
cd /path/to/project
/path/to/contagent/contagent opencode
```

Workspace state is stored in `.contagent/appopen/home/` inside the project directory.

---

### appopen-cvmfs (Apptainer, DRAC/Alliance clusters)

#### Build

```bash
/path/to/contagent/contagent build
# Select option 1 (apptainer-cvmfs, default)
```

#### Usage

```bash
cd /path/to/project
/path/to/contagent/contagent opencode
```

Workspace state is stored in `.contagent/appopen/home/` inside the project directory.

Module tracking works the same as `applaude-cvmfs` (see above), using `.contagent/appopen/modules`.

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
