#!/usr/bin/env bash
# glados_unmute.sh - Unmute GLaDOS TTS audio playback
# Usage: glados_unmute.sh [--session]
#   --session: Unmute only the current session (uses CORTEX_SESSION_ID)
#   No flag: Unmute all sessions globally

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "${PLUGIN_ROOT}/lib/state-dir.sh"

if [[ "${1:-}" == "--session" ]]; then
    SESSION_ID="${CORTEX_SESSION_ID:-${CLAUDE_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-unknown}}}"
    rm -f "${GLADOS_STATE_DIR}/sessions/.muted-${SESSION_ID}"
    echo "[GLaDOS TTS] Audio unmuted for this session (${SESSION_ID:0:8}...)"
else
    rm -f "${GLADOS_STATE_DIR}/.muted"
    echo "[GLaDOS TTS] Audio unmuted globally (all sessions)"
fi
