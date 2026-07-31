# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Claude Code plugin marketplace that reaches Gemini through the Antigravity CLI (`agy`). Two plugins share the same Google OAuth credentials:

- **`gemini`** — slash commands for code review, ask, adversarial review, security review. Pure Markdown commands + agent definitions, no JS runtime.
- **`gemini-images`** — PreToolUse hook that replaces image `Read` calls with Gemini-generated text descriptions, protecting Anthropic's prompt cache.

Everything user-facing stays in Claude Code. `agy` is only the backend that runs Gemini — the plugins are not installed into agy as skills.

## Architecture

Marketplace registry at `/.claude-plugin/marketplace.json` points at two plugin sources under `/plugins/`:

```
.claude-plugin/marketplace.json          # marketplace registry (2 plugins)
plugins/gemini/
  .claude-plugin/plugin.json
  commands/                              # /gemini:setup, review, ask, adversarial-review, security-review
  agy/plugin.json                        # agy-side plugin — agents only, no commands
  agy/agents/<name>/agent.md             # system prompts, installed via `agy plugin install`
plugins/gemini-images/
  .claude-plugin/plugin.json             # registers PreToolUse hook on Read
  hooks/intercept-image-read.sh          # entry point
  hooks/image-describe.mjs               # resize + agy describe + parallel tesseract OCR
  agy/agents/gemini-image-describe/agent.md
  scripts/doctor.sh                      # dependency check
```

The agent bodies are the primary quality lever — they define reviewer role, output structure, and severity criteria. Eval: custom prompt 10/10 vs bare model 4/10.

## How System Prompts Reach agy

`agy` has no per-call system prompt injection (no `GEMINI_SYSTEM_MD` equivalent). Prompts must be registered up front as Markdown custom agents (requires agy ≥ 1.1.6):

```
---
name: gemini-review
mainAgent: true
tools: [view_file, find_by_name]    # replaces the old --admin-policy readonly.toml
---

# Agent System Instructions        ← this exact H1 is the delimiter; anything else is silently ignored

<prompt body>
```

`/gemini:setup` installs them with `agy plugin install <plugin-root>/agy`, landing in `~/.gemini/config/plugins/gemini-agents/`. The agy-side plugin deliberately ships agents only — including `commands/` would make agy convert them into skills carrying unusable Claude Code syntax (`$ARGUMENTS`, `allowed-tools`).

**`--agent` silently ignores unknown names.** A failed install produces plausible output with no system prompt applied and no error, so both `/gemini:setup` and `doctor.sh` verify the install explicitly.

## How `gemini` Commands Work

Commands are Markdown files with YAML frontmatter (`description`, `allowed-tools`, `argument-hint`). Claude Code reads and executes the instructions within. The review / ask / etc. commands pipe input to agy via stdin:

```bash
echo "$INPUT" | agy --agent gemini-review --model "$MODEL" --print-timeout 5m 2>&1
```

All commands default to `gemini-3.6-flash-high` with effort pinned to `high`. There is no automatic fallback: a quota / rate-limit error surfaces to the user, who can retry or pick another model with `--model`.

The old pro-by-default routing is gone: agy's Pro is `gemini-3.1-pro`, two generations behind 3.6 flash, and flash-high already scores 10/10 on the eval suite. `--model pro` still resolves to `gemini-3.1-pro-high` for explicit opt-in, and any other value passes through to agy unchanged (`agy models` lists the slugs).

## How `gemini-images` Works

`PreToolUse` hook fires on every `Read`. If the path matches an image extension, the hook resizes (magick → sips → skip), spawns agy to describe it, runs tesseract OCR in parallel, writes the combined output to a temp `desc.txt`, and rewrites `updatedInput.file_path` so Claude reads text instead of image bytes. Keeps the prompt cache warm.

## Testing

### Manual

1. Install plugin from this repo:
   - `claude plugin marketplace add .` — register local dir as marketplace
   - `claude plugin install gemini --scope project` (and/or `gemini-images`)
   - Restart Claude Code session (plugins require restart)
   - Alternative for one-off testing: `claude --plugin-dir .`
2. `/gemini:setup` — verify agy, version (≥ 1.1.6), OAuth, install the agents, and confirm they took effect
3. `/gemini:review` — review current git diff
4. `/gemini:review path/to/file` — review specific file
5. `bash plugins/gemini-images/scripts/doctor.sh` — verify gemini-images dependencies

### Eval suite

`eval/` ships promptfoo configs comparing the custom agent against the bare model. Run via `eval/run-agy*.sh` scripts. See `CONTRIBUTING.md` for the workflow.

Judge note: the rubric provider must be a current model. `claude-sonnet-4-20250514` is retired (404) and promptfoo ≤ 0.121.5 sends a deprecated `temperature` to newer models (400) — either failure grades every case FAIL regardless of output quality. Use promptfoo `@latest`.

## Design Constraints

- Zero-code core: no JS runtime for `gemini` plugin (only Markdown + bash). `gemini-images` uses a Node.js hook but stays self-contained.
- Review output must be returned verbatim from Gemini — do not reformat or summarize.
- Read-only is enforced by the `tools` whitelist in each agent's frontmatter (`view_file`, `find_by_name`), replacing the old `--admin-policy readonly.toml`. This is strictly stronger: the tools are absent from the agent rather than denied, so even `--dangerously-skip-permissions` cannot write files or run shell commands. Verified by `/gemini:setup` step 6.
- Never add `--dangerously-skip-permissions` to a plugin invocation. The whitelist holds without it, and the flag would only matter for tools the agents should not have.
- Specs live in `docs/specs/`, design docs in `docs/plans/`.
