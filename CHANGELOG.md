# Changelog

All notable changes to this project are documented here.

Both plugins are versioned independently, but have moved together so far, so releases are tagged once for the repo (`v<version>`). See [CLAUDE.md](CLAUDE.md#versioning) for the bump rules.

## [0.2.1] — 2026-07-31

`/gemini:review` picks up four review disciplines ported from this repo's `dev` plugin `task-reviewer` agent, plus an optional way to hand it the requirements.

### Upgrading

**Re-run `/gemini:setup`.** The prompt lives in agy, not in the plugin — upgrading the plugin alone leaves you on the old one, and `--agent` will not tell you.

### Added

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
