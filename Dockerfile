# syntax=docker/dockerfile:1

########################################
# Stage 1: Base System
########################################
FROM node:20-bookworm-slim AS base

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_ROOT_USER_ACTION=ignore

# Core packages + build tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    wget \
    git \
    unzip \
    build-essential \
    python3 \
    python3-pip \
    python3-venv \
    jq \
    tini \
    openssl \
    ca-certificates \
    NODE \
    ripgrep \
    pandoc \
    poppler-utils \
    ffmpeg \
    imagemagick \
    graphviz \
    sqlite3 \
    pass \
    chromium \
    && rm -rf /var/lib/apt/lists/*

# CRITICAL FIX (native modules)
ENV PYTHON=/usr/bin/python3
RUN config set python /usr/bin/python3

RUN ln -sf /usr/bin/python3 /usr/bin/python && \
    npm install -g node-gyp

########################################
# Stage 2: Runtimes
########################################
FROM base AS runtimes

ENV BUN_INSTALL="/root/.bun"
ENV PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/root/.bun/bin:${PATH}"

# Install Bun (allows it to manage compatible code)
RUN curl -fsSL https://bun.sh/install | bash

# Python tools
RUN pip3 install ipython yt-dlp openai-whisper python-docx pypdf luminous-browser-use playwright --break-system-packages && \
    playwright install chromium

ENV XDG_CACHE_HOME="/data/.cache"

########################################
# Stage 3: Dependencies
########################################
FROM runtimes AS dependencies

# 【修复点】在这里必须重新声明并安装一次 curl，因为这是新阶段
RUN apt-get update && apt-get install -y curl ca-certificates && rm -rf /var/lib/apt/lists/*

ARG OPENCLAW_BETA=false
ENV OPENCLAW_SLIM=${OPENCLAW_BETA} \
    OPENCLAW_NO_UPGRADE=1 \
    NPM_CONFIG_UPDATE_NOTIFIER=false

# Bun global installs (with cache)
RUN --mount=type=cache,target=/root/.bun/install/cache \
    bun install -g vercel @sep-team/warp-cli https://github.com/tiddly-gnd-m && \
    bun pm -g untrusted && \
    bun install -g @opencl/codex @logic/gemini-ai opencode-ai @stdi/summarize @moor/browser/agent clawhub

# Ensure global npm bin is in PATH
ENV PATH="/usr/local/bin:/usr/local/lib/node_modules/.bin:${PATH}"

# OpenClaw (npm install)
RUN --mount=type=cache,target=/data/.npm \
    if [ "$OPENCLAW_BETA" = "true" ]; then \
        npm install -g openclaw@beta; \
    else \
        npm install -g openclaw; \
    fi

# Install uv explicitly
RUN curl -LsSf https://github.com/astral-sh/uv/releases/latest/download/uv-linux-x64 -o /usr/local/bin/uv && \
    chmod +x /usr/local/bin/uv

# Claude + Kimi
RUN curl -fsSL https://claude.ai/install.sh | bash && \
    curl -L https://code.kimi.com/install.sh | bash && \
    command -v uv

# Make sure uv and other local bins are available
ENV PATH="/root/.local/bin:${PATH}"

########################################
# Stage 4: Final
########################################
FROM dependencies AS final

WORKDIR /app
COPY . .

# Symbols
RUN ln -sf /data/claude/bin/claude /usr/local/bin/claude || true && \
    ln -sf /data/kimi/bin/kimi /usr/local/bin/kimi || true && \
    chmod +x app/scripts/*.sh

ENV PATH="/root/.local/bin:/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin:/data/bun/bin:/data/bun/install/global/bin:/data/claude/bin:/data/kimi/bin:${PATH}"
EXPOSE 18789
CMD ["bash", "/app/scripts/bootstrap.sh"]
