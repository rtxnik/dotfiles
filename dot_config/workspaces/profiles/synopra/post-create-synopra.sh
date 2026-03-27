#!/usr/bin/env bash
set -euo pipefail

log() { printf '[synopra] %s\n' "$1"; }

# Install Playwright browser (headless Chromium for E2E testing and self-QA)
if command -v npx &>/dev/null; then
    log "Installing Playwright Chromium"
    npx playwright install chromium 2>/dev/null || log "Playwright install skipped (will retry on first use)"
fi

# Install GSD (Get Shit Done) locally
if command -v npx &>/dev/null; then
    log "Installing GSD"
    npx get-shit-done-cc --claude --local 2>/dev/null || log "GSD install skipped"
fi

# Register MCP servers for Claude Code (if available)
if command -v claude &>/dev/null; then
    log "Registering MCP servers"
    claude mcp add context7 -- npx -y @upstash/context7-mcp@latest 2>/dev/null || true
    claude mcp add playwright -- npx @playwright/mcp@latest --headless 2>/dev/null || true
    log "MCP servers registered: context7, playwright"
fi
