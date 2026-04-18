# gemini-images Plugin 設計

## 概要

在既有 gemini-plugin-cc marketplace 新增第二個 plugin `gemini-images`，透過 PreToolUse hook 攔截 Read 工具對圖片檔的讀取，改以 Gemini CLI 產生的文字描述回傳，避免 prompt 含圖片導致 Anthropic prompt cache 失效。與 `gemini` plugin 共用 marketplace 與 OAuth，獨立版號從 0.1.0 起步。

靈感來源：HCYT/agent-cookbook 的 `claude-cache-safe-images` hook，重寫成 Claude Code Plugin 形式並替換 Gemini system prompt。

對應 spec：`docs/specs/gemini-images.md`

## 設計決策

### D1: 獨立 plugin 共用基礎設施
新建 `plugins/gemini-images/`，不擴充既有 `gemini` plugin。觸發面（PreToolUse hook）與生命週期都跟 slash command 不同，獨立版號讓兩個 plugin 各自演進；共用同一 marketplace 與 Gemini OAuth，成本極低。

### D2: System Prompt 取代而非追加
沿用 gemini-plugin-cc 既有的 `GEMINI_SYSTEM_MD` pattern，但這個場景要完全取代 Gemini 預設 system prompt。User prompt 極簡化為 `Read this image: @${path}`，所有規則（輸出長度、格式限制、保留/忽略清單、台灣慣用語、Gemini 3 Pro 客套話壓制）集中在 system prompt。

### D3: OCR 預設開啟，平行補強
`OCR_BIN=tesseract`、要求 `chi_tra` 語言包。OCR 與 Gemini 描述平行跑，結果以 `[OCR Supplement]` 段落附加於描述之後。Gemini 對中文圖表/截圖的文字辨識仍有遺漏，OCR 可補；使用者主要場景為中文。

### D4: 雙失敗放行而非寫假描述
Gemini 與 OCR 皆失敗時 hook 不輸出 `updatedInput`，Claude 照原流程讀原圖；stderr 印警告。單邊失敗照樣輸出成功那邊的結果。不以「無法描述」字串取代描述——一次 cache 失效可接受，誤導 Claude 不可接受。

### D5: 三層 Fallback 而非硬綁工具
圖片 resize 與 format conversion 依序嘗試 `magick`（跨平台首選）→ `sips`（macOS 原生備援）→ 略過（傳原圖給 Gemini）。Windows 無 sips、macOS 預設無 magick，三層涵蓋所有組合。

### D6: 無停用開關
不提供環境變數關閉攔截，要關就 uninstall plugin。plugin 粒度已足夠細，啟停交由 plugin 生命週期管理，避免過度設計。

### D7: 跨平台限於 macOS + Windows
Windows 透過 Git Bash 執行 shell。不支援 Linux，使用者不用。

## 架構

```
┌─────────────────────────────────────────────────────────┐
│ Claude Code                                             │
│   Read(image.png) ──► PreToolUse hook ◄─────┐           │
└─────────────────────────────────────────────┼───────────┘
                                              │
                  ┌───────────────────────────▼──────────┐
                  │ intercept-image-read.sh              │
                  │   1. 判斷副檔名是否為圖片            │
                  │   2. resize/convert (magick→sips→×)  │
                  │   3. 呼叫 image-describe.mjs         │
                  │   4. 平行跑 tesseract OCR            │
                  │   5. 合併結果，輸出 updatedInput     │
                  └───────────────┬──────────────────────┘
                                  │
                  ┌───────────────▼──────────────────────┐
                  │ image-describe.mjs                   │
                  │   GEMINI_SYSTEM_MD=image-describe.md │
                  │   gemini -o text @${path}            │
                  └──────────────────────────────────────┘
```

## 檔案清單

新增：
- `plugins/gemini-images/.claude-plugin/plugin.json` — hook 註冊
- `plugins/gemini-images/hooks/intercept-image-read.sh` — 攔截 + magick/sips fallback + OCR 合併
- `plugins/gemini-images/hooks/image-describe.mjs` — spawn gemini，注入 `GEMINI_SYSTEM_MD`
- `plugins/gemini-images/system-prompts/image-describe.md` — 取代 Gemini 預設 system prompt
- `plugins/gemini-images/scripts/doctor.sh` — 環境診斷
- `plugins/gemini-images/README.md` — plugin 層說明（英文）

修改：
- `.claude-plugin/marketplace.json` — 新增 `gemini-images` 項目
- `README.md`（根目錄）— 重新定位為「marketplace of Gemini-powered plugins」，新增 Plugins 章節對比表，Installation 改為 `marketplace add` → `plugin install <name>` 兩步

文件：
- `docs/specs/gemini-images.md` — spec 草稿
- `docs/plans/2026-04-18-gemini-images-plugin-design.md` — 本文件

## 元件規格

### plugin.json
```json
{
  "name": "gemini-images",
  "version": "0.1.0",
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

### intercept-image-read.sh
- 輸入：stdin JSON 含 `tool_input.file_path`
- 副檔名白名單比對：png/jpg/jpeg/gif/webp/avif/bmp/tiff
- `resize_if_needed()`：三層 fallback（magick → sips → skip）
- `convert_if_needed()`：同樣三層 fallback
- 呼叫 `image-describe.mjs` 取得描述
- 平行呼叫 `tesseract` 取得 OCR 文字（若 `OCR_BIN=tesseract` 且可用）
- 合併輸出：描述 + `\n\n[OCR Supplement]\n` + OCR 結果
- 雙失敗：`exit 0` 不輸出 `updatedInput`，stderr 印警告

### image-describe.mjs
- `spawn('gemini', ['-o', 'text', '-m', model])`
- 環境變數：`GEMINI_SYSTEM_MD = resolve(__dirname, '../system-prompts/image-describe.md')`
- User prompt：`Read this image: @${imagePath}`
- 所有描述規則集中在 system prompt，user prompt 最精簡

### system-prompts/image-describe.md
核心規則（細節見實作）：
- Role：圖片轉文字助手
- 長度：300 字以內繁體中文
- 格式：單段落、無 markdown、無 bullet
- 保留：程式碼、錯誤訊息、UI 文字、圖表數據、零件編號、金額、URL
- 忽略：純裝飾、無意義色彩、排版位置
- 起手句：明確類型（截圖/工程圖/簡報等）
- 風格：台灣慣用語、描述性不推測、無法辨識就承認
- What Not To Do：針對 Gemini 3 Pro 客套話問題的明確禁令

### doctor.sh
- 預設輸出：Required + Optional，`--verbose` 加 Environment
- Required：gemini CLI、OAuth 憑證、node、jq、plugin 檔案完整性
- Optional：magick、sips、tesseract、tesseract `chi_tra` 語言包
- 輸出前綴：`[OK]` / `[FAIL]` / `[WARN]` / `[SKIP]`
- Required 任一失敗 `exit 1`，其他 `exit 0`
- 結尾提示：「See README Troubleshooting for fixes」

## 環境變數

| 變數 | 預設 | 用途 |
|------|------|------|
| `GEMINI_MODEL` | `flash` | 傳給 Gemini CLI 的 `-m` 值 |
| `MAX_WIDTH` | `1568` | resize 上限寬度（px） |
| `OCR_BIN` | `tesseract` | OCR 執行檔名，設空字串停用 |
| `GEMINI_BIN` | `gemini` | Gemini CLI 執行檔名 |

## 依賴

| 工具 | macOS | Windows | 必要性 |
|------|-------|---------|--------|
| gemini CLI | 已裝 | 已裝 | 必要 |
| node | 已裝 | 已裝 | 必要 |
| jq | `brew install jq` | Git Bash 內含 | 必要 |
| ImageMagick | `brew install imagemagick` | `winget install ImageMagick.ImageMagick` | 選用 |
| tesseract | `brew install tesseract tesseract-lang` | `winget install UB-Mannheim.TesseractOCR` | 選用但預設開 |
| sips | 內建 | 無（由 magick 替代） | 選用 |

## 實作順序

1. 建立 plugin 骨架（資料夾 + `plugin.json`）
2. 移植並改造 `intercept-image-read.sh`（加 magick fallback、改失敗處置）
3. 改造 `image-describe.mjs`（注入 `GEMINI_SYSTEM_MD`、簡化 user prompt）
4. 撰寫 `system-prompts/image-describe.md`
5. 撰寫 `scripts/doctor.sh`
6. 撰寫 plugin 層 README（英文）
7. 更新 `marketplace.json`
8. 重構根 `README.md`
9. 本機安裝驗證（Windows 先測、macOS 後測）
10. commit + PR

## 待驗證事項（實作時）

- Claude Code Windows 環境下 `${CLAUDE_PLUGIN_ROOT}` 變數展開行為
- Git Bash 下 `mktemp` 與 `$TMPDIR` 實測運作
- Windows hook 接收的 `file_path` 是 Unix style 還是 Windows style
- `gemini` CLI 在子程序環境下 `GEMINI_SYSTEM_MD` 是否仍生效
- 大圖（>10MB）在未 resize 下傳給 Gemini 的 token 成本

## 不做的事（YAGNI）

- CHANGELOG：兩個 plugin 都沒有，對稱省略；未來頻繁 release 再補
- Linux 安裝說明：使用者不用
- 中英雙語 README：對齊既有 `gemini` plugin 風格，先英文
- 停用攔截的環境變數：要關就 uninstall
- 圖片路徑白名單：過度設計
- Gemini 失敗自動重試 / fallback 到其他模型：失敗就放行，簡單可靠

## 相關連結

- [原始 hook 專案](https://github.com/HCYT/agent-cookbook/tree/main/hooks/claude-cache-safe-images)
- [Anthropic prompt caching 限制文件](https://docs.claude.com/en/docs/build-with-claude/prompt-caching)
- vault 原始設計方案：`02-Projects/03-開發工具與基礎設施/gemini-plugin-cc/gemini-images-plugin-設計方案.md`
