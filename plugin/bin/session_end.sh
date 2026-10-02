#!/usr/bin/env bash
# session_end.sh - Clean up session registration on session end (SessionEnd hook)
# Removes the session's opt-in marker and per-session mute file.
# Stops the TTS server if no sessions remain active.

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "${PLUGIN_ROOT}/lib/tts-helpers.sh"

# Read hook input from stdin to get session_id
INPUT=$(cat)
SESSION_ID=$(echo "${INPUT}" | "${PYTHON}" -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('session_id', ''))
" 2>/dev/null || echo "")

if [[ -z "${SESSION_ID}" ]]; then
    exit 0
fi

SESSIONS_DIR="${GLADOS_STATE_DIR}/sessions"

# Remove session registration and per-session mute
rm -f "${SESSIONS_DIR}/${SESSION_ID}"
rm -f "${SESSIONS_DIR}/.muted-${SESSION_ID}"

# If no sessions remain opted in, stop the server
ACTIVE_SESSIONS=$(find "${SESSIONS_DIR}" -maxdepth 1 -type f ! -name '.*' 2>/dev/null | wc -l)

if [[ "${ACTIVE_SESSIONS}" -eq 0 ]] && is_server_running; then
    "${PLUGIN_ROOT}/bin/stop.sh"
fi

exit 0
