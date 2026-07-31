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
3. Iterate on commands or system prompts. Commands are pure Markdown — no build step.
4. For `gemini-images`, run `bash plugins/gemini-images/scripts/doctor.sh` to verify dependencies (jq, tesseract, optionally imagemagick).

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
npx promptfoo@latest eval -c promptfooconfig-security.yaml      # security, flash
npx promptfoo@latest eval -c promptfooconfig-security-pro.yaml  # security, pro
```

Each config runs two providers — bare model vs custom agent — through the shared `run-agy.sh <agent|-> <model-slug>` runner.

Use promptfoo `@latest`. Older releases send a deprecated `temperature` to current judge models, which fails every grading call with a 400 and reports 0% pass regardless of output quality. A retired judge model gives the same misleading result via 404 — if every case fails, check `gradingResult` before blaming the model under test.

Eval runs hit live agy quota — be signed in via `agy` OAuth.

When changing an agent's system prompt, run the relevant eval before and after. A useful guard rail: the custom prompt should not regress on cases the bare model already passes.

## PR checklist

- [ ] Slash commands still work after restart (`/gemini:setup` ≥ smoke test)
- [ ] If you touched an agent's system prompt, re-ran `agy plugin install` and the matching eval suite, and the diff is non-regressive
- [ ] If you touched `gemini-images/hooks/`, `doctor.sh` still passes on your OS
- [ ] No secrets, API keys, or personal paths in commits (the `tools` whitelist in each `agy/agents/*/agent.md` is the second line of defense — keep it minimal)
- [ ] README / CLAUDE.md updated if behavior changed

## Reporting issues

Please include:

- OS + shell (macOS / Windows Git Bash)
- `claude --version` and `agy --version`
- The slash command + arguments you ran
- Console output (redact any paths or secrets)
