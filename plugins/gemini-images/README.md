# gemini-images

A Claude Code plugin that intercepts `Read` calls on image files and replaces them with Gemini-generated text descriptions, preventing image bytes from invalidating Anthropic's prompt cache.

## What & Why

Anthropic's prompt cache is invalidated when inline images change in a prompt ([docs](https://docs.claude.com/en/docs/build-with-claude/prompt-caching)). In a long Claude Code session, every screenshot or diagram you ask Claude to read silently blows away your cache hit rate — and your wallet.

This plugin hooks into `PreToolUse` for the `Read` tool, detects image files by extension, and calls agy (Antigravity CLI) to produce a compact text description. Claude receives the description instead of the image, the cache stays warm, and you still get the information.

## How It Works

```
Claude Code
  Read(image.png) ──► PreToolUse hook
                        │
                        ├── resize (magick → sips → skip)
                        ├── spawn agy with --agent gemini-image-describe
                        └── parallel: tesseract OCR
                        │
                        └──► updatedInput.file_path = desc.txt
                             Claude reads text, not image
```

Sister plugin `gemini` provides slash commands (`/gemini:review`, `/gemini:ask`, etc.) and shares the same agy OAuth credentials — install whichever ones you want.

## Prerequisites

### macOS

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview)
- [Antigravity CLI](https://antigravity.google) 1.1.6+, plus `agy plugin install <repo>/plugins/gemini-images/agy`
- `jq`: `brew install jq`
- Node.js
- **Strongly recommended** (matches the default `OCR_LANG=chi_tra+eng`): `brew install tesseract tesseract-lang`
- **Optional**: `brew install imagemagick`

### Windows (Git Bash)

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview)
- [Antigravity CLI](https://antigravity.google)
- Git Bash (provides `bash`)
- `jq`: download from https://jqlang.github.io/jq/download/ or `winget install jqlang.jq`
- Node.js
- **Strongly recommended** (matches the default `OCR_LANG=chi_tra+eng`): `winget install UB-Mannheim.TesseractOCR` (select Traditional Chinese in the installer)
- **Optional**: `winget install ImageMagick.ImageMagick`

Linux is not supported.

## Installation

**1. Install the plugin in Claude Code**

```
/plugin marketplace add https://github.com/haunchen/gemini-plugin-cc
/plugin install gemini-images
```

Restart Claude Code — plugins are not picked up until you do.

**2. Install the agent into agy**

Required. `agy` cannot take a system prompt per call, so the image-describe prompt has to be registered with it up front. From a clone of this repo:

```bash
agy plugin install "$(pwd)/plugins/gemini-images/agy"
```

Expect `agents : 1 processed`. Re-running upgrades in place.

Without this step the hook still returns a description, but a generic one — `--agent` silently ignores names it does not recognise, so nothing reports an error. Descriptions will be markdown-formatted, English or Simplified Chinese, and padded with filler instead of the compact single paragraph the prompt specifies.

## Verification

Run the diagnostic from the repository root:

```bash
bash plugins/gemini-images/scripts/doctor.sh
```

Required checks must all pass — including `agent installed: gemini-image-describe`, which is the check for step 2 above. Optional warnings are fine for basic use but reduce quality.

## Configuration

| Variable | Default | Purpose |
|----------|---------|---------|
| `AGY_MODEL` | `gemini-3.6-flash-high` | Model passed to agy `--model` |
| `MAX_WIDTH` | `1568` | Resize ceiling (pixels) |
| `OCR_BIN` | `tesseract` | OCR binary; set to `none` to disable |
| `OCR_LANG` | `chi_tra+eng` | tesseract `-l` value. Falls back to default if the pack is missing. |
| `AGY_BIN` | `agy` | agy binary name |

Set these in your shell profile or per-session before launching Claude Code.

## Troubleshooting

**Hook runs but Claude still sees images**
Confirm the plugin is loaded: `/plugin list` should show `gemini-images`. Restart Claude Code after install.

**agy fails with OAuth error**
Run `gemini` interactively once to complete Google OAuth.

**Chinese text missing or garbled in OCR**
Default `OCR_LANG=chi_tra+eng` needs the `chi_tra` pack. Install via `brew install tesseract-lang` (macOS) or pick Traditional Chinese in UB-Mannheim's Windows installer. Override with e.g. `OCR_LANG=eng` if you don't want Chinese.

**Gemini describes the wrong image / makes up content**
Usually means agy couldn't actually load the file — `-p` mode doesn't always refresh a stale OAuth token. Run `agy` interactively once to refresh, then retry. The hook already passes `--add-dir <image dir>` so workspace sandboxing shouldn't be the culprit. Also confirm the agent is installed: `agy plugin install <repo>/plugins/gemini-images/agy` (an unknown `--agent` name is silently ignored, yielding a generic description).

**Large images time out**
Install ImageMagick to enable resize. Without resize, Gemini receives the original image and may hit token limits.

## Uninstall

```
/plugin uninstall gemini-images
```

The agent lives in agy, not in Claude Code, so remove it separately or it stays behind:

```bash
agy plugin uninstall gemini-images-agents
```

## Limitations

- **Only intercepts explicit `Read` tool calls.** Images pasted or dragged directly into the chat arrive as message content blocks and bypass this hook. Claude Code's hook system does not currently expose those attachments — `UserPromptSubmit` only sees the prompt text, never the image content. The plugin therefore protects prompt cache for agent-driven `Read(image.png)` flows, not for images you attach to a user message.
- Engineering drawings lose fine-grained detail at 300-character output limits.
- Handwriting recognition is unreliable (both Gemini and tesseract).
- Hook failure silently passes through to original image Read — check stderr for warnings.
- No per-image opt-out; uninstall if you need to keep specific images intact.
