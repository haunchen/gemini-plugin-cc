# Contributing

Thanks for your interest. This repo is a Claude Code plugin marketplace; PRs that improve the system prompts, harden the read-only policy, or extend OS support are especially welcome.

## Repo layout

See [CLAUDE.md](CLAUDE.md) for the architecture overview. The short version:

- `plugins/gemini/` — slash-command plugin (Markdown + bash, no runtime)
- `plugins/gemini-images/` — PreToolUse hook plugin (Node.js + bash)
- `eval/` — promptfoo configs that compare the bare model vs the custom agents
- `docs/plans/`, `docs/specs/` — design docs and specs

## Development workflow

1. Fork & clone.
2. Install the plugin locally for live testing:
   ```
   claude plugin marketplace add .
   claude plugin install gemini --scope project
   # restart Claude Code session
   ```
3. Install the agents into agy — the plugins cannot apply their system prompts without this:
   ```bash
   agy plugin install "$(pwd)/plugins/gemini/agy"           # expect: agents : 3 processed
   agy plugin install "$(pwd)/plugins/gemini-images/agy"    # expect: agents : 1 processed
   ```
4. Iterate. Commands are pure Markdown and take effect on the next run — no build step.

   **Agent definitions do not.** `agy plugin install` *copies* them into `~/.gemini/config/plugins/`, so after editing any `agy/agents/*/agent.md` you must re-run the install for that plugin. Skip it and you will keep testing the previous prompt while reading the new one — and since `--agent` never errors, nothing will tell you.
5. For `gemini-images`, run `bash plugins/gemini-images/scripts/doctor.sh` to verify dependencies (jq, tesseract, optionally imagemagick) and that the agent is installed.

## Running the eval suite

The `eval/` directory uses [promptfoo](https://www.promptfoo.dev/) to compare the bare model against this repo's custom agents across realistic diffs.

Install the agents first — an unknown `--agent` name is silently ignored, so a missing install quietly grades as baseline:

```bash
agy plugin install "$(pwd)/plugins/gemini/agy"
```

```bash
cd eval
npx promptfoo@latest eval -c promptfooconfig.yaml               # review, flash
npx promptfoo@latest eval -c promptfooconfig-pro.yaml           # review, pro
npx promptfoo@latest eval -c promptfooconfig-hard.yaml          # reasoning-heavy set, 3.6 vs 3.7
npx promptfoo@latest eval -c promptfooconfig-flash37.yaml       # 3.6 vs 3.7 vs bare 3.7

# Parked — the security-review command was removed in v0.2.0 (agy declines
# security-audit requests). Configs and test cases are kept for its return.
# npx promptfoo@latest eval -c promptfooconfig-security.yaml
# npx promptfoo@latest eval -c promptfooconfig-security-pro.yaml
```

Each config runs its arms through `agy-provider.js`. An arm is `id: file://agy-provider.js` plus a `config:` block: `model` is required, `agent` selects a custom agent (omit it for the bare model), and `addDir` / `timeout` map to the matching agy flags.

The provider sends the prompt over agy's stdin. Do not replace it with an `exec:` provider that passes the prompt as a shell argument — that is what the old `run-agy.sh` did, and the shell silently ate one level of backslash escaping. A diff containing `replace(/[.*+?^${}()|[\]\\]/g, "\\$&")` arrived as `replace(/[.*+?^${}()|[\]\]/g, "\$&")`, and the model dutifully reported the unterminated character class it was shown. It looks like a hallucination, it reproduces every run, and only cases with consecutive backslashes are hit — so it quietly corrupts a row or two rather than failing the suite. If a finding looks impossible, check what the harness actually sent before doubting the model.

Use promptfoo `@latest`. Older releases send a deprecated `temperature` to current judge models, which fails every grading call with a 400 and reports 0% pass regardless of output quality. A retired judge model gives the same misleading result via 404 — if every case fails, check `gradingResult` before blaming the model under test.

Eval runs hit live agy quota — be signed in via `agy` OAuth.

Before recording a score, check why each red cell is red. Three different things look identical in the summary table: a genuine rubric failure (has a written verdict), a provider error (`agy did not return a response: …`, empty output — a 503, quota, or headless permission denial, already counted separately by promptfoo), and a judge parse failure (`Could not extract JSON from llm-rubric response` or `No output`, while the output field holds a normal review — promptfoo counts this as a failure even though the grading call is what broke). Only the first belongs in a score. The last one hit 4 of 39 cells in one run and 1 of 39 at half the concurrency, so it is worth checking every time.

Expect more run-to-run variance than the pre-0.2.0 numbers. Gemini CLI was pinned to `temperature: 0` through `.gemini/settings.json`; agy exposes no sampling controls at all, so that file was removed and there is nothing to replace it with. Treat a one-case difference between runs as noise, not a regression.

When changing an agent's system prompt, run the relevant eval before and after. A useful guard rail: the custom prompt should not regress on cases the bare model already passes.

## PR checklist

- [ ] Slash commands still work after restart (`/gemini:setup` ≥ smoke test)
- [ ] If you touched an agent's system prompt, re-ran `agy plugin install` and the matching eval suite, and the diff is non-regressive
- [ ] If you touched `gemini-images/hooks/`, `doctor.sh` still passes on your OS
- [ ] No secrets, API keys, or personal paths in commits (the `tools` whitelist in each `agy/agents/*/agent.md` is the second line of defense — keep it minimal)
- [ ] README / CLAUDE.md updated if behavior changed
- [ ] Version bumped and `CHANGELOG.md` updated if the change reaches users — see [Versioning](CLAUDE.md#versioning). Editing an agent's system prompt counts: it does not reach an existing install until they re-run setup, and nothing warns them

## Reporting issues

Please include:

- OS + shell (macOS / Windows Git Bash)
- `claude --version` and `agy --version`
- The slash command + arguments you ran
- Console output (redact any paths or secrets)
