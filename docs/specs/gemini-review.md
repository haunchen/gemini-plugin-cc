---
domain: gemini-review
status: active
created: 2026-04-09
last_modified: 2026-04-24
---

# Gemini Review

Claude Code plugin，透過 Antigravity CLI（`agy`）驅動 Gemini 提供第二意見的程式碼審查。使用者介面全在 Claude Code，agy 僅為執行後端。

## Requirements

### R1: Setup 檢查
- **Level**: MUST
- **Description**: /gemini:setup 依序檢查 agy 安裝狀態、版本（需 ≥ 1.1.6）、Google OAuth 認證狀態，安裝四個 agent，並驗證 agent 確實生效與 read-only 限制仍在，回報結果。

### R2: Review 輸入來源
- **Level**: MUST
- **Description**: /gemini:review 有參數時以參數為檔案路徑讀取內容，無參數時取 git diff HEAD 作為輸入。

### R3: System Prompt 注入
- **Level**: MUST
- **Description**: agy 無 per-call system prompt 注入機制，改以 Markdown custom agent 預先註冊場景化 system prompt（`agy/agents/<name>/agent.md`，H1 分隔字串固定為 `# Agent System Instructions`），command 以 `--agent <name>` 指定。`--agent` 對未知名稱靜默忽略，故 setup 必須主動驗證。

### R4: 結構化 Review 輸出
- **Level**: MUST
- **Description**: Review 結果包含 Summary、Findings（含 severity 和 location）、Verdict 三個區塊。

### R5: 錯誤情境引導
- **Level**: SHOULD
- **Description**: CLI 不存在、OAuth 未認證、網路錯誤等情境，提供使用者可理解的錯誤訊息和修復建議。

### R6: 零程式碼實作
- **Level**: MUST
- **Description**: Phase 1 僅使用 Markdown commands 和 system prompts，不包含任何 JS 程式碼。

### R7: 模型切換參數
- **Level**: MUST
- **Description**: 所有 command 支援 `--model <value>` 參數，未指定時一律 `gemini-3.6-flash-high`（effort 固定 high）。別名 `flash` → `gemini-3.6-flash-high`、`pro` → `gemini-3.1-pro-high`（保留供明示選用），其餘值原樣傳給 agy。

### R8: Ask 提問功能
- **Level**: MUST
- **Description**: /gemini:ask 接受文字問題，可選附帶檔案路徑作為 context，透過 agy 回答。輸出為自由格式。

### R9: Adversarial Review
- **Level**: MUST
- **Description**: /gemini:adversarial-review 以 devil's advocate 角度挑戰設計決策，輸出包含 Challenge Summary、Challenges（含 IMPACT 和 alternative）、Overall Assessment（SOLID/RECONSIDER/RETHINK）。

### R10: Security Review
- **Level**: MUST
- **Description**: /gemini:security-review 專攻安全漏洞檢查（OWASP Top 10、CSRF、供應鏈 CVE、secrets 掃描、HTTP 標頭等），輸出包含 Security Summary、Vulnerabilities（含攻擊範例、CWE 編號、驗證方法）、Verdict（SECURE/CONCERNS/VULNERABLE）。

### R11: Security Review 四級嚴重度
- **Level**: MUST
- **Description**: Security review 的 severity 使用 CRITICAL/HIGH/MEDIUM/LOW 四級，比普通 review 多一級 CRITICAL。

### R12: Ask 檔案 Context 判斷
- **Level**: SHOULD
- **Description**: /gemini:ask 的參數中，最後一個 token 若為既有檔案路徑則讀取為 context，其餘為問題文字。

### R13: 零程式碼延續
- **Level**: MUST
- **Description**: Phase 2 延續零程式碼架構，所有新 command 以 Markdown 實作，不引入 JS。

### R14: Gemini subprocess tool policy
- **Level**: MUST
- **Description**: 四個呼叫 agy 的 command（review / adversarial-review / security-review / ask）所用的 agent 一律在 frontmatter 帶 `tools` 白名單，只允許 `view_file` 與 `find_by_name`。寫檔、shell、web、MCP 等工具不在 agent 工具集內，故 `--dangerously-skip-permissions` 亦無法繞過（實測對照確認）。

### R15: 統一 429 fallback
- **Level**: MUST
- **Description**（已由 D11 移除）: 原本 review / adversarial-review / security-review / ask 撞 429 / RESOURCE_EXHAUSTED / rate limit / overloaded 時會自動降級重試。現行行為為不自動 fallback，錯誤原樣呈現給使用者，由使用者決定重試或改 `--model`。

## Scenarios

### S1: 首次設定檢查
- **Given**: 使用者尚未確認 agy 環境
- **When**: 執行 /gemini:setup
- **Then**: 依序顯示 CLI 安裝狀態、版本號、OAuth 認證狀態
- **Implements**: #R1

### S2: 以 git diff 審查
- **Given**: 工作目錄有未提交的變更
- **When**: 執行 /gemini:review（無參數）
- **Then**: 取 git diff HEAD 作為輸入，透過 agy 產出結構化 review
- **Implements**: #R2, #R3, #R4

### S3: 以指定檔案審查
- **Given**: 使用者指定檔案路徑
- **When**: 執行 /gemini:review src/index.js
- **Then**: 讀取指定檔案內容作為輸入，透過 agy 產出結構化 review
- **Implements**: #R2, #R3, #R4

### S4: CLI 未安裝
- **Given**: 系統未安裝 agy
- **When**: 執行 /gemini:review
- **Then**: 提示使用者安裝 agy 的方法
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

### D4: 預設使用 Gemini Pro 模型（已由 D10 取代）
- **Decision**: review command 硬編碼 `-m flash`（CLI 別名，自動解析到最新 flash 版本）
- **Rationale**: Pro 系列透過 OAuth 頻繁 429（MODEL_CAPACITY_EXHAUSTED），flash 容量充裕且 code review 品質足夠。Phase 2 的 /gemini:config 再開放模型切換
- **Date**: 2026-04-09

### D5: Tool policy 共用單檔（已由 D8 取代）
- **Decision**: `plugins/gemini/policies/readonly.toml` 一份，四個 command 共用
- **Rationale**: 四者安全需求一致（read-only 查證），分檔維護容易漂移
- **Date**: 2026-04-24

### D6: 不改 approval mode（已隨 Gemini CLI 淘汰）
- **Decision**: 維持 Gemini CLI 預設 approval mode，僅靠 `--admin-policy` 限制
- **Rationale**: 避開 Plan Mode → YOLO 切換陷阱與 Issue #20469 的 policy 被忽略情境
- **Date**: 2026-04-24

### D7: Admin-policy 單次呼叫帶入（已由 D8 取代）
- **Decision**: 不寫到 `~/.gemini/policies/`，透過 `--admin-policy` 單次帶入
- **Rationale**: 不污染使用者 Gemini CLI 個人設定，policy 生命週期與 plugin 綁定
- **Date**: 2026-04-24

### D8: 遷移到 agy，system prompt 改用 custom agent，policy 改用 tools 白名單
- **Decision**: Gemini CLI 6/18 停服（實測回 `IneligibleTierError`）後全面改走 `agy`。system prompt 從 `GEMINI_SYSTEM_MD` per-call 注入改為預先安裝的 Markdown custom agent；`--admin-policy readonly.toml` 改為 agent frontmatter 的 `tools` 白名單（`view_file` / `find_by_name`）
- **Rationale**: agy 1.1.6 起支援 Markdown custom agent，是唯一可用的 system prompt 注入點（eval 驗證 custom 10/10 vs bare 4/10，與 Gemini CLI 時代的 10/10 持平）。白名單比 policy 強：工具不存在於 agent 工具集，`--dangerously-skip-permissions` 也繞不過。代價是 plugin 從零安裝變成 setup 需真的佈署 agent，且 `--agent` 靜默忽略未知名稱，故 setup 與 doctor.sh 必須主動驗證
- **Date**: 2026-07-31

### D9: agy 端只安裝 agents，不安裝 commands
- **Decision**: agy plugin 獨立於 `plugins/<plugin>/agy/`，只含 `plugin.json` + `agents/`
- **Rationale**: 直接 `agy plugin install` 整個 CC plugin 會把 5 個 command 轉成 agy skill，內容是 CC command.md 逐字複製（含 `$ARGUMENTS` / `allowed-tools` 等不可攜語法），污染 agy skill 清單。agy 只需要 system prompt 容器
- **Date**: 2026-07-31

### D10: 取消 Pro 預設，全面改用 3.6 flash-high
- **Decision**: 四個 command 預設一律 `gemini-3.6-flash-high`，effort 固定 high；429 fallback 目標從 flash 改為 `gemini-3.5-flash-high`。`pro` 別名保留但不再是預設
- **Rationale**: agy 的 Pro 是 `gemini-3.1-pro`，比 3.6 flash 落後兩個世代，2026-04-16 訂 Pro routing 時「Pro 品質 > Flash」的前提已反轉；flash-high 在 review eval 拿 10/10 滿分，無品質缺口需要 Pro 補；Pro 頻繁 429 本來就是 fallback 邏輯的存在理由，預設改 flash 後這個痛點一併消失。fallback 改指 3.5 flash 是因為預設已是 3.6 flash-high，退回同一個 slug 等於原地重試——換模型池的推論尚未實測，effort 檔位是否影響配額亦未知
- **Date**: 2026-07-31

### D11: 移除自動 fallback
- **Decision**: 四個 command 不再於 429 / quota 錯誤時自動改用其他模型，錯誤直接呈現，並提示可用 `--model` 改選
- **Rationale**: fallback 的原始理由是 Pro 頻繁 429（D4），D10 取消 Pro 預設後該前提消失。預設已是 3.6 flash-high，退回同一 slug 等於原地重試；改指 3.5 flash 則建立在「不同模型走不同配額池」的推論上，而 agy 沒有任何配額文件可佐證，effort 檔位是否獨立計費亦未知。與其保留一個依據不明、且會靜默改變使用者拿到的模型的行為，不如讓錯誤可見
- **Date**: 2026-07-31

## Pending Changes

<!-- Brownfield delta 放這裡，dev-finish spec sync 時清除 -->
