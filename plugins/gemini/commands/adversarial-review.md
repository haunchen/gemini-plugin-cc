---
description: Get a devil's advocate review that challenges your design decisions
allowed-tools: Bash, Read, Glob
argument-hint: [file-path] [--model <model>]
---

Get a devil's advocate review using Gemini via the Antigravity CLI (`agy`). Instead of finding bugs, this challenges your design decisions and proposes alternatives.

## Step 1: Parse --model parameter

Check if $ARGUMENTS contains `--model <value>`:
- If yes: extract the value as MODEL, remove `--model <value>` from $ARGUMENTS
- If no: set MODEL = pro

Map the alias to an agy model slug:
- `pro` → `gemini-3.1-pro-high`
- `flash` → `gemini-3.6-flash-high`
- Anything else is passed through unchanged (run `agy models` to list available slugs).

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

## Step 3: Call agy

The system prompt lives in the `gemini-adversarial-review` agent, installed by `/gemini:setup`. The agent's `tools` whitelist keeps the run read-only — there is no separate policy file.

Run the following bash command, passing REVIEW_INPUT via stdin:

```bash
output=$(printf "%s" "$REVIEW_INPUT" | agy --agent gemini-adversarial-review --model $MODEL --print-timeout 5m 2>&1)
exit_code=$?
if [ $exit_code -ne 0 ] && echo "$output" | grep -qi "429\|quota\|RESOURCE_EXHAUSTED\|rate limit\|overloaded"; then
  echo "[Fallback] $MODEL unavailable (quota/rate limit), retrying with flash..." >&2
  output=$(printf "%s" "$REVIEW_INPUT" | agy --agent gemini-adversarial-review --model gemini-3.6-flash-high --print-timeout 5m 2>&1)
fi
echo "$output"
```

Note: We pipe input via stdin instead of -p to handle large diffs and special characters safely. If the preferred model hits quota limits, it automatically falls back to flash.

If the output does not follow the agent's expected structure, the agent is not installed — `--agent` silently ignores unknown names. Tell the user to run `/gemini:setup`.

## Step 4: Present results

Show the Gemini response directly to the user. Do not modify, summarize, or reformat it.

## Error handling

- If `agy` command is not found: suggest running `/gemini:setup` first
- If the command fails with an auth error: suggest running `agy` interactively to re-authenticate via Google OAuth
- If the command times out or returns an error: show the error message and suggest retrying
