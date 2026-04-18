#!/bin/bash
# Custom system prompt wrapper — 用 plugin 的 review.md 作為 system prompt
GEMINI_SYSTEM_MD="$(dirname "$0")/../plugins/gemini/system-prompts/review.md" \
  gemini -p "$1" -m flash
