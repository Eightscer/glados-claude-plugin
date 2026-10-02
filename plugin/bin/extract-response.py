#!/usr/bin/env python3
"""
extract-response.py - Extract the last assistant message from a transcript file.
Used by speak.sh to get the text that should be spoken.
"""

import json
import os
import sys
import re


def strip_markdown(text):
    """Remove markdown formatting, code blocks, and special characters for cleaner TTS."""
    # Remove code blocks entirely
    text = re.sub(r'```[\s\S]*?```', '', text)
    # Protect inline code from the markdown rules below (e.g. underscores in
    # identifiers). Backticks are kept: the TTS server renders them as clicks.
    code_spans = []

    def stash_code(match):
        code_spans.append(match.group(1))
        return f'\x00{len(code_spans) - 1}\x00'

    text = re.sub(r'`([^`\n]+)`', stash_code, text)
    # Drop any stray unmatched backticks
    text = text.replace('`', '')
    # Remove headers
    text = re.sub(r'^#{1,6}\s+', '', text, flags=re.MULTILINE)
    # Remove bold/italic markers
    text = re.sub(r'\*{1,3}([^*]+)\*{1,3}', r'\1', text)
    text = re.sub(r'(?<!\w)_{1,3}([^_]+)_{1,3}(?!\w)', r'\1', text)  # not snake_case
    # Remove markdown tables (keep cell text, drop pipes and header separators)
    text = re.sub(r'^\|?[-:| ]+\|?$', '', text, flags=re.MULTILINE)  # header separator rows
    text = re.sub(r'\|', ' ', text)  # remaining pipes → spaces
    # Remove links, keep text
    text = re.sub(r'\[([^\]]+)\]\([^)]+\)', r'\1', text)
    # Remove bullet points
    text = re.sub(r'^\s*[-*+]\s+', '', text, flags=re.MULTILINE)
    # Remove numbered lists prefix
    text = re.sub(r'^\s*\d+\.\s+', '', text, flags=re.MULTILINE)
    # Collapse whitespace
    text = re.sub(r'([.!?:;])?\s*\n{2,}', lambda m: (m.group(1) or '.') + ' ', text)
    text = re.sub(r'\n', ' ', text)
    text = re.sub(r'\s{2,}', ' ', text)
    # Restore inline code, still wrapped in backticks
    text = re.sub(r'\x00(\d+)\x00', lambda m: f'`{code_spans[int(m.group(1))]}`', text)
    return text.strip()


def extract_last_response(transcript_path):
    """Extract the last assistant message from transcript JSON or JSONL."""
    messages = []

    # Strategy 1: JSONL file (direct path or .history.jsonl companion)
    # Claude Code: each line is {"message": {"role":..., "content":...}, ...}
    # Cortex Code: each line is {"role":..., "content":...} (flat messages)
    jsonl_path = transcript_path
    if not jsonl_path.endswith('.jsonl'):
        jsonl_path = transcript_path.replace('.json', '.history.jsonl')
    if os.path.isfile(jsonl_path):
        try:
            with open(jsonl_path, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line:
                        entry = json.loads(line)
                        if "message" in entry and isinstance(entry["message"], dict):
                            messages.append(entry["message"])
                        elif "role" in entry:
                            messages.append(entry)
        except (json.JSONDecodeError, FileNotFoundError):
            messages = []

    # Strategy 2: JSON transcript file (array of messages or {messages: [...]})
    if not messages and not transcript_path.endswith('.jsonl'):
        try:
            with open(transcript_path, 'r') as f:
                transcript = json.load(f)
        except (json.JSONDecodeError, FileNotFoundError):
            return ""

        messages = transcript if isinstance(transcript, list) else transcript.get("messages", [])

    # Find the last assistant message that contains actual text (skip tool_use-only messages)
    last_assistant_text = ""
    for msg in reversed(messages):
        role = msg.get("role", "")
        if role == "assistant":
            content = msg.get("content", "")
            if isinstance(content, list):
                text_parts = []
                for block in content:
                    if isinstance(block, dict) and block.get("type") == "text":
                        text_parts.append(block.get("text", ""))
                    elif isinstance(block, str):
                        text_parts.append(block)
                candidate = " ".join(text_parts).strip()
                if candidate:
                    last_assistant_text = candidate
                    break
            elif isinstance(content, str) and content.strip():
                last_assistant_text = content
                break

    if not last_assistant_text:
        return ""

    # Clean for TTS
    return strip_markdown(last_assistant_text)


def extract_from_hook_input(hook_input):
    """Extract the response from Stop hook JSON.

    Prefers last_assistant_message, which the hook receives before the final
    message is flushed to the transcript; falls back to the transcript.
    """
    message = hook_input.get("last_assistant_message")
    if isinstance(message, str) and message.strip():
        return strip_markdown(message)

    transcript_path = hook_input.get("transcript_path", "")
    if transcript_path and os.path.isfile(transcript_path):
        return extract_last_response(transcript_path)
    return ""


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--hook-input":
        try:
            result = extract_from_hook_input(json.load(sys.stdin))
        except json.JSONDecodeError:
            result = ""
    elif len(sys.argv) == 2:
        result = extract_last_response(sys.argv[1])
    else:
        print("Usage: extract-response.py <transcript_path> | --hook-input < hook.json", file=sys.stderr)
        sys.exit(1)

    print(result)
