---
description: Ask Gemini (via agy) a question, optionally with file context
allowed-tools: Bash, Read, Glob
argument-hint: <question> [file-path] [--model <model>]
---

Ask Gemini a question via the Antigravity CLI (`agy`). Optionally provide a file for context.

## Step 1: Parse --model parameter

Check if $ARGUMENTS contains `--model <value>`:
- If yes: extract the value as MODEL, remove `--model <value>` from $ARGUMENTS
- If no: set MODEL = flash

Map the alias to an agy model slug:
- `flash` → `gemini-3.6-flash-high` (the default)
- `pro` → `gemini-3.1-pro-high` — an older generation than 3.6 flash; available for explicit opt-in, not recommended
- Anything else is passed through unchanged (run `agy models` to list available slugs).

## Step 2: Determine input

Split the remaining $ARGUMENTS into QUESTION and optional FILE_PATH:
- Check if the last token in $ARGUMENTS is an existing file path (use `test -f <last_token>`)
- If yes: Read the file contents as CONTEXT, the rest of $ARGUMENTS is the QUESTION
- If no: the entire $ARGUMENTS is the QUESTION, no CONTEXT

If QUESTION is empty, tell the user: "Please provide a question. Example: /gemini:ask What does this regex do? src/utils.js"

Build ASK_INPUT:
- If CONTEXT exists:
  ```
  Question: {QUESTION}
  ---
  {CONTEXT}
  ```
- If no CONTEXT:
  ```
  Question: {QUESTION}
  ```

## Step 3: Call agy

The system prompt lives in the `gemini-ask` agent, installed by `/gemini:setup`. The agent's `tools` whitelist keeps the run read-only — there is no separate policy file.

Run the following bash command, passing ASK_INPUT via stdin.

```bash
output=$(printf "%s" "$ASK_INPUT" | agy --agent gemini-ask --model $MODEL --print-timeout 5m 2>&1)
echo "$output"
```

Note: We pipe input via stdin instead of -p to handle large inputs and special characters safely.

## Step 4: Present results

Show the Gemini response directly to the user. Do not modify, summarize, or reformat it.

## Error handling

- If `agy` command is not found: suggest running `/gemini:setup` first
- If the command fails with an auth error: suggest running `agy` interactively to re-authenticate via Google OAuth
- If the output reports a quota or rate-limit error (429, RESOURCE_EXHAUSTED, overloaded): show it as-is and suggest retrying later, or picking a different model with `--model` (`agy models` lists the slugs). There is no automatic fallback
- If the command times out or returns an error: show the error message and suggest retrying
