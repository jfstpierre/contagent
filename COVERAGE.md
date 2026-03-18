# Coverage: AI Coding Tool File Locations

This document tracks all files and directories created by AI coding tools — both globally (central, per-user) and locally (per-project). This is used to plan container sandboxing in **contagent**, which currently wraps Claude Code and plans to add Cursor CLI and OpenCode.

---

## Claude Code

**Official docs:** https://docs.anthropic.com/en/docs/claude-code

### Global / Central (per user)

| Path | Description |
|------|-------------|
| `~/.claude.json` | Main global configuration file |
| `~/.claude/` | Main global data directory |
| `~/.claude/.credentials.json` | API credentials (OAuth tokens) |
| `~/.claude/history.jsonl` | Global conversation history |
| `~/.claude/cache/` | Cache data (e.g. `changelog.md`) |
| `~/.claude/backups/` | Timestamped backups of `.claude.json` |
| `~/.claude/plugins/blocklist.json` | Plugin allow/blocklist |
| `~/.claude/mcp-needs-auth-cache.json` | MCP server authentication cache |
| `~/.claude/file-history/` | Versioned file edit history (per session, per file hash) |
| `~/.claude/projects/` | Per-project metadata and memory files |
| `~/.cache/claude-cli-nodejs/` | MCP server logs (per project path) |
| `~/.local/share/claude/versions/` | Installed Claude Code version binaries |
| `~/.local/state/claude/locks/` | Version lock files (e.g. `2.1.75.lock`) |

### Project-level (per workspace)

| Path | Description |
|------|-------------|
| `CLAUDE.md` | Project instructions / system prompt (committed to repo) |
| `.claude/` | Project-specific overrides and settings |

### Contagent workspace state directories

These are created by contagent wrappers to isolate tool state from the host. All state lives under `.contagent/` in the workspace root:

| Path | Variant | Description |
|------|---------|-------------|
| `.contagent/docklaude/` | `docklaude` (Docker) | Full workspace state directory for Claude Code |
| `.contagent/applaude/home/` | `applaude`, `applaude-cvmfs` (Apptainer) | Full workspace state directory for Claude Code (mirrors `~/.claude/` structure) |
| `.contagent/applaude/modules` | `applaude-cvmfs` only | List of lmod modules loaded for the session |
| `.contagent/docksur/home/` | `docksur` (Docker) | Full workspace state directory for Cursor CLI |
| `.contagent/appsur/home/` | `appsur`, `appsur-cvmfs` (Apptainer) | Full workspace state directory for Cursor CLI (mirrors `~/.cursor/`, `~/.config/cursor/` structure) |
| `.contagent/appsur/modules` | `appsur-cvmfs` only | List of lmod modules loaded for the session |
| `.contagent/dockopen/home/` | `dockopen` (Docker) | Full workspace state directory for OpenCode |
| `.contagent/appopen/home/` | `appopen`, `appopen-cvmfs` (Apptainer) | Full workspace state directory for OpenCode (mirrors `~/.config/opencode/`, `~/.local/share/opencode/` structure) |
| `.contagent/appopen/modules` | `appopen-cvmfs` only | List of lmod modules loaded for the session |
| `.contagent/dockbash/home/` | `dockbash` (Docker) | Isolated home directory for interactive shell sessions |
| `.contagent/appbash/home/` | `appbash`, `appbash-cvmfs` (Apptainer) | Isolated home directory for interactive shell sessions |
| `.contagent/mounts` | all variants | Optional extra bind mounts file (`host_path:container_path[:mode]`) |

The per-tool `home/` directories contain a copy of the tool's global state scoped to the workspace. Credentials are **copied** from the host on first run; the host files are never modified.

For Claude Code, the container also carries `~/.local/share/claude/versions/` (the Claude Code binary) but **not** `~/.local/state/claude/locks/` — lock files remain on the host only.

---

## Cursor CLI

**Official docs:** https://cursor.com/docs

### Global / Central (per user)

| Path | OS | Description |
|------|----|-------------|
| `~/.config/cursor/auth.json` | Linux | **Credentials / auth tokens** |
| `~/.cursor/cli-config.json` | macOS / Linux | CLI configuration file |
| `$XDG_CONFIG_HOME/cursor/cli-config.json` | Linux / BSD | XDG alternative config path |
| `%USERPROFILE%\.cursor\cli-config.json` | Windows | CLI configuration file |
| Cursor app data dir | macOS: `~/Library/Application Support/Cursor/` | Editor settings, extensions, cache |
| Cursor app data dir | Linux: `~/.config/Cursor/` | Editor settings, extensions, cache |
| Cursor app data dir | Windows: `%APPDATA%\Cursor\` | Editor settings, extensions, cache |

User-level rules are configured via **Cursor Settings → Rules** (stored inside the app data directory).

### Project-level (per workspace)

| Path | Description |
|------|-------------|
| `.cursor/cli.json` | Project-level CLI configuration |
| `.cursor/rules/` | Project rules (`.md` / `.mdc` files); version-controlled |
| `.cursorrules` | Legacy project rules file (single file, root of project) |
| `.cursorignore` | Files/directories to exclude from Cursor's context |
| `AGENTS.md` | Simplified alternative to `.cursor/rules/` (also read by OpenCode) |
| `.vscode/settings.json` | VS Code-compatible workspace settings (Cursor is VS Code-based) |

### XDG data / state directories

| Path | Description |
|------|-------------|
| `~/.local/bin/cursor` | CLI binary (added to PATH post-install) |
| `~/.local/share/Cursor/` | Likely app data on Linux (unconfirmed — Cursor docs do not document this explicitly) |
| `~/.local/state/Cursor/` | Likely state/logs on Linux (unconfirmed) |

### Notes for contagent

- **Credentials live in `~/.config/cursor/auth.json`** — this is the file copied into the container home on first run.
- `~/.cursor/cli-config.json` (CLI configuration) is also copied into the container home on first run.
- Project state lives in `.cursor/` — safe to bind-mount with the workspace.
- The full app data directory is large (extensions, cache); only the CLI config and auth file need to be copied/mounted.
- `~/.local/share/` and `~/.local/state/` usage is not explicitly documented by Cursor; requires verification on a live installation.

---

## OpenCode

**Official docs:** https://opencode.ai/docs
**Source:** https://github.com/sst/opencode

### Global / Central (per user)

| Path | Description |
|------|-------------|
| `~/.config/opencode/opencode.json` | Main global configuration |
| `~/.config/opencode/tui.json` | TUI (terminal UI) settings |
| `~/.config/opencode/agents/` | Custom agent definitions |
| `~/.config/opencode/commands/` | Custom command definitions |
| `~/.config/opencode/modes/` | UI mode definitions |
| `~/.config/opencode/plugins/` | Plugin files |
| `~/.config/opencode/skills/` | Agent skill definitions |
| `~/.config/opencode/themes/` | Theme configurations |
| `~/.config/opencode/tools/` | Tool definitions |

Paths follow the XDG Base Directory specification. Override with:
- `OPENCODE_CONFIG` — custom config file path
- `OPENCODE_CONFIG_DIR` — custom config directory
- `OPENCODE_TUI_CONFIG` — custom TUI config path

### Project-level (per workspace)

| Path | Description |
|------|-------------|
| `opencode.json` | Project-level main configuration (root of project) |
| `tui.json` | Project-level TUI settings (root of project) |
| `.opencode/agents/` | Project-specific agent definitions |
| `.opencode/commands/` | Project-specific command definitions |
| `.opencode/modes/` | Project-specific UI modes |
| `.opencode/plugins/` | Project-specific plugins |
| `.opencode/skills/` | Project-specific skills |
| `.opencode/themes/` | Project-specific themes |
| `.opencode/tools/` | Project-specific tools |
| `AGENTS.md` | Project instructions / system prompt (also read by Cursor) |

### XDG data / state directories

| Path | Description |
|------|-------------|
| `~/.local/share/opencode/auth.json` | **API keys / credentials** (provider API keys stored here, not in `~/.config/`) |
| `~/.local/share/opencode/opencode.db` | SQLite database (sessions, conversation history) |
| `~/.local/share/opencode/opencode.db-shm` | SQLite shared-memory file |
| `~/.local/share/opencode/opencode.db-wal` | SQLite write-ahead log |
| `~/.local/share/opencode/storage/` | Internal storage (migration metadata, session diffs) |
| `~/.local/share/opencode/log/` | Application logs |
| `~/.local/share/opencode/bin/` | Managed binary directory |
| `~/.local/state/opencode/model.json` | Recently used and favourite models |
| `~/.local/state/opencode/prompt-history.jsonl` | Input/prompt history |

### Plugin installation directory

| Path | Description |
|------|-------------|
| `~/.opencode/` | Global plugin install root (bun/npm package tree) |
| `~/.opencode/package.json` | Plugin dependency manifest |
| `~/.opencode/bun.lock` | Bun lockfile for plugin dependencies |
| `~/.opencode/node_modules/` | Installed plugin packages |
| `~/.opencode/bin/` | Plugin binaries |

### Notes for contagent

- **Credentials live in `~/.local/share/opencode/auth.json`**, not in `~/.config/opencode/`. This is the file that must be copied into the container home on first run.
- `~/.config/opencode/` holds settings (model preferences, themes, etc.) but not API keys.
- The SQLite database (`opencode.db*`) and `storage/` hold session/conversation history — these should live in the per-workspace container home so sessions are scoped to the workspace.
- `~/.local/state/opencode/model.json` (recently-used model preference) is copied from the host on first run so the container starts with the user's preferred model. `prompt-history.jsonl` is left workspace-local (not copied) so prompt history does not leak between workspaces.
- `~/.opencode/` is the plugin install tree. On first run inside the container it will be re-created inside the container home if plugins are used.
- Project state lives in `.opencode/` — safe to bind-mount with the workspace.
- `AGENTS.md` is shared with Cursor; both tools read it as project-level instructions.

---

## Cross-tool: Shared / Interoperable Files

| File | Tools | Description |
|------|-------|-------------|
| `AGENTS.md` | Cursor, OpenCode | Project instructions; both tools read this file |
| `.vscode/settings.json` | Cursor | Cursor inherits VS Code workspace settings |

---

## Summary Table

| Tool | Global config root | Project state dir | Credentials / auth |
|------|--------------------|-------------------|--------------------|
| Claude Code | `~/.claude/`, `~/.claude.json` | `.claude/` (native), `.contagent/applaude/home/` or `.contagent/docklaude/` (contagent) | `~/.claude/.credentials.json` |
| Cursor CLI | `~/.cursor/`, `~/.config/cursor/` | `.cursor/` | `~/.config/cursor/auth.json` |
| OpenCode | `~/.config/opencode/`, `~/.local/share/opencode/` | `.opencode/` | `~/.local/share/opencode/auth.json` |
