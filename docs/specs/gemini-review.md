---
domain: gemini-review
status: active
created: 2026-04-09
last_modified: 2026-04-09
---

# Gemini Review

Claude Code plugin，透過 Gemini CLI 提供第二意見的程式碼審查。

## Requirements

### R1: Setup 檢查
- **Level**: MUST
- **Description**: /gemini:setup 依序檢查 Gemini CLI 安裝狀態、版本、Google OAuth 認證狀態，回報結果。

### R2: Review 輸入來源
- **Level**: MUST
- **Description**: /gemini:review 有參數時以參數為檔案路徑讀取內容，無參數時取 git diff HEAD 作為輸入。

### R3: System Prompt 注入
- **Level**: MUST
- **Description**: 呼叫 Gemini CLI 時透過 GEMINI_SYSTEM_MD 環境變數指定場景化 system prompt。

### R4: 結構化 Review 輸出
- **Level**: MUST
- **Description**: Review 結果包含 Summary、Findings（含 severity 和 location）、Verdict 三個區塊。

### R5: 錯誤情境引導
- **Level**: SHOULD
- **Description**: CLI 不存在、OAuth 未認證、網路錯誤等情境，提供使用者可理解的錯誤訊息和修復建議。

### R6: 零程式碼實作
- **Level**: MUST
- **Description**: Phase 1 僅使用 Markdown commands 和 system prompts，不包含任何 JS 程式碼。

## Scenarios

### S1: 首次設定檢查
- **Given**: 使用者尚未確認 Gemini CLI 環境
- **When**: 執行 /gemini:setup
- **Then**: 依序顯示 CLI 安裝狀態、版本號、OAuth 認證狀態
- **Implements**: #R1

### S2: 以 git diff 審查
- **Given**: 工作目錄有未提交的變更
- **When**: 執行 /gemini:review（無參數）
- **Then**: 取 git diff HEAD 作為輸入，透過 Gemini CLI 產出結構化 review
- **Implements**: #R2, #R3, #R4

### S3: 以指定檔案審查
- **Given**: 使用者指定檔案路徑
- **When**: 執行 /gemini:review src/index.js
- **Then**: 讀取指定檔案內容作為輸入，透過 Gemini CLI 產出結構化 review
- **Implements**: #R2, #R3, #R4

### S4: CLI 未安裝
- **Given**: 系統未安裝 Gemini CLI
- **When**: 執行 /gemini:review
- **Then**: 提示使用者安裝 Gemini CLI 的方法
- **Implements**: #R5

### S5: 無問題的 diff
- **Given**: git diff 內容沒有值得指出的問題
- **When**: 執行 /gemini:review
- **Then**: Review 結果 Verdict 為 PASS，不硬找問題
- **Implements**: #R4

## Design Decisions

### D1: 零程式碼架構
- **Decision**: Phase 1 純 Markdown，不寫 JS
- **Rationale**: cc-gemini-plugin 證明 plugin 框架足以驅動 Gemini CLI，先驗證機制和 system prompt 品質
- **Date**: 2026-04-09

### D2: 錯誤訊息直接呈現
- **Decision**: 不做結構化錯誤碼，由 Claude Code 轉述
- **Rationale**: Phase 1 簡單場景不需要程式化錯誤處理，之後專案長大再考慮
- **Date**: 2026-04-09

### D3: Verdict 值域
- **Decision**: PASS / NEEDS_CHANGES / CRITICAL 三級
- **Rationale**: PASS 對應無問題或僅 LOW，NEEDS_CHANGES 對應 MEDIUM，CRITICAL 對應 HIGH，與 severity 直接對應便於未來 Review Gate 自動化判斷
- **Date**: 2026-04-09

### D4: 預設使用 Gemini Pro 模型
- **Decision**: review command 硬編碼 `-m flash`（CLI 別名，自動解析到最新 flash 版本）
- **Rationale**: Pro 系列透過 OAuth 頻繁 429（MODEL_CAPACITY_EXHAUSTED），flash 容量充裕且 code review 品質足夠。Phase 2 的 /gemini:config 再開放模型切換
- **Date**: 2026-04-09

## Pending Changes

### R7: 模型切換參數
- **Level**: MUST
- **Description**: 所有 command 支援 `--model <value>` 參數指定 Gemini 模型，未指定時 fallback 到 flash。
- **Status**: ADDED

### R8: Ask 提問功能
- **Level**: MUST
- **Description**: /gemini:ask 接受文字問題，可選附帶檔案路徑作為 context，透過 Gemini CLI 回答。輸出為自由格式。
- **Status**: ADDED

### R9: Adversarial Review
- **Level**: MUST
- **Description**: /gemini:adversarial-review 以 devil's advocate 角度挑戰設計決策，輸出包含 Challenge Summary、Challenges（含 IMPACT 和 alternative）、Overall Assessment（SOLID/RECONSIDER/RETHINK）。
- **Status**: ADDED

### R10: Security Review
- **Level**: MUST
- **Description**: /gemini:security-review 專攻安全漏洞檢查（OWASP Top 10、CSRF、供應鏈 CVE、secrets 掃描、HTTP 標頭等），輸出包含 Security Summary、Vulnerabilities（含攻擊範例、CWE 編號、驗證方法）、Verdict（SECURE/CONCERNS/VULNERABLE）。
- **Status**: ADDED

### R11: Security Review 四級嚴重度
- **Level**: MUST
- **Description**: Security review 的 severity 使用 CRITICAL/HIGH/MEDIUM/LOW 四級，比普通 review 多一級 CRITICAL。
- **Status**: ADDED

### R12: Ask 檔案 Context 判斷
- **Level**: SHOULD
- **Description**: /gemini:ask 的參數中，最後一個 token 若為既有檔案路徑則讀取為 context，其餘為問題文字。
- **Status**: ADDED

### R13: 零程式碼延續
- **Level**: MUST
- **Description**: Phase 2 延續零程式碼架構，所有新 command 以 Markdown 實作，不引入 JS。
- **Status**: ADDED
