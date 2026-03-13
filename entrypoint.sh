#!/bin/sh
# Docklaude entrypoint - copies credentials from host and starts Claude

# Directories
HOST_CLAUDE_DIR="/home/claude/.claude-host"
CONTAINER_CLAUDE_DIR="/home/claude/.claude"

# Copy credentials from host if they exist and we don't have them
if [ -d "$HOST_CLAUDE_DIR" ]; then
    # Copy credential files if they don't exist in container
    for file in .credentials.json .credentials; do
        if [ -f "$HOST_CLAUDE_DIR/$file" ] && [ ! -f "$CONTAINER_CLAUDE_DIR/$file" ]; then
            cp "$HOST_CLAUDE_DIR/$file" "$CONTAINER_CLAUDE_DIR/$file"
            chmod 600 "$CONTAINER_CLAUDE_DIR/$file"
        fi
    done

    # Copy settings if they don't exist
    if [ -f "$HOST_CLAUDE_DIR/settings.json" ] && [ ! -f "$CONTAINER_CLAUDE_DIR/settings.json" ]; then
        cp "$HOST_CLAUDE_DIR/settings.json" "$CONTAINER_CLAUDE_DIR/settings.json"
    fi
fi

# Execute claude with all arguments
exec claude "$@"
