# Phase 2 設計：擴充 Commands

## 概要

Phase 1 的零程式碼架構延續到 Phase 2。新增四個 command + 三個 system prompt，既有 command 加入 `--model` 參數支援。不引入 JS（runner.mjs 留給 Phase 3 agent 整合）。

## 設計決策

### D5: 繼續零程式碼
Phase 2 的四個新 command 本質上都是「不同 system prompt + 略不同 input 來源」，跟 Phase 1 同一個模式。引入 JS 的時機是 Phase 3 agent 整合。

### D6: 不做 /gemini:config
參考 thepushkarp/cc-gemini-plugin 的做法，模型切換透過 per-command `--model` 參數處理，不需要持久化 config 檔案。預設值寫在 command.md 裡。

### D7: Security review 獨立於 adversarial review
兩者切入角度不同：adversarial 挑戰設計決策（devil's advocate），security 專攻安全漏洞。實作成本一樣（換 system prompt），但使用者意圖和輸出結構不同。

## --model 參數機制

所有 command 的 Step 1 加入模型判斷：

```
如果 $ARGUMENTS 包含 --model <value>：
  MODEL = <value>（從 $ARGUMENTS 中移除 --model <value>）
否則：
  MODEL = flash
```

優先順序：`--model 參數` > fallback `flash`

可用值：`flash`、`pro`、`flash-lite`，或完整模型名。

## /gemini:ask

單次提問，可選附帶檔案 context。

使用方式：
- `/gemini:ask 這段 regex 在做什麼？` — 純文字
- `/gemini:ask 時間複雜度？ src/sort.js` — 帶檔案 context
- `/gemini:ask --model pro 解釋這個演算法 lib/algo.js` — 指定模型

輸入判斷：剩餘參數中最後一個 token 若為既有檔案路徑 → 讀取為 context，其餘為問題。

System prompt（ask.md）：資深工程師，回答簡潔直接。有 context 引用行號，無 context 一般技術問答。自由格式輸出（不強制結構）。

## /gemini:adversarial-review

Devil's advocate 模式。不找 bug，挑戰設計決策。

輸入方式：同 /gemini:review（有參數讀檔案，無參數讀 git diff）。

System prompt（adversarial-review.md）輸出結構：

```
## Challenge Summary
{一句話總結挑戰方向}

## Challenges

### [IMPACT] {主題}
- **Current approach**: {目前怎麼做}
- **Challenge**: {為什麼可能有問題}
- **Alternative**: {替代方案}

## Overall Assessment: {SOLID | RECONSIDER | RETHINK}
```

IMPACT 等級：HIGH / MEDIUM / LOW（潛在影響，非嚴重度）。
Verdict：SOLID（設計合理）、RECONSIDER（有值得重新想的點）、RETHINK（建議大改方向）。

## /gemini:security-review

安全性專攻。檢查面向（參考資安檢查清單）：

- 注入攻擊（SQL/XSS/Command injection）
- CSRF
- 認證授權缺陷
- 敏感資料外洩 / 硬編碼 secrets
- HTTP 安全標頭（CSP、CORS、X-Frame-Options）
- Cookie 安全設定（HttpOnly、Secure、SameSite）
- 不安全的依賴（供應鏈 CVE）
- 路徑穿越、SSRF、不安全的反序列化
- Rate limiting 缺失
- 錯誤訊息洩漏（stack trace 暴露）

System prompt（security-review.md）輸出結構：

```
## Security Summary
{一句話總結安全狀態}

## Vulnerabilities

### [SEVERITY] {vulnerability type} — {file_path}:{line}
- **Risk**: {可能被怎麼利用}
- **Attack example**: {具體攻擊 payload 或情境}
- **Evidence**: {程式碼中哪裡有問題}
- **Fix**: {修復方式，附程式碼}
- **Verify**: {驗證修復的方法}
- **CWE**: {對應的 CWE 編號}

## Verdict: {SECURE | CONCERNS | VULNERABLE}
```

SEVERITY 四級：CRITICAL / HIGH / MEDIUM / LOW。
Verdict：SECURE（無發現）、CONCERNS（有 MEDIUM/LOW）、VULNERABLE（有 HIGH/CRITICAL）。

## 檔案清單

新增：
- `plugins/gemini/commands/ask.md`
- `plugins/gemini/commands/adversarial-review.md`
- `plugins/gemini/commands/security-review.md`
- `plugins/gemini/system-prompts/ask.md`
- `plugins/gemini/system-prompts/adversarial-review.md`
- `plugins/gemini/system-prompts/security-review.md`

修改：
- `plugins/gemini/commands/review.md` — 加入 --model 參數
- `plugins/gemini/commands/setup.md` — 加入 --model 參數

文件：
- `docs/specs/gemini-review.md` — brownfield delta（R7~R13）
- `docs/plans/2026-04-09-phase2-commands-design.md` — 本文件

## 不做的事

- runner.mjs / JS 程式碼（Phase 3）
- /gemini:config command（per-command --model 取代）
- config 持久化檔案
- job tracking / state
- Review Gate Stop hook（Phase 4）
