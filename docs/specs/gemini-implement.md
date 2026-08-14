---
domain: gemini-implement
status: active
created: 2026-08-14
last_modified: 2026-08-14
---

# Gemini Implement

`/gemini:implement` 把一項任務交給 Gemini 直接改寫工作區的檔案。這是本 repo 第一個會寫入使用者檔案的功能，其餘命令一律唯讀。

適用範圍是機械性、規格明確、驗證成本低的工作（批次改名、樣板、測試骨架、同一模式套到多個檔案）。需要整個 repo 判斷力的實作留在 Claude Code session 內做，那裡本來就有 context。

## Requirements

### R1: 命令介面
- **Level**: MUST
- **Description**: `/gemini:implement <task>` 接受行內任務描述；`--brief <path>` 讀需求檔；`--context <path>` 可重複且支援 glob，提供參考材料；`--model` 覆寫模型。`--brief` 與行內描述並存時，行內描述附加於 brief 之後。BRIEF 為空則停止並詢問。

### R2: 執行前置條件
- **Level**: MUST
- **Description**: 必須在 git repository 內執行，否則停止且不得提供繞過方式。執行前以 `git status --porcelain` 取得基線；工作樹非乾淨時列出已髒的檔案並詢問是否續行。

### R3: Payload 標記
- **Level**: MUST
- **Description**: payload 由 `=== WORKSPACE ROOT ===`、`=== TASK BRIEF (what to implement) ===`、`=== CONTEXT (files and conventions to follow) ===` 三段組成，前兩段必存在，CONTEXT 為空時整段省略。標記字串（含括號內文字）須與 agent 端逐字一致，任一方變更必須同 commit 改另一方。

### R4: Agent 工具白名單
- **Level**: MUST
- **Description**: `gemini-implement` 的 tools 為 `view_file`、`find_by_name`、`replace_file_content`、`write_to_file`。不得含任何可執行指令的工具。`/gemini:setup` 步驟 7 驗證此性質（預期 `NO_SHELL_OK`）。

### R5: 事後稽核
- **Level**: MUST
- **Description**: 呼叫後比對三方：基線 `git status`、執行後 `git status`、agent 回報的 `## Files Changed`。分別回報「有申報且有改」「有改但未申報」「有申報但未改」，並說明本檢查看不到 repository root 以外的寫入。

### R6: 不 commit
- **Level**: MUST
- **Description**: 命令不得 commit，變更留在工作樹，使其可用 `git diff` 審查、`git checkout` 還原。

### R7: 需求不足時停手
- **Level**: MUST
- **Description**: agent 依五項具體判準檢查 brief，命中任一項時不得寫入任何檔案，回報 `NEEDS_CONTEXT`，列出命中的判準、需要使用者裁定的決策、以及（若有）建議選項。

### R8: 測試誠實聲明
- **Level**: MUST
- **Description**: agent 無 shell，不得回報測試通過。須寫出測試檔並明示「未執行」及使用者應執行的確切指令。同理不得聲稱已 commit、已安裝、已驗證。

### R9: 回報格式
- **Level**: MUST
- **Description**: 輸出含 `## Status:`（`DONE` | `DONE_WITH_CONCERNS` | `BLOCKED` | `NEEDS_CONTEXT`）、`## What I Implemented`、`## Files Changed`、`## Tests`、`## Self-Review`，以及有內容時才出現的 `## Concerns`。所有寫入的檔案必須全數列於 Files Changed。

## Decisions

### D1: 跨越唯讀界線，但限縮在單一 agent 與單一命令
- **Decision**: 新增獨立的 `gemini-implement` agent 承載寫入能力，不放寬既有三個 agent 的白名單；寫入能力只透過 `/gemini:implement` 使用
- **Rationale**: 唯讀是本 plugin 至今的核心安全性質，且 `/gemini:setup` 每次驗證它。把寫入工具加進既有 agent 會讓「review 只會看不會改」這個保證消失，而 review 是最常用的命令。分成獨立 agent 後，兩種能力在 `agy agents` 與 setup 驗證中都可分辨，使用者也能只用 review 而不啟用寫入
- **Date**: 2026-08-14

### D2: 白名單給編輯工具、不給 shell
- **Decision**: tools 只放 `replace_file_content` 與 `write_to_file`，不放 `run_command`；agent 因此不能跑測試、不能 commit，改由呼叫端與使用者執行
- **Rationale**: 實測 headless 下白名單內的寫檔工具可直接運作，不需權限提示、不需 `--dangerously-skip-permissions`、不需 `permissions.allow`——與 `view_file` 的 `read_file` 權限被 soft-deny 的情形相反（見 gemini-review D18）。`run_command` 則確定在 headless 被自動拒絕，且該拒絕會丟掉整個 turn。即使可用也不應給：能執行指令等於能繞過白名單做任何事，而測試執行留在 Claude Code 側本來就更容易查核。代價是 agent 寫出的測試從未跑過，由 R8 要求誠實聲明處理
- **Date**: 2026-08-14

### D3: `--add-dir` 不是沙盒，補償控制是 git 稽核
- **Decision**: 不把 `--add-dir` 當邊界看待；改以「必須在 git repo 內執行」＋「事後比對申報與 `git status`」作為可稽核性的來源
- **Rationale**: 實測要求 agent 寫入工作區外的絕對路徑，它照寫，無任何阻擋或警告；`view_file` 同樣讀得到 `--add-dir` 以外的任意絕對路徑。agy 沒有提供可用的圍籬（`--mode accept-edits` 見 D4，`--sandbox` 只限制終端而本來就不給 shell）。既然無法防止，就必須讓事後看得見：git 是唯一隨手可得的稽核與還原機制，因此不在 git repo 內就不執行。此控制的界線要誠實說明——repo 外的寫入不會出現在 `git status`
- **Date**: 2026-08-14

### D4: 不採用 `--mode accept-edits`
- **Decision**: 呼叫時不加 `--mode accept-edits`
- **Rationale**: 兩次實測皆回 `Eligibility check failed: UNAVAILABLE (503)`，而拿掉該 flag 的相同請求正常執行，可判定是 flag 本身不可用而非服務問題。白名單路徑已足以在 headless 下寫檔，該 flag 無必要
- **Date**: 2026-08-14

### D5: 需求不足的判準寫成可操作條件，不用形容詞
- **Decision**: agent prompt 以五項字面判準判定 brief 是否可實作（行為變更未述輸入輸出、引入狀態未述上限/生命週期/失效、目標只是形容詞、可能位置多於一處、依賴未出現於任何輸入的值），命中即零寫入並回 `NEEDS_CONTEXT`
- **Rationale**: 初版寫「ambiguous or incomplete 就停」。以 brief「Add caching to the format module so it is faster」實測，agent 直接實作無上限 `Map` 快取於兩個函式、回報 `DONE`、無任何 concerns——它不認為那算 ambiguous。改為五項字面判準後同一 brief 得到 `NEEDS_CONTEXT`、零檔案寫入、列出三項待裁定決策並附建議；以完整規格的 brief 回歸測試仍正常完成並寫入兩檔，可見判準具鑑別力而非一律拒絕。模型有「想幫上忙」的傾向，抽象指令壓不住它，可勾選的條件可以
- **Date**: 2026-08-14

### D6: 預設 3.7 flash，而 `/gemini:review` 續用 3.6
- **Decision**: `/gemini:implement` 預設 `gemini-3.7-flash-high`；不動 review 的預設
- **Rationale**: 以本 repo eval 實測，兩者在 review 上分不出高下：既有 12 案例各 12/12，為此次新增的四個推理密集案例各 4/4，16 案例雙向順序的 pairwise 對比（Claude Sonnet 4.6 評判）決定性結果 5:2，該樣本數下屬雜訊。既然 review 沒有可測得的改善就不動它（換預設本身有風險而無收益）。而 Google 公布的 3.7 增益集中在寫程式（DeepSWE v1.1 49.0% → 65.3%），正是本命令的工作內容，故新命令採用 3.7。兩命令預設不同是有依據的分歧，不是疏漏
- **Date**: 2026-08-14

### D7: 不 commit
- **Decision**: 命令完成後不 commit，也不提供 commit 選項
- **Rationale**: 未 commit 的變更才能用 `git diff` 逐行審、用 `git checkout` 一次還原。agent 本身也無法 commit（無 shell），若由命令代為 commit，等於把「Gemini 寫的」與「使用者寫的」混進同一個歷史節點，而 D3 的稽核正是靠兩者可分辨
- **Date**: 2026-08-14

### D8: 讀取範圍無邊界一事適用於既有唯讀 agent
- **Decision**: 於 README 與本檔明記：`tools` 白名單保證的是「不能寫」，不保證「能讀多少」
- **Rationale**: 實測 `view_file` 可開啟 `--add-dir` 以外的任意絕對路徑。既有文件把唯讀描述為比 `--admin-policy` 更強的保證，該敘述對寫入成立、對讀取範圍不成立。實務上 review 不會亂讀，是因為 gemini-review 的 prompt 規定只讀 repository root 底下（見 gemini-review D16），那是行為約束不是機制邊界，兩者不應混為一談。此事與 implement 無直接關係，但在調查 implement 的圍籬時才被測出來，記於此並回頭修正 README
- **Date**: 2026-08-14
