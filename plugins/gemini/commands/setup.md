---
description: Check agy (Antigravity CLI) installation, install the plugin's agents, and verify they work
allowed-tools: Bash
argument-hint: [--model <model>]
---

## Step 0: Parse --model parameter

Check if $ARGUMENTS contains `--model <value>`:
- If yes: extract the value as MODEL, remove `--model <value>` from $ARGUMENTS
- If no: set MODEL = `gemini-3.6-flash-high`

Run the following checks in order and report the results.

## 1. Check if agy is installed

Run: `which agy || where agy 2>/dev/null`

- If found: report the path
- If not found: tell the user to install the Antigravity CLI from https://antigravity.google and stop here

## 2. Check agy version

Run: `agy --version`

Markdown custom agents require **1.1.6 or newer** — that is how this plugin injects its system prompts. If the version is older, tell the user to run `agy update` and stop here.

## 3. Check authentication

Run: `agy -p "ping" --model $MODEL --print-timeout 2m 2>&1 | head -5`

- If it returns a normal reply: authentication is working
- If it reports an authentication or eligibility error: tell the user to run `agy` interactively once to sign in via Google OAuth

## 4. Install the agents

Determine the absolute path to the plugin root (the parent of the `commands/` directory containing this file). The agy plugin lives in `agy/` under that root.

Run: `agy plugin install "<plugin-root>/agy"`

Expect `agents : 4 processed` in the output. This installs four read-only agents into `~/.gemini/config/plugins/gemini-agents/`:

- `gemini-review` — used by `/gemini:review`
- `gemini-adversarial-review` — used by `/gemini:adversarial-review`
- `gemini-security-review` — used by `/gemini:security-review`
- `gemini-ask` — used by `/gemini:ask`

Re-running this command upgrades an existing install in place.

## 5. Verify the agents actually took effect

This step is not optional. `agy --agent <name>` **silently ignores unknown agent names** — a failed install produces plausible-looking output with none of the plugin's system prompt applied, and the user would never notice.

Run:

```bash
printf '%s' 'diff --git a/README.md b/README.md
--- a/README.md
+++ b/README.md
@@ -1 +1 @@
-# Old Title
+# New Title' | agy --agent gemini-review --model $MODEL --print-timeout 3m 2>&1 | head -20
```

- If the output contains `## Verdict:` — the agent is live, the system prompt is being applied
- If the output is a free-form review with no `## Verdict:` line — the agent is NOT installed. Re-run step 4 and check for errors.

## 6. Check the read-only restriction

The agents carry a `tools` whitelist (`view_file`, `find_by_name`) instead of a policy file. Confirm it holds:

```bash
agy -p "Create a file named setup-check.txt containing HELLO, then run the shell command 'echo RAN'. If you lack the tools for either, say exactly: READ_ONLY_OK" --agent gemini-ask --model $MODEL --print-timeout 3m 2>&1 | tail -3
```

- Expect `READ_ONLY_OK`. Anything that reports creating a file or running a command means the whitelist is not in effect — report this as a problem.

## Summary

After all checks, provide a one-line summary:
- All checks passed: "agy is ready with model $MODEL and 4 agents installed. Try /gemini:review"
- Something missing: list what needs to be fixed
