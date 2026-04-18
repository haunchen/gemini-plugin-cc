# gemini-images Plugin Implementation Plan

Goal: 在 gemini-plugin-cc marketplace 新增 `gemini-images` plugin，透過 PreToolUse hook 攔截 Read 圖片檔，以 Gemini CLI 產生的文字描述取代圖片回傳給 Claude，避免 prompt cache 失效。

Architecture: 獨立 plugin 目錄 `plugins/gemini-images/`，PreToolUse hook 由 bash 腳本（攔截 + fallback + OCR 合併）+ Node.js 腳本（呼叫 Gemini CLI）組成。沿用 `GEMINI_SYSTEM_MD` 注入專用 system prompt。圖片前處理三層 fallback（magick → sips → skip）確保 macOS + Windows 跨平台。

Tech Stack: Claude Code Plugin framework, Bash (Git Bash on Windows), Node.js (ESM), Gemini CLI, jq, ImageMagick/sips (optional), tesseract (optional)

Spec: `docs/specs/gemini-images.md`

Design: `docs/plans/2026-04-18-gemini-images-plugin-design.md`

---

### Task 1: 建立 plugin 骨架

Implements: `gemini-images.md` #R2

Files:
- Create: `plugins/gemini-images/.claude-plugin/plugin.json`

Step 1: 建立目錄

Run:
```bash
mkdir -p plugins/gemini-images/.claude-plugin plugins/gemini-images/hooks plugins/gemini-images/system-prompts plugins/gemini-images/scripts
```

Step 2: 寫入 `plugins/gemini-images/.claude-plugin/plugin.json`

```json
{
  "name": "gemini-images",
  "version": "0.1.0",
  "description": "Intercept Claude Code Read on image files and replace with Gemini-generated text descriptions to avoid prompt cache invalidation",
  "author": {
    "name": "Frank Chen"
  },
  "repository": "https://github.com/haunchen/gemini-plugin-cc",
  "license": "MIT",
  "keywords": ["gemini", "image", "ocr", "prompt-cache", "hook"],
  "hooks": {
    "PreToolUse": [{
      "matcher": "Read",
      "hooks": [{
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/hooks/intercept-image-read.sh"
      }]
    }]
  }
}
```

Step 3: 驗證 JSON 格式

Run: `jq . plugins/gemini-images/.claude-plugin/plugin.json`
Expected: 回傳格式化的 JSON，無語法錯誤

Step 4: Commit

```bash
git add plugins/gemini-images/.claude-plugin/plugin.json
git commit -m "feat(gemini-images): scaffold plugin manifest"
```

---

### Task 2: 撰寫 image-describe system prompt

Implements: `gemini-images.md` #R3, #R4

Files:
- Create: `plugins/gemini-images/system-prompts/image-describe.md`

Step 1: 寫入 `plugins/gemini-images/system-prompts/image-describe.md`

```markdown
# Role

你是圖片轉文字助手。使用者會給你一張圖片，你要輸出一段精煉的文字描述，供後續 AI agent 閱讀使用。

## Output Rules

- **長度**：300 個繁體中文字以內。
- **格式**：單一段落。不要使用 markdown、bullet、編號清單、標題。
- **語言**：繁體中文，台灣慣用語。
- **起手句**：第一句明確交代圖片類型（例如：這是一張 VSCode 編輯器截圖 / 這是一張工程圖面 / 這是一張商業簡報投影片 / 這是一張手機介面截圖 / 這是一張照片）。

## What to Preserve

- 程式碼片段（原樣保留關鍵行，不用解釋）
- 錯誤訊息（完整引用）
- UI 文字、按鈕標籤、選單項目
- 圖表數據、數字、百分比、座標
- 零件編號、型號、規格、尺寸標註
- 金額、日期、URL、email
- 檔案路徑、指令、環境變數名稱

## What to Ignore

- 純裝飾性元素（背景紋理、漸層、陰影）
- 無資訊價值的色彩描述
- 排版位置與對齊（除非影響意義）
- 品牌 logo 的視覺細節（只需提到品牌名）

## Style

- 描述性，不推測也不發明圖片沒有的資訊。
- 看不清楚或無法辨識的內容直接說「無法辨識」，不要猜。
- 用詞精準，不要堆砌形容詞。

## What Not To Do

- 不要加客套話（「好的」「讓我來描述」「希望這份描述對你有幫助」等）。
- 不要加前言（「這張圖片顯示了」開頭也不要，直接講內容）。
- 不要加結尾（「如果需要更多資訊請告訴我」等）。
- 不要使用 markdown 語法（**粗體**、`code`、# 標題都不行）。
- 不要輸出 bullet 或編號清單。
- 不要分段，全部擠在一段。
- 不要翻譯原圖內的程式碼或英文錯誤訊息。
```

Step 2: Commit

```bash
git add plugins/gemini-images/system-prompts/image-describe.md
git commit -m "feat(gemini-images): add image-describe system prompt"
```

---

### Task 3: 撰寫 image-describe.mjs

Implements: `gemini-images.md` #R3

Files:
- Create: `plugins/gemini-images/hooks/image-describe.mjs`

Step 1: 寫入 `plugins/gemini-images/hooks/image-describe.mjs`

```javascript
#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));

const imagePath = process.argv[2];
if (!imagePath) {
  process.exit(1);
}

const geminiBin = process.env.GEMINI_BIN || "gemini";
const geminiModel = process.env.GEMINI_MODEL || "flash";
const systemPromptPath = resolve(__dirname, "../system-prompts/image-describe.md");

const prompt = `Read this image: @${imagePath}`;

const args = ["-m", geminiModel, "-o", "text", "-p", prompt];

const result = spawnSync(geminiBin, args, {
  encoding: "utf8",
  stdio: ["ignore", "pipe", "ignore"],
  env: { ...process.env, GEMINI_SYSTEM_MD: systemPromptPath },
});

if (result.status !== 0) {
  process.exit(1);
}

const output = (result.stdout || "").trim();
if (!output) {
  process.exit(1);
}

process.stdout.write(output);
```

Step 2: 設執行權限

Run: `chmod +x plugins/gemini-images/hooks/image-describe.mjs`

Step 3: 手動驗證（需要有一張測試圖片 + gemini CLI 已設定）

Run:
```bash
node plugins/gemini-images/hooks/image-describe.mjs /path/to/any-test-image.png
```
Expected: 輸出一段繁體中文描述（300 字以內、單段、無 markdown）。若 gemini CLI 未設定會 exit 1。

Step 4: Commit

```bash
git add plugins/gemini-images/hooks/image-describe.mjs
git commit -m "feat(gemini-images): add gemini describe invoker with system prompt injection"
```

---

### Task 4: 撰寫 intercept-image-read.sh（含 fallback 與放行策略）

Implements: `gemini-images.md` #R1, #R5, #R6, #R7

Files:
- Create: `plugins/gemini-images/hooks/intercept-image-read.sh`

Step 1: 寫入 `plugins/gemini-images/hooks/intercept-image-read.sh`

```bash
#!/bin/bash
# Intercept Claude Read tool calls for image files.
# Convert the image into a short text description before it enters the main session.

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

case "${FILE_PATH##*.}" in
  png|jpg|jpeg|gif|webp|avif|bmp|tiff|tif|PNG|JPG|JPEG|GIF|WEBP|AVIF|BMP|TIFF|TIF)
    ;;
  *)
    exit 0
    ;;
esac

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TMP_DIR="${TMPDIR:-/tmp}"
TIMESTAMP=$(date +%s)
MAX_WIDTH="${MAX_WIDTH:-1568}"
OCR_BIN="${OCR_BIN:-tesseract}"

DESC_FILE=$(mktemp "${TMP_DIR%/}/claude-image-desc-${TIMESTAMP}-XXXXXX.txt")
WORK_FILE="$FILE_PATH"
RESIZED_FILE="$WORK_FILE"
OCR_FILE=$(mktemp "${TMP_DIR%/}/claude-image-ocr-${TIMESTAMP}-XXXXXX.txt")
GEMINI_FILE=$(mktemp "${TMP_DIR%/}/claude-image-gemini-${TIMESTAMP}-XXXXXX.txt")

cleanup() {
  rm -f "$OCR_FILE" "$GEMINI_FILE" 2>/dev/null || true
  if [ "$RESIZED_FILE" != "$WORK_FILE" ]; then
    rm -f "$RESIZED_FILE" 2>/dev/null || true
  fi
  if [ "$WORK_FILE" != "$FILE_PATH" ]; then
    rm -f "$WORK_FILE" 2>/dev/null || true
  fi
}
trap cleanup EXIT

convert_if_needed() {
  case "${FILE_PATH##*.}" in
    avif|AVIF|bmp|BMP|tiff|tif|TIFF|TIF)
      local converted
      converted=$(mktemp "${TMP_DIR%/}/claude-image-convert-${TIMESTAMP}-XXXXXX.jpg")
      if command -v magick >/dev/null 2>&1; then
        if magick "$FILE_PATH" "$converted" >/dev/null 2>&1; then
          WORK_FILE="$converted"
          return 0
        fi
      fi
      if command -v sips >/dev/null 2>&1; then
        if sips -s format jpeg "$FILE_PATH" --out "$converted" >/dev/null 2>&1; then
          WORK_FILE="$converted"
          return 0
        fi
      fi
      rm -f "$converted" >/dev/null 2>&1 || true
      ;;
  esac
}

resize_if_needed() {
  local resized
  resized=$(mktemp "${TMP_DIR%/}/claude-image-resize-${TIMESTAMP}-XXXXXX.jpg")

  if command -v magick >/dev/null 2>&1; then
    local width
    width=$(magick identify -format '%w' "$WORK_FILE" 2>/dev/null || echo "")
    if [ -z "$width" ] || [ "$width" -le "$MAX_WIDTH" ] 2>/dev/null; then
      rm -f "$resized" >/dev/null 2>&1 || true
      return 0
    fi
    if magick "$WORK_FILE" -resize "${MAX_WIDTH}x>" -quality 80 "$resized" >/dev/null 2>&1; then
      RESIZED_FILE="$resized"
      return 0
    fi
    rm -f "$resized" >/dev/null 2>&1 || true
    return 0
  fi

  if command -v sips >/dev/null 2>&1; then
    local width
    width=$(sips -g pixelWidth "$WORK_FILE" 2>/dev/null | awk '/pixelWidth/ {print $2}')
    if [ -z "$width" ] || [ "$width" -le "$MAX_WIDTH" ] 2>/dev/null; then
      rm -f "$resized" >/dev/null 2>&1 || true
      return 0
    fi
    if sips --resampleWidth "$MAX_WIDTH" -s format jpeg -s formatOptions 80 "$WORK_FILE" --out "$resized" >/dev/null 2>&1; then
      RESIZED_FILE="$resized"
      return 0
    fi
    rm -f "$resized" >/dev/null 2>&1 || true
    return 0
  fi

  rm -f "$resized" >/dev/null 2>&1 || true
}

run_ocr() {
  if [ "$OCR_BIN" = "none" ] || [ -z "$OCR_BIN" ]; then
    return 0
  fi

  if ! command -v "$OCR_BIN" >/dev/null 2>&1; then
    return 0
  fi

  "$OCR_BIN" "$RESIZED_FILE" stdout 2>/dev/null || true
}

convert_if_needed
resize_if_needed

run_ocr > "$OCR_FILE" &
OCR_PID=$!

node "$SCRIPT_DIR/image-describe.mjs" "$RESIZED_FILE" > "$GEMINI_FILE" 2>/dev/null &
GEMINI_PID=$!

wait "$OCR_PID" 2>/dev/null || true
wait "$GEMINI_PID" 2>/dev/null || true

GEMINI_DESC=$(cat "$GEMINI_FILE" 2>/dev/null || true)
OCR_TEXT=$(cat "$OCR_FILE" 2>/dev/null || true)

if [ -z "$GEMINI_DESC" ] && [ -z "$OCR_TEXT" ]; then
  echo "[gemini-images] Both Gemini and OCR failed for $FILE_PATH; letting Claude read the original image." >&2
  rm -f "$DESC_FILE" >/dev/null 2>&1 || true
  exit 0
fi

{
  echo "[Image: $(basename "$FILE_PATH")]"
  echo
  if [ -n "$GEMINI_DESC" ]; then
    echo "$GEMINI_DESC"
  fi
  if [ -n "$OCR_TEXT" ]; then
    echo
    if [ -n "$GEMINI_DESC" ]; then
      echo "[OCR Supplement]"
    else
      echo "[OCR Text]"
    fi
    echo "$OCR_TEXT"
  fi
} > "$DESC_FILE"

jq -n --arg path "$DESC_FILE" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    updatedInput: { file_path: $path },
    additionalContext: "The image was converted into a text description before entering the main session to reduce Claude cache churn."
  }
}'
```

Step 2: 設執行權限

Run: `chmod +x plugins/gemini-images/hooks/intercept-image-read.sh`

Step 3: 手動驗證非圖片檔放行

Run:
```bash
echo '{"tool_input":{"file_path":"plugins/gemini-images/hooks/intercept-image-read.sh"}}' | plugins/gemini-images/hooks/intercept-image-read.sh
```
Expected: 無輸出、exit 0（非圖片檔直接放行）

Step 4: 手動驗證缺少 file_path 放行

Run:
```bash
echo '{"tool_input":{}}' | plugins/gemini-images/hooks/intercept-image-read.sh
```
Expected: 無輸出、exit 0

Step 5: Commit

```bash
git add plugins/gemini-images/hooks/intercept-image-read.sh
git commit -m "feat(gemini-images): add PreToolUse interceptor with magick/sips fallback"
```

---

### Task 5: 撰寫 doctor.sh

Implements: `gemini-images.md` #R9

Files:
- Create: `plugins/gemini-images/scripts/doctor.sh`

Step 1: 寫入 `plugins/gemini-images/scripts/doctor.sh`

```bash
#!/bin/bash
# Environment diagnostic for gemini-images plugin.
# Usage: doctor.sh [--verbose]

set -uo pipefail

VERBOSE=0
for arg in "$@"; do
  case "$arg" in
    --verbose|-v) VERBOSE=1 ;;
  esac
done

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PLUGIN_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
STATUS=0

ok()   { echo "[OK]   $1"; }
fail() { echo "[FAIL] $1"; STATUS=1; }
warn() { echo "[WARN] $1"; }
skip() { echo "[SKIP] $1"; }

check_required_cmd() {
  if command -v "$1" >/dev/null 2>&1; then
    ok "command: $1"
  else
    fail "command: $1 not found"
  fi
}

check_optional_cmd() {
  if command -v "$1" >/dev/null 2>&1; then
    ok "optional: $1"
  else
    warn "optional: $1 not found ($2)"
  fi
}

check_file() {
  if [ -f "$1" ]; then
    ok "file: $1"
  else
    fail "file: $1 missing"
  fi
}

echo "== Required =="
check_required_cmd gemini
check_required_cmd node
check_required_cmd jq
check_file "$PLUGIN_DIR/.claude-plugin/plugin.json"
check_file "$PLUGIN_DIR/hooks/intercept-image-read.sh"
check_file "$PLUGIN_DIR/hooks/image-describe.mjs"
check_file "$PLUGIN_DIR/system-prompts/image-describe.md"

if command -v gemini >/dev/null 2>&1; then
  if gemini --help >/dev/null 2>&1; then
    ok "gemini CLI runnable"
  else
    fail "gemini CLI installed but fails to run (check OAuth)"
  fi
fi

echo
echo "== Optional =="
check_optional_cmd magick "image resize/convert; install via 'brew install imagemagick' or 'winget install ImageMagick.ImageMagick'"
check_optional_cmd sips "macOS native image tool; no install needed on macOS, skipped on Windows"
check_optional_cmd tesseract "OCR supplement; install via 'brew install tesseract tesseract-lang' or 'winget install UB-Mannheim.TesseractOCR'"

if command -v tesseract >/dev/null 2>&1; then
  if tesseract --list-langs 2>&1 | grep -q '^chi_tra$'; then
    ok "tesseract language: chi_tra"
  else
    warn "tesseract language: chi_tra not installed (Chinese OCR unavailable)"
  fi
fi

if [ "$VERBOSE" = "1" ]; then
  echo
  echo "== Environment =="
  echo "PLUGIN_DIR: $PLUGIN_DIR"
  echo "GEMINI_MODEL: ${GEMINI_MODEL:-flash (default)}"
  echo "MAX_WIDTH: ${MAX_WIDTH:-1568 (default)}"
  echo "OCR_BIN: ${OCR_BIN:-tesseract (default)}"
  echo "GEMINI_BIN: ${GEMINI_BIN:-gemini (default)}"
  echo "TMPDIR: ${TMPDIR:-/tmp (default)}"
  echo "OS: $(uname -s)"
  if command -v gemini >/dev/null 2>&1; then
    echo "gemini version: $(gemini --version 2>&1 | head -1)"
  fi
  if command -v node >/dev/null 2>&1; then
    echo "node version: $(node --version)"
  fi
fi

echo
if [ "$STATUS" -ne 0 ]; then
  echo "Required checks failed. See README Troubleshooting for fixes."
else
  echo "See README Troubleshooting for fixes if you hit runtime issues."
fi

exit "$STATUS"
```

Step 2: 設執行權限

Run: `chmod +x plugins/gemini-images/scripts/doctor.sh`

Step 3: 驗證 doctor.sh 可運作

Run: `bash plugins/gemini-images/scripts/doctor.sh`
Expected: 顯示 Required + Optional 兩區塊。若本機環境齊全，`exit 0`。

Step 4: 驗證 --verbose 旗標

Run: `bash plugins/gemini-images/scripts/doctor.sh --verbose`
Expected: 額外輸出 Environment 區塊，列出 PLUGIN_DIR、環境變數預設值、OS、gemini/node 版本。

Step 5: Commit

```bash
git add plugins/gemini-images/scripts/doctor.sh
git commit -m "feat(gemini-images): add doctor.sh environment diagnostic"
```

---

### Task 6: 撰寫 plugin 層 README

Implements: `gemini-images.md` (documentation)

Files:
- Create: `plugins/gemini-images/README.md`

Step 1: 寫入 `plugins/gemini-images/README.md`

```markdown
# gemini-images

A Claude Code plugin that intercepts `Read` calls on image files and replaces them with Gemini-generated text descriptions, preventing image bytes from invalidating Anthropic's prompt cache.

## What & Why

Anthropic's prompt cache is invalidated when inline images change in a prompt ([docs](https://docs.claude.com/en/docs/build-with-claude/prompt-caching)). In a long Claude Code session, every screenshot or diagram you ask Claude to read silently blows away your cache hit rate — and your wallet.

This plugin hooks into `PreToolUse` for the `Read` tool, detects image files by extension, and calls Gemini CLI to produce a compact text description. Claude receives the description instead of the image, the cache stays warm, and you still get the information.

## How It Works

```
Claude Code
  Read(image.png) ──► PreToolUse hook
                        │
                        ├── resize (magick → sips → skip)
                        ├── spawn Gemini CLI with GEMINI_SYSTEM_MD
                        └── parallel: tesseract OCR
                        │
                        └──► updatedInput.file_path = desc.txt
                             Claude reads text, not image
```

Sister plugin `gemini` provides slash commands (`/gemini:review`, `/gemini:ask`, etc.) and shares the same Gemini CLI OAuth credentials — install whichever ones you want.

## Prerequisites

### macOS

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview)
- [Gemini CLI](https://github.com/google-gemini/gemini-cli): `npm install -g @google/gemini-cli`
- `jq`: `brew install jq`
- Node.js (bundled with Gemini CLI's install)
- **Optional**: `brew install imagemagick tesseract tesseract-lang`

### Windows (Git Bash)

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview)
- [Gemini CLI](https://github.com/google-gemini/gemini-cli)
- Git Bash (provides `bash`, `jq` built-in)
- Node.js
- **Optional**: `winget install ImageMagick.ImageMagick UB-Mannheim.TesseractOCR`

Linux is not supported.

## Installation

```
/plugin marketplace add https://github.com/haunchen/gemini-plugin-cc
/plugin install gemini-images
```

Restart Claude Code after installation.

## Verification

Run the diagnostic:

```bash
bash plugins/gemini-images/scripts/doctor.sh
```

Required checks must all pass. Optional warnings are fine for basic use but reduce quality.

## Configuration

| Variable | Default | Purpose |
|----------|---------|---------|
| `GEMINI_MODEL` | `flash` | Model passed to Gemini CLI `-m` |
| `MAX_WIDTH` | `1568` | Resize ceiling (pixels) |
| `OCR_BIN` | `tesseract` | OCR binary; set to `none` to disable |
| `GEMINI_BIN` | `gemini` | Gemini CLI binary name |

Set these in your shell profile or per-session before launching Claude Code.

## Troubleshooting

**Hook runs but Claude still sees images**
Confirm the plugin is loaded: `/plugin list` should show `gemini-images`. Restart Claude Code after install.

**Gemini CLI fails with OAuth error**
Run `gemini` interactively once to complete Google OAuth.

**Chinese text missing from OCR**
Install `chi_tra` language pack: `brew install tesseract-lang` (macOS) or download from UB-Mannheim GitHub releases (Windows).

**Large images time out**
Install ImageMagick to enable resize. Without resize, Gemini receives the original image and may hit token limits.

## Uninstall

```
/plugin uninstall gemini-images
```

## Limitations

- Engineering drawings lose fine-grained detail at 300-character output limits.
- Handwriting recognition is unreliable (both Gemini and tesseract).
- Hook failure silently passes through to original image Read — check stderr for warnings.
- No per-image opt-out; uninstall if you need to keep specific images intact.
```

Step 2: Commit

```bash
git add plugins/gemini-images/README.md
git commit -m "docs(gemini-images): add plugin README with troubleshooting"
```

---

### Task 7: 註冊到 marketplace

Implements: `gemini-images.md` #R2

Files:
- Modify: `.claude-plugin/marketplace.json`

Step 1: 將 `.claude-plugin/marketplace.json` 完整替換為：

```json
{
  "name": "gemini-plugin-cc",
  "owner": {
    "name": "Frank Chen"
  },
  "plugins": [
    {
      "name": "gemini",
      "description": "Get a second opinion from Gemini on your code reviews",
      "version": "0.1.0",
      "author": {
        "name": "Frank Chen"
      },
      "source": "./plugins/gemini",
      "category": "development"
    },
    {
      "name": "gemini-images",
      "description": "Intercept Read on image files and replace with Gemini text descriptions to protect prompt cache",
      "version": "0.1.0",
      "author": {
        "name": "Frank Chen"
      },
      "source": "./plugins/gemini-images",
      "category": "development"
    }
  ]
}
```

Step 2: 驗證 JSON 格式

Run: `jq . .claude-plugin/marketplace.json`
Expected: 正確格式化兩個 plugin 項目。

Step 3: Commit

```bash
git add .claude-plugin/marketplace.json
git commit -m "feat(marketplace): register gemini-images plugin"
```

---

### Task 8: 重構根 README

Implements: `gemini-images.md` (documentation)

Files:
- Modify: `README.md`

Step 1: 將根 `README.md` 完整替換為：

```markdown
# gemini-plugin-cc

A marketplace of [Claude Code plugins](https://docs.anthropic.com/en/docs/claude-code/plugins) that integrate [Gemini CLI](https://github.com/google-gemini/gemini-cli) — get a second opinion on code, and keep your prompt cache warm while reading images.

## Plugins

| Plugin | Purpose | Triggers |
|--------|---------|----------|
| [`gemini`](plugins/gemini/) | Slash commands for code review, ask, adversarial review, security review | `/gemini:*` |
| [`gemini-images`](plugins/gemini-images/) | PreToolUse hook that converts image Reads into text descriptions to protect prompt cache | Automatic on `Read` image files |

Both plugins share the same Gemini CLI OAuth credentials. Install one or both.

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview) installed
- [Gemini CLI](https://github.com/google-gemini/gemini-cli) installed (`npm install -g @google/gemini-cli`)
- `GEMINI_API_KEY` environment variable, or authenticated via `gemini` OAuth

Plugin-specific extra dependencies are listed in each plugin's README.

## Installation

```
/plugin marketplace add https://github.com/haunchen/gemini-plugin-cc
/plugin install gemini
/plugin install gemini-images
```

Restart Claude Code after installation.

For `gemini`, run `/gemini:setup` to verify.
For `gemini-images`, run `bash plugins/gemini-images/scripts/doctor.sh` to verify.

## Commands (gemini plugin)

- `/gemini:setup` — check CLI, version, OAuth
- `/gemini:review [path] [--model <m>]` — code review (default model: Pro with Flash fallback)
- `/gemini:ask <question> [file] [--model <m>]` — free-form technical question
- `/gemini:adversarial-review [path] [--model <m>]` — devil's advocate design challenge
- `/gemini:security-review [path] [--model <m>]` — OWASP-focused security review

## Project Structure

```
gemini-plugin-cc/
├── .claude-plugin/
│   └── marketplace.json          # Marketplace registry
├── plugins/
│   ├── gemini/                   # Slash-command plugin
│   │   ├── .claude-plugin/plugin.json
│   │   ├── commands/
│   │   └── system-prompts/
│   └── gemini-images/            # PreToolUse hook plugin
│       ├── .claude-plugin/plugin.json
│       ├── hooks/
│       ├── system-prompts/
│       ├── scripts/doctor.sh
│       └── README.md
└── docs/
    ├── plans/                    # Design + implementation plans
    └── specs/                    # Feature specs
```

## License

MIT
```

Step 2: Commit

```bash
git add README.md
git commit -m "docs: reposition README as marketplace, add gemini-images entry"
```

---

### Task 9: 本機安裝驗證（macOS）

Implements: E2E 驗收

Files:
- None (manual verification)

Step 1: 註冊 marketplace 並安裝 plugin

Run:
```bash
claude plugin marketplace add .
claude plugin install gemini-images --scope project
```
Expected: 無錯誤，`claude plugin list` 可看到 `gemini-images`。

Step 2: 重啟 Claude Code session

（plugin 需要重啟才載入 hook）

Step 3: 跑 doctor

Run:
```bash
bash plugins/gemini-images/scripts/doctor.sh --verbose
```
Expected: Required 全 `[OK]`，Optional 依本機狀況顯示 `[OK]` / `[WARN]`，Environment 區塊顯示版本資訊。

Step 4: 準備測試圖片

Run:
```bash
mkdir -p /tmp/gemini-images-test
# 準備一張含中文或程式碼的截圖，或用任何現成 PNG
cp ~/Desktop/screenshot.png /tmp/gemini-images-test/test.png 2>/dev/null || \
  curl -s -o /tmp/gemini-images-test/test.png https://via.placeholder.com/800x600.png
ls -la /tmp/gemini-images-test/test.png
```
Expected: `/tmp/gemini-images-test/test.png` 存在。

Step 5: 手動觸發 hook（模擬 Claude Code 的 stdin 格式）

Run:
```bash
echo '{"tool_input":{"file_path":"/tmp/gemini-images-test/test.png"}}' | \
  plugins/gemini-images/hooks/intercept-image-read.sh
```
Expected: 輸出 JSON 含 `hookSpecificOutput.updatedInput.file_path`，該路徑指向 `/tmp/claude-image-desc-*.txt`；檢視該檔案應看到繁體中文描述（+ 若有 tesseract 則有 `[OCR Supplement]`）。

Step 6: 在 Claude Code session 內實測

在 Claude Code 內請 Claude 執行 `Read /tmp/gemini-images-test/test.png`。

Expected: Claude 看到的是文字描述，不是圖片；回應內容能準確反映圖片內的文字/程式碼/介面。

Step 7: 非圖片檔不受影響驗證

在 Claude Code 內請 Claude 執行 `Read plugins/gemini-images/README.md`。

Expected: Claude 正常讀到 README 原始內容，hook 放行。

Step 8: Commit（若驗證過程有 fix 才需）

若 Task 1–8 的程式碼在實測中需要微調，建立 fix commit；否則跳過此步。

---

### Task 10: 本機安裝驗證（Windows Git Bash）

Implements: `gemini-images.md` #R8

Files:
- None (manual verification, Windows machine required)

Step 1: 在 Windows 機器 clone 分支

Run (Git Bash):
```bash
git clone https://github.com/haunchen/gemini-plugin-cc.git
cd gemini-plugin-cc
git checkout feat/gemini-images-plugin
```

Step 2: 安裝 plugin

Run:
```bash
claude plugin marketplace add .
claude plugin install gemini-images --scope project
```
Expected: 無錯誤。

Step 3: 跑 doctor

Run: `bash plugins/gemini-images/scripts/doctor.sh --verbose`
Expected: Required 全 `[OK]`；若未裝 magick 會 `[WARN]`（需裝 `winget install ImageMagick.ImageMagick`）；sips 預期 `[WARN]`（Windows 無）。

Step 4: 驗證 Windows path 處理

準備一張圖片於 `C:\Users\<user>\Pictures\test.png`，在 Claude Code 內 `Read C:\Users\<user>\Pictures\test.png`。

Expected: hook 正確處理路徑；若失敗則需調查 `file_path` 在 Windows 是 Unix style 還是 Windows style，在 `intercept-image-read.sh` 加入路徑轉換。

Step 5: 驗證 `${CLAUDE_PLUGIN_ROOT}` 展開

檢查 hook 實際被呼叫的路徑是否正確（可在 hook 內暫時加 `echo "CLAUDE_PLUGIN_ROOT=$CLAUDE_PLUGIN_ROOT" >&2` 診斷）。

Step 6: 回報結果

若 Windows 有問題：
- 在同 branch 修 bug、commit、推回
- 在 PR 描述補記已驗證的情境

若完全通過：
- 在 PR 描述註明「macOS + Windows 皆驗證通過」

---

## 完成流程

所有 task 通過後，由 `/dev:finish` 處理：
1. 最終驗證 → 2. spec sync（status: draft → active，清空 Pending Changes）→ 3. commit spec 變更 → 4. push branch → 5. 開 PR。
