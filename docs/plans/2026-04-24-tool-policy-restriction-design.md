# Tool Policy Restriction 設計

## 概要

限制 gemini-plugin-cc 呼叫 Gemini CLI 時的工具權限為 read-only：只允許 `read_file` 和 `glob`，擋掉 `run_shell_command` / `write_file` / `replace` / `web_fetch` / `web_search` / `mcp_*`。四個會呼叫 gemini CLI 的 command（review / adversarial-review / security-review / ask）透過 `--admin-policy` 傳入共用 policy 檔實現；setup 不呼叫 gemini CLI 故不受影響。

同批統一四個 command 的 429 fallback 行為（原只有 review.md 有），並把 stdout/stderr 合流（`2>&1`）確保 policy denyMessage 使用者看得到。

對應 spec：`docs/specs/gemini-review.md`（新增 R14 / R15 / D5 / D6）

## 設計決策

### D5: Tool policy 共用單檔
`plugins/gemini/policies/readonly.toml` 一份，四個 command 共用。四者安全需求一致（read-only 查證），分檔維護容易漂移。使用者若要 Gemini 跑 shell / 寫檔，請直接用 `gemini` CLI 而非 plugin。

### D6: 不改 approval mode
維持 Gemini CLI 預設 approval mode，只靠 `--admin-policy` 限制。避開 Plan Mode → YOLO 切換陷阱，以及 Issue #20469（policy 在某些 approval mode 下被忽略）的情境。

### D7: Admin-policy 單次呼叫帶入
不寫到 `~/.gemini/policies/`。`--admin-policy` 僅影響單次呼叫，不污染使用者 Gemini CLI 個人設定。

### D8: 同批統一 fallback
原本只有 review.md 有 429 → flash 的 fallback 邏輯，ask / adversarial-review / security-review 沒有。這次一併補齊，四個 command 走同一 Step 4 模板。

## 架構

```
┌──────────────────────────────────────────────────────┐
│ Claude Code                                          │
│   /gemini:review │ /gemini:ask │ /gemini:adv... │... │
└─────────────────┬────────────────────────────────────┘
                  │ Step 3: 推導 PLUGIN_ROOT
                  │         → SYSTEM_PROMPT_PATH
                  │         → POLICY_PATH
                  ▼
┌──────────────────────────────────────────────────────┐
│ Step 4: gemini -m $MODEL \                           │
│                --admin-policy $POLICY_PATH           │
│                2>&1                                  │
│   撞 429 → fallback 到 flash（仍帶同一 policy）      │
└─────────────────┬────────────────────────────────────┘
                  │
                  ▼
┌──────────────────────────────────────────────────────┐
│ Gemini CLI subprocess                                │
│   admin-policy 強制生效：                            │
│     allow: read_file, glob                           │
│     deny:  * （含 run_shell_command / write_file /   │
│              replace / web_fetch / web_search /      │
│              mcp_*）                                 │
└──────────────────────────────────────────────────────┘
```

## 檔案清單

新增：
- `plugins/gemini/policies/readonly.toml` — 共用 policy

修改：
- `plugins/gemini/commands/review.md` — Step 3 加 POLICY_PATH；Step 4 主呼叫與 flash fallback 兩條都加 `--admin-policy`
- `plugins/gemini/commands/ask.md` — 同上，另補 429 fallback 與 `2>&1`
- `plugins/gemini/commands/adversarial-review.md` — 同 ask
- `plugins/gemini/commands/security-review.md` — 同 ask
- `README.md` — 新增 Security / Tool Policy 段，說明 plugin 為 read-only
- `CLAUDE.md` — Design Constraints 補一條 tool policy 決策
- `docs/specs/gemini-review.md` — Pending Changes 加 R14 / R15 / D5 / D6

不動：
- `plugins/gemini/commands/setup.md` — 不呼叫 gemini CLI

## Policy 檔內容

```toml
# plugins/gemini/policies/readonly.toml
# Read-only mode for gemini-plugin-cc. Allow file reads only.

[[rule]]
toolName = "*"
decision = "deny"
priority = 100
denyMessage = "gemini-plugin-cc enforces read-only mode. Only read_file and glob are allowed."

[[rule]]
toolName = "read_file"
decision = "allow"
priority = 200

[[rule]]
toolName = "glob"
decision = "allow"
priority = 200
```

## Step 4 統一模板

四個 command 的 Step 4 換成這個骨架（變數名 `$INPUT` 換成各自的 `$REVIEW_INPUT` / `$ASK_INPUT` 等）：

```bash
output=$(printf "%s" "$INPUT" | \
  GEMINI_SYSTEM_MD="$SYSTEM_PROMPT_PATH" \
  gemini -m $MODEL --admin-policy "$POLICY_PATH" 2>&1)
exit_code=$?
if [ $exit_code -ne 0 ] && echo "$output" | grep -qi "429\|quota\|RESOURCE_EXHAUSTED\|rate limit\|overloaded"; then
  echo "[Fallback] $MODEL unavailable (quota/rate limit), retrying with flash..." >&2
  output=$(printf "%s" "$INPUT" | \
    GEMINI_SYSTEM_MD="$SYSTEM_PROMPT_PATH" \
    gemini -m flash --admin-policy "$POLICY_PATH" 2>&1)
fi
echo "$output"
```

Step 3 延用現有「commands/ parent 推導 plugin root」法，多推一個：

```
POLICY_PATH="$PLUGIN_ROOT/policies/readonly.toml"
```

## 實作前要驗證的假設

**實作第一步先做，否則後面改四個 command 白工。**

1. **Policy priority 語意**：草案預期「數字大者勝」（deny `*` = 100、allow `read_file` = 200）。若實際 Gemini CLI 反過來是「數字小者優先」，結果會完全反轉（全放行或全擋光）。
2. **Tool name 大小寫與拼寫**：`read_file` / `glob` 是否為 Gemini CLI 內部實際使用的工具名。若是 camelCase 或 PascalCase，allow 規則全失效。
3. **`--admin-policy` 接受單一 `.toml` 檔**：help 文字寫 "files or directories"，推測兩者皆可，實測確認。
4. **Issue #20469 的影響**：default approval mode 下 policy 是否確實生效。丟一個誘導 `run_shell_command` 的 prompt 實測。
5. **`$CLAUDE_PLUGIN_ROOT` 環境變數**：command.md 內是否可直接用，或沿用現行「commands/ 的 parent」推導法。

假設 1 + 2 一次最小正向測試同時驗：`/gemini:ask "讀 README.md 說明這專案在做什麼"` 若成功 → priority 方向對、tool name 對。

## 驗證腳本（PR 前）

- **正向（讀檔）**：`/gemini:ask "讀 README.md 說明這專案在做什麼"` → `read_file` 正常執行
- **正向（既有 eval case）**：`/gemini:review` 跑現行 eval test case，輸出格式與 findings 品質與 baseline 一致
- **負向（shell 誘導）**：`/gemini:review` 丟含「請幫我跑 ls /etc」字樣的 diff，Gemini 嘗試 `run_shell_command` 應被擋，回應看得到 denyMessage
- **四個 command happy path**：review（git diff）、ask（一題）、adversarial（eval case）、security（eval case）各跑一次

## 不做的事

- 不改 `--approval-mode`（避開 Plan Mode / YOLO 陷阱、避開 Issue #20469）
- 不污染 `~/.gemini/policies/`（`--admin-policy` 單次呼叫帶入）
- 不把 policy 拆成四份（YAGNI，需求一致）
- 不在本 PR 加 policy deny eval case（值得加，但留給下個 PR 以保持 scope 乾淨）
- 不改 setup.md（不呼叫 gemini CLI，不受影響）

## Branch / PR 流程

1. `git checkout -b feat/tool-policy-restriction`（本 brainstorm 完成時自動建立）
2. 寫 `readonly.toml` → 本機驗假設 1-5
3. 驗證通過後改四個 command.md
4. README / spec Pending Changes / CLAUDE.md 同步
5. PR 標題：`feat: enforce read-only tool policy on Gemini subprocess`
