# Contributing

Thanks for your interest. This repo is a Claude Code plugin marketplace; PRs that improve the system prompts, harden the read-only policy, or extend OS support are especially welcome.

## Repo layout

See [CLAUDE.md](CLAUDE.md) for the architecture overview. The short version:

- `plugins/gemini/` — slash-command plugin (Markdown + bash, no runtime)
- `plugins/gemini-images/` — PreToolUse hook plugin (Node.js + bash)
- `eval/` — promptfoo configs that compare default vs custom system prompts
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

The `eval/` directory uses [promptfoo](https://www.promptfoo.dev/) to compare the default Gemini system prompt against this repo's custom prompt across realistic diffs.

```bash
# Code review eval (default vs custom × flash vs pro)
eval/run-gemini.sh                 # custom prompt × flash
eval/run-gemini-pro.sh             # custom prompt × pro
eval/run-gemini-default.sh         # default prompt × flash
eval/run-gemini-default-pro.sh     # default prompt × pro

# Security review eval
eval/run-gemini-security.sh
eval/run-gemini-security-pro.sh
eval/run-gemini-security-default.sh
eval/run-gemini-security-default-pro.sh
```

Eval runs hit live Gemini quota — keep a `GEMINI_API_KEY` handy or be signed in via `gemini` OAuth.

When changing a system prompt, run the relevant eval before and after. A useful guard rail: the custom prompt should not regress on cases the default prompt already passes.

## PR checklist

- [ ] Slash commands still work after restart (`/gemini:setup` ≥ smoke test)
- [ ] If you touched a system prompt, ran the matching eval suite and the diff is non-regressive
- [ ] If you touched `gemini-images/hooks/`, `doctor.sh` still passes on your OS
- [ ] No secrets, API keys, or personal paths in commits (the read-only policy at `plugins/gemini/policies/readonly.toml` is the second line of defense — keep it strict)
- [ ] README / CLAUDE.md updated if behavior changed

## Reporting issues

Please include:

- OS + shell (macOS / Windows Git Bash)
- `claude --version` and `gemini --version`
- The slash command + arguments you ran
- Console output (redact any paths or secrets)
