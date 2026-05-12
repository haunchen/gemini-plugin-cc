# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Claude Code plugin marketplace that integrates Gemini CLI. Two plugins share the same Gemini OAuth credentials:

- **`gemini`** — slash commands for code review, ask, adversarial review, security review. Pure Markdown commands + system prompts, no JS runtime.
- **`gemini-images`** — PreToolUse hook that replaces image `Read` calls with Gemini-generated text descriptions, protecting Anthropic's prompt cache.

## Architecture

Marketplace registry at `/.claude-plugin/marketplace.json` points at two plugin sources under `/plugins/`:

```
.claude-plugin/marketplace.json          # marketplace registry (2 plugins)
plugins/gemini/
  .claude-plugin/plugin.json
  commands/                              # /gemini:setup, review, ask, adversarial-review, security-review
  system-prompts/                        # injected via GEMINI_SYSTEM_MD when invoking Gemini CLI
  policies/readonly.toml                 # shared read-only admin policy
plugins/gemini-images/
  .claude-plugin/plugin.json             # registers PreToolUse hook on Read
  hooks/intercept-image-read.sh          # entry point
  hooks/image-describe.mjs               # resize + Gemini describe + parallel tesseract OCR
  system-prompts/image-describe.md
  scripts/doctor.sh                      # dependency check
```

System prompts in `plugins/gemini/system-prompts/*.md` are the primary quality lever — they define reviewer role, output structure, and severity criteria.

## How `gemini` Commands Work

Commands are Markdown files with YAML frontmatter (`description`, `allowed-tools`, `argument-hint`). Claude Code reads and executes the instructions within. The review / ask / etc. commands pipe input to Gemini CLI via stdin:

```bash
echo "$INPUT" | GEMINI_SYSTEM_MD="$PATH" gemini -m "$MODEL" --admin-policy "$POLICY" 2>&1
```

Default model is `pro` for review / adversarial-review / security-review and `flash` for ask, all with automatic fallback to `flash` on quota / rate-limit errors. Users can override with `--model <m>`.

## How `gemini-images` Works

`PreToolUse` hook fires on every `Read`. If the path matches an image extension, the hook resizes (magick → sips → skip), spawns Gemini CLI to describe it, runs tesseract OCR in parallel, writes the combined output to a temp `desc.txt`, and rewrites `updatedInput.file_path` so Claude reads text instead of image bytes. Keeps the prompt cache warm.

## Testing

### Manual

1. Install plugin from this repo:
   - `claude plugin marketplace add .` — register local dir as marketplace
   - `claude plugin install gemini --scope project` (and/or `gemini-images`)
   - Restart Claude Code session (plugins require restart)
   - Alternative for one-off testing: `claude --plugin-dir .`
2. `/gemini:setup` — verify CLI, version, OAuth
3. `/gemini:review` — review current git diff
4. `/gemini:review path/to/file` — review specific file
5. `bash plugins/gemini-images/scripts/doctor.sh` — verify gemini-images dependencies

### Eval suite

`eval/` ships promptfoo configs for the review command (default prompt vs custom prompt × flash vs pro) and the security-review command. Run via `eval/run-gemini*.sh` scripts. See `CONTRIBUTING.md` for the workflow.

## Design Constraints

- Zero-code core: no JS runtime for `gemini` plugin (only Markdown + bash). `gemini-images` uses a Node.js hook but stays self-contained.
- Review output must be returned verbatim from Gemini — do not reformat or summarize.
- Gemini CLI is invoked with `--admin-policy plugins/gemini/policies/readonly.toml`, restricting it to `read_file` + `glob`. Single shared policy across review / ask / adversarial-review / security-review; setup does not call Gemini so it is unaffected.
- Do not change `--approval-mode` to work around the policy — the read-only restriction is intentional and the default mode avoids Issue #20469 where some approval modes bypass policies.
- Specs live in `docs/specs/`, design docs in `docs/plans/`.
