# Contagent

Container wrappers for agentic coding tools that sandbox execution to the selected workspace directory.

Currently supported tools:

| Tool | Variant | Runtime | Target environment |
|---|---|---|---|
| Claude Code | `docklaude` | Docker | Local workstation |
| Claude Code | `applaude` | Apptainer | HPC clusters (generic) |
| Claude Code | `applaude-cvmfs` | Apptainer | DRAC/Alliance clusters (Cedar, Graham, Narval, Béluga, Niagara) |

Planned: Cursor CLI, opencode, and other agentic coding tools.

## Prerequisites

- The target agentic tool configured on the host (e.g. `claude login`)
- Docker (for `docklaude`) or Apptainer (for `applaude` / `applaude-cvmfs`)

---

## Claude Code

### docklaude (Docker)

#### Build

```bash
cd /path/to/contagent
docker build -t docklaude .
```

#### Usage

```bash
cd /path/to/project
/path/to/contagent/docklaude
```

Workspace state is stored in `.docklaude/` inside the project directory.

---

### applaude (Apptainer, generic HPC)

#### Build

```bash
cd /path/to/contagent
apptainer build applaude.sif applaude.def
```

#### Usage

```bash
cd /path/to/project
/path/to/contagent/applaude
```

Workspace state is stored in `.applaude/home/` inside the project directory.

---

### applaude-cvmfs (Apptainer, DRAC/Alliance clusters)

Variant for clusters that use a CVMFS-mounted software stack (`/cvmfs/soft.computecanada.ca/`) managed by **lmod**. Softwares come from `module load` rather than the SIF image.

#### Build (once on a login node)

```bash
apptainer build --fakeroot applaude-cvmfs.sif /path/to/contagent/applaude-cvmfs.def
```

#### Module tracking

`applaude-cvmfs` keeps track of the lmod modules loaded in your shell, storing them in `.applaude/modules` in the project directory and reloading them on your next session. Load the modules you will need for the session before invoking the script:

```bash
module load python/3.11.5 scipy-stack/2023b
cd /path/to/project
/path/to/contagent/applaude-cvmfs
```

**First run:** the currently loaded modules are saved to `.applaude/modules` automatically.

**Subsequent runs:** the loaded modules are compared against `.applaude/modules`. If they differ, you are prompted:

```
Loaded modules differ from .applaude/modules:
  Currently loaded: python/3.11.5
  In modules file:  python/3.11.5 scipy-stack/2023b
(C)hange loaded modules to match file, (U)pdate file with current modules, (I)gnore? [C/U/I]:
```

| Choice | Effect |
|--------|--------|
| `C`hange | Purge current modules and reload from `.applaude/modules` |
| `U`pdate | Overwrite `.applaude/modules` with the currently loaded modules |
| `I`gnore | Proceed as-is, leaving both the environment and the file unchanged |

#### Usage

```bash
cd /path/to/project
/path/to/contagent/applaude-cvmfs
```

What the script does:
1. Compares loaded modules against `.applaude/modules` (creating it on first run)
2. Binds `/cvmfs:/cvmfs` into the container (if `/cvmfs` exists on the host)
3. Propagates the post-load environment (PATH, LD_LIBRARY_PATH, PYTHONPATH, etc.) into the container
4. Runs Claude scoped to the workspace

Workspace state is stored in `.applaude/home/` (shared with `applaude`).

---

## Common behaviour

All Claude Code variants:

- Copy `~/.claude/.credentials.json` and `~/.claude.json` into a per-workspace state directory on first run — host credential files are **never modified**
- Mount the current directory as `/workspace`
- Isolate container HOME to prevent host `~/.claude` leaking in
- Pass all command-line arguments through to `claude`

> **Warning**: Do not run any of these scripts from your home directory (`~/`). This mounts your entire home as the workspace.

## Security model

- Host `~/.claude/` is never mounted into the container
- Credentials are copied to the workspace state directory before the container starts
- Container cannot modify host credential files
- All container state is confined to `.docklaude/` or `.applaude/` in each workspace
