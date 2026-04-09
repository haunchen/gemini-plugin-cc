# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Claude Code plugin that calls Gemini CLI for second-opinion code reviews. Zero-code architecture — pure Markdown commands and system prompts, no JavaScript.

## Architecture

Two-layer plugin structure following Claude Code plugin spec:

- `/.claude-plugin/marketplace.json` — marketplace registry, `source` points to `./plugins/gemini`
- `/plugins/gemini/.claude-plugin/plugin.json` — plugin manifest
- `/plugins/gemini/commands/*.md` — slash command definitions (`/gemini:setup`, `/gemini:review`)
- `/plugins/gemini/system-prompts/*.md` — injected via `GEMINI_SYSTEM_MD` env var when calling Gemini CLI

The system prompt (`system-prompts/review.md`) is the primary quality lever. It defines reviewer role, output structure (Summary → Findings → Verdict), and severity criteria (HIGH/MEDIUM/LOW).

## How Commands Work

Commands are Markdown files with YAML frontmatter (`description`, `allowed-tools`, `argument-hint`). Claude Code reads and executes the instructions within. The review command pipes input to Gemini CLI via stdin:

```
echo "$INPUT" | GEMINI_SYSTEM_MD="$PATH" gemini -o text -m pro
```

## Testing

No automated tests yet. Manual testing:

1. Install plugin from this repo:
   - `claude plugin marketplace add .` — register local dir as marketplace
   - `claude plugin install gemini --scope project` — install the plugin
   - Restart Claude Code session (plugins require restart)
   - Alternative for one-off testing: `claude --plugin-dir .`
2. `/gemini:setup` — verify CLI, version, API key
3. `/gemini:review` — review current git diff
4. `/gemini:review path/to/file` — review specific file

## Design Constraints

- Phase 1 is zero-code: no JS, no runners, no job tracking
- Review output must be returned verbatim from Gemini — do not reformat or summarize
- Hardcoded `-m flash` for review (alias, auto-resolves to latest flash); model switching deferred to Phase 2
- Specs live in `docs/specs/`, design docs in `docs/plans/`
