#!/usr/bin/env bash
# glados_deactivate.sh - Deactivate GLaDOS TTS for the current session
# Unregisters this session. If no sessions remain, stops the TTS server.

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "${PLUGIN_ROOT}/lib/tts-helpers.sh"

SESSION_ID="${CORTEX_SESSION_ID:-${CLAUDE_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-unknown}}}"
SESSIONS_DIR="${GLADOS_STATE_DIR}/sessions"

# Remove session registration and per-session mute
rm -f "${SESSIONS_DIR}/${SESSION_ID}"
rm -f "${SESSIONS_DIR}/.muted-${SESSION_ID}"

# If no sessions remain opted in, stop the server
ACTIVE_SESSIONS=$(find "${SESSIONS_DIR}" -maxdepth 1 -type f ! -name '.*' 2>/dev/null | wc -l)

if [[ "${ACTIVE_SESSIONS}" -eq 0 ]]; then
    "${PLUGIN_ROOT}/bin/stop.sh"
    echo "[GLaDOS TTS] No active sessions remain — server stopped"
else
    echo "[GLaDOS TTS] Session deactivated (${SESSION_ID:0:8}...)"
    echo "[GLaDOS TTS] ${ACTIVE_SESSIONS} session(s) still active"
fi
