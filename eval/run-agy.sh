#!/bin/bash
# Eval runner for agy (Antigravity CLI).
# Usage (promptfoo appends the prompt as the last argument):
#   exec: bash ./run-agy.sh <agent|-> <model-slug>
# Pass "-" as the agent to run the bare model with no system prompt (baseline).
#
# agy has no GEMINI_SYSTEM_MD equivalent; the system prompt comes from an agent
# installed with `agy plugin install ../plugins/gemini/agy`. An unknown --agent
# name is silently ignored, so a missing install shows up as baseline-quality
# output rather than an error — install before trusting the numbers.
AGENT="$1"
MODEL="$2"
PROMPT="$3"

if [ "$AGENT" = "-" ]; then
  agy -p "$PROMPT" --model "$MODEL" --print-timeout 5m 2>&1
else
  agy -p "$PROMPT" --agent "$AGENT" --model "$MODEL" --print-timeout 5m 2>&1
fi
