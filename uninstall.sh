#!/usr/bin/env bash
# uninstall.sh - Remove GLaDOS TTS models, venv, audio cache, and global registration
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="${SCRIPT_DIR}/plugin"
TTS_DIR="${PLUGIN_DIR}/tts"

# Prefer the plugin venv interpreter (system python3 may not exist)
if [[ -x "${TTS_DIR}/.venv/bin/python" ]]; then
    PYTHON="${TTS_DIR}/.venv/bin/python"
else
    PYTHON="python3"
fi

echo "GLaDOS TTS Plugin - Uninstall"
echo ""

# Stop server if running
"${PLUGIN_DIR}/bin/stop.sh" 2>/dev/null || true

# --- Remove global registration ---
echo "Removing global registration..."

unregister_cortex_code() {
    local config_dir="$HOME/.snowflake/cortex"
    local settings_file="${config_dir}/settings.json"
    local skills_dir="${config_dir}/skills/glados"

    # Remove skill directory
    if [[ -d "${skills_dir}" ]]; then
        rm -rf "${skills_dir}"
        echo "  ✓ Removed skill from ${skills_dir}"
    fi

    # Remove hooks from settings.json
    if [[ -f "${settings_file}" ]]; then
        "${PYTHON}" << MERGE_EOF
import json

settings_file = "${settings_file}"
plugin_dir = "${PLUGIN_DIR}"

with open(settings_file, 'r') as f:
    settings = json.load(f)

hooks = settings.get('hooks', {})
modified = False

serve_cmd = f"bash {plugin_dir}/bin/serve.sh"
speak_cmd = f"bash {plugin_dir}/bin/speak.sh"
session_end_cmd = f"bash {plugin_dir}/bin/session_end.sh"

# Remove SessionStart hooks (legacy)
session_start = hooks.get('SessionStart', [])
new_session_start = [
    entry for entry in session_start
    if not any(h.get('command', '').endswith(serve_cmd) for h in entry.get('hooks', []))
]
if len(new_session_start) != len(session_start):
    modified = True
    if new_session_start:
        hooks['SessionStart'] = new_session_start
    else:
        hooks.pop('SessionStart', None)

# Remove Stop hooks
stop = hooks.get('Stop', [])
new_stop = [
    entry for entry in stop
    if not any(h.get('command', '').endswith(speak_cmd) for h in entry.get('hooks', []))
]
if len(new_stop) != len(stop):
    modified = True
    if new_stop:
        hooks['Stop'] = new_stop
    else:
        hooks.pop('Stop', None)

# Remove SessionEnd hooks
session_end = hooks.get('SessionEnd', [])
new_session_end = [
    entry for entry in session_end
    if not any(h.get('command', '').endswith(session_end_cmd) for h in entry.get('hooks', []))
]
if len(new_session_end) != len(session_end):
    modified = True
    if new_session_end:
        hooks['SessionEnd'] = new_session_end
    else:
        hooks.pop('SessionEnd', None)

if not hooks:
    settings.pop('hooks', None)

if modified:
    with open(settings_file, 'w') as f:
        json.dump(settings, f, indent=2)
        f.write('\n')
    print("  ✓ Hooks removed from " + settings_file)
else:
    print("  - No hooks to remove in " + settings_file)
MERGE_EOF
    fi
}

unregister_claude_code() {
    local config_dir="$HOME/.claude"
    local settings_file="${config_dir}/settings.json"
    local skills_dir="${config_dir}/skills/glados"

    # Remove skill directory
    if [[ -d "${skills_dir}" ]]; then
        rm -rf "${skills_dir}"
        echo "  ✓ Removed skill from ${skills_dir}"
    fi

    if [[ ! -f "${settings_file}" ]]; then
        return 0
    fi

    "${PYTHON}" << MERGE_EOF
import json

settings_file = "${settings_file}"
plugin_dir = "${PLUGIN_DIR}"

with open(settings_file, 'r') as f:
    settings = json.load(f)

hooks = settings.get('hooks', {})
modified = False

serve_cmd = f"bash {plugin_dir}/bin/serve.sh"
speak_cmd = f"bash {plugin_dir}/bin/speak.sh"
session_end_cmd = f"bash {plugin_dir}/bin/session_end.sh"

# Remove SessionStart hooks (legacy)
session_start = hooks.get('SessionStart', [])
new_session_start = [
    entry for entry in session_start
    if not any(h.get('command', '').endswith(serve_cmd) for h in entry.get('hooks', []))
]
if len(new_session_start) != len(session_start):
    modified = True
    if new_session_start:
        hooks['SessionStart'] = new_session_start
    else:
        hooks.pop('SessionStart', None)

# Remove Stop hooks
stop = hooks.get('Stop', [])
new_stop = [
    entry for entry in stop
    if not any(h.get('command', '').endswith(speak_cmd) for h in entry.get('hooks', []))
]
if len(new_stop) != len(stop):
    modified = True
    if new_stop:
        hooks['Stop'] = new_stop
    else:
        hooks.pop('Stop', None)

# Remove SessionEnd hooks
session_end = hooks.get('SessionEnd', [])
new_session_end = [
    entry for entry in session_end
    if not any(h.get('command', '').endswith(session_end_cmd) for h in entry.get('hooks', []))
]
if len(new_session_end) != len(session_end):
    modified = True
    if new_session_end:
        hooks['SessionEnd'] = new_session_end
    else:
        hooks.pop('SessionEnd', None)

if not hooks:
    settings.pop('hooks', None)

if modified:
    with open(settings_file, 'w') as f:
        json.dump(settings, f, indent=2)
        f.write('\n')
    print("  ✓ Hooks removed from " + settings_file)
else:
    print("  - No hooks to remove in " + settings_file)
MERGE_EOF
}

unregister_cortex_code
unregister_claude_code

# --- Remove slash commands ---
echo "Removing slash commands..."

remove_slash_commands() {
    local commands_dir="$1"
    local label="$2"
    local removed=false

    for cmd in glados_mute glados_unmute glados_mute_session glados_unmute_session glados_restart_server glados_off glados_off_all; do
        if [[ -f "${commands_dir}/${cmd}.md" ]]; then
            rm -f "${commands_dir}/${cmd}.md"
            removed=true
        fi
    done

    if [[ "${removed}" == "true" ]]; then
        echo "  ✓ ${label} commands removed"
    fi
}

remove_slash_commands "$HOME/.snowflake/cortex/commands" "Cortex Code"
remove_slash_commands "$HOME/.claude/commands" "Claude Code"

# --- Remove session registry ---
if [[ -d "${TTS_DIR}/sessions" ]]; then
    echo "Removing session registry..."
    rm -rf "${TTS_DIR}/sessions"
    echo "  ✓ Sessions directory removed"
fi

# --- Remove models ---
if [[ -d "${TTS_DIR}/models" ]]; then
    echo "Removing models..."
    rm -rf "${TTS_DIR}/models"
    mkdir -p "${TTS_DIR}/models/emb"
    echo "  ✓ Models removed"
fi

# --- Remove venv ---
if [[ -d "${TTS_DIR}/.venv" ]]; then
    echo "Removing virtual environment..."
    rm -rf "${TTS_DIR}/.venv"
    echo "  ✓ Venv removed"
fi

# --- Remove audio cache ---
if [[ -d "${TTS_DIR}/audio" ]]; then
    echo "Removing legacy audio cache..."
    rm -rf "${TTS_DIR}/audio"
    echo "  ✓ Legacy audio cache removed"
fi

# Remove legacy server runtime files (pre-state-dir migration)
rm -f "${TTS_DIR}/server.log" "${TTS_DIR}/server.pid"

# --- Remove runtime state directory ---
echo "Removing runtime state directories..."
for state_dir in \
    "${HOME}/.snowflake/cortex/cache/glados" \
    "${HOME}/.claude/cache/glados" \
    "${HOME}/.local/state/glados-tts"; do
    if [[ -d "${state_dir}" ]]; then
        rm -rf "${state_dir}"
        echo "  ✓ Removed ${state_dir}"
    fi
done

echo ""
echo "Uninstall complete. Plugin source code remains — models, dependencies, and"
echo "global registration have been removed. Run install.sh to re-install."
