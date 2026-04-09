---
description: Get a code review from Gemini CLI as a second opinion
allowed-tools: Bash, Read, Glob
argument-hint: [file-path]
---

Perform a code review using Gemini CLI. This gives you a second opinion from a different AI model.

## Step 1: Determine input

If $ARGUMENTS is provided:
- If it contains glob characters (* or ?), use the Glob tool to expand it, then Read each matched file
- Otherwise, Read the single file directly
- Concatenate all file contents as REVIEW_INPUT

If $ARGUMENTS is empty:
- Run: `git diff HEAD 2>/dev/null`
- If the command fails (e.g., no commits yet) or the diff is empty, also try: `git diff --cached`
- If still empty, tell the user: "No changes found. Provide a file path or make some changes first."
- Store the diff output as REVIEW_INPUT

## Step 2: Locate system prompt

Determine the absolute path to the system prompt file:
- The file is at `system-prompts/review.md` relative to this plugin's root directory
- The plugin root is the parent of the `commands/` directory containing this file
- Store this absolute path as SYSTEM_PROMPT_PATH

## Step 3: Call Gemini CLI

Run the following bash command, passing REVIEW_INPUT via stdin to avoid shell escaping issues:

```bash
echo "$REVIEW_INPUT" | GEMINI_SYSTEM_MD="$SYSTEM_PROMPT_PATH" gemini -o text -m pro
```

Note: We pipe input via stdin instead of -p flag to handle large diffs and special characters safely.

## Step 4: Present results

Show the Gemini response directly to the user. Do not modify, summarize, or reformat it.

## Error handling

- If `gemini` command is not found: suggest running `/gemini:setup` first
- If the command fails with an auth error: suggest checking GEMINI_API_KEY or running `gemini` interactively to re-authenticate
- If the command times out or returns an error: show the error message and suggest retrying
