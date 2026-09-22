---
domain: gemini-review
status: active
created: 2026-04-09
last_modified: 2026-09-22
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

### R22: 漏報向的 eval 計分
- **Level**: MUST
- **Description**: `eval/promptfooconfig-recall.yaml` 為獨立於 `promptfooconfig.yaml` 的第二份 config，量的是 reviewer 漏報的代價。每個埋在 fixture 裡的缺陷掛一條獨立 `llm-rubric`，以 promptfoo 的 `metric` 欄位分流；recall 與 fabrication 兩個數字各自彙總，不平均成單一分數，亦不記該列的 pass/fail。fabrication 的判準沿用 D21：只罰把未查證的事實當成既成事實——斷言、評 MEDIUM/HIGH、或讓它左右 verdict；標明「not verifiable from this diff」的 LOW 明確放行。判準一律是「有沒有報出指定缺陷」，任何以報告長度或檢查清單完整度為判準的 assertion 均不得加入（D19）。現行 `promptfooconfig.yaml` 維持不動當回歸網。

### R23: 缺陷難度分層
- **Level**: SHOULD
- **Description**: 每份 fixture 配一份 `eval/ground-truth/<fixture>.md`，逐條記缺陷的證據來源、難度 tier 與已證偽的誤報清單。tier 為 L1（讀 diff 即見）／L2（需領域知識或跨 hunk 串接）／L3（需推理 diff 內看不到的事實）。recall 按 tier 切分彙總，使「揉到哪一層」可讀。難度梯度以標註表達，不另造刻意安排梯度的合成 diff。

### R24: eval provider 的結構化外殼與紅格分類
- **Level**: MUST
- **Description**: `eval/agy-provider.js` 帶 `--output-format json` 並解析外殼取 `response`，不帶 `--json-schema`。基礎設施失敗依序判定：外殼 `status !== "SUCCESS"`、外殼無法解析時回落現有 `INFRA_FAILURE` regex、外殼正常但 `response` 命中該 regex。外殼的 `num_turns`、`usage.output_tokens`、`duration_seconds` 放進 `metadata` 僅供觀測，不得進入任何 assertion。`eval/score-recall.mjs` 讀 promptfoo 的 JSON 輸出，逐條 assertion 分為真失敗、provider 錯誤、judge 解析失敗三類，後兩類移出 recall 分母並單獨列計數。

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

### S9: 量出 reviewer 變安靜的代價
- **Given**: 一份 prompt 改動已通過現行 `promptfooconfig.yaml` 的六個罰誤報案例
- **When**: 對同一改動跑 `promptfooconfig-recall.yaml` 三輪
- **Then**: 輸出按 tier 切分的 recall 與獨立的 fabrication 數字，使「誤報沒變多但真缺陷少報了」這個組合可被讀出
- **Implements**: #R22, #R23

### S10: 排除非模型成因的紅格
- **Given**: 一輪 eval 中出現 provider 錯誤與 judge 解析失敗
- **When**: 以 `score-recall.mjs` 判讀該輪輸出
- **Then**: 兩類紅格移出 recall 分母並單獨列出計數，不計為品質退步
- **Implements**: #R24

## Design Decisions

編號說明：D19–D25 保留給 `experiment/review-prompt-ab` 分支上已寫、尚未合併的條目，避免兩邊各自從 D19 開始而在合併時撞號。本檔內對 D19／D21／D22／D24 的引用（以及 `CLAUDE.md`、`CONTEXT.md`、`eval/promptfooconfig-recall.yaml`、`eval/ground-truth/` 內的同類引用）指向該分支，合併後才會出現在本檔。

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


### D26: 計數用每缺陷一條 rubric，不用 agy 的結構化輸出
- **Decision**: 放棄原訂的 `--json-schema` 方案。計數改以「一個缺陷一條 `llm-rubric`」表達，recall 即通過條數比例；`--output-format json` 仍採用，但只用於取外殼與基礎設施判別
- **Rationale**: 實測（agy 1.2.7、`gemini-3.6-flash-high`）`--json-schema` 配 `--agent gemini-review` 時 schema 被無聲忽略——吐 markdown、`num_turns: 4`、同一份報告重複四次、6461 output tokens，兩次跑皆然；推測是 agent prompt 的 `## Output Format` 段與 schema 打架。不帶 agent 的裸模型臂確實吐 JSON，但 `response` 內是兩個串接的 JSON 物件，且多出 schema 未定義的 `toolAction` / `toolSummary` 鍵。可用的那一臂不是要量的對象，要量的那一臂不可用。改 agent prompt 讓它吐 JSON 亦不採用：D19/D21/D22 已量到輸出格式的改動會實質移動 findings 數，那樣量到的就不是出貨 prompt 的 recall。每缺陷一條 rubric 另解掉原方案要解的問題——judge 偶發解析失敗（實測 39 格中 4 格，併發降到 2 仍 1 格）從整案歸零降為只損失 1/N，且看得出是哪一格
- **Date**: 2026-09-22

### D27: recall 與 fabrication 同 fixture 量、分開彙總
- **Decision**: `migration-cli-entrypoint.diff` 上同時掛「該報的 G4/G8/G9/G10」與「不該斷言的 N1–N7」兩組 assertion，兩個數字各自彙總不平均。不另開第三份 config
- **Rationale**: D21/D22 的核心發現是兩種失效互為代價——收窄 LOW 上限就多抓一條真缺陷、同時多虛構一條外鍵，總量不變。只記 recall 會誘導把 prompt 推向亂報。N1–N7 的 ground truth 只在這份 diff 上成立，搬到別處無意義。不另開 config：那需要對同一份 diff 跑兩次 review，而 agy 無 sampling 控制，兩次是不同 sample，「這一跑多抓一條真的、也多虛構一條」的配對關係會消失。與 `promptfooconfig.yaml` 分家的理由不同且仍成立——誤報案例的 PASS 是「沒有多報」、漏報案例的分數是「報出比例」，混進同一份 config 算平均會讓兩邊都讀不出來
- **Date**: 2026-09-22

### D28: 難度梯度做成標註維度，不另造梯度案例
- **Decision**: 不新寫刻意安排「明顯／中等／需推理」三層的合成 diff。改在 ground truth 為每條既有缺陷標 tier，由 score 腳本按 tier 切分 recall
- **Rationale**: 新造梯度 diff 的缺陷會是憑空寫的，不是人工查證過的真缺陷，與整份設計「不憑空造缺陷」的前提直接衝突。而現有素材本就含梯度：`migration-cli-entrypoint.diff` 的 G9 / G4、G10 / G8 正好是三層，`snowflake-filter.diff` 的 `Number()` 精度是另一個 L3。標註路線另有一項合成 diff 沒有的好處——每加一份 fixture 都自動進梯度讀數。D22 量到的 trade-off 正落在這個維度上：arm N 的「不得臆測未見程式碼」同時擋掉虛構的外鍵與 snowflake 精度，兩者都是 L3，tier 切分讓下次改 prompt 時看得出是不是又在兩種失效模式之間搬運
- **Date**: 2026-09-22
