---
description: Check Gemini CLI installation, version, and authentication status
allowed-tools: Bash
---

Run the following checks in order and report the results:

## 1. Check if Gemini CLI is installed

Run: `which gemini || where gemini 2>/dev/null`

- If found: report the path
- If not found: tell the user to install it with `npm install -g @google/gemini-cli` or visit https://github.com/google-gemini/gemini-cli

## 2. Check Gemini CLI version

Run: `gemini --version`

- Report the version number

## 3. Check authentication

Run: `test -f ~/.gemini/oauth_creds.json && echo "OAuth credentials found" || echo "OAuth credentials not found"`

- If found: confirm Google OAuth is configured
- If not found: tell the user to run `gemini` interactively to authenticate via Google OAuth

## Summary

After all checks, provide a one-line summary:
- All checks passed: "Gemini CLI is ready to use. Try /gemini:review"
- Something missing: list what needs to be fixed
