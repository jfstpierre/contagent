# Docklaude - Containerized Claude Code
# Provides sandboxing by limiting file access to a workspace folder

# Use official Python 3.14 slim image (Debian bookworm-based)
FROM python:3.14-slim

# Install Node.js 20.x (required for Claude Code)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    ca-certificates \
    gnupg \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Verify installations
RUN python3 --version && pip3 --version && node --version && npm --version

# Install Claude Code CLI via official installer
RUN curl -fsSL https://claude.ai/install.sh | bash

# Installer puts claude in /root/.local/bin — add to PATH.
# Also include /home/claude/.local/bin so claude's startup check doesn't
# warn about ~/.local/bin not being in PATH (HOME is set to /home/claude at runtime).
ENV PATH="/root/.local/bin:/home/claude/.local/bin:$PATH"

# Make claude accessible to non-root users (needed when --user is passed to docker run)
RUN chmod 755 /root && chmod -R a+rX /root/.local

# Create workspace and home directories
RUN mkdir -p /workspace /home/claude && chmod 777 /home/claude

# Set working directory
WORKDIR /workspace

# Set entrypoint directly to claude (exec form, no shell)
ENTRYPOINT ["claude"]
