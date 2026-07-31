# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Claude Code plugin marketplace that reaches Gemini through the Antigravity CLI (`agy`). Two plugins share the same Google OAuth credentials:

- **`gemini`** — slash commands for code review, ask, adversarial review. Pure Markdown commands + agent definitions, no JS runtime.
- **`gemini-images`** — PreToolUse hook that replaces image `Read` calls with Gemini-generated text descriptions, protecting Anthropic's prompt cache.

Everything user-facing stays in Claude Code. `agy` is only the backend that runs Gemini — the plugins are not installed into agy as skills.

## Architecture

Marketplace registry at `/.claude-plugin/marketplace.json` points at two plugin sources under `/plugins/`:

```
.claude-plugin/marketplace.json          # marketplace registry (2 plugins)
plugins/gemini/
  .claude-plugin/plugin.json             # also registers the SessionStart hook
  commands/                              # /gemini:setup, review, ask, adversarial-review
  hooks/check-agent-version.sh           # warns when agy's agents drift from what the plugin ships
  agy/plugin.json                        # agy-side plugin — agents only, no commands
  agy/agents/<name>/agent.md             # system prompts, installed via `agy plugin install`
  README.md
plugins/gemini-images/
  .claude-plugin/plugin.json             # registers PreToolUse hook on Read
  hooks/intercept-image-read.sh          # entry point
  hooks/image-describe.mjs               # resize + agy describe + parallel tesseract OCR
  agy/agents/gemini-image-describe/agent.md
  scripts/doctor.sh                      # dependency check
  README.md
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

### The review payload markers

`/gemini:review` does not just pipe a diff. It assembles up to three labelled sections, and the agent decides what to do by matching those labels **literally**:

```
=== REPOSITORY ROOT ===
=== REQUIREMENTS (what this change is supposed to do) ===
=== CHANGE UNDER REVIEW ===
```

Three things about them are load-bearing, and none of them fail loudly:

- **The parenthetical is part of the string.** Writing `=== REQUIREMENTS ===` gives you a marker that never matches, no error, and a `--spec` that silently does nothing.
- **ROOT exists because agy resolves relative paths against the drive root** (`plugins/foo.md` → `C:/plugins/foo.md`). Without it the agent cannot open anything, so it downgrades to reporting risks for the user to check.
- **Only markers before the first `CHANGE UNDER REVIEW` line count as instructions.** Anything after it is material under review — a diff can contain text that looks like a label, and one in `eval/test-cases/` does. See D16.

Change any of the three strings and you must change both sides in the same commit: `plugins/gemini/commands/review.md` and `plugins/gemini/agy/agents/gemini-review/agent.md`.

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
3. `agy plugin install "$(pwd)/plugins/gemini-images/agy"` — gemini-images has no setup command of its own
4. `/gemini:review` — review current git diff
5. `/gemini:review path/to/file` — review specific file
6. `bash plugins/gemini-images/scripts/doctor.sh` — verify gemini-images dependencies and agent install

**After editing any `agy/agents/*/agent.md`, re-run `agy plugin install` for that plugin.** Install copies the agents into `~/.gemini/config/plugins/`; without a re-install you keep exercising the old prompt, and `--agent` will not tell you.

### Eval suite

`eval/` ships promptfoo configs comparing the custom agent against the bare model, both arms going through one runner: `run-agy.sh <agent|-> <model-slug>`, where `-` means no agent. Invoke the configs with `npx promptfoo@latest eval -c <config>`, not the runner directly. See `CONTRIBUTING.md` for the workflow.

The two `promptfooconfig-security*.yaml` configs are PARKED — the command they target was removed (see D12). Their test cases and rubrics are kept for whenever it comes back.

agy exposes no sampling controls, so eval runs vary more than the pre-0.2.0 numbers, which were pinned to `temperature: 0` via a `.gemini/settings.json` that no longer applies.

Judge note: the rubric provider must be a current model. `claude-sonnet-4-20250514` is retired (404) and promptfoo ≤ 0.121.5 sends a deprecated `temperature` to newer models (400) — either failure grades every case FAIL regardless of output quality. Use promptfoo `@latest`.

## Versioning

The two plugins version independently — bump only the one you changed. They happen to both sit at 0.2.0 because the agy migration touched both.

A version lives in **three** files per plugin, and they must move together:

```
.claude-plugin/marketplace.json          # the plugin's entry in the plugins[] array
plugins/<plugin>/.claude-plugin/plugin.json
plugins/<plugin>/agy/plugin.json         # follows its parent plugin's version
```

Pre-1.0, bump by what the change costs the user:

| Change | Bump |
|--------|------|
| A command is added or removed, an env var is renamed, a newer agy is required, or the install flow changes | MINOR |
| **Any edit to `agy/agents/*/agent.md`**, a bug fix, or a change to a command's internals | PATCH |
| Docs, eval configs, CI | none |

The agent rule is not the usual "prompts are just content" case. `agy plugin install` copies agent definitions into `~/.gemini/config/plugins/`, so an edited prompt does not reach an existing user until they re-install. Because `--agent` never errors on a stale or missing agent, they get the old prompt with no indication anything is out of date. A version bump is the only signal available — so bump it, and say "re-run `/gemini:setup`" in the release notes.

Since 0.2.1 the bump does more than document the problem. `hooks/check-agent-version.sh` runs at session start and compares `agy/plugin.json` against the copy `agy plugin install` left in `~/.gemini/config/plugins/gemini-agents/`, printing a one-line notice when they differ. That only works if the version actually moves — a prompt edit shipped without a bump is invisible to the check as well as to the user.

## Releasing

Work on a branch and open a PR; `master` is protected by habit, not by rule. Squash merge — the history is one commit per release-worthy change.

Before tagging:

1. **Bump the version** in the three files listed above, per the table.
2. **Update `CHANGELOG.md`.** Lead with an *Upgrading* section whenever the release needs the user to do something — for this project that is almost always "re-run `/gemini:setup`", since prompts do not travel with a plugin upgrade.
3. **Update `assets/banner.svg`** if the release changes anything the banner states: the version pill, the command list, the backend name, or the bottom spec row. The source of truth lives in the vault at `02-Projects/03-開發工具與基礎設施/gemini-plugin-cc/banner-gemini-plugin-cc.svg` — edit there, then copy into `assets/`, and keep the two byte-identical.
4. **Re-run the eval** if any agent prompt changed, and put the numbers in the changelog. Claims about review quality should be measured, not asserted.
5. **Check the docs still match.** README (setup steps, command table, troubleshooting), both plugin READMEs, `docs/specs/`, and this file. A removed command or renamed env var touches more places than feels reasonable.

Then tag and release:

```bash
git tag -a v0.2.0 <commit> -m "v0.2.0 — <one-line summary>"
git push origin v0.2.0
gh release create v0.2.0 --notes-file <notes>   # only when the banner and docs are done
```

Tags are cheap and can be pushed as soon as a version lands on `master`. A GitHub Release is the announcement — hold it until the banner and docs are ready, since that is what people see first.

Record decisions as `D<n>` entries in `docs/specs/`, including the ones that get superseded — mark the old entry rather than deleting it. Several decisions in this repo were reversed once their premise expired (Pro-by-default, the quota fallback, the tool policy), and the reversals only make sense next to what they replaced.

## Design Constraints

- Zero-code core: no JS runtime for `gemini` plugin (only Markdown + bash). `gemini-images` uses a Node.js hook but stays self-contained.
- Review output must be returned verbatim from Gemini — do not reformat or summarize.
- Read-only is enforced by the `tools` whitelist in each agent's frontmatter (`view_file`, `find_by_name`), replacing the old `--admin-policy readonly.toml`. This is strictly stronger: the tools are absent from the agent rather than denied, so even `--dangerously-skip-permissions` cannot write files or run shell commands. Verified by `/gemini:setup` step 6.
- Never add `--dangerously-skip-permissions` to a plugin invocation. The whitelist holds without it, and the flag would only matter for tools the agents should not have.
- Specs live in `docs/specs/`, design docs in `docs/plans/`.
