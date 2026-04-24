---
description: Ask Gemini a question, optionally with file context
allowed-tools: Bash, Read, Glob
argument-hint: <question> [file-path] [--model <model>]
---

Ask Gemini CLI a question. Optionally provide a file for context.

## Step 1: Parse --model parameter

Check if $ARGUMENTS contains `--model <value>`:
- If yes: extract the value as MODEL, remove `--model <value>` from $ARGUMENTS
- If no: set MODEL = flash

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

## Step 3: Locate system prompt and policy

Determine the absolute path to the plugin root (the parent of the `commands/` directory containing this file).

- `system-prompts/ask.md` → SYSTEM_PROMPT_PATH
- `policies/readonly.toml` → POLICY_PATH

## Step 4: Call Gemini CLI

Run the following bash command, passing ASK_INPUT via stdin. The call enforces the read-only admin policy. If the model hits a quota limit it automatically falls back to flash (carrying the same policy).

```bash
output=$(printf "%s" "$ASK_INPUT" | GEMINI_SYSTEM_MD="$SYSTEM_PROMPT_PATH" gemini -m $MODEL --admin-policy "$POLICY_PATH" 2>&1)
exit_code=$?
if [ $exit_code -ne 0 ] && echo "$output" | grep -qi "429\|quota\|RESOURCE_EXHAUSTED\|rate limit\|overloaded"; then
  echo "[Fallback] $MODEL unavailable (quota/rate limit), retrying with flash..." >&2
  output=$(printf "%s" "$ASK_INPUT" | GEMINI_SYSTEM_MD="$SYSTEM_PROMPT_PATH" gemini -m flash --admin-policy "$POLICY_PATH" 2>&1)
fi
echo "$output"
```

Note: We pipe input via stdin instead of -p flag to handle large inputs and special characters safely.

## Step 5: Present results

Show the Gemini response directly to the user. Do not modify, summarize, or reformat it.

## Error handling

- If `gemini` command is not found: suggest running `/gemini:setup` first
- If the command fails with an auth error: suggest running `gemini` interactively to re-authenticate via Google OAuth
- If the command times out or returns an error: show the error message and suggest retrying
