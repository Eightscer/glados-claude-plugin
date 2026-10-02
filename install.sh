#!/usr/bin/env bash
# install.sh - Install GLaDOS TTS plugin dependencies, models, and register globally
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="${SCRIPT_DIR}/plugin"
TTS_DIR="${PLUGIN_DIR}/tts"
MODELS_DIR="${TTS_DIR}/models"
VENV_DIR="${TTS_DIR}/.venv"

echo "======================================"
echo " GLaDOS TTS Plugin - Installation"
echo "======================================"
echo ""

# --- Python venv setup ---
echo "[1/4] Setting up Python virtual environment..."

if ! command -v uv &>/dev/null; then
    echo "  ✗ 'uv' not found. Install it: https://docs.astral.sh/uv/getting-started/installation/" >&2
    exit 1
fi

if [[ ! -d "${VENV_DIR}" ]]; then
    uv venv --python 3.12 "${VENV_DIR}"
fi

uv pip install -r "${TTS_DIR}/requirements.txt" -q -p "${VENV_DIR}/bin/python"

echo "  ✓ Dependencies installed"

# --- Model download ---
echo ""
echo "[2/4] Downloading GLaDOS TTS models (~260MB)..."
echo "      Source: https://github.com/R2D2FISH/glados-tts"
echo ""

mkdir -p "${MODELS_DIR}/emb"

# Model URLs (GitHub raw files from R2D2FISH/glados-tts)
GLADOS_MODEL_URL="https://github.com/R2D2FISH/glados-tts/raw/main/models/glados-new.pt"
VOCODER_URL="https://github.com/R2D2FISH/glados-tts/raw/main/models/vocoder-gpu.pt"
EMB_URL="https://github.com/R2D2FISH/glados-tts/raw/main/models/emb/glados_p2.pt"
PHONEMIZER_URL="https://github.com/R2D2FISH/glados-tts/raw/main/models/en_us_cmudict_ipa_forward.pt"

download_model() {
    local url="$1"
    local dest="$2"
    local name="$3"

    if [[ -f "${dest}" ]]; then
        echo "  ✓ ${name} (already exists)"
        return 0
    fi

    echo "  ↓ Downloading ${name}..."
    if curl -fSL --progress-bar "${url}" -o "${dest}"; then
        echo "  ✓ ${name}"
    else
        echo "  ✗ Failed to download ${name}" >&2
        echo "    Try manually: curl -L '${url}' -o '${dest}'" >&2
        return 1
    fi
}

download_model "${GLADOS_MODEL_URL}" "${MODELS_DIR}/glados-new.pt" "Forward Tacotron (glados-new.pt)"
download_model "${VOCODER_URL}" "${MODELS_DIR}/vocoder-gpu.pt" "HiFiGAN Vocoder (vocoder-gpu.pt)"
download_model "${EMB_URL}" "${MODELS_DIR}/emb/glados_p2.pt" "Speaker Embedding (glados_p2.pt)"
download_model "${PHONEMIZER_URL}" "${MODELS_DIR}/en_us_cmudict_ipa_forward.pt" "Phonemizer Model (en_us_cmudict_ipa_forward.pt)"

# --- State directories ---
echo ""
echo "[3/5] Creating runtime state directories..."

# Each platform gets a fixed state directory. It is passed explicitly to hooks
# and commands as GLADOS_STATE_DIR, because hook processes don't inherit the
# env vars state-dir.sh would otherwise use to detect the platform.
CORTEX_STATE_DIR="${HOME}/.snowflake/cortex/cache/glados"
CLAUDE_STATE_DIR="${HOME}/.claude/cache/glados"

create_state_dir() {
    mkdir -p "$1/sessions" "$1/audio"
    echo "  ✓ State directory: $1"
}

create_state_dir "${CORTEX_STATE_DIR}"
if [[ -d "$HOME/.claude" ]]; then
    create_state_dir "${CLAUDE_STATE_DIR}"
fi

# --- Global registration ---
echo ""
echo "[4/5] Registering plugin globally..."

# register_platform <config_dir> <state_dir>
register_platform() {
    local config_dir="$1"
    local state_dir="$2"
    local settings_file="${config_dir}/settings.json"
    local skills_dir="${config_dir}/skills/glados"

    # Install skill files (substitute placeholders with actual paths)
    mkdir -p "${skills_dir}"
    for skill_file in "${PLUGIN_DIR}/skills/glados/"*.md; do
        sed -e "s|__PLUGIN_DIR__|${PLUGIN_DIR}|g" -e "s|__STATE_DIR__|${state_dir}|g" \
            "${skill_file}" > "${skills_dir}/$(basename "${skill_file}")"
    done
    echo "  ✓ GLaDOS skill installed to ${skills_dir}"

    # Register hooks in settings.json (Stop + SessionEnd only; no SessionStart).
    # Existing GLaDOS hooks are matched by script path so older installs
    # (without GLADOS_STATE_DIR) are replaced rather than duplicated.
    "${VENV_DIR}/bin/python" - "${settings_file}" "${PLUGIN_DIR}" "${state_dir}" << 'MERGE_EOF'
import json, os, sys

settings_file, plugin_dir, state_dir = sys.argv[1:4]

settings = {}
if os.path.exists(settings_file):
    with open(settings_file, 'r') as f:
        settings = json.load(f)

hooks = settings.setdefault('hooks', {})

def without(event, script):
    suffix = f"bash {plugin_dir}/bin/{script}"
    return [
        entry for entry in hooks.get(event, [])
        if not any(h.get('command', '').endswith(suffix) for h in entry.get('hooks', []))
    ]

# Remove old SessionStart hook if present (migration from previous install)
session_start = without('SessionStart', 'serve.sh')
if session_start:
    hooks['SessionStart'] = session_start
else:
    hooks.pop('SessionStart', None)

for event, script, timeout in (('Stop', 'speak.sh', 30), ('SessionEnd', 'session_end.sh', 10)):
    entries = without(event, script)
    entries.append({
        "hooks": [{
            "type": "command",
            "command": f'GLADOS_STATE_DIR="{state_dir}" bash {plugin_dir}/bin/{script}',
            "timeout": timeout,
        }]
    })
    hooks[event] = entries

os.makedirs(os.path.dirname(settings_file), exist_ok=True)
with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')

print("  ✓ Hooks registered in " + settings_file)
MERGE_EOF
}

echo "  Registering for Cortex Code..."
register_platform "$HOME/.snowflake/cortex" "${CORTEX_STATE_DIR}"

echo "  Registering for Claude Code..."
if [[ -d "$HOME/.claude" ]]; then
    register_platform "$HOME/.claude" "${CLAUDE_STATE_DIR}"
else
    echo "  - Claude Code not detected (no ~/.claude), skipping"
fi

# --- Slash commands ---
echo ""
echo "[5/5] Installing slash commands..."

# install_slash_commands <commands_dir> <state_dir> <label>
install_slash_commands() {
    local commands_dir="$1"
    local state_dir="$2"
    local label="$3"
    local name

    mkdir -p "${commands_dir}"

    for name in glados_mute glados_unmute glados_mute_session glados_unmute_session \
                glados_restart_server glados_off glados_off_all; do
        cat > "${commands_dir}/${name}.md" << CMD_EOF
Run this command: GLADOS_STATE_DIR="${state_dir}" bash ${PLUGIN_DIR}/bin/${name}.sh
CMD_EOF
    done

    echo "  ✓ ${label}: /glados_mute, /glados_unmute, /glados_mute_session, /glados_unmute_session, /glados_restart_server, /glados_off, /glados_off_all"
}

# Cortex Code commands
install_slash_commands "$HOME/.snowflake/cortex/commands" "${CORTEX_STATE_DIR}" "Cortex Code"

# Claude Code commands (if ~/.claude exists)
if [[ -d "$HOME/.claude" ]]; then
    install_slash_commands "$HOME/.claude/commands" "${CLAUDE_STATE_DIR}" "Claude Code"
else
    echo "  - Claude Code not detected, skipping commands"
fi

# --- Done ---
echo ""
echo "======================================"
echo " Installation complete!"
echo "======================================"
echo ""
echo "Models:  ${MODELS_DIR}"
echo "Venv:    ${VENV_DIR}"
echo ""
echo "To test the TTS server manually:"
echo "  ${PLUGIN_DIR}/bin/serve.sh"
echo "  curl http://localhost:8124/synthesize/Hello%20test%20subject"
echo "  ${PLUGIN_DIR}/bin/stop.sh"
echo ""
echo "The TTS server starts on-demand when you activate the /glados skill."
echo "Only sessions that have opted in will receive audio output."
echo ""
echo "Slash commands available:"
echo "  /glados                 - Activate GLaDOS personality + TTS for this session"
echo "  /glados_mute            - Mute audio globally (all sessions)"
echo "  /glados_unmute          - Unmute audio globally"
echo "  /glados_mute_session    - Mute audio for this session only"
echo "  /glados_unmute_session  - Unmute audio for this session only"
echo "  /glados_restart_server  - Restart the TTS server"
