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

First get the repository root and keep it as ROOT — both the payload and the `agy` invocation below need it:

```bash
ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
```

The agent's `view_file` only accepts absolute paths — agy does not run in this shell's working directory, so a repo-relative path resolves against the wrong root. Handing it the root is what lets it check a call site when it spots a nameable risk. If the command fails (not a git repo), ROOT is empty: omit the section entirely, and the agent then reports such risks for the user to check instead of reading files.

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
output=$(printf "%s" "$PAYLOAD" | agy --agent gemini-review --model $MODEL ${ROOT:+--add-dir "$ROOT"} --print-timeout 5m 2>&1)
echo "$output"
```

`--add-dir "$ROOT"` is what makes the agent's `view_file` usable. Without it a headless run cannot get the read permission approved and agy discards the whole review — see the error handling below. The `${ROOT:+...}` expansion drops the flag when ROOT is empty, which is the same case that omits the `=== REPOSITORY ROOT ===` section: there is nothing to grant, and the agent is already told it cannot read. (agy does tolerate `--add-dir ""`, so this is about keeping the two halves of the decision in one place rather than avoiding a crash.)

The flag is not a formality. On a diff that renames an exported symbol, the same agent returns a LOW "callers may need updating, not verifiable from this diff" without it, and a HIGH naming the two files that actually import the old name with it.

Note: We pipe input via stdin instead of -p to handle large diffs and special characters safely.

A run can come back without a review for two different reasons. They need different responses, and the wrong diagnosis sends the user somewhere useless.

**A denied file read.** If the output says `no output produced` and names a permission (`read_file`), the agent tried to open something `--add-dir` did not cover: a headless run cannot show a permission prompt, and the denial throws away the entire review rather than just the tool call. Nothing is wrong with the install, so do not send the user to `/gemini:setup`.

This should be rare once `--add-dir "$ROOT"` is passed. It still happens when the diff points outside the repository — a sibling checkout, a path reached through `..`, a file the agent decided to look up by absolute path.

Re-run once with the `=== REPOSITORY ROOT ===` section removed from PAYLOAD, leaving REQUIREMENTS and CHANGE UNDER REVIEW untouched, and drop `--add-dir` with it. Without that section the agent knows it cannot open anything and reports such risks for the user to check instead, which completes normally. Say that the review ran without file-lookup capability, so any finding about code outside the diff is something to confirm rather than something Gemini verified — that downgrade is visible in the output, where verified call sites become "not verifiable from this diff".

Whether the agent reaches outside at all depends on what it finds in the diff, so the same review can succeed one run and fail the next. Do not report this as flaky output.

**An agent that never loaded.** If the output is a free-form review with no `## Verdict:` line, `--agent` silently ignored an unknown name. Tell the user to run `/gemini:setup`.

## Step 4: Present results

Show the Gemini response directly to the user. Do not modify, summarize, or reformat it.

## Error handling

- If `agy` command is not found: suggest running `/gemini:setup` first
- If the output reports `no output produced` and a denied permission: follow the re-run without `=== REPOSITORY ROOT ===` described in Step 3. Do not send the user to `/gemini:setup` — the install is fine
- If the command fails with an auth error: suggest running `agy` interactively to re-authenticate via Google OAuth
- If the output reports a quota or rate-limit error (429, RESOURCE_EXHAUSTED, overloaded): show it as-is and suggest retrying later, or picking a different model with `--model` (`agy models` lists the slugs). There is no automatic fallback
- If the command times out or returns an error: show the error message and suggest retrying
