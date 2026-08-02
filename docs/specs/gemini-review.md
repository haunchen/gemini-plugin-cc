---
domain: gemini-review
status: active
created: 2026-04-09
last_modified: 2026-08-02
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
- **Description**: Review 結果包含 Summary、Findings（含 severity 和 location）、Verdict 三個區塊；另依條件輸出 Spec Compliance（有需求輸入時，見 R20）與 Incidental Findings（有既有問題時，見 R19）。severity 維持 HIGH/MEDIUM/LOW 三級、Verdict 維持 PASS/NEEDS_CHANGES，不改用 task-reviewer 的術語。

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
- **Description**（已由 D12 移除）: 原 /gemini:security-review 專攻安全漏洞檢查（OWASP Top 10、CSRF、供應鏈 CVE、secrets 掃描、HTTP 標頭等）。v0.2.0 起移除，理由見 D12。

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
- **Description**: 三個呼叫 agy 的 command（review / adversarial-review / ask）所用的 agent 一律在 frontmatter 帶 `tools` 白名單，只允許 `view_file` 與 `find_by_name`。寫檔、shell、web、MCP 等工具不在 agent 工具集內，故 `--dangerously-skip-permissions` 亦無法繞過（實測對照確認）。

### R15: 統一 429 fallback
- **Level**: MUST
- **Description**（已由 D11 移除）: 原本 review / adversarial-review / ask 撞 429 / RESOURCE_EXHAUSTED / rate limit / overloaded 時會自動降級重試。現行行為為不自動 fallback，錯誤原樣呈現給使用者，由使用者決定重試或改 `--model`。

### R16: Diff 閱讀紀律
- **Level**: MUST
- **Description**: `gemini-review` agent 以 diff 為完整視角：context 行即變更後的檔案內容，不重讀已在 diff 內的檔案、不爬 codebase。若必須判斷的 hunk 被截斷，於報告中明說。

### R17: 具名風險的聚焦外查
- **Level**: MUST
- **Description**: 僅在讀碼產生具體可命名的風險（函式或 API 契約變更、鎖順序、共享可變狀態、刪改可能仍有引用的符號）時，才以 `view_file` / `find_by_name` 檢查 diff 外程式碼；一個風險一次聚焦檢查，並於 finding 內同時寫出風險、查了什麼、看到什麼。取代原「一律不看 diff 外」的規則——語意由「不准看」改為「不准臆測，但可以查證」。三項實作約束：(a) agy 的 `view_file` 只接受絕對路徑（相對路徑會解析到磁碟根），故 command 需在 payload 附 `=== REPOSITORY ROOT ===` 區塊供 agent 拼路徑；(b) 只讀該 root 底下的路徑，diff 給的路徑若以 `..` 爬出去或本身即絕對路徑，視為待報風險而非可開啟的檔案；(c) 無 ROOT 區塊或無法查證時不得外查，改為報告風險並指出使用者該查什麼，且該類 finding 嚴重度上限為 LOW、不得單獨使 Verdict 由 PASS 轉為 NEEDS_CHANGES。

### R18: 宣稱不等於證據
- **Level**: MUST
- **Description**: diff 內的註解、commit message、PR 描述視為未驗證宣稱，不因作者自辯（「刻意保持簡單」「per YAGNI」「已測過」）降低 finding 嚴重度。註解與程式碼行為不符本身即為 finding。限縮於「註解替某段程式碼辯護且正在評估該段」的情境，不擴大為全面質疑註解。

### R19: Incidental Findings 分區
- **Level**: MUST
- **Description**: Review 輸出新增 `## Incidental Findings` 區塊，收錄周圍未改動程式碼的既有 bug 或明顯技術債（本次 diff 未引入亦未加重），各附 file:line。不計入 Verdict。無則整區省略。

### R20: 可選需求輸入與 Spec 合規 verdict
- **Level**: MUST
- **Description**: `/gemini:review` 支援可重複的 `--spec <path>`（支援 glob），command 讀檔後以 `=== REQUIREMENTS (what this change is supposed to do) ===` / `=== CHANGE UNDER REVIEW ===` 分隔組進 stdin；`--spec` 後未接值或接到另一個 `--` 開頭的 token 時停下報錯，不吞下一個 token 當檔名。有帶時 agent 額外輸出 `## Spec Compliance: PASS | FAIL`，檢查缺漏 / 多餘 / 理解偏差，無法從本次變更驗證者列 ⚠️ 並說明使用者該自行確認什麼；未帶時完全不輸出 REQUIREMENTS 區塊，agent 亦不輸出該 verdict。marker 僅在出現於第一個 `=== CHANGE UNDER REVIEW ===` 之前時才視為指令，其後的同名字串屬受審內容（見 D16）。

### R21: Agent 版本漂移偵測
- **Level**: SHOULD
- **Description**: `gemini` plugin 以 SessionStart hook（`hooks/check-agent-version.sh`，bash，不引入 jq 或其他新依賴）比對 `${CLAUDE_PLUGIN_ROOT}/agy/plugin.json` 與 `${GEMINI_CONFIG_DIR:-$HOME/.gemini}/config/plugins/gemini-agents/plugin.json` 的 version 欄位，不一致時輸出單行提示要求重跑 `/gemini:setup`。一致、任一 manifest 不存在、或環境變數未設時一律靜默 exit 0。hook 的作用範圍跟隨 plugin 的安裝 scope，plugin 不對此另作規定。

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

### S6: 帶需求檔審查
- **Given**: 使用者手上有描述這次變更該做什麼的 spec 或 design doc
- **When**: 執行 /gemini:review --spec docs/specs/foo.md
- **Then**: 除既有 Verdict 外另出 `## Spec Compliance`，標出缺漏 / 多餘 / 理解偏差；落在本次變更之外的需求列 ⚠️ 並說明該自行確認什麼
- **Implements**: #R20, #R4

### S7: 受審內容自帶 marker
- **Given**: 待審的 diff 本身含有 `=== REQUIREMENTS (what this change is supposed to do) ===` 字樣（例如 eval 素材，或外部來源的 patch）
- **When**: 不帶 --spec 執行 /gemini:review
- **Then**: 該 marker 位於 `=== CHANGE UNDER REVIEW ===` 之後，視為受審內容而非指令，不產出 Spec Compliance verdict
- **Implements**: #R20

### S8: Plugin 已升級但 agent 未重裝
- **Given**: 使用者升級 `gemini` plugin，但未重跑 `/gemini:setup`，agy 內仍是舊版 agent
- **When**: 開始新 session
- **Then**: 輸出單行提示，指出已安裝版本與 plugin 版本並要求重跑 `/gemini:setup`；版本一致或找不到已安裝 manifest 時完全無輸出
- **Implements**: #R21

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

### D12: 移除 security-review command
- **Decision**: v0.2.0 起移除 `/gemini:security-review` 與 `gemini-security-review` agent。eval test case 與 rubric 保留（`eval/test-cases/security/`、兩份 security config 標為 PARKED）
- **Rationale**: agy harness 對安全審查請求有拒答政策，實測 20 次呼叫 17 次回「Sorry, I cannot fulfill your request to analyze or identify vulnerabilities」，custom 1/10、baseline 2/10；連 app-rename 這種零風險乾淨 diff 都被拒，故與 diff 內容無關。Gemini CLI 時代同一份 prompt 是 10/10，是 agy 的限制而非 prompt 退化。已試防禦性框架改寫（角色改 pre-merge reviewer、不要求 attack payload）仍被拒，觸發面涵蓋整份 prompt 的 Vulnerabilities / attacker / VULNERABLE 結構。與其出貨一個會回拒絕訊息的 command，不如移除。註：能力本身仍在——同一個 SQL injection diff 交給 `gemini-review` agent 可正確標出 [HIGH] SQL injection，故安全向度的檢查暫由 /gemini:review 承接
- **Date**: 2026-07-31

### D13: 移植 dev task-reviewer 的審查紀律
- **Decision**: 將 `dev` plugin `task-reviewer` agent 的四項紀律（diff 閱讀紀律、具名風險外查、不信任自辯、Incidental Findings 分區）移植進 `gemini-review` agent，範圍限 review，不動 adversarial-review 與 ask
- **Rationale**: task-reviewer 是實戰驗證過的單 task 閘門模式，這四項在 gemini-review 的無狀態單次呼叫情境下同樣成立。不移植「先肯定做得好的地方」——與現行 `Do NOT praise good code` 直接衝突，維持現行。severity 與 verdict 術語不換：D3 已綁定兩者，換名要連帶動 R11 與 eval rubric，三級對三級換不到品質
- **Date**: 2026-07-31

### D14: `--spec` 以區塊存在與否切換雙 verdict
- **Decision**: 新增可選 `--spec <path>`，以 stdin 內有無 `=== REQUIREMENTS (what this change is supposed to do) ===` 區塊決定是否輸出 Spec Compliance verdict，不另設旗標。此處的「有無」在 D16 精確化為「有無出現在第一個 `=== CHANGE UNDER REVIEW ===` 之前」
- **Rationale**: task-reviewer 能判 spec 合規是因派遣訊息附了需求原文，gemini-review 原本只吃 diff。可選輸入補上這一層而不強迫每次都要準備需求檔；用區塊存在性當開關，prompt 側零額外狀態
- **Date**: 2026-07-31

### D15: 未查證風險的嚴重度上限
- **Decision**: agent 因無法讀取 diff 外程式碼而只能推測的風險，嚴重度上限 LOW，且不得單獨把 Verdict 由 PASS 轉成 NEEDS_CHANGES；措辭須為「可能需要更新，無法從這份 diff 查證」而非「會編譯失敗」
- **Rationale**: R17 放寬外查後出現非預期副作用——eval 的 app-rename（純命名變更，原本穩定 PASS）被判成兩個 MEDIUM + NEEDS_CHANGES，理由是「其他檔案的 import 會編譯失敗」，而 eval 情境根本沒有 ROOT 區塊可查。rename 命中「刪改可能仍有引用的符號」這條具名風險，agent 照指示報告了它，卻把查不到的推測寫成已確立的事實。加上上限後該 case 回到 LOW + PASS，未快取重跑兩次一致。這是「定向鬆綁」必須配套的煞車：允許查證的同時，必須規定查不到時說話的份量
- **Date**: 2026-07-31

### D16: 分隔 marker 僅在受審內容之前有效
- **Decision**: `=== REQUIREMENTS (what this change is supposed to do) ===` 只有出現在第一個 `=== CHANGE UNDER REVIEW ===` 之前才被視為指令；其後的同名字串屬受審內容。同理，diff header 給的路徑只在 repository root 底下才可開啟，`..` 或絕對路徑一律視為待報風險
- **Rationale**: 原措辭是「input contains」，與 prompt 另一處「CHANGE UNDER REVIEW 之後都是受審內容」自相矛盾，實際走哪邊看模型當下判斷。後果具體：一份自身含有該 marker 的 diff 就能讓 agent 依攻擊者提供的「需求」產出 Spec Compliance verdict——本 repo 的 `eval/test-cases/spec-compliance-missing.diff` 正是這種結構。危害有上限（agent 無寫入、無網路工具，輸出只回到使用者眼前），但受審內容本來就是不可信輸入，控制通道不該與它共用命名空間。路徑那一半同源：diff header 由受審內容控制，不設邊界等於讓 patch 決定 agent 讀哪個檔案
- **Date**: 2026-07-31

### D17: 版本漂移用 hook 偵測，不用輸出印記
- **Decision**: 以 SessionStart bash hook 比對兩份 `plugin.json` 的 version 欄位，而非讓 agent 在 review 輸出帶版本字串，也不在每個 command 開頭檢查
- **Rationale**: 偵測所需的資料早就存在——`agy plugin install` 是逐字複製，連 `plugin.json` 一併裝進 `~/.gemini/config/plugins/gemini-agents/`，所以不必新增任何 metadata。選 hook 而非 per-command 檢查：每 session 只跑一次而非每次 review，且不必改三個 command、未來新增 command 自動涵蓋。不選輸出印記：那會污染 review 輸出，與「Gemini 輸出必須逐字呈現、不重排」直接衝突。找不到已安裝 manifest 時選擇靜默而非報「未安裝」：agy 在其他平台的 config 路徑未經實測，猜錯會變成每個 session 都誤報，而「完全沒安裝」本來就有既有訊號（review 輸出沒有 `## Verdict:` 結構）。bash 實作不違反零程式碼約束——原文限制的是 JS runtime，`gemini-images` 的 hook 入口本就是 `.sh`
- **Date**: 2026-07-31

### D18: 讀檔權限用 `--add-dir` 授權，不改全域 settings
- **Decision**: `/gemini:review` 呼叫 agy 時加 `--add-dir "$ROOT"`（`$ROOT` 即 payload 內 `=== REPOSITORY ROOT ===` 的同一個值），無 git root 時兩者一併省略。權限被拒時降級重跑一次（拿掉 ROOT 區塊與 `--add-dir`），並在回報中說明本次無查證能力
- **Rationale**: agy 的 `view_file` 背後權限名為 `read_file`，headless 無法跳確認提示故一律 soft-deny，且該拒絕會丟掉整個 turn——command 拿回的是一行 `no output produced`，不是少一個 finding 的 review。D9 為此建立的整套 nameable-risk 查證規則因而全程失效。實測（agy 1.1.9，rename 已匯出符號的 diff）：不帶 flag 2/2 被拒，帶 flag 2/2 完成；輸出差異是「callers may need updating, not verifiable」的 LOW 對上指名兩個實際 import 檔的 HIGH。選 `--add-dir` 而非 `~/.gemini/settings.json` 的 `permissions.allow`：後者是每台機器的設定，無法隨 plugin 出貨，別人裝了照樣壞。不選 `--dangerously-skip-permissions`：既有約束禁止，且 `--add-dir` 已足夠。三個 command 的錯誤處理同步更正——原本把「輸出沒有 `## Verdict:`」一律讀成 agent 未安裝並導向 `/gemini:setup`，對本失敗模式是錯的指引。此失敗非確定性（是否讀檔取決於 diff 內容），這正是它長期未被發現的原因
- **Date**: 2026-08-02

### D19: 不在 reviewer prompt 加強制檢查清單
- **Decision**: 維持 `agy/agents/gemini-review/agent.md` 原樣，不加「輸出 PASS 前必須列出檢查了哪些項目」的清單，system prompt 內與 diff 之後兩種放法都不採用
- **Rationale**: 起因是一份搬遷腳本的 review 在 3 秒內回空 Findings + PASS。實測四臂（每臂 payload 相同，均為該腳本的兩個 commit）：帶清單 5 次跑出 0 個 finding，不帶清單 4 次跑出 2 個。清單會排擠 findings——模型把輸出預算花在敘述檢查過程，然後把敘述當成交付物；額外加的「不得在 Review Summary 內化解已陳述的失效情境」一條無效。此結果與 Google 對 Gemini 3.x 的指引一致：為舊模型設計的冗長 prompt 工程會導致 over-analyze，該指引要求 prompt 簡潔。樣本小（各臂 3 次、agy 無 sampling 控制），但方向一致且與官方指引同向。
- **Correction (2026-08-02，同日)**: 本條原本另舉兩例，說模型「講出風險卻未列入 Findings」——一次是 TRUNCATE 沒有防呆、兩次是兩帳戶餘額互換可通過 SUM 驗證。這兩項後來查證為非缺陷，該處敘述已刪除：spec 明文要求「可重複執行（每次先清空目標表）」，防呆從未被要求；而資料是帶原 id、全欄位、單一 transaction 內直接複製，不存在能產生「SUM 相等但逐筆不等」的機制。模型當時的判斷是對的，是原計分基準錯了。詳見 D20
- **Date**: 2026-08-02

### D20: 先補漏報向的 eval 案例，再談縮短 prompt
- **Decision**: 新增 `eval/test-cases/migration-cli-entrypoint.diff` 與 `promptfooconfig.yaml` 的 Test Case 14，其 rubric 同時罰漏報與罰虛構。在此案例存在前不改 `agent.md`
- **Rationale**: 追查「review 在 3 秒內回空 PASS」的根因，實測（agy 1.1.9、`gemini-3.6-flash-high`、同一份 payload 與工具白名單）每次跑報出的真缺陷數：六行最小 prompt 2.0、現行 141 行 0.78、現行加強制檢查清單 0。單調且方向明確——prompt 講越多報越少。收窄 `agent.md:37` LOW 上限的適用範圍（單一變因）三次無效，故癥結是抑制型指令的總量而非某一條（**此句已被 D21 推翻**）。但縮短不能直接做：既有 13 個案例中有 6 個專罰誤報，0 個罰漏報，那些抑制規則正是為了通過那 6 個而累積的。無檔案存取時模型確實會虛構——一次宣稱 `users.default_account` 有指向 `accounts(id)` 的外鍵並判 HIGH，而 schema 中該欄無 `REFERENCES`。兩種失效互為代價，缺少漏報向的錨點就無法判斷縮短是改善還是把誤報換回來。新案例實測現行 prompt 四次中一次，assertion 天生會抖，用途是對照而非門檻。另記一項條件差異：`run-agy.sh` 不帶 `--add-dir`，eval 一直在「讀不到任何檔案」的條件下評測，而 0.2.2 起 `/gemini:review` 會帶——虛構正是發生在讀不到檔時，故 eval 量到的漏報率是上界，非使用者實際體驗
- **Date**: 2026-08-02

### D21: 決定漏報的是 LOW 上限那一句的措辭，不是 prompt 長度
- **Decision**: 推翻 D20「癥結是抑制型指令的總量」。改以 `agent.md:37` 的措辭為單一變因繼續調，暫不縮短 prompt。目前最佳臂（arm L，把上限的判準從「缺陷長在哪」改成「這個 finding 靠什麼成立」）尚未達到可出貨標準，不進 `plugins/`
- **Rationale**: 做了長度 × 上限措辭的 2×2，每格 4 次跑，條件與 eval 一致（Test Case 14 的 diff、`gemini-3.6-flash-high`、不帶 `--add-dir`），判準為是否報出 CLI 進入點缺陷：

  | | 未收窄上限 | 收窄上限 |
  |---|---|---|
  | 141 行 | 現行 4/8 | arm I **4/4** |
  | 81 行 | arm K **1/4** | arm J **4/4** |

  長度控制住之後沒有作用（I 4/4 = J 4/4；同為未收窄的現行 4/8 與 K 1/4 落差即噪音）。上限措辭則是 8/8 對 5/12，Fisher 精確檢定 p≈0.018。D20 說「收窄上限三次無效」是在另一份 payload 上用「真缺陷數」量的，換了判準後結論相反——單一變因的結論不能跨判準沿用。
- **代價**: 收窄後模型把那條虛構的 `users.default_account → accounts(id)` 外鍵直接斷言為 MEDIUM/HIGH（I 4/4、J 3/4），未收窄版則壓成標明未查證的 LOW 或根本不提。arm L 把界線改畫在證據上（「這個 finding 需不需要一個你沒看到的事實」）後，偵測維持 4/4，外鍵回到有保留的 LOW 3/4，且六個罰誤報的案例 12/12 全乾淨——與現行 prompt 同分，無退步。但用 Test Case 14 完整 rubric 評分（每臂 4 次）是現行 2/4、arm L 1/4，兩種失效仍在互換，未構成勝出
- **同時修正 Test Case 14 的 rubric**: 原條件 (2) 罰「宣稱 diff 沒顯示的外鍵」，judge 連明確標示「not verifiable from this diff」的 LOW 都判 FAIL。那正是 prompt 的 LOW 上限規則要求的行為，罰它等於把 prompt 推回沉默——恰是加這個案例要修的單向偏斜。改為只罰「當成既成事實」：斷言、評為 MEDIUM/HIGH、或讓它左右 verdict 才 FAIL，標明未查證的 LOW 明確視為通過。改後已驗證 judge 會據此放行
- **Date**: 2026-08-02

### D22: 不回退到 v0.2.0 的 prompt；移除規格審查是架構決定，不是品質手段
- **Decision**: 保留 `agent.md` 現行的具名風險外查與 LOW 上限規則，不採用 v0.2.0 的「只報 diff 裡看得到的問題」硬規定。`--spec` 是否從 `/gemini:review` 拆出獨立 command 依 D21 的架構理由決定，但不得以「拆掉能提升審查品質」為由——實測不成立
- **Rationale**: 兩支對照臂，條件同 D21（tc14 diff、`gemini-3.6-flash-high`、不帶 `--add-dir`）。

  | 臂 | prompt | tc14 抓到 G4 | 虛構外鍵 | 誤報關卡 | snowflake 精度 |
  |---|---|---|---|---|---|
  | 現行 | 141 行 | 4/8 | 4/4 | 12/12 | 4/4 |
  | M（現行減規格審查） | 124 行 | 3/4 | 2/4 | 11/12 | — |
  | N（v0.2.0 原樣） | 79 行 | 3/4 | 0/4 | 12/12 | 1/4 |

  arm M 為單一變因（只移除規格審查與其輸出區塊）。三項指標皆落在現行的噪音範圍內，換不到品質。其 app-rename 的一次退化經查為關卡判準過粗——它把 Dart 建構子未同步改名判為 HIGH，而 `BatteryMonitorApp` 配 `const BatteryGuardianApp({super.key})` 確實無法編譯，該 finding 是對的。

  arm N 在虛構、誤報、偵測三項都不輸現行，長度只有一半，但在 snowflake-filter 上四次僅一次指出 `Number()` 對 17-19 位 ID 的精度問題，現行四次全中（Fisher p=0.029）。機制同源：v0.2.0 的「不得臆測未見程式碼」同時擋掉虛構的外鍵與 snowflake——後者需要推理執行期資料的形狀（Discord ID 的位數），那同樣不在 diff 內，該規則無法區分兩者。故其乾淨是以漏報買來的，不能靠調措辭只留一邊。虛構問題改由帶檔案存取的查證階段處理（實測 8 次 0 次），不必付這個代價
- **Date**: 2026-08-02

### D23: fan-out 架構——發散生成、逐條查證、確認才投票
- **Decision**: `/gemini:review` 的原型改為兩段：無檔案存取的 `gemini-scan` 平行跑 N 次列出候選，語意去重後由帶 `--add-dir` 的 `gemini-verify` 逐條查證。查證判 CONFIRMED 才追加兩票取多數，判 REJECTED 直接定案。原型在 `eval/ab/`，`plugins/` 未動
- **Rationale**: D21/D22 顯示調 prompt 只在搬移失效模式——收窄 LOW 上限就多抓一個真缺陷、多虛構一條外鍵，放寬則反之，總量不變。根因是單一次呼叫同時擔任生成與判斷。拆開之後兩邊各自可以做對：生成階段用最小 prompt 偏向 recall（實測六行 prompt 每次 2.0 個真缺陷，141 行 0.78），查證階段用檔案存取消滅虛構（實測 8 次 0 次）。檔案存取必須只放在查證——實測在生成階段給 `--add-dir` 會讓輸出長度砍半並退化成空 PASS（arm L 四次有兩次，另一次吐出原始 tool call 文字），那正是本次追查的原始症狀
- **原型實測**（`run10.sh`，3 次 scan、19 條唯一候選、19 次平行查證、0 次權限被拒）: 確認 4 條、駁回 15 條。找出一條所有 single-shot 跑法都沒報過的真缺陷（`settlement_account_id` 回填未檢查孤兒，查證階段開 schema 確認該欄確有 `REFERENCES`）；並以證據殺掉一條現行 prompt 會報成 LOW 的誤報（測試用 `?` 佔位符，查證階段找到 DB 層的 `toPositional()` 指名駁回）
- **投票的必要性與形狀**: 查證器對「關於執行期語意而非本 repo 程式碼」的錯誤宣稱會誤確認，單票約 1/4——那個事實不在 repo 裡，給再多檔案存取也沒用。實測 3 票取多數（每組 4 輪）：機制錯誤的宣稱 4/4 正確駁回（12 張個別票中僅 2 張誤確認，且從未在同一輪湊到兩張），機制正確的宣稱 4/4 確認且 12/12 全票。誤確認零星且不相關、正確確認則一致，這個不對稱正是投票能生效的原因，也代表投票不會誤傷正確宣稱。只對 CONFIRMED 追票是因為駁回方向可靠（虛構外鍵兩次測試合計 8/8 駁回）——但「真宣稱在第一票就被誤駁」這個方向尚未測到，樣本內沒有發生過，不等於不會發生
- **成本**: 原型為 22 次呼叫；加上只對確認追票約 30 次。相對單次呼叫是一個數量級的增加，是否可接受尚未決定
- **待解**: 語意去重（原型按 `file:line` 去重，同一個缺陷出現在 :139 與 :141 被驗兩次且結論相反）；嚴重度偏高（`devDependencies` 判 HIGH）；「輸出必須逐字回傳 Gemini」這條約束需重寫，目前的想法是查證階段也由 Gemini 寫、Claude 只做串接與去重
- **Date**: 2026-08-02

### D24: fan-out 在第二份 diff 上仍然成立，但樣本仍只有兩份
- **Decision**: 繼續發展 fan-out 原型。`plugins/` 仍不動——泛化性只驗過兩份 diff，不足以支撐把正式 command 改成 27–33 次呼叫的架構
- **Rationale**: 先前所有測量都集中在 `migration-cli-entrypoint.diff` 一份 diff 上，架構的優勢可能只是對這份素材過擬。換一份驗證：同一個來源 repo 的另一個子系統（REST route 的非同步化重構，3 檔 68 行），工作樹用 `git worktree` 釘在該 commit，避免查證器讀到後續被改過的程式碼
- **結果**: 28 條候選 → 語意去重 17 條 → 確認 3 條，27 次呼叫。其中一條為真：DELETE 處理內兩個連續寫入未包在交易中（先 `UPDATE accounts SET is_active = 0`，再 `UPDATE users SET default_account = NULL`），第二個失敗則帳戶已停用而 `users.default_account` 仍指向它；上游的 `referenced` 檢查到更新之間亦未序列化。經人工讀原始碼確認，且該檔自該 commit 起未再變動。同一份 diff 交給現行 single-shot（同樣帶 `--add-dir`）跑兩次，兩次皆 PASS 零 finding
- **旁證**: 該專案後續在 `reconcile` 與 `transactions` 兩處各自修掉同一類問題（讀改寫包進單一交易並鎖列），可見其團隊認定這是真缺陷；但 accounts route 未被涵蓋
- **一致性**: 查證階段駁回 14/17，其中多數屬 `?` 佔位符那一類——與它在前一份 diff 上正確駁回的是同一類宣稱，行為未因換 repo 而漂移
- **弱點**: 另兩條確認是測試檔內的 non-null assertion（LOW），實務上偏噪音。樣本仍只有兩份 diff、皆出自同一個 repo 與同一種語言棧
- **一個值得記住的靜默失敗**: `run10.sh` 原本把路徑內插進 `xargs ... sh -c` 字串，路徑一長即超過命令列上限。它不會中止腳本，只是查證一次都不跑，而逐條輸出全為空 verdict——與「全部駁回」在畫面上無法區分，差點被讀成「乾淨 diff 守住了」。已改為經環境變數傳遞
- **Date**: 2026-08-02
