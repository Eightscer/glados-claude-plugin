#!/usr/bin/env bash
# glados_mute.sh - Mute GLaDOS TTS audio playback
# Usage: glados_mute.sh [--session]
#   --session: Mute only the current session (uses CORTEX_SESSION_ID)
#   No flag: Mute all sessions globally

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "${PLUGIN_ROOT}/lib/state-dir.sh"

if [[ "${1:-}" == "--session" ]]; then
    SESSION_ID="${CORTEX_SESSION_ID:-${CLAUDE_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-unknown}}}"
    mkdir -p "${GLADOS_STATE_DIR}/sessions"
    touch "${GLADOS_STATE_DIR}/sessions/.muted-${SESSION_ID}"
    echo "[GLaDOS TTS] Audio muted for this session (${SESSION_ID:0:8}...)"
else
    touch "${GLADOS_STATE_DIR}/.muted"
    echo "[GLaDOS TTS] Audio muted globally (all sessions)"
fi
