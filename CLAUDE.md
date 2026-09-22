# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Claude Code plugin marketplace that reaches Gemini through the Antigravity CLI (`agy`). Two plugins share the same Google OAuth credentials:

- **`gemini`** — slash commands for code review, ask, adversarial review, and implementation. Pure Markdown commands + agent definitions, no JS runtime. Everything is read-only except `/gemini:implement`, which edits files.
- **`gemini-images`** — PreToolUse hook that replaces image `Read` calls with Gemini-generated text descriptions, protecting Anthropic's prompt cache.

Everything user-facing stays in Claude Code. `agy` is only the backend that runs Gemini — the plugins are not installed into agy as skills.

## Architecture

Marketplace registry at `/.claude-plugin/marketplace.json` points at two plugin sources under `/plugins/`:

```
.claude-plugin/marketplace.json          # marketplace registry (2 plugins)
plugins/gemini/
  .claude-plugin/plugin.json             # also registers the SessionStart hook
  commands/                              # /gemini:setup, review, ask, adversarial-review, implement
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

### A whitelisted tool is not a permitted tool

The `tools` whitelist decides what the agent *has*. A second, independent layer decides whether a given call is *allowed*, and a headless run cannot show a permission prompt — so agy soft-denies anything that would need one. That denial does not fail just the tool call. It discards the whole turn, and the command gets back one line of prose where a review should be:

```
jetski: no output produced — a tool required the "read_file" permission that headless mode
cannot prompt for, so it was auto-denied.
```

This lands on `view_file`, whose permission is named `read_file` — the one capability the review agent is supposed to have. Measured on agy 1.1.9 with a diff that renames an exported symbol, which is a nameable risk under `agent.md`'s lookup rule: 2/2 runs denied with `=== REPOSITORY ROOT ===` present, 3/3 completed with it removed. It is not deterministic in general, because whether the agent reaches for a file depends on what it finds in the diff — the same review can pass one run and vanish the next.

Two dead ends, both measured, so nobody re-walks them:

- **Adding `read_file` to the `tools` whitelist.** The agent then fails outright with `Error: Agent execution terminated due to error.` It is not a valid tool name; the whitelist was never what blocked it.
- **Reasoning from a synthetic probe agent.** `agy plugin install` reports `agents : N processed` and writes the files, yet the agents may still not register — check `agy agents` for the name, because `--agent` silently ignores what it cannot resolve and runs the *default* agent, which has full tools. A probe built this way looks like it proves the whitelist is inert. It proves nothing.

`review.md` handles this by re-running once without the ROOT section, which downgrades the agent to reporting risks instead of checking them. A `permissions.allow` rule in `~/.gemini/settings.json` is the other half of the fix, but it is per-machine and cannot ship with the plugin.

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

## How `/gemini:implement` Works

The one command that writes. Same shape as review — labelled payload, agent decides by matching the labels literally — with three different markers:

```
=== WORKSPACE ROOT ===
=== TASK BRIEF (what to implement) ===
=== CONTEXT (files and conventions to follow) ===
```

Same rule as review's: the parentheticals are part of the string, and changing one means changing `commands/implement.md` and `agy/agents/gemini-implement/agent.md` in the same commit.

Three things are load-bearing and specific to this command:

- **It refuses to run outside a git repository.** Not a convenience check. `--add-dir` does not confine writes, so `git diff` is the only thing making the run reviewable and reversible. Without a repo there is no undo, so there is no run.
- **It reconciles the report against reality.** The agent's `## Files Changed` list is a claim. The command diffs it against `git status --porcelain` taken before and after, and reports undeclared writes and declared-but-absent files separately. Undeclared writes are the case that matters — read that diff first.
- **It never commits.** Uncommitted is what keeps `git checkout` available, and what keeps Gemini's edits distinguishable from the user's.

The agent has no shell, so it cannot run the tests it writes. It is required to say so rather than report them passing, and the command repeats that when handing back: tests now exist, none has passed.

The default model is `gemini-3.7-flash-high` while review stays on 3.6. That split is measured, not an oversight — see `docs/specs/gemini-implement.md` D6. Reviewing is where the two are indistinguishable; writing code is where 3.7's gains are.

The prompt's underspecification gate is worth reading before editing it. It lists five literal conditions rather than saying "stop if ambiguous", because the adjective version demonstrably did not work: given "add caching so it is faster" the agent shipped an unbounded cache and reported `DONE`. See D5.

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
7. `/gemini:implement` — test in a throwaway git repo, never the working checkout. Three runs cover it:
   - A fully specified task (states inputs, outputs, and any error message verbatim) — expect `Status: DONE`, files actually changed, and the `## Files Changed` list matching `git status` exactly
   - An underspecified one, e.g. "add caching so it is faster" — expect `Status: NEEDS_CONTEXT` and **zero** files touched. If it implements something, the gate in the agent prompt has regressed; that is the check worth repeating after any edit to that prompt
   - `agy -p "Run the shell command 'echo RAN'..." --agent gemini-implement` — expect `NO_SHELL_OK`

**After editing any `agy/agents/*/agent.md`, re-run `agy plugin install` for that plugin.** Install copies the agents into `~/.gemini/config/plugins/`; without a re-install you keep exercising the old prompt, and `--agent` will not tell you.

### Eval suite

`eval/` ships promptfoo configs comparing the custom agent against the bare model. Both arms go through `agy-provider.js`, a promptfoo JS provider — each arm is `id: file://agy-provider.js` plus a `config:` block naming `model` and, for the custom arm, `agent` (omit `agent` for the bare model). Optional `addDir` and `timeout` map to the matching agy flags. Invoke with `npx promptfoo@latest eval -c <config>`.

**There are two scoring configs, and they measure opposite failures.** `promptfooconfig.yaml` is the regression net: six of its thirteen cases punish false positives, and their diffs are clean, so a PASS there means "did not invent anything". `promptfooconfig-recall.yaml` punishes the other direction — each planted defect gets its own `llm-rubric` tagged with a `metric`, and the score is the fraction reported. They are kept apart because averaging "did not over-report" with "reported this fraction" makes both unreadable.

Three things about the recall config are load-bearing:

- **The ground truth lives in `eval/ground-truth/`, not in the rubrics.** Each entry records where the defect was verified (read the source, confirmed upstream, found by the fan-out prototype) and its tier — L1 visible in the diff, L2 needing domain knowledge or cross-hunk reasoning, L3 needing a fact the diff does not contain. `score-recall.mjs` splits recall by tier, but the tier aggregate is direction-only — individual IDs flip between rounds (agy has no sampling controls), so the actual read is per-ID, not the tier total; see the design doc's Baseline section and the per-ID table `score-recall.mjs` prints alongside the tier summary.
- **`migration-cli-entrypoint.diff` carries both directions at once.** Four recall points and seven fabrication gates on the same diff, aggregated as two separate numbers. That pairing is the point: D21/D22 measured that tightening the LOW cap buys one more real defect and one more invented foreign key, and a recall-only score would read that trade as pure progress.
- **The fabrication gates never punish a hedged LOW.** A risk marked "not verifiable from this diff" is exactly what the shipped prompt asks for (D15). Only asserting it as fact, rating it MEDIUM/HIGH, or letting it drive the verdict fails.

Read a run with `node eval/score-recall.mjs eval/out/recall-r*.json`, which classifies every assertion as a real failure, a provider error, or a judge parse failure and drops the latter two from the denominators. Run three independent invocations rather than `--repeat 3` — agy has no sampling controls, so a single round is not a baseline, and you need per-round output to tell variance from a real drop.

**Never pass the prompt as a shell argument.** The provider writes it to agy's stdin, and that is load-bearing rather than stylistic. The `exec: bash ./run-agy.sh …` providers this replaced put the prompt in argv, where the shell ate one level of backslash escaping: a test case containing `replace(/[.*+?^${}()|[\]\\]/g, "\\$&")` reached the model as `replace(/[.*+?^${}()|[\]\]/g, "\$&")`, which really is broken code. The model then reported an unterminated character class — reproducibly, on both 3.6 and 3.7, 6 runs out of 6 — and it reads exactly like a hallucination until you diff what the harness sent against the file on disk. Only cases with consecutive backslashes were affected, so it corrupted one row of the suite rather than failing loudly. `agy-provider.js` has the full account in its header comment.

The two `promptfooconfig-security*.yaml` configs are PARKED — the command they target was removed (see D12). Their test cases and rubrics are kept for whenever it comes back.

agy exposes no sampling controls, so eval runs vary more than the pre-0.2.0 numbers, which were pinned to `temperature: 0` via a `.gemini/settings.json` that no longer applies.

**`--json-schema` is not a way out of that variance, and it was measured.** The provider carries `--output-format json` for the envelope (`status` is a deterministic infrastructure check, unlike pattern-matching prose) but deliberately not `--json-schema`. On agy 1.2.7 with `--agent gemini-review` the schema is silently ignored: markdown comes back, `num_turns` is 4, and the same report repeats four times for 6461 output tokens — the agent prompt's `## Output Format` section wins. Without `--agent` the bare model does emit JSON, but `response` then holds two concatenated JSON objects. The arm that works is not the arm being measured, and changing the agent's output format to suit the harness would measure a prompt nobody ships (D19/D21/D22 all measured that output-format changes move the finding count).

**The suite does not reproduce how the command actually runs.** No config sets `addDir`, so the agent cannot open a single file, while `/gemini:review` has granted that since 0.2.2. The regime is not a detail: with no file access the reviewer has to guess about anything outside the diff, and with access it can check. Numbers from the suite describe the blind regime, not what a user sees.

Judge note: the rubric provider must be a current model. `claude-sonnet-4-20250514` is retired (404) and promptfoo ≤ 0.121.5 sends a deprecated `temperature` to newer models (400) — either failure grades every case FAIL regardless of output quality. Use promptfoo `@latest`.

**A red cell has three possible causes, and only one of them is the model.** Read the reason before recording any number:

- **A real failure** — a written rubric verdict explaining what the review missed or overclaimed.
- **A provider error** — `agy did not return a response: …` in the error field, with an empty output. That is a 503, an exhausted quota, or a headless permission denial. `agy-provider.js` classifies these so promptfoo counts them as errors, not failures; exclude them from scores.
- **A judge parse failure** — the reason reads `Could not extract JSON from llm-rubric response` or `No output` while `response.output` holds a perfectly normal review. The grading call failed, not the model. promptfoo counts these as failures, so they have to be excluded by hand.

That last one is not rare: 4 of 39 cells in one run, still 1 of 39 after dropping concurrency from 4 to 2, so it is not purely a rate-limit effect. A score reported without excluding these two categories will understate whichever arm got unlucky, which is exactly how a service outage turns into a fabricated quality regression.

## Versioning

The two plugins version independently — bump only the one you changed. They happen to both sit at 0.2.0 because the agy migration touched both.

Two files carry the plugin's version and always move together:

```
.claude-plugin/marketplace.json          # the plugin's entry in the plugins[] array
plugins/<plugin>/.claude-plugin/plugin.json
```

A third file, `plugins/<plugin>/agy/plugin.json`, versions the agents rather than the plugin. **Move it only when an `agy/agents/*/agent.md` actually changed**, and then set it to the same version as its parent so the two stay legible side by side. It used to be described as following the parent unconditionally; that is wrong, and 0.2.2 is where it stopped. `check-agent-version.sh` compares exactly this file, so bumping it for a change the agents did not see fires "your prompts are stale" at people whose prompts are current — the failure the hook's own comment warns about, where a notice that cries wolf gets ignored on the session where it matters.

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
3. **Update `assets/banner.svg`** if the release changes anything the banner states: the version pill, the command list, the backend name, or the bottom spec row. The source of truth lives in the vault at `20-Side/gemini-plugin-cc/banner-gemini-plugin-cc.svg` (it moved there when the vault was restructured; the old `02-Projects/…` path is gone) — edit there, then copy into `assets/`. The two differ in line endings only: the vault copy is LF, the repo copy CRLF, so sync with `sed 's/$/\r/'` rather than a plain `cp`, which would rewrite all 96 lines and bury the real change.
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
- **`gemini-implement` is the one exception, and it is scoped rather than a loosening.** It adds `replace_file_content` and `write_to_file` and nothing else — still no shell, verified separately by `/gemini:setup` step 7 (`NO_SHELL_OK`). The other three agents are untouched, so `/gemini:review` remains something that cannot alter your files. See `docs/specs/gemini-implement.md` D1.
- **The whitelist bounds what an agent can do, not where.** `--add-dir` sets the workspace; it does not fence it. Measured: the implementer wrote an absolute path outside `--add-dir` with nothing blocking or warning, and `view_file` read a file well outside it. That second half applies to the read-only agents too — they cannot write anywhere, but they can read anything the user can. `/gemini:review` staying inside the repo root is its prompt behaving, not a boundary holding. `/gemini:implement` compensates by refusing to run outside a git repo and reconciling declared writes against `git status`; a write outside the repo root is invisible to that check and nothing prevents one.
- Never add `--dangerously-skip-permissions` to a plugin invocation. The whitelist holds without it — including for the write tools, which work headless with no permission prompt — and the flag would only matter for tools the agents should not have.
- Specs live in `docs/specs/`, design docs in `docs/plans/`.
