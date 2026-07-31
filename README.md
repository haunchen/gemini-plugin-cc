<p align="center">
  <img src="assets/banner.svg" alt="gemini-plugin-cc" width="100%">
</p>

# gemini-plugin-cc

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-plugin-blueviolet)](https://docs.anthropic.com/en/docs/claude-code/plugins)
[![Antigravity CLI](https://img.shields.io/badge/Antigravity%20CLI-required-4285F4)](https://antigravity.google)

> [!IMPORTANT]
> **Migrated from Gemini CLI to the Antigravity CLI (`agy`) as of v0.2.0.**
>
> Gemini CLI stopped serving consumer tiers on June 18, 2026 ([official notice](https://developers.google.com/gemini-code-assist/docs/deprecations/code-assist-individuals)) and now returns `IneligibleTierError`. Both plugins call `agy` instead, which requires **agy 1.1.6 or newer** for custom agent support.
>
> One behaviour change: `agy` cannot take a system prompt per call, so `/gemini:setup` now installs the prompts into agy as agents. Run it once after upgrading. Everything else — the `/gemini:*` commands, their output, the read-only restriction — works the same. Review quality is unchanged (10/10 on the eval suite, same as Gemini CLI scored).

A marketplace of [Claude Code plugins](https://docs.anthropic.com/en/docs/claude-code/plugins) that bring Gemini into Claude Code via the [Antigravity CLI](https://antigravity.google) — get a second opinion on code, and keep your prompt cache warm while reading images.

## Plugins

| Plugin | Purpose | Triggers |
|--------|---------|----------|
| [`gemini`](plugins/gemini/) | Slash commands for code review, ask, adversarial review, security review | `/gemini:*` |
| [`gemini-images`](plugins/gemini-images/) | PreToolUse hook that converts image Reads into text descriptions to protect prompt cache | Automatic on `Read` image files |

Both plugins share the same agy OAuth credentials. Install one or both.

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview) installed
- [Antigravity CLI](https://antigravity.google) **1.1.6 or newer** (`agy --version`; older builds cannot load the custom agents these plugins install)
- Signed in — run `agy` once interactively to authenticate via Google OAuth

Plugin-specific extra dependencies are listed in each plugin's README.

## Installation

```
/plugin marketplace add https://github.com/haunchen/gemini-plugin-cc
/plugin install gemini
/plugin install gemini-images
```

Restart Claude Code after installation.

For `gemini`, run `/gemini:setup` — this is **required**, not just a check: it installs the four system prompts into agy as agents. Without it the commands still run but produce generic, unstructured output.

For `gemini-images`, install its agent and verify:

```
agy plugin install <repo>/plugins/gemini-images/agy
bash plugins/gemini-images/scripts/doctor.sh
```

## Commands (gemini plugin)

- `/gemini:setup` — check agy, install the agents, verify they took effect
- `/gemini:review [path] [--model <m>]` — code review (default model: Pro with Flash fallback)
- `/gemini:ask <question> [file] [--model <m>]` — free-form technical question
- `/gemini:adversarial-review [path] [--model <m>]` — devil's advocate design challenge
- `/gemini:security-review [path] [--model <m>]` — OWASP-focused security review

## Security

Each agent carries a `tools` whitelist in its frontmatter — only `view_file` and `find_by_name`. Writing files, running shell commands, web access and MCP tools are not in the agent's toolset at all, so there is nothing to bypass: the restriction holds even under `--dangerously-skip-permissions`. `/gemini:setup` verifies this on every run.

This keeps the review / ask / adversarial-review / security-review commands focused on inspection. If you need Gemini to execute shell commands or modify files, invoke `agy` directly instead of going through this plugin.

## Project Structure

```
gemini-plugin-cc/
├── .claude-plugin/
│   └── marketplace.json          # Marketplace registry
├── plugins/
│   ├── gemini/                   # Slash-command plugin
│   │   ├── .claude-plugin/plugin.json
│   │   ├── commands/             # Claude Code slash commands
│   │   └── agy/agents/           # System prompts, installed into agy
│   └── gemini-images/            # PreToolUse hook plugin
│       ├── .claude-plugin/plugin.json
│       ├── hooks/
│       ├── agy/agents/
│       ├── scripts/doctor.sh
│       └── README.md
└── docs/
    ├── plans/                    # Design + implementation plans
    └── specs/                    # Feature specs
```

## License

MIT
