---
description: Get a code review from Gemini (via agy) as a second opinion
allowed-tools: Bash, Read, Glob
argument-hint: [file-path] [--spec <path>] [--model <model>]
---

Perform a code review using Gemini via the Antigravity CLI (`agy`). This gives you a second opinion from a different AI model.

## Step 1: Parse --model parameter

Check if $ARGUMENTS contains `--model <value>`:
- If yes: extract the value as MODEL, remove `--model <value>` from $ARGUMENTS
- If no: set MODEL = flash

Map the alias to an agy model slug:
- `flash` → `gemini-3.6-flash-high` (the default)
- `pro` → `gemini-3.1-pro-high` — an older generation than 3.6 flash; available for explicit opt-in, not recommended
- Anything else is passed through unchanged (run `agy models` to list available slugs).

## Step 1b: Parse --spec parameter

Check if $ARGUMENTS contains one or more `--spec <path>` pairs:
- If none: set SPEC_INPUT = empty, skip the rest of this step
- For each `--spec <path>` found:
  - If the path contains glob characters (* or ?), use the Glob tool to expand it, then Read each matched file
  - Otherwise, Read the single file directly
  - If a path does not exist, tell the user which one and stop — a silently missing requirements file would produce a spec-compliance verdict based on nothing
  - If `--spec` is not followed by a value, or is followed by something starting with `--`, tell the user it needs a path and stop — do not consume the next flag as a filename
- Remove every `--spec <value>` pair from $ARGUMENTS
- Concatenate all spec file contents (separated by a blank line) as SPEC_INPUT

`--spec` and `--model` may appear in any order, before or after the file path.

## Step 2: Determine input

If $ARGUMENTS (after --model and --spec removal) is provided:
- If it contains glob characters (* or ?), use the Glob tool to expand it, then Read each matched file
- Otherwise, Read the single file directly
- Concatenate all file contents as REVIEW_INPUT

If $ARGUMENTS is empty:
- Run: `git diff HEAD 2>/dev/null`
- If the command fails (e.g., no commits yet) or the diff is empty, also try: `git diff --cached`
- If still empty, tell the user: "No changes found. Provide a file path or make some changes first."
- Store the diff output as REVIEW_INPUT

## Step 3: Call agy

The system prompt lives in the `gemini-review` agent, installed by `/gemini:setup`. The agent's `tools` whitelist keeps the run read-only — there is no separate policy file.

Assemble PAYLOAD (the variable the bash command below reads) from up to three sections.

First get the repository root:

```bash
git rev-parse --show-toplevel 2>/dev/null
```

The agent's `view_file` only accepts absolute paths — agy does not run in this shell's working directory, so a repo-relative path resolves against the wrong root. Handing it the root is what lets it check a call site when it spots a nameable risk. If the command fails (not a git repo), omit the section entirely; the agent then reports such risks for the user to check instead of reading files.

PAYLOAD is the concatenation of whichever of these apply, in this order:

```
=== REPOSITORY ROOT ===
{absolute path from git rev-parse --show-toplevel}
=== REQUIREMENTS (what this change is supposed to do) ===
{SPEC_INPUT}
=== CHANGE UNDER REVIEW ===
{REVIEW_INPUT}
```

- Omit the REPOSITORY ROOT section when not in a git repo.
- Omit the REQUIREMENTS section when SPEC_INPUT is empty. Do **not** emit it empty — the agent decides whether to return a spec-compliance verdict purely by whether that section is present.
- When both are omitted, PAYLOAD is REVIEW_INPUT unchanged.
- Whenever any section is present, the `=== CHANGE UNDER REVIEW ===` line must precede REVIEW_INPUT.

All `===` marker lines must be reproduced verbatim, including the parenthetical in the REQUIREMENTS marker; the agent matches on them.

Run the following bash command, passing PAYLOAD via stdin to avoid shell escaping issues:

```bash
output=$(printf "%s" "$PAYLOAD" | agy --agent gemini-review --model $MODEL --print-timeout 5m 2>&1)
echo "$output"
```

Note: We pipe input via stdin instead of -p to handle large diffs and special characters safely.

If the output does not follow the review format (`## Review Summary` / `## Findings` / `## Verdict`), the agent is not installed — `--agent` silently ignores unknown names. Tell the user to run `/gemini:setup`.

## Step 4: Present results

Show the Gemini response directly to the user. Do not modify, summarize, or reformat it.

## Error handling

- If `agy` command is not found: suggest running `/gemini:setup` first
- If the command fails with an auth error: suggest running `agy` interactively to re-authenticate via Google OAuth
- If the output reports a quota or rate-limit error (429, RESOURCE_EXHAUSTED, overloaded): show it as-is and suggest retrying later, or picking a different model with `--model` (`agy models` lists the slugs). There is no automatic fallback
- If the command times out or returns an error: show the error message and suggest retrying
