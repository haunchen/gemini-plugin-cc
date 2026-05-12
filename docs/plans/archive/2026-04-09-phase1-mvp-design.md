# Phase 1 MVP 設計

## 概要

零程式碼 Gemini CLI plugin for Claude Code。純 Markdown commands，不寫 JS。
透過 GEMINI_SYSTEM_MD 環境變數注入場景化 system prompt，提升 Gemini review 品質。

## 設計決策

### D1: 零程式碼架構（純 Markdown）
參考 cc-gemini-plugin（thepushkarp）證明 plugin 框架本身足以組裝 bash 指令呼叫 Gemini CLI。
Phase 1 不寫任何 JS，最快驗證 plugin 機制和 system prompt 品質。
需要程式化控制（timeout、job tracking）時再升級到 runner.mjs。

### D2: 錯誤訊息直接呈現
spawn 失敗時由 Claude Code 轉述錯誤訊息，不做結構化錯誤碼。
command.md 描述常見錯誤情境（CLI 不存在、API key 未設、network error），引導 Claude Code 回應。
之後專案長大再考慮結構化。

### D3: review 輸入來源
有參數 → 視為檔案路徑，讀取內容。
無參數 → git diff HEAD（staged + unstaged）。

## 檔案結構

```
plugins/gemini/
├── plugin.json              # plugin manifest（僅註冊 2 commands）
├── marketplace.json         # marketplace 元資料
├── commands/
│   ├── setup.md             # /gemini:setup — 檢查 CLI、版本、API key
│   └── review.md            # /gemini:review — code review
└── system-prompts/
    └── review.md            # Gemini review system prompt
```

## /gemini:setup 流程

依序檢查：
1. `which gemini` — CLI 是否安裝
2. `gemini --version` — 版本資訊
3. 檢查 `GEMINI_API_KEY` 環境變數是否設定（不印出值）

## /gemini:review 流程

1. 判斷輸入來源（有參數用檔案，無參數用 git diff HEAD）
2. 計算 system-prompts/review.md 絕對路徑
3. 設定 `GEMINI_SYSTEM_MD=<path>` 環境變數
4. 執行 `gemini -p "<content>" -o text -m pro`
5. 直接呈現 Gemini 回應

## system-prompts/review.md 設計

- 角色：資深 code reviewer，專注找問題
- 輸出結構：Summary → Findings（severity + location + description + suggestion）→ Verdict
- Severity 三級：HIGH / MEDIUM / LOW
- Verdict 三級：PASS / NEEDS_CHANGES / CRITICAL
- 明確指示：不解釋 diff 格式、不讚美好程式碼、沒問題就 PASS

## 不做的事（YAGNI）

- runner.mjs / 任何 JS 程式碼
- job tracking / state 持久化
- agents / skills / hooks
- prompt-builder / output-parser
- config.mjs / 模型切換 UI
- Review Gate（Stop hook）
