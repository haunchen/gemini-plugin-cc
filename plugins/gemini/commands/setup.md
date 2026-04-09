---
description: Check Gemini CLI installation, version, and API key configuration
allowed-tools: Bash
---

Run the following checks in order and report the results:

## 1. Check if Gemini CLI is installed

Run: `which gemini || where gemini 2>/dev/null`

- If found: report the path
- If not found: tell the user to install it with `npm install -g @anthropic-ai/gemini-cli` or visit https://github.com/google-gemini/gemini-cli

## 2. Check Gemini CLI version

Run: `gemini --version`

- Report the version number

## 3. Check API key

Run: `test -n "$GEMINI_API_KEY" && echo "GEMINI_API_KEY is set" || echo "GEMINI_API_KEY is not set"`

- If set: confirm it is configured (do NOT print the actual key value)
- If not set: tell the user to set it with `export GEMINI_API_KEY=your-key-here` or run `gemini` interactively to authenticate via Google OAuth

## Summary

After all checks, provide a one-line summary:
- All checks passed: "Gemini CLI is ready to use. Try /gemini:review"
- Something missing: list what needs to be fixed
