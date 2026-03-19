<!-- contagent-skill-version: 1 -->
# Add Mount

Use this skill when you need access to a host path that is not currently mounted in
this contagent container.

## Steps

1. Identify the host path you need and explain to the user why you need it.
2. Propose the specific line to add to `/workspace/.contagent/mounts`:
   ```
   host_path:container_path[:mode]
   ```
   - `host_path` — absolute path on the host (tilde `~` expands to `$HOME`)
   - `container_path` — where it should appear inside the container (e.g. `/data`)
   - `mode` — `ro` (read-only, default) or `rw` (read-write)

3. **Wait for explicit user approval before writing anything.**

4. After the user approves, append the line to `/workspace/.contagent/mounts`.

5. Inform the user that **a session restart is required** for the mount to take effect.

## Example

To mount `/home/user/datasets` read-only at `/datasets`:
```
/home/user/datasets:/datasets:ro
```

Never modify `/workspace/.contagent/mounts` without the user's explicit consent.
