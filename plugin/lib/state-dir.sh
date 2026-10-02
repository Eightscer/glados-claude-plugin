#!/usr/bin/env bash
# state-dir.sh - Resolve GLADOS_STATE_DIR based on active tool environment
#
# Runtime state (sessions, mute flags, PID, logs, audio cache) lives outside
# the git repo in a platform-appropriate location:
#   Cortex Code: ~/.snowflake/cortex/cache/glados/
#   Claude Code:  ~/.claude/cache/glados/
#   Fallback:     ~/.local/state/glados-tts/

if [[ -n "${GLADOS_STATE_DIR:-}" ]]; then
    # Already set (e.g. by parent script or env override)
    :
elif [[ -n "${CORTEX_SESSION_ID:-}" ]]; then
    GLADOS_STATE_DIR="${HOME}/.snowflake/cortex/cache/glados"
elif [[ -n "${CLAUDE_SESSION_ID:-}" || -n "${CLAUDE_CODE_SESSION_ID:-}" || -n "${CLAUDECODE:-}" ]]; then
    GLADOS_STATE_DIR="${HOME}/.claude/cache/glados"
else
    GLADOS_STATE_DIR="${HOME}/.local/state/glados-tts"
fi

export GLADOS_STATE_DIR
mkdir -p "${GLADOS_STATE_DIR}"
