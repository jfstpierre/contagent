# Containerized AI coding agents (Claude Code, Cursor, OpenCode)
# Provides sandboxing by limiting file access to a workspace folder

# Use official Python 3.14 slim image (Debian bookworm-based)
FROM python:3.14-slim

# Install Node.js 20.x (required for Claude Code)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    ca-certificates \
    gnupg \
    openssh-client \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Verify installations
RUN python3 --version && pip3 --version && node --version && npm --version

# Install Claude Code, Cursor, and OpenCode CLIs
RUN curl -fsSL https://claude.ai/install.sh | bash \
    && curl https://cursor.com/install -fsS | bash \
    && curl -fsSL https://opencode.ai/install | bash

# claude → /root/.local/bin, opencode → /root/.opencode/bin
# Also include tool-specific home dirs so startup checks don't warn about ~/.local/bin.
ENV PATH="/root/.opencode/bin:/root/.local/bin:/home/claude/.local/bin:/home/cursor/.local/bin:/home/opencode/.local/bin:$PATH"

# Make all tools accessible to non-root users (needed when --user is passed to docker run)
RUN chmod 755 /root && chmod -R a+rX /root/.local /root/.opencode

# Create workspace and per-tool home directories
RUN mkdir -p /workspace /home/claude /home/cursor /home/opencode \
    && chmod 777 /home/claude /home/cursor /home/opencode

# Set working directory
WORKDIR /workspace

# Set entrypoint directly to claude (exec form, no shell)
ENTRYPOINT ["claude"]
