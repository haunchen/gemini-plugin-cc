# Changelog

All notable changes to this project are documented here.

Both plugins are versioned independently, but have moved together so far, so releases are tagged once for the repo (`v<version>`). See [CLAUDE.md](CLAUDE.md#versioning) for the bump rules.

## [0.3.0] — 2026-08-14

`gemini` only. The plugin gets a command that writes to your files. Everything before this release only ever read them, and that line is worth crossing deliberately rather than quietly.

### Upgrading

**Re-run `/gemini:setup`.** This release adds a fourth agent, and agents do not travel with a plugin upgrade — `agy --agent` will keep answering with the three you already have and never mention the missing one. `/gemini:implement` cannot work until setup has run.

### Added

- **`/gemini:implement <task>`.** Hands a task to Gemini, which edits the files directly. Takes `--brief <path>` for a requirements file, `--context <path>` (repeatable, glob-aware) for supporting material, and `--model`. Defaults to `gemini-3.7-flash-high`.

  It is for work that is mechanical, well-specified, and cheap to verify — batch renames, boilerplate, test scaffolding, one pattern applied across several files. Work needing whole-repo judgment is better done in the Claude Code session that already holds the context.

- **The `gemini-implement` agent.** Whitelist is `view_file`, `find_by_name`, `replace_file_content`, `write_to_file` — file editing, no shell. Its disciplines are ported from this repo's `dev` plugin `implementer` agent: scope discipline, read-before-edit, follow the surrounding conventions, self-review checklist, and a four-value status (`DONE` / `DONE_WITH_CONCERNS` / `BLOCKED` / `NEEDS_CONTEXT`).

  Three things had to change in the port, all because agy is headless and one-shot. The original can pause and ask its controller a question; this one cannot, so every question becomes a `NEEDS_CONTEXT` report that ends the run. The original runs tests and commits; this one has no shell, so it writes tests it has never executed and is required to say so rather than report them passing. The original is dispatched by a controller that already resolved brief ambiguities; this one gets whatever the user typed.

### The default model is 3.7 here and 3.6 in `/gemini:review`

Deliberate, and measured. On this repo's eval suite the two are indistinguishable at reviewing: 12/12 each on the existing cases, 4/4 each on four new reasoning-heavy ones written for this release (a `Promise.all` that defeats a dedup guard, a cache key missing the dimensions its value depends on, early returns that skip the `finally` releasing a lock, plus a negative control of genuinely safe parallelism that neither flagged). A pairwise comparison across 16 cases in both orderings — judged by Claude Sonnet 4.6 — split 5:2 in decisive cases, which at that sample size is noise, not a signal.

So review stays on 3.6, and 3.7 gets the command whose job is writing code, where Google's own numbers put the gain (DeepSWE v1.1 49.0% → 65.3%).

### What was measured about writing files

- **A whitelisted write tool works headless.** No permission prompt, no `--dangerously-skip-permissions`, no `permissions.allow` entry. This is the opposite of `view_file`, whose `read_file` permission is soft-denied in headless mode and takes the whole turn with it (see 0.2.2).
- **`--mode accept-edits` is not available.** Two runs, both `Eligibility check failed: UNAVAILABLE (503)`; the identical request without the flag executed normally. It is the flag, not the service.
- **`--add-dir` is not a sandbox.** Asked to write an absolute path outside the workspace, the agent did, with nothing blocking or warning. The same is true for reads: `view_file` opened a file well outside `--add-dir` and returned its contents.

  That last one applies to the read-only agents already shipping. The `tools` whitelist guarantees they cannot *write*; it says nothing about *where they can read*. A `/gemini:review` run can open any file the user can. It does not go looking — the reviewer's own prompt keeps it inside the repository root — but that is a behavioral constraint, not a boundary, and it should not be mistaken for one.

- **`/gemini:implement` is built around that.** It refuses to run outside a git repository, snapshots `git status --porcelain` first, and afterwards reconciles what the agent *declared* it changed against what git *shows* changed — reporting undeclared writes and declared-but-absent ones separately. It never commits, so `git diff` and `git checkout` stay available. The check is honest about its limit: a write outside the repository root does not appear in `git status`, and nothing in agy prevents one.

### The underspecification gate, and why it is written the way it is

The first version of the agent prompt said to stop and report `NEEDS_CONTEXT` when a brief is "ambiguous or incomplete". Given the brief *"Add caching to the format module so it is faster"*, it implemented an unbounded `Map` cache on two functions, reported `DONE`, and raised no concerns. It did not consider that ambiguous.

Replacing the adjective with five literal tests — behavior change with no stated input/output, state introduced with no bound or lifetime or invalidation, a goal that is only an adjective, more than one plausible location, a dependency on a value that appears nowhere — changed the outcome on the identical brief: `NEEDS_CONTEXT`, zero files written, the three decisions it would have been making listed, and a recommendation to confirm. A regression on a fully specified brief still completed and wrote both files, so the gate discriminates rather than just refusing.

`view_file` reading outside `--add-dir` is what makes this gate matter more than it looks: the failure mode is not a bad edit in one file, it is a confident agent acting on requirements it invented.

### Fixed

- **The eval harness was corrupting test cases containing backslashes.** Every config ran through `exec: bash ./run-agy.sh …`, which passed the prompt as a shell argument, and the shell ate one level of backslash escaping on the way. A test case containing

  ```js
  cmdName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
  ```

  reached the model as

  ```js
  cmdName.replace(/[.*+?^${}()|[\]\]/g, "\$&")
  ```

  which is genuinely broken. The model reported an unterminated character class and a replacement string that fails to prepend a backslash — correct findings about the text it was given, and indistinguishable from a hallucination until you compare what the harness sent against the file on disk. Both 3.6 and 3.7 produced it, 6 runs out of 6; feeding the same diff to agy directly, both said the code was correct.

  Replaced with `eval/agy-provider.js`, a promptfoo JS provider that writes the prompt to agy's stdin, so nothing but flag values ever reaches a shell. `run-agy.sh` is deleted. Only cases with consecutive backslashes were affected — `incidental-findings` and `security-filename-injection` — which is why this survived several releases: it corrupts one or two rows instead of failing the run.

- **Infrastructure failures no longer count as failed test cases.** agy reports a 503, an exhausted quota, or a headless permission denial on stdout with exit 0. The old runner handed those straight back as the model's answer, the rubric failed them for not containing a review, and an outage came out looking like a quality regression. Measured while writing this release: a 503 cost 3.7 a point on the hard set, and two permission denials cost the bare-3.7 arm two points on the main suite.

  `agy-provider.js` now classifies those as provider errors, so promptfoo counts them in its error column instead of the pass rate. The loose tokens (`RESOURCE_EXHAUSTED`, `429`, `503`) are only trusted on short outputs, since a real review may well discuss retry handling in the code it is reviewing.

### Changed

- **`/gemini:setup` installs and verifies four agents.** Expect `agents : 4 processed`. A new step 7 checks that `gemini-implement` has no shell (expects `NO_SHELL_OK`), since for that agent the read-only check does not apply and the absence of execution is the property worth confirming.
- **`agy/plugin.json` moves to 0.3.0**, because `agy/agents/` gained a file. Per the rule added in 0.2.2, it moves only when the agents do.

## [0.2.2] — 2026-08-02

`gemini` only. The reviewer has been unable to open a file since agy started soft-denying permissions in headless mode, and the failure took the whole review with it. This release gives the capability back.

### Upgrading

Nothing to do. The agent prompts did not change, so `/gemini:setup` is not needed — and this is the first release where that is true. If a session-start notice says your prompts are stale, it is left over from 0.2.1.

### Fixed

- **`/gemini:review` can read files again.** agy runs `view_file` behind a permission named `read_file`, and a headless run cannot show a permission prompt, so agy soft-denies it. The denial does not fail just the tool call — it discards the entire turn, and the command gets back `jetski: no output produced — a tool required the "read_file" permission...` where a review should be. `/gemini:review` now passes `--add-dir "$ROOT"`, which grants the read without a global settings change.

  Measured on agy 1.1.9 against a diff renaming an exported symbol: 2/2 runs denied without the flag, 2/2 completed with it. The difference in what comes back is not subtle — without file access the same agent returns one LOW finding saying callers "may need updating, not verifiable from this diff"; with it, a HIGH naming the two files that actually import the old name.

  It is not deterministic, because whether the agent reaches for a file depends on what it finds in the diff. The same review could succeed one run and vanish the next, which is why this went unnoticed.

- **The failure is no longer misdiagnosed as a broken install.** All three commands used to read "no `## Verdict:` line" as proof that `--agent` had ignored an unknown name, and sent the user to `/gemini:setup` — which fixes nothing here. They now tell the two cases apart. `/gemini:review` also re-runs once without the ROOT section when a read is denied anyway, which completes but downgrades the reviewer to reporting risks instead of checking them; the output says so.

### Changed

- **`agy/plugin.json` versions the agents, not the plugin.** It used to be documented as following its parent unconditionally. `check-agent-version.sh` compares exactly that file, so bumping it for a release the agents did not see tells people their prompts are stale when they are current — and a notice that cries wolf gets ignored on the session where it matters. It now moves only when an `agy/agents/*/agent.md` moves, which is why it stays at 0.2.1 here.

### Not changed, and why

An A/B run on this release's question — why a review of a data-migration script came back in three seconds with an empty `PASS` — tried adding a mandatory checklist to the reviewer, both inside the system prompt and appended after the diff. It made things worse: 0 findings across 5 runs with a checklist, against 2 across 4 without. The checklist gets the model to narrate what it checked and then treat the narration as the deliverable. Not shipped, and the reviewer prompt is unchanged here.

Shortening that prompt is the hypothesis worth testing next, and this release deliberately does not attempt it. On the same payload and tool whitelist, a six-line prompt averaged 2.0 real findings per run against the shipped prompt's 0.78 — but it also invents things, and the rules that would be cut are the ones stopping that. `eval/` has no case that fails the reviewer for staying quiet, so there is nothing to measure the trade against yet. That comes first.

## [0.2.1] — 2026-07-31

`/gemini:review` picks up four review disciplines ported from this repo's `dev` plugin `task-reviewer` agent, plus an optional way to hand it the requirements. The plugin also stops relying on you to remember that prompts need reinstalling.

### Upgrading

**Re-run `/gemini:setup`.** The prompt lives in agy, not in the plugin — upgrading the plugin alone leaves you on the old one, and `--agent` will not tell you. From this release on, the plugin notices for you and says so at the start of a session.

### Added

- **A session-start check for stale prompts.** Every release so far has ended with "remember to re-run `/gemini:setup`", which is a documentation fix for a mechanical problem: the agents live in `~/.gemini/`, a plugin upgrade does not touch them, and `agy --agent` answers happily with whatever it already has. The plugin now compares the version it ships against the one installed in agy at session start, and prints a one-line notice when they diverge. It stays silent when they match, and silent when it cannot find the installed manifest at all — a check that guesses wrong on every session would just train you to ignore it.
- **`--spec <path>`.** Point `/gemini:review` at a spec, design doc, or task brief and it returns a second verdict — `## Spec Compliance: PASS | FAIL` — checking the change for missing requirements, unrequested extras, and misread intent. Requirements that cannot be settled from the change alone come back as ⚠️ with a note on what to confirm yourself. Repeatable, glob-aware. Without it nothing changes: no requirements section in the input, no second verdict.
- **`## Incidental Findings`.** Existing bugs and technical debt in surrounding code that the change neither introduced nor made worse now get their own section instead of being dropped or misfiled as defects of the change. They never affect either verdict.

### Changed

- **The reviewer may now verify a nameable risk outside the diff.** The old rule was a flat "do not speculate about unseen code", which read as "do not look". It can now follow one focused lookup per specific, nameable risk — a changed signature or API contract, changed lock ordering or shared mutable state, a symbol that may still be referenced — and must report what it checked and what it found. "I would like to look around" still does not qualify.
- **A risk it could not verify is capped at LOW** and never on its own turns a `PASS` into `NEEDS_CHANGES`. Without that cap the reviewer wrote unchecked guesses as established facts — an early build called a pure rename a compile break. It now says what it could not check, and says so as a pointer rather than a defect.
- **Comments no longer count as evidence.** "Intentionally kept simple", "per YAGNI", "already tested" are treated as unverified claims; a stated rationale cannot lower a finding's severity, and a comment contradicting its code is itself a finding.
- **Diff reading is explicit.** Context lines are the post-change file, so files already shown are not re-read; a truncated hunk is reported rather than guessed at.

Severity levels (`HIGH`/`MEDIUM`/`LOW`) and the main verdict (`PASS`/`NEEDS_CHANGES`) are unchanged. `adversarial-review` and `ask` are untouched.

### Verified

| | |
|---|---|
| review eval, custom agent | 11/13 |
| review eval, bare model | 8/13 |
| new cases: self-justifying comment, spec compliance, verdict suppression | all pass on the custom agent |

Treat those two numbers as coarse. agy exposes no sampling controls, and across runs of this same suite the untouched bare-model arm moved by three points on its own — enough that a one- or two-point gap means nothing. What the runs do establish: the three new behaviours fire, and an early version of this prompt escalated a pure rename to `NEEDS_CHANGES`, which the LOW cap on unverifiable risks fixed.

The two that slipped were `attribute-shadowing` and `incidental-findings`, both previously passing. Rerunning them uncached told different stories: `incidental-findings` swung from naming one improvement to naming all five, which is the sampling noise described above. `attribute-shadowing` reproduced its shape both times — a one-line summary, empty findings, an immediate `PASS` — which is what the prompt asks for on a clean fix, while that case's rubric wants the crash mechanism spelled out. Worth watching rather than resolved.

## [0.2.0] — 2026-07-31

Migrated both plugins from Gemini CLI to the Antigravity CLI (`agy`). Gemini CLI stopped serving consumer tiers on June 18, 2026 and now returns `IneligibleTierError`.

### Upgrading

1. Install [agy](https://antigravity.google) **1.1.6 or newer** and sign in (`agy` once, interactively).
2. Update the plugins, restart Claude Code.
3. **Run `/gemini:setup`.** This is no longer optional — it installs the system prompts into agy as agents. Skip it and the commands still answer, but with none of this repo's review structure applied, and nothing will warn you.
4. For `gemini-images`, run `agy plugin install <repo>/plugins/gemini-images/agy` from a clone.
5. If you set `GEMINI_BIN` or `GEMINI_MODEL`, rename them to `AGY_BIN` / `AGY_MODEL`.

### Removed

- **`/gemini:security-review`.** agy declines security-audit requests: 17 of 20 eval calls came back as *"Sorry, I cannot fulfill your request to analyze or identify vulnerabilities"*, including one on a pure rename diff with nothing to find. The same prompt scored 10/10 under Gemini CLI, and rewriting it into a defensive framing did not help. `/gemini:review` still reports security defects — it flags SQL injection as `[HIGH]` on the exact case the security agent refused. Test cases and rubrics are kept in `eval/`, marked PARKED.
- **Automatic model fallback on quota errors.** It existed because Pro hit 429 constantly; with Pro no longer the default, retrying on the same model is a no-op and retrying on another assumes separate quota pools, which agy does not document. Quota errors now surface as-is.
- **`plugins/gemini/policies/readonly.toml`** — replaced by the `tools` whitelist (see below).
- **`.gemini/settings.json`** — pinned `temperature: 0` for Gemini CLI; agy exposes no sampling controls, so eval runs now vary more.

### Changed

- **System prompts are installed, not injected.** agy has no `GEMINI_SYSTEM_MD` equivalent, so prompts are registered up front as Markdown custom agents (`agy/agents/<name>/agent.md`, delimited by an exact `# Agent System Instructions` H1). The plugins go from stateless to stateful; `/gemini:setup` becomes a real installer and verifies the result, because `agy --agent` silently ignores unknown names — a failed install returns exit 0 and a plausible answer.
- **Read-only enforcement is stronger.** The agents carry a `tools` whitelist (`view_file`, `find_by_name`) instead of a deny-by-default policy. The tools are absent from the agent rather than denied, so `--dangerously-skip-permissions` cannot bypass it — verified against a control agent, which did write files and run shell commands.
- **All commands default to `gemini-3.6-flash-high`**, effort pinned to `high`. The previous pro-by-default routing assumed Pro outscored Flash; agy's Pro is `gemini-3.1-pro`, two generations behind. `--model pro` still works for explicit opt-in.
- `gemini-images`: `--include-directories` → `--add-dir`, and the `@escaped/path` prompt syntax is gone (agy takes a plain path).
- Eval: eight runner scripts collapsed into one parameterized `run-agy.sh <agent|-> <model-slug>`.
- Both plugins gained a full README; the `gemini` plugin had none before.

### Verified

| | |
|---|---|
| review eval, custom agent | 10/10 — the same score Gemini CLI achieved |
| review eval, bare model | 4/10 |
| adversarial-review, ask, gemini-images hook | smoke tested end to end |
| `doctor.sh` | all checks green, including agent install |

## [0.1.0] — 2026-05-12

Initial open-source release.

- **`gemini`** — `/gemini:setup`, `review`, `ask`, `adversarial-review`, `security-review`. Markdown commands with no JS runtime, driving Gemini CLI over stdin with a per-call system prompt via `GEMINI_SYSTEM_MD`, restricted to `read_file` + `glob` by `--admin-policy`.
- **`gemini-images`** — `PreToolUse` hook on `Read` that resizes an image, describes it through Gemini, runs tesseract OCR in parallel, and hands Claude the text so the prompt cache survives.
- promptfoo eval suite with LLM-as-judge rubrics over real-world diffs.

[0.2.1]: https://github.com/haunchen/gemini-plugin-cc/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/haunchen/gemini-plugin-cc/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/haunchen/gemini-plugin-cc/releases/tag/v0.1.0
