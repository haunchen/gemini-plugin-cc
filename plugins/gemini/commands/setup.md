---
description: Check Gemini CLI installation, version, and authentication status
allowed-tools: Bash
argument-hint: [--model <model>]
---

## Step 0: Parse --model parameter

Check if $ARGUMENTS contains `--model <value>`:
- If yes: extract the value as MODEL, remove `--model <value>` from $ARGUMENTS
- If no: set MODEL = flash

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

## 4. Test model availability

Run: `echo "ping" | gemini -m $MODEL`

- If the command succeeds: report that the model is available
- If the command fails with a model error: report the error and suggest trying a different model

## Summary

After all checks, provide a one-line summary:
- All checks passed: "Gemini CLI is ready to use with model $MODEL. Try /gemini:review"
- Something missing: list what needs to be fixed
