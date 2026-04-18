---
domain: gemini-images
status: active
created: 2026-04-18
last_modified: 2026-04-18
---

# Gemini Images

Claude Code plugin，在 Read 工具讀取圖片檔前攔截，透過 Gemini CLI 轉為文字描述後回傳，避免圖片內容導致 prompt cache 失效。

## Requirements

### R1: 圖片 Read 攔截
- **Level**: MUST
- **Description**: 對 Read 工具的 PreToolUse hook 攔截圖片檔（png/jpg/jpeg/gif/webp/avif/bmp/tiff），非圖片檔放行不影響其他 Read 行為。

### R2: 獨立 plugin 共用基礎設施
- **Level**: MUST
- **Description**: `gemini-images` 為獨立 plugin 具獨立版號，與 `gemini` plugin 共用同一 marketplace 與 Gemini CLI OAuth。

### R3: System Prompt 注入
- **Level**: MUST
- **Description**: 呼叫 Gemini CLI 描述圖片時透過 `GEMINI_SYSTEM_MD` 環境變數指定場景化 system prompt，取代 Gemini 預設 system prompt。

### R4: 圖片描述輸出限制
- **Level**: MUST
- **Description**: 圖片描述為 300 字以內繁體中文，單段落、無 markdown、無 bullet；保留程式碼/錯誤訊息/UI 文字/圖表數據/零件編號/金額/URL 等關鍵內容。

### R5: OCR 補強
- **Level**: SHOULD
- **Description**: 預設啟用 tesseract OCR 與 Gemini 描述平行執行，OCR 結果以 `[OCR Supplement]` 段落附加於描述之後。

### R6: 失敗放行策略
- **Level**: MUST
- **Description**: Gemini 與 OCR 雙方皆失敗時，hook 不輸出 `updatedInput`，Claude 照原流程讀原圖；單邊失敗仍輸出成功結果。不得以錯誤訊息字串取代描述。

### R7: 圖片前處理 Fallback
- **Level**: MUST
- **Description**: 圖片 resize 與 format conversion 依序嘗試 `magick` → `sips` → 略過，任一可用即成功，皆不可用時傳原圖給 Gemini。

### R8: 跨平台支援
- **Level**: MUST
- **Description**: 支援 macOS 與 Windows（Git Bash），不支援 Linux。

### R9: 環境診斷工具
- **Level**: SHOULD
- **Description**: 提供 `doctor.sh` 檢查 Required（gemini CLI、OAuth、node、jq、plugin 檔案）與 Optional（magick、sips、tesseract、chi_tra 語言包）依賴，支援 `--verbose` 顯示環境資訊。

## Scenarios

### S1: 攔截圖片 Read
- **Given**: 使用者觸發 Read 讀取 `screenshot.png`
- **When**: PreToolUse hook 執行
- **Then**: hook 透過 Gemini CLI 取得圖片描述並以 `updatedInput` 回傳文字，Claude 讀到文字而非圖片
- **Implements**: #R1, #R3

### S2: 非圖片檔放行
- **Given**: 使用者觸發 Read 讀取 `src/index.js`
- **When**: PreToolUse hook 執行
- **Then**: hook 不改寫輸入，Read 照原流程執行
- **Implements**: #R1

### S3: Gemini 與 OCR 雙失敗
- **Given**: Gemini CLI 呼叫失敗且 OCR 失敗或未安裝
- **When**: hook 結束
- **Then**: hook 不輸出 `updatedInput`，Claude 讀原圖；stderr 印警告訊息
- **Implements**: #R6

### S4: OCR 補強附加
- **Given**: 圖片含中文文字、OCR 可用
- **When**: Gemini 描述成功且 OCR 回傳結果
- **Then**: 輸出為 Gemini 描述加上 `[OCR Supplement]` 段落
- **Implements**: #R5

### S5: 跨平台 Resize Fallback
- **Given**: Windows 環境僅有 `magick` 可用
- **When**: hook 執行 resize
- **Then**: 使用 `magick` 完成 resize，不嘗試 `sips`
- **Implements**: #R7, #R8

### S6: 環境診斷
- **Given**: 使用者首次安裝後驗證環境
- **When**: 執行 `doctor.sh`
- **Then**: 顯示 Required/Optional 檢查結果，Required 任一失敗則 exit 1
- **Implements**: #R9

## Design Decisions

### D1: 獨立 plugin 而非擴充 gemini
- **Decision**: 新建 `gemini-images` plugin，不併入既有 `gemini` plugin
- **Rationale**: 觸發方式（hook vs slash command）與生命週期不同，獨立版號便於各自演進；共用 marketplace 與 OAuth 成本極低
- **Date**: 2026-04-17

### D2: OCR 預設開啟
- **Decision**: `OCR_BIN=tesseract` 為預設值，要求 `chi_tra` 語言包
- **Rationale**: Gemini 對中文圖表/截圖的文字辨識仍有遺漏，OCR 平行執行可補強；使用者需求場景以中文為主
- **Date**: 2026-04-17

### D3: 雙失敗放行而非寫假描述
- **Decision**: Gemini 與 OCR 都失敗時 hook 不輸出 `updatedInput`，Claude 讀原圖
- **Rationale**: 一次 cache 失效可接受，資訊丟失不可接受；寫「無法描述」字串會誤導 Claude 做錯判斷
- **Date**: 2026-04-17

### D4: 三層 Fallback 而非單一工具
- **Decision**: resize/convert 依序嘗試 `magick` → `sips` → 略過
- **Rationale**: macOS 預設有 sips、Windows 無，需 magick 補齊；雙方皆不可用時傳原圖仍可運作
- **Date**: 2026-04-17

### D5: 不支援停用開關
- **Decision**: 不提供環境變數停用攔截，要關就 uninstall plugin
- **Rationale**: 避免過度設計；plugin 粒度已足夠細，啟停由 plugin 生命週期管理
- **Date**: 2026-04-17

## Pending Changes

<!-- Brownfield delta 放這裡，dev-finish spec sync 時清除 -->
