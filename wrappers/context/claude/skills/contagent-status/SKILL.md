<!-- contagent-skill-version: 1 -->
# Contagent Status

Invokable as `/contagent-status`. Reports the current contagent container environment.

## When invoked

Read `/workspace/.contagent/context.md` and summarise:

1. **Variant** — which contagent container is running (e.g. `applaude`, `docklaude`).
2. **Mounted paths** — every path accessible inside this container, with its host
   counterpart and access mode (read-only / read-write).
3. **Loaded modules** — if the context mentions a modules section, list the currently
   loaded modules and the file where they are saved.
4. **How to expand access** — remind the user of the two levers:
   - Add paths via `/workspace/.contagent/mounts` (requires restart).
   - Change modules via the modules file shown in the context (requires restart).

Keep the output concise and structured. Do not modify any files.
