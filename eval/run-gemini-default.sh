#!/bin/bash
# Baseline — 不設 GEMINI_SYSTEM_MD，使用 Gemini CLI 內建 system prompt
gemini -p "$1" -m flash
