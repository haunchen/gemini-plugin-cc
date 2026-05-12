#!/bin/bash
# Custom system prompt wrapper — 用 plugin 的 review.md 作為 system prompt
# Mirror production invocation including --admin-policy (PR #4).
SCRIPT_DIR="$(dirname "$0")"
GEMINI_SYSTEM_MD="$SCRIPT_DIR/../plugins/gemini/system-prompts/review.md" \
  gemini -p "$1" -m pro \
  --admin-policy "$SCRIPT_DIR/../plugins/gemini/policies/readonly.toml"
