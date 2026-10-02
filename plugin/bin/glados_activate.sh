#!/usr/bin/env bash
# glados_activate.sh - Activate GLaDOS TTS for the current session
# Registers this session for audio output and starts the TTS server if needed.

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "${PLUGIN_ROOT}/lib/tts-helpers.sh"

SESSION_ID="${CORTEX_SESSION_ID:-${CLAUDE_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-unknown}}}"
SESSIONS_DIR="${GLADOS_STATE_DIR}/sessions"

mkdir -p "${SESSIONS_DIR}"
touch "${SESSIONS_DIR}/${SESSION_ID}"

# Start server if not running
if ! is_server_running; then
    "${PLUGIN_ROOT}/bin/serve.sh"
fi

echo "[GLaDOS TTS] Session activated (${SESSION_ID:0:8}...)"
echo "[GLaDOS TTS] Audio will play for this session"
