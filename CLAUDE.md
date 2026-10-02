# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A GLaDOS personality plugin with neural TTS for Cortex Code and Claude Code. Registers hooks (Stop, SessionEnd) that synthesize assistant responses into speech using Forward Tacotron + HiFiGAN, played via `afplay`/`aplay`.

## Commands

```bash
# Install (downloads ~260MB models, sets up venv, registers hooks/skills/commands)
./install.sh

# Uninstall (removes models, venv, hooks, skills, commands, state dirs)
./uninstall.sh

# Manual server control
./plugin/bin/serve.sh          # Start TTS server (port 8124)
./plugin/bin/stop.sh           # Stop TTS server
curl http://localhost:8124/health  # Health check

# Syntax-check all shell scripts
for f in plugin/bin/*.sh plugin/lib/*.sh; do bash -n "$f"; done
```

No test suite exists. Validation is `bash -n` syntax checks and manual functional testing (activate → speak → mute/unmute → deactivate).

## Architecture

### Runtime State Lives Outside the Repo

All ephemeral state is stored in `$GLADOS_STATE_DIR`, resolved by `plugin/lib/state-dir.sh`:
- Cortex Code: `~/.snowflake/cortex/cache/glados/`
- Claude Code: `~/.claude/cache/glados/`
- Fallback: `~/.local/state/glados-tts/`

Detection uses `CORTEX_SESSION_ID` / `CLAUDE_SESSION_ID` env vars. The state dir contains: `sessions/`, `.muted`, `server.pid`, `server.log`, `audio/`.

### Key Patterns

- **Session opt-in model**: Audio only plays for sessions that explicitly activate via `/glados`. Session markers are empty files at `$GLADOS_STATE_DIR/sessions/<session-id>`.
- **Shared library sourcing**: All `plugin/bin/*.sh` scripts source `plugin/lib/tts-helpers.sh`, which in turn sources `plugin/lib/state-dir.sh`. This provides `$GLADOS_STATE_DIR`, `$PID_FILE`, `$PLUGIN_ROOT`, `is_server_running()`, and `wait_for_server()`.
- **Mute hierarchy**: Global mute (`$GLADOS_STATE_DIR/.muted`) → session registration check → per-session mute (`sessions/.muted-<id>`).
- **Async playback**: `speak.sh` forks synthesis+playback into `( ... ) &>/dev/null & disown` so the hook returns immediately and text displays without delay.
- **Chunk splitting**: Responses are split at sentence boundaries into chunks (~200 chars for the first, ~400 after, 900 hard cap under the server's 1000-char limit). Chunks are synthesized ahead while earlier ones play.
- **Inline code cues**: `extract-response.py` keeps backticks around inline code; `engine.py` replaces opening/closing backticks with `plugin/tts/sounds/ding_on.wav` / `ding_off.wav`. Fenced code blocks are dropped.

### Hook Flow

```
Stop hook → speak.sh
  → reads JSON from stdin (session_id, last_assistant_message, transcript_path)
  → checks session registered + not muted
  → extract-response.py reads last_assistant_message from hook input
    (falls back to parsing transcript; the transcript lags one message behind)
  → chunks text → synthesizes chunks via /synthesize/<text> while playing finished ones in order (in background)

SessionEnd hook → session_end.sh
  → removes session marker + per-session mute
  → stops server if no sessions remain
```

### TTS Pipeline (Python)

```
engine.py (Flask on :8124) → glados.py (TTSRunner)
  → utils/tools.py prepare_text()
  → utils/text/cleaners.py (english_cleaners + IPA phonemization)
  → Forward Tacotron → HiFiGAN → WAV
```

Models live in `plugin/tts/models/` (gitignored, downloaded at install). The Python venv is at `plugin/tts/.venv/`.

### Install-time Substitution

The skill's `SKILL.md` uses `__PLUGIN_DIR__` and `__STATE_DIR__` placeholders that `install.sh` replaces with absolute paths via `sed` when copying to `~/.snowflake/cortex/skills/glados/` or `~/.claude/skills/glados/`.

Hook processes don't inherit the env vars `state-dir.sh` uses for platform detection, so `install.sh` prefixes every hook, slash command, and the skill's activate command with an explicit `GLADOS_STATE_DIR="<platform state dir>"`. Existing GLaDOS hooks are matched by script-path suffix, so re-running the installer replaces them rather than duplicating them.

## Conventions

- Shell scripts use `set -euo pipefail` and resolve `PLUGIN_ROOT` relative to `$0`.
- Scripts that need state paths source `tts-helpers.sh` (which sources `state-dir.sh`). Scripts that don't need `is_server_running()`/`wait_for_server()` can source `state-dir.sh` directly (e.g., `glados_mute.sh`).
- The `GLADOS_AUDIO_DIR` env var is passed from `serve.sh` to `engine.py` to direct audio output to the state directory.
- Slash commands are `.md` files that invoke `bash <absolute-path-to-script>`. They live in `plugin/skills/glados/commands/` (source) and get copied to platform command dirs at install.
