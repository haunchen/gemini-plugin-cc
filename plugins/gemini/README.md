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

Re-run setup after upgrading the plugin — new prompt versions do not reach agy until you do. Since 0.2.1 the plugin checks this for you: at the start of a session it compares the version it ships against the one installed in agy, and prints a one-line notice if they differ. The check follows wherever you installed the plugin, so a user-scope install reports on every session and a project-scope install only inside that project. It prints nothing when the versions match.

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
| `/gemini:review [path] [--spec <path>] [--model <m>]` | Code review of `git diff HEAD`, or of a file / glob you name. `--spec` adds a spec-compliance verdict |
| `/gemini:ask <question> [file] [--model <m>]` | Free-form technical question, optionally with a file as context |
| `/gemini:adversarial-review [path] [--model <m>]` | Devil's advocate — challenges design decisions instead of hunting bugs |
| `/gemini:implement <task> [--brief <path>] [--context <path>] [--model <m>]` | **Writes to your files.** Hands a task to Gemini, which edits the workspace directly |

`review` and `adversarial-review` fall back to `git diff HEAD` (then `--cached`) when you give no path.

### Implementing, not just reviewing

`/gemini:implement` is the only command that changes your files. It suits mechanical, well-specified work that is cheap to check — batch renames, boilerplate, test scaffolding, applying one pattern across several files. Work that needs judgment about the whole repo is better done in the Claude Code session that already has the context.

```
/gemini:implement Add a truncate(input, maxLength) helper to src/format.ts with tests
/gemini:implement --brief docs/tasks/T3.md --context src/format.ts
```

What it does around the edit:

- Refuses to run outside a git repository, and tells you if the tree is already dirty before starting
- Afterwards, checks what the agent *said* it changed against what `git status` shows — undeclared writes are called out, because those are the ones you would otherwise miss
- Never commits, so `git diff` reviews it and `git checkout` undoes it

Two things it will not do. It has no shell, so tests it writes have never run — you get the exact command to run them, and it is required to say they are unrun rather than claim they pass. And when the brief leaves a real decision open (state with no bound, a goal that is only "faster", more than one plausible file), it writes nothing and comes back with `NEEDS_CONTEXT` plus the decisions it needs from you.

Default model is 3.7 Flash here, against 3.6 for review. The two are indistinguishable at reviewing on this repo's eval suite; 3.7's measured gains are in writing code.

### Reviewing against requirements

Point `--spec` at whatever states the intent — a spec, a design doc, a task brief — and the review returns a second verdict:

```
/gemini:review --spec docs/specs/auth.md
```

```
## Spec Compliance: FAIL
- Missing: R3 (rate limiting on /login) — no reference in the diff
- Extra: a "remember me" cookie set on login, not requested by any requirement
- ⚠️ R5 (session expiry) lives in code this diff does not touch — confirm separately
```

It reports three things: requirements that were skipped, functionality nobody asked for, and requirements solved the wrong way. Anything it cannot settle from the change alone comes back as ⚠️ rather than a guess. `--spec` is repeatable and takes globs. Leave it off and the output is exactly as before.

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

**`jetski: no output produced — a tool required the "read_file" permission...`**

The reviewer reached for a file and agy auto-denied it: a headless run has no way to show a permission prompt, and the denial throws away the entire turn rather than the single tool call. What comes back is that one line instead of a review. Nothing is wrong with the install, so `/gemini:setup` is not the fix.

v0.2.2 grants the read by passing `--add-dir` with the repository root, so upgrade if you are on anything older. It can still appear when the diff points outside that root — a sibling checkout, a path climbing out through `..`, an absolute path. `/gemini:review` then retries once with file lookup switched off and tells you; in that mode a call-site question comes back as "not verifiable from this diff" instead of an answer.

Because whether the agent reaches for a file depends on what it finds in the diff, this is not reproducible on demand — the same review can succeed one run and fail the next.

**Output has no `## Verdict:` line, just prose**

The agents are not installed. `agy --agent <name>` **silently ignores names it does not recognise** — exit code 0, a normal-looking answer, no warning — so a failed install stays invisible until you notice the structure is missing. Re-run `/gemini:setup` and confirm it reports `agents : 3 processed`.

**`[gemini] The review prompts installed in agy are vX; this plugin ships vY`**

Exactly what it says: the plugin was upgraded, the prompts in agy were not. Run `/gemini:setup`. The reason this needs announcing is that nothing else would — `agy --agent` runs an outdated prompt without complaint, so the output looks normal and simply lacks whatever the newer version added.

The check stays quiet when it cannot find agy's installed manifest, which also means it will not catch a stale prompt if your agy keeps its config somewhere other than `$GEMINI_CONFIG_DIR` or `~/.gemini`. Set `GEMINI_CONFIG_DIR` if that applies to you.

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
- **Read-only by design, except the implementer.** `gemini-review`, `gemini-ask` and `gemini-adversarial-review` cannot run commands, write files, or fetch URLs — they work from the input you give them plus files they can read locally. `gemini-implement` adds file editing and nothing else; it still has no shell and no network.
- **No shell anywhere.** Nothing in this plugin can execute a command, which is why `/gemini:implement` writes tests it cannot run.
- **The workspace flag is not a fence.** `--add-dir` says where the work is, not where writes are allowed — a run can touch paths outside it, and reads are unrestricted for every agent including the read-only ones. `/gemini:implement` handles this by requiring a git repo and auditing `git status` afterwards, which covers everything inside the repository and nothing outside it.
