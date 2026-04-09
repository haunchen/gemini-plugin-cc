# gemini-plugin-cc

A [Claude Code plugin](https://docs.anthropic.com/en/docs/claude-code/plugins) that calls [Gemini CLI](https://github.com/google-gemini/gemini-cli) to give you a second opinion on code reviews.

Zero-code plugin — pure Markdown commands, no JavaScript required.

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview) installed
- [Gemini CLI](https://github.com/google-gemini/gemini-cli) installed (`npm install -g @google/gemini-cli`)
- `GEMINI_API_KEY` environment variable set, or authenticated via `gemini` OAuth

## Installation

Add this plugin marketplace in Claude Code:

```
/install-plugin https://github.com/haunchen/gemini-plugin-cc
```

Then run `/gemini:setup` to verify everything is configured.

## Commands

### `/gemini:setup`

Checks Gemini CLI installation, version, and API key status.

### `/gemini:review [file-path]`

Get a code review from Gemini as a second opinion.

- With argument: reviews the specified file
- Without argument: reviews `git diff HEAD` (staged + unstaged changes)

Uses a tuned system prompt (`system-prompts/review.md`) to produce structured output:

- **Summary** — one-line overview
- **Findings** — severity (HIGH/MEDIUM/LOW), location, description, suggestion
- **Verdict** — PASS / NEEDS_CHANGES / CRITICAL

## Project Structure

```
gemini-plugin-cc/
├── .claude-plugin/
│   └── marketplace.json          # Marketplace registry
├── plugins/
│   └── gemini/
│       ├── .claude-plugin/
│       │   └── plugin.json       # Plugin manifest
│       ├── commands/
│       │   ├── setup.md          # /gemini:setup
│       │   └── review.md         # /gemini:review
│       └── system-prompts/
│           └── review.md         # Review system prompt
└── docs/
    ├── plans/                    # Design documents
    └── specs/                    # Feature specs
```

## How It Works

1. `/gemini:review` collects the diff or file content
2. Sets `GEMINI_SYSTEM_MD` environment variable pointing to the review system prompt
3. Pipes input to `gemini -o text -m pro` via stdin
4. Returns Gemini's response directly

The system prompt is the primary quality lever — it defines the reviewer role, output structure, and severity criteria.

## License

MIT
