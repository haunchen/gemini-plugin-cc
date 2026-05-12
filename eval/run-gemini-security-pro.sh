#!/bin/bash
# Custom system prompt wrapper — 用 plugin 的 security-review.md 作為 system prompt（pro，對齊 production 預設）
# Mirror production invocation including --admin-policy.
SCRIPT_DIR="$(dirname "$0")"
GEMINI_SYSTEM_MD="$SCRIPT_DIR/../plugins/gemini/system-prompts/security-review.md" \
  gemini -p "$1" -m pro \
  --admin-policy "$SCRIPT_DIR/../plugins/gemini/policies/readonly.toml"
