---
description: Have Gemini (via agy) implement a task by editing files directly
allowed-tools: Bash, Read, Glob
argument-hint: <task description> [--brief <path>] [--context <path>] [--model <model>]
---

Implement a task using Gemini via the Antigravity CLI (`agy`). Unlike `/gemini:review`, this command **writes to your files**.

Use it for work that is mechanical, well-specified, and cheap to verify — batch renames, boilerplate, test scaffolding, applying one pattern across several files. Work that needs whole-repo judgment is better done in this session, where the context already exists.

## Step 1: Establish the workspace

The agent writes files, so a non-recoverable run is not acceptable. Get the repository root:

```bash
ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
```

If this fails, **stop**. Tell the user `/gemini:implement` only runs inside a git repository, because `git diff` is the only thing that makes the agent's writes reviewable and reversible. Do not offer to run it anyway.

Then capture what the tree looks like before the run — this is what makes an unannounced write visible in Step 5:

```bash
git status --porcelain
```

Keep the output as BEFORE. If it is non-empty, tell the user which files are already dirty and ask whether to continue. Uncommitted work is not a blocker, but after the run there is no way to tell their edits from Gemini's, and that is worth one question. If they decline, stop.

## Step 2: Parse arguments

`--model <value>`: extract as MODEL and remove the pair from $ARGUMENTS. If absent, MODEL = `gemini-3.7-flash-high`.

Aliases: `flash` → `gemini-3.7-flash-high`, `pro` → `gemini-3.1-pro-high`. Anything else passes through unchanged (`agy models` lists the slugs).

The default is 3.7 rather than the 3.6 that `/gemini:review` uses, and the split is deliberate: measured on this repo's eval suite the two are indistinguishable at reviewing, so review stays where it is, while 3.7's gains are in writing code, which is this command's entire job.

`--brief <path>`: Read the file and use its contents as BRIEF. Remove the pair from $ARGUMENTS. If the path does not exist, say which one and stop.

`--context <path>` (repeatable): for each, Read the file (expand with Glob first if it contains `*` or `?`). Concatenate the contents, each preceded by a line naming the file, as CONTEXT. Remove every `--context <value>` pair from $ARGUMENTS. A missing path stops the command — a silently dropped context file produces a plausible implementation built on nothing.

Whatever remains in $ARGUMENTS after removals is the inline task description. If `--brief` was given, append the remaining text to BRIEF as an additional instruction; otherwise it *is* BRIEF.

If BRIEF ends up empty, stop and ask what to implement.

## Step 3: Assemble the payload

```
=== WORKSPACE ROOT ===
{ROOT}
=== TASK BRIEF (what to implement) ===
{BRIEF}
=== CONTEXT (files and conventions to follow) ===
{CONTEXT}
```

Omit the CONTEXT section when CONTEXT is empty — do not emit it empty. The first two sections are always present.

Reproduce the `===` marker lines verbatim, parentheticals included; the agent matches on them literally. Changing one means changing it here and in `plugins/gemini/agy/agents/gemini-implement/agent.md` in the same commit.

## Step 4: Call agy

```bash
output=$(printf "%s" "$PAYLOAD" | agy --agent gemini-implement --model $MODEL --add-dir "$ROOT" --print-timeout 10m 2>&1)
echo "$output"
```

The timeout is longer than the review command's: implementing means reading several files and writing several more.

`--add-dir "$ROOT"` sets the workspace. It is **not** a sandbox — it does not stop the agent writing outside that path, which is why Step 5 exists and why Step 1 refuses to run outside a git repository.

Do not add `--dangerously-skip-permissions`. The write tools in the agent's whitelist work in headless mode without it; the flag would only enable the shell access this agent deliberately does not have.

## Step 5: Audit what actually changed

The agent's report is a claim. Verify it:

```bash
git status --porcelain
git diff --stat
```

Compare against BEFORE and against the `## Files Changed` list in the agent's report. Then tell the user, plainly:

- **Files it changed and declared** — the expected case.
- **Files it changed but did not declare** — say so explicitly. This is the failure mode that matters most, and the user should read that diff before anything else.
- **Files it declared but did not change** — the report is describing work it did not do. Treat the whole report as unreliable and say so.

State the limit of this check: it only sees inside the repository. A write outside `$ROOT` does not appear in `git status`, and nothing in agy prevents one.

## Step 6: Hand back

Show the agent's report as-is, then the `git diff --stat` summary.

The agent cannot run anything, so its tests have never been executed. Offer to run them, and say clearly that no test has passed yet — only that tests now exist.

If Status is `BLOCKED` or `NEEDS_CONTEXT`, the workspace may still have been partially written. Show what the audit found before discussing what to do next.

Do not commit. Leaving the change uncommitted is what keeps `git diff` and `git checkout` available as the review and undo path.

## Error handling

- `agy` not found: suggest `/gemini:setup`
- Output has no `## Status:` line: `--agent` silently ignored an unknown name — the agent is not installed. Send the user to `/gemini:setup`. Run the Step 5 audit anyway; the run may have written files through the default agent
- `no output produced` naming a denied permission: the agent reached for a tool outside its whitelist. Report it verbatim; do not re-run with `--dangerously-skip-permissions`
- Auth error: suggest running `agy` interactively to re-authenticate via Google OAuth
- Quota or rate limit (429, RESOURCE_EXHAUSTED, overloaded): show as-is, suggest retrying or `--model`. There is no automatic fallback
- Timeout: the workspace may hold a partial write. Run the Step 5 audit before anything else
