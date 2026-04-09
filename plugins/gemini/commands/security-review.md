---
description: Get a security-focused review that checks for vulnerabilities
allowed-tools: Bash, Read, Glob
argument-hint: [file-path] [--model <model>]
---

Get a security-focused review using Gemini CLI. This checks for OWASP Top 10 vulnerabilities, injection attacks, auth flaws, hardcoded secrets, and more.

## Step 1: Parse --model parameter

Check if $ARGUMENTS contains `--model <value>`:
- If yes: extract the value as MODEL, remove `--model <value>` from $ARGUMENTS
- If no: set MODEL = flash

Valid model values: flash, pro, flash-lite, or any full model name.

## Step 2: Determine input

If $ARGUMENTS (after --model removal) is provided:
- If it contains glob characters (* or ?), use the Glob tool to expand it, then Read each matched file
- Otherwise, Read the single file directly
- Concatenate all file contents as REVIEW_INPUT

If $ARGUMENTS is empty:
- Run: `git diff HEAD 2>/dev/null`
- If the command fails (e.g., no commits yet) or the diff is empty, also try: `git diff --cached`
- If still empty, tell the user: "No changes found. Provide a file path or make some changes first."
- Store the diff output as REVIEW_INPUT

## Step 3: Locate system prompt

Determine the absolute path to the system prompt file:
- The file is at `system-prompts/security-review.md` relative to this plugin's root directory
- The plugin root is the parent of the `commands/` directory containing this file
- Store this absolute path as SYSTEM_PROMPT_PATH

## Step 4: Call Gemini CLI

Run the following bash command, passing REVIEW_INPUT via stdin:

```bash
echo "$REVIEW_INPUT" | GEMINI_SYSTEM_MD="$SYSTEM_PROMPT_PATH" gemini -o text -m $MODEL
```

Note: We pipe input via stdin instead of -p flag to handle large diffs and special characters safely.

## Step 5: Present results

Show the Gemini response directly to the user. Do not modify, summarize, or reformat it.

## Error handling

- If `gemini` command is not found: suggest running `/gemini:setup` first
- If the command fails with an auth error: suggest running `gemini` interactively to re-authenticate via Google OAuth
- If the command times out or returns an error: show the error message and suggest retrying
