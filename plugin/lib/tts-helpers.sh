#!/usr/bin/env bash
# tts-helpers.sh - Shared utility functions for GLaDOS TTS scripts

TTS_PORT=8124
PLUGIN_ROOT="${PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Resolve state directory (sessions, mute flags, PID, logs, audio)
source "${PLUGIN_ROOT}/lib/state-dir.sh"

PID_FILE="${GLADOS_STATE_DIR}/server.pid"

# Python interpreter: prefer the plugin venv (system python3 may not exist)
if [[ -x "${PLUGIN_ROOT}/tts/.venv/bin/python" ]]; then
    PYTHON="${PLUGIN_ROOT}/tts/.venv/bin/python"
else
    PYTHON="python3"
fi

# Play a WAV file with the first available player
play_audio() {
    local file="$1"
    if command -v afplay &>/dev/null; then
        afplay "${file}"
    elif command -v aplay &>/dev/null; then
        aplay -q "${file}"
    elif command -v pw-play &>/dev/null; then
        pw-play "${file}"
    elif command -v paplay &>/dev/null; then
        paplay "${file}"
    elif command -v ffplay &>/dev/null; then
        ffplay -nodisp -autoexit -loglevel quiet "${file}"
    fi
}

is_server_running() {
    # Check by PID file first
    if [[ -f "${PID_FILE}" ]]; then
        local pid
        pid=$(cat "${PID_FILE}")
        if kill -0 "${pid}" 2>/dev/null; then
            return 0
        fi
        # Stale PID file
        rm -f "${PID_FILE}"
    fi

    # Check by port
    if curl -sf "http://localhost:${TTS_PORT}/health" >/dev/null 2>&1; then
        return 0
    fi

    return 1
}

wait_for_server() {
    local timeout="${1:-10}"
    local elapsed=0

    while (( elapsed < timeout )); do
        if curl -sf "http://localhost:${TTS_PORT}/health" >/dev/null 2>&1; then
            echo "[GLaDOS TTS] Server ready"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    echo "[GLaDOS TTS] Server failed to start within ${timeout}s" >&2
    return 1
}
