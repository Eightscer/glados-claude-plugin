#!/usr/bin/env bash
# speak.sh - Synthesize the latest response via GLaDOS TTS (Stop hook)
# Reads the assistant's last response from the hook input (or transcript), sends to TTS server,
# and plays the resulting audio.

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "${PLUGIN_ROOT}/lib/tts-helpers.sh"

# Read hook input from stdin
INPUT=$(cat)

# Extract session_id from hook input
SESSION_ID=$(echo "${INPUT}" | "${PYTHON}" -c "
import sys, json
print(json.load(sys.stdin).get('session_id', ''))
" 2>/dev/null || true)

# Check if this session has opted in to GLaDOS TTS
SESSIONS_DIR="${GLADOS_STATE_DIR}/sessions"
if [[ -z "${SESSION_ID}" || ! -f "${SESSIONS_DIR}/${SESSION_ID}" ]]; then
    exit 0  # Session not opted in, skip silently
fi

# Check if server is running
if ! is_server_running; then
    exit 0  # Server not running, skip silently
fi

# Check global mute
if [[ -f "${GLADOS_STATE_DIR}/.muted" ]]; then
    exit 0
fi

# Check per-session mute
if [[ -f "${SESSIONS_DIR}/.muted-${SESSION_ID}" ]]; then
    exit 0
fi

# Extract the last assistant response text
RESPONSE_TEXT=$(echo "${INPUT}" | "${PYTHON}" "${PLUGIN_ROOT}/bin/extract-response.py" --hook-input)

if [[ -z "${RESPONSE_TEXT}" ]]; then
    exit 0
fi

# Fork synthesis + playback into background so the hook exits immediately
# and the text response is shown to the user without delay.
(
    WORK_DIR=$(mktemp -d /tmp/glados-tts-XXXXXXXXXXXX)
    trap 'rm -rf "${WORK_DIR}"' EXIT

    # Split text into sentence-bounded chunks, one per line. The first chunk is
    # kept short so playback starts quickly; later chunks are larger since they
    # are synthesized while earlier ones play. Hard cap stays under the
    # server's 1000-char limit.
    "${PYTHON}" -c "
import sys, re

text = sys.argv[1]
first_limit, limit, hard_limit = 200, 400, 900

sentences = []
for s in re.split(r'(?<=[.!?])\s+', text):
    s = s.strip()
    # Break any oversized sentence at word boundaries
    while len(s) > hard_limit:
        cut = s.rfind(' ', 0, hard_limit)
        if cut <= 0:
            cut = hard_limit
        sentences.append(s[:cut].strip())
        s = s[cut:].strip()
    if s:
        sentences.append(s)

chunks, current = [], ''
for s in sentences:
    cap = first_limit if not chunks else limit
    if current and len(current) + 1 + len(s) > cap:
        chunks.append(current)
        current = s
    else:
        current = f'{current} {s}' if current else s
if current:
    chunks.append(current)

for c in chunks:
    print(c)
" "${RESPONSE_TEXT}" > "${WORK_DIR}/chunks"

    TOTAL=$(wc -l < "${WORK_DIR}/chunks")

    # Producer: synthesize chunks in order. Each WAV is renamed into place only
    # when complete; a .fail marker lets the player skip a failed chunk.
    (
        i=0
        while IFS= read -r CHUNK; do
            i=$((i + 1))
            ENCODED_TEXT=$("${PYTHON}" -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "${CHUNK}")
            HTTP_CODE=$(curl -s -o "${WORK_DIR}/${i}.part" -w "%{http_code}" \
                "http://localhost:${TTS_PORT}/synthesize/${ENCODED_TEXT}" 2>/dev/null || echo "000")
            if [[ "${HTTP_CODE}" == "200" && -s "${WORK_DIR}/${i}.part" ]]; then
                mv "${WORK_DIR}/${i}.part" "${WORK_DIR}/${i}.wav"
            else
                touch "${WORK_DIR}/${i}.fail"
            fi
        done < "${WORK_DIR}/chunks"
    ) &
    PRODUCER_PID=$!

    # Consumer: play each chunk as soon as it is ready, while later chunks synthesize
    for ((i = 1; i <= TOTAL; i++)); do
        while [[ ! -f "${WORK_DIR}/${i}.wav" && ! -f "${WORK_DIR}/${i}.fail" ]]; do
            if ! kill -0 "${PRODUCER_PID}" 2>/dev/null; then
                # Producer exited; re-check once in case it finished just now
                [[ -f "${WORK_DIR}/${i}.wav" ]] || break 2
            fi
            sleep 0.1
        done
        [[ -f "${WORK_DIR}/${i}.wav" ]] && play_audio "${WORK_DIR}/${i}.wav"
    done

    wait "${PRODUCER_PID}" 2>/dev/null || true
) &>/dev/null &
disown

exit 0
