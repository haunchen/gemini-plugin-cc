# gemini

A Claude Code plugin that gets you a second opinion from Gemini — code review, adversarial design critique, and general questions — without leaving Claude Code.

## What & Why

Reviewing your own model's output with the same model has a blind spot: it tends to agree with itself. This plugin routes a diff or a file to Gemini through the Antigravity CLI (`agy`) and returns the answer verbatim, so you get a genuinely independent read.

The system prompts do the heavy lifting. On the repo's eval suite the review agent scores **10/10**; the same model with no system prompt scores **4/10** — the gap is entirely false positives the prompt suppresses (imaginary breaking changes in a rename, "prompt injection" in an LLM prompt edit, security warnings on a CI config bump).

## How It Works

```
Claude Code
  /gemini:review ──► command.md (Markdown, no runtime)
                       │
                       ├── collect input: git diff HEAD, or a file/glob you name
                       │
                       └── stdin ──► agy --agent gemini-review --model <slug>
                                       │
                                       └── system prompt comes from the agent,
                                           installed into agy by /gemini:setup
                       │
                       └──► output returned verbatim, never reformatted
```

`agy` is only the backend that runs Gemini. This plugin is not installed into agy as a skill — only the system prompts are, as agents.

Sister plugin `gemini-images` converts image `Read` calls into text descriptions to protect the prompt cache, and shares the same agy OAuth credentials — install whichever ones you want.

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview)
- [Antigravity CLI](https://antigravity.google) **1.1.6 or newer** — older builds cannot load custom agents, which is how this plugin injects its system prompts
- Signed in: run `agy` once interactively to authenticate via Google OAuth

No other dependencies. The commands are pure Markdown and bash; there is no JS runtime.

## Installation

**1. Install the plugin in Claude Code**

```
/plugin marketplace add https://github.com/haunchen/gemini-plugin-cc
/plugin install gemini
```

Restart Claude Code — plugins are not picked up until you do.

**2. Run setup**

```
/gemini:setup
```

Required. `agy` has no per-call system prompt injection, so setup registers the prompts with it as agents (`agy plugin install <plugin-root>/agy`) and then verifies they took effect. Expect `agents : 3 processed`.

Re-run setup after upgrading the plugin — new prompt versions do not reach agy until you do.

## Verification

Run `/gemini:review` on a repo with uncommitted changes. A working install returns:

```
## Review Summary
...
## Findings
...
## Verdict: PASS
```

Free-form prose with no such headings means the agents are not installed. See [Troubleshooting](#troubleshooting).

## Commands

| Command | Purpose |
|---------|---------|
| `/gemini:setup` | Check agy, install the agents, verify they work |
| `/gemini:review [path] [--model <m>]` | Code review of `git diff HEAD`, or of a file / glob you name |
| `/gemini:ask <question> [file] [--model <m>]` | Free-form technical question, optionally with a file as context |
| `/gemini:adversarial-review [path] [--model <m>]` | Devil's advocate — challenges design decisions instead of hunting bugs |

`review` and `adversarial-review` fall back to `git diff HEAD` (then `--cached`) when you give no path.

### Models

All commands default to `gemini-3.6-flash-high`, with reasoning effort pinned to `high`.

| `--model` value | Resolves to |
|-----------------|-------------|
| `flash` | `gemini-3.6-flash-high` (default) |
| `pro` | `gemini-3.1-pro-high` — an older generation than 3.6 flash; available, not recommended |
| anything else | passed to agy unchanged — run `agy models` for the list |

There is no automatic fallback on quota errors. A 429 surfaces as-is; retry or pass a different `--model`.

## Security

Each agent carries a `tools` whitelist in its frontmatter — `view_file` and `find_by_name`, nothing else. Writing files, running shell commands, web access and MCP tools are not in the agent's toolset at all, so there is nothing to bypass: the restriction holds even under `--dangerously-skip-permissions`, which was verified against a control agent without the whitelist (it wrote the file and ran the command). `/gemini:setup` re-checks this on every run.

If you need Gemini to execute commands or modify files, invoke `agy` directly rather than going through this plugin.

## Troubleshooting

**Output has no `## Verdict:` line, just prose**

The agents are not installed. `agy --agent <name>` **silently ignores names it does not recognise** — exit code 0, a normal-looking answer, no warning — so a failed install stays invisible until you notice the structure is missing. Re-run `/gemini:setup` and confirm it reports `agents : 3 processed`.

**`Sorry, I cannot fulfill your request to analyze or identify vulnerabilities...`**

agy declines requests it reads as security auditing. This is why there is no `/gemini:security-review` (see [Limitations](#limitations)). `/gemini:review` is unaffected and still reports security defects — it flags SQL injection as `[HIGH]`.

**`IneligibleTierError` / `This client is no longer supported`**

Something is still calling the old `gemini` CLI, which stopped serving consumer tiers on June 18, 2026. Upgrade to plugin v0.2.0 or newer.

**Auth errors, or the command hangs**

Run `agy` interactively once to refresh the OAuth token — `-p` (print) mode does not always refresh a stale one.

## Uninstall

```
/plugin uninstall gemini
```

The agents live in agy, not in Claude Code, so remove them separately or they stay behind:

```bash
agy plugin uninstall gemini-agents
```

## Limitations

- **No security-review command.** It existed up to v0.1.0. agy refuses security-audit requests — 17 of 20 eval calls came back as a refusal, including one on a pure rename diff with nothing to find — so the command could not do its job. The same prompt scored 10/10 under Gemini CLI, and rewriting it into a defensive framing did not help. Test cases and rubrics are kept in `eval/` for whenever this changes.
- **Setup is stateful.** Prompts live in agy, not in the plugin, so a plugin upgrade alone does not update them; re-run `/gemini:setup`.
- **No sampling control.** agy exposes no temperature or top-p setting, so repeated runs on the same input vary more than they did under Gemini CLI, which this repo pinned to `temperature: 0`.
- **Read-only by design.** The agents cannot run commands, write files, or fetch URLs, so they review only what is in the input you give them plus files they can read locally.
