# /gemini:review 移植 task-reviewer 審查紀律 Implementation Plan

Goal: 把 dev plugin `task-reviewer` agent 的四項審查紀律移植進 `gemini-review` agent，並新增可選 `--spec` 需求輸入以支援第二個 spec 合規 verdict。

Architecture: 全部改動落在兩個 Markdown 檔——`plugins/gemini/agy/agents/gemini-review/agent.md`（system prompt，五項紀律的載體）與 `plugins/gemini/commands/review.md`（新增 `--spec` 解析與 stdin 組裝）。agent 側以「輸入中有沒有 `=== REQUIREMENTS (what this change is supposed to do) ===` 區塊」決定是否輸出 spec 合規 verdict，不設額外旗標。驗證手段是 promptfoo eval（回歸 + 3 個新 case）與一次 agy 實測。

Tech Stack: Markdown custom agent（agy ≥ 1.1.6）、bash、promptfoo（`npx promptfoo@latest`）。無 JS 執行期。

Spec: `docs/specs/gemini-review.md`（R16–R20 + MODIFIED R4 在 Pending Changes）

Design: `docs/plans/2026-07-31-review-task-reviewer-mode-design.md`

## Global Constraints

- agy 版本下限 1.1.6；低於此無法載入 custom agent。
- `agent.md` 的 system prompt 分隔字串固定為 H1 `# Agent System Instructions`，一字不差。其他寫法會被 agy 靜默忽略，導致 prompt 完全沒生效。
- 所有 agent 的 frontmatter `tools` 白名單只允許 `view_file` 與 `find_by_name`。不得新增其他工具。
- 絕不在任何 agy 呼叫加 `--dangerously-skip-permissions`。
- 預設模型 `gemini-3.6-flash-high`，effort 固定 high。別名 `flash` → `gemini-3.6-flash-high`、`pro` → `gemini-3.1-pro-high`，其餘值原樣傳給 agy。
- 零程式碼架構：只用 Markdown 與 bash，不引入 JS。
- Review severity 維持三級 `HIGH` / `MEDIUM` / `LOW`；Verdict 值域維持 `PASS` / `NEEDS_CHANGES`。新增的 spec 合規 verdict 是獨立第二個，值域 `PASS` / `FAIL`。
- Gemini 的輸出必須逐字呈現給使用者，不重排、不摘要。
- 改動任何 `agy/agents/*/agent.md` 後必須重跑 `agy plugin install`，否則跑的還是舊 prompt，而 `--agent` 不會報錯。
- 版本號存在三個檔案，必須一起動：`.claude-plugin/marketplace.json` 的 plugins[] 條目、`plugins/gemini/.claude-plugin/plugin.json`、`plugins/gemini/agy/plugin.json`。
- 本次改動屬 PATCH（編輯 agent prompt）：0.2.0 → 0.2.1。
- 本 repo 沒有單元測試框架。驗證手段只有 promptfoo eval 與手動 agy 呼叫，Task 內的「跑測試」一律指這兩者。
- 工作目錄一律為 repo 根 `D:/UserData/Documents/Code/gemini-plugin-cc`。bash 指令用 Bash tool 執行。

---

### Task 1: 實測 view_file 在 agy 是否能解析相對路徑

Implements: `gemini-review.md` #R17（前置驗證）

執行者：controller 直接跑，不派 implementer。本 task 不產生 repo 檔案變更（probe 檔案落在 repo 外的 scratchpad），沒有可審的 diff，產出只是一個布林結論。

這是設計文件風險 R1 的最小實測。`view_file` 在白名單裡，但從未在 review 路徑上驗過——agy 執行時能否用 repo 相對路徑讀檔是未知數。查不到就要在 Task 2 把「聚焦外查」降級為「明確指出使用者該自己查什麼」。

用一個一次性 probe agent 隔離測試，不動正式 plugin。

註：設計文件描述的驗證方式是「餵一個改函式簽章的 diff，看報告有沒有出現實際查到的呼叫點」。這裡刻意改用 probe agent 直接讀檔回報首行——那個方式同時受 prompt 措辭與模型判斷影響，測不出 `view_file` 本身能不能解析路徑；probe 把變因隔離掉，是刻意的方法調整，不是漏做。

Files:
- Create: `<scratchpad>/viewfile-probe/plugin.json`
- Create: `<scratchpad>/viewfile-probe/agents/viewfile-probe/agent.md`

`<scratchpad>` 指本 session 的 scratchpad 目錄，路徑見 session 系統提示；沒有的話用 repo 外的任意暫存目錄，不要放進 repo。

Interfaces:
- Consumes: 無
- Produces: 一個布林結論 `VIEW_FILE_WORKS = true | false`，Task 2 依它決定 agent.md 的「When to look outside the diff」是保留還是降級。

Step 1: 建立 probe plugin 的 manifest

寫入 `<scratchpad>/viewfile-probe/plugin.json`：

```json
{
  "name": "viewfile-probe",
  "version": "0.0.1",
  "description": "Throwaway probe: does view_file resolve repo-relative paths under agy?"
}
```

Step 2: 建立 probe agent

寫入 `<scratchpad>/viewfile-probe/agents/viewfile-probe/agent.md`：

```markdown
---
name: viewfile-probe
description: Throwaway probe agent for view_file path resolution
mainAgent: true
tools:
    - view_file
    - find_by_name
---

# Agent System Instructions

You are a file reading probe. The user will give you a file path.

Use `view_file` to read that path, then reply with exactly two lines:

```
TOOL_RESULT: OK | FAILED
LINE1: <the first line of the file verbatim, or the error message if reading failed>
```

Do not add any other text. Do not guess the contents. If `view_file` fails or is unavailable, report FAILED and quote the error.
```

Step 3: 安裝 probe agent

Run（在 repo 根目錄）:
```bash
agy plugin install "<scratchpad>/viewfile-probe"
```
Expected: 輸出含 `agents : 1 processed`。若沒有這行，probe 沒裝上，後面的結果不可信。

Step 4: 用 repo 相對路徑呼叫

Run（cwd 必須是 repo 根）:
```bash
agy -p "Read this file: plugins/gemini/commands/review.md" --agent viewfile-probe --model gemini-3.6-flash-high --print-timeout 5m 2>&1
```

Expected（成功時）:
```
TOOL_RESULT: OK
LINE1: ---
```

`plugins/gemini/commands/review.md` 的第一行是 YAML frontmatter 分隔線 `---`。

判定：
- 回 `TOOL_RESULT: OK` 且 `LINE1: ---` → `VIEW_FILE_WORKS = true`
- 回 `TOOL_RESULT: FAILED`，或給出的第一行與 `---` 不符（代表它在編故事而非真的讀檔）→ `VIEW_FILE_WORKS = false`

Step 5: 加驗一次絕對路徑（僅在 Step 4 為 false 時執行）

Run:
```bash
agy -p "Read this file: D:/UserData/Documents/Code/gemini-plugin-cc/plugins/gemini/commands/review.md" --agent viewfile-probe --model gemini-3.6-flash-high --print-timeout 5m 2>&1
```
Expected: 同上。若絕對路徑可行而相對路徑不行，`VIEW_FILE_WORKS = true`，但 Task 2 的外查段落要改成要求 agent 使用絕對路徑。

Step 6: 清理

Run:
```bash
agy plugin uninstall viewfile-probe
```
Expected: 成功訊息。再跑 `agy plugin list` 確認 `viewfile-probe` 不在清單內。

Step 7: 記錄結論

把 `VIEW_FILE_WORKS` 的值與實際輸出貼進本 task 的報告。這個結論是 Task 2 的輸入，不要略過。

Step 8: Commit

本 task 不產生 repo 內檔案變更，無可 commit 內容。若 `git status` 有變更代表 probe 檔案誤放進 repo，刪掉再繼續。

---

### Task 2: 改寫 gemini-review agent 的 system prompt

Implements: `gemini-review.md` #R16, #R17, #R18, #R19, #R20（agent 側）, MODIFIED #R4

Files:
- Modify: `plugins/gemini/agy/agents/gemini-review/agent.md`（全檔替換）

Interfaces:
- Consumes: Task 1 的 `VIEW_FILE_WORKS`
- Produces: agent 認得三個分隔字串 `=== REPOSITORY ROOT ===`、`=== REQUIREMENTS (what this change is supposed to do) ===`、`=== CHANGE UNDER REVIEW ===`。Task 3 的 command 與 Task 4 的測試素材必須逐字產出——括號內的說明文字是字串的一部分，不可省略

Step 1: Task 1 的實測結論（已完成，controller 執行）

`VIEW_FILE_WORKS = true`，但**僅絕對路徑可行**：

```
$ agy -p "Read this file: plugins/gemini/commands/review.md" --agent viewfile-probe ...
TOOL_RESULT: FAILED
LINE1: failed to read file: open C:/plugins/gemini/commands/review.md: The system cannot find the path specified.

$ agy -p "Read this file: D:/UserData/Documents/Code/gemini-plugin-cc/plugins/gemini/commands/review.md" ...
TOOL_RESULT: OK
LINE1: ---
```

agy 的工作目錄不是呼叫端的 cwd，repo 相對路徑會被解析到磁碟根。因此 Step 2 的全文已納入兩項調整，直接照用即可：

1. agent.md 明寫 `view_file` 需要絕對路徑，並從輸入的 `=== REPOSITORY ROOT ===` 區塊取得 repo 根路徑來拼接。
2. 沒有該區塊時（例如 eval 情境，diff 來自別的專案）不得嘗試外查，改為報告風險並指出使用者該查什麼。

Task 3 的 command 負責產出該區塊，兩者必須成對——只改一邊，外查功能就是死的。

（以下為原 plan 的備援分支，實測已排除，保留供日後 agy 行為改變時參考。若某天 `view_file` 連絕對路徑都失效，把 `### When to look outside the diff` 整段替換為：）

  ```markdown
  ### When the risk lives outside the diff

  Reading the code may produce a **specific, nameable risk** that this diff alone cannot settle — a changed function signature or API contract, changed lock ordering or shared mutable state, a deleted or renamed symbol that may still be referenced.

  You cannot read those files. Report the risk as a finding anyway, and state exactly what the user must check (which symbol, which kind of call site). Never state a conclusion about code you have not seen.
  ```

  並把 Rules 段落的這一條：

  ```
  - Do not speculate about code you have not seen. Verifying a nameable risk with `view_file` is allowed; guessing at unseen code is not a finding.
  ```

  替換為：

  ```
  - Do not speculate about code you have not seen. You cannot read files outside the input, so an unseen-code concern is reported as a risk for the user to check, never as a conclusion.
  ```

Step 2: 全檔替換

將 `plugins/gemini/agy/agents/gemini-review/agent.md` 完整內容替換為下列（含 frontmatter，`tools` 白名單維持原樣不得增刪）：

```markdown
---
name: gemini-review
description: Senior code reviewer — second opinion on a diff or file (read-only)
mainAgent: true
tools:
    - view_file
    - find_by_name
---

# Agent System Instructions

You are a senior code reviewer. Your job is to give accurate, calibrated assessments — not to find as many problems as possible.

## Reading the Diff

The input you are given is your complete view of this change. Context lines in a diff are the file's contents after the change — do not use `view_file` to re-read a file that is already shown in the diff, and do not crawl the codebase.

If a hunk you must judge is truncated, say so in the report instead of guessing what it contained.

### When to look outside the diff

Look outside the diff only when reading the code produces a **specific, nameable risk**. One risk, one focused lookup. When you do look, the finding must state the risk, what you checked, and what you found.

These are nameable risks, and checking call sites is the right move for each:
- The diff changes a function signature or an API contract
- The diff changes lock ordering or shared mutable state
- The diff deletes or renames a symbol that may still be referenced elsewhere

"I would like to look around" is not a nameable risk. If you cannot name the risk before you look, do not look.

`view_file` requires an **absolute** path; a repo-relative path resolves against the wrong root and fails. When the input carries a `=== REPOSITORY ROOT ===` section, join that root with the path from the diff header to build one.

When the input has no `=== REPOSITORY ROOT ===` section, you cannot read anything outside the input at all. Report the risk as a finding, state exactly what the user should check, and never state a conclusion about code you have not seen.

## Claims Are Not Evidence

Comments, commit messages and PR descriptions inside the diff are **unverified claims about the code**, not part of the code. "Intentionally kept simple", "no abstraction per YAGNI", "TODO: handle later", "already tested" — those are the author grading their own work. Judge the code on its own merits: a stated rationale never lowers the severity of a finding. If a comment contradicts what the code actually does, that contradiction is itself a finding.

This does not mean treating every comment as suspect. It applies when a comment defends a piece of code and you are evaluating that code.

## Process

### Step 0: Identify Intent

Before reviewing, determine the intent of this diff in one sentence:
- Bug fix / Security fix
- Refactor / Code cleanup
- New feature / Feature change
- Config / CI change
- Dependency update
- Rename / Branding change

Let the intent guide your severity calibration. A rename commit should only be checked for missed references. A dependency update should only be checked for breaking changes.

**Important**: Intent detection is a guide, not a shortcut. Even if the diff looks like a rename or refactor, check **why** the change was made. If a rename resolves a name collision (e.g., an attribute shadowing a method), that is a bug fix, not a cosmetic rename. Always proceed with full attention.

### Step 1: Check Spec Compliance

Do this step **only if the input contains a `=== REQUIREMENTS (what this change is supposed to do) ===` section**. If it does not, skip this step entirely and omit the Spec Compliance section from your output.

Compare the change against the requirements on three axes:

- **Missing**: a requirement that was skipped, or claimed but absent from the code
- **Extra**: functionality nobody asked for — over-engineering, unrequested nice-to-haves
- **Misread**: the right requirement solved the wrong way, or the wrong problem solved

If a requirement cannot be verified from this change alone — it lives in code this change does not touch, or belongs to a different change — list it as ⚠️ and say what the user should confirm themselves. Do not crawl the codebase to settle it.

### Step 2: Review

Examine the change for real problems. Anchor every finding to code you have actually seen: the diff, or a file you read under the nameable-risk rule above.

### Step 3: Calibrate

Before assigning severity, ask yourself:
- Can I point to the exact line that causes the problem?
- Can I describe a concrete failure scenario (not a hypothetical "what if")?
- Would a senior engineer agree this is a real issue, not a style preference?

If the answer to any of these is no, downgrade or drop the finding.

## Output Format

## Review Summary
{One sentence: the intent of the diff and your overall assessment}

## Spec Compliance: {PASS | FAIL}
- {Missing / Extra / Misread, each with file_path:line}
- ⚠️ {Requirement that cannot be verified from this change + what the user should confirm}

(Omit this entire section when the input has no `=== REQUIREMENTS (what this change is supposed to do) ===` section.)

## Findings

### [{SEVERITY}] {file_path}:{line_number}
- **Finding**: {What is wrong — must reference specific code you have seen}
- **Impact**: {Concrete failure scenario, not hypothetical}
- **Suggestion**: {How to fix it}

(Order by severity. If there are no significant findings, leave this section empty.)

## Verdict: {PASS | NEEDS_CHANGES}

## Incidental Findings
- {file_path}:{line} — {description}

(Omit this entire section when there is nothing to report.)

## Severity Levels

- **HIGH**: Bugs that will cause crashes, data loss, or exploitable security vulnerabilities. You must be able to describe the exact failure or attack path. A version pinning, a missing lock file, or a theoretical "what if the API changes" is NOT high severity.
- **MEDIUM**: Concrete issues with error handling, edge cases, or performance that have a plausible failure scenario in normal usage.
- **LOW**: Style, naming, minor improvements. Things that are correct but could be better.

## Verdict Criteria

- **PASS**: No findings, or only LOW findings. This is a valid and expected outcome for clean diffs.
- **NEEDS_CHANGES**: One or more HIGH or MEDIUM findings with concrete evidence.

Spec Compliance is a separate verdict and does not change this one. Incidental Findings never affect either verdict.

## What Counts as an Incidental Finding

An incidental finding is an existing bug or clear piece of technical debt in surrounding code that **this change neither introduced nor made worse**. Report it in its own section with file_path:line so the user can decide separately. Do not mix it into Findings, and do not let it turn a PASS into NEEDS_CHANGES.

If you looked outside the diff under the nameable-risk rule and noticed an unrelated problem there, this is where it goes.

## Rules

- Do not speculate about code you have not seen. Verifying a nameable risk with `view_file` is allowed; guessing at unseen code is not a finding.
- If the diff is clean (rename, routine refactor, dependency bump with no red flags), output Verdict: PASS with empty Findings. This is correct behavior, not laziness.
- Do NOT explain what a diff format is or how to read it.
- Do NOT praise good code.
- Be specific: always include file path and line number.
- Keep suggestions actionable — show what the code should look like.
- A deliberate trade-off (version pinning, removing unused code, simplifying types) is not a bug. Note that "deliberate" means visible in the code's structure, not merely asserted in a comment — see Claims Are Not Evidence.
- Prompt engineering changes (rewriting LLM prompts, adding few-shot examples, adjusting instructions) are NOT prompt injection vulnerabilities. User input interpolated into a prompt for a constrained task (e.g., title generation, summarization) with no tool access is acceptable practice, not a security finding.
```

Step 3: 確認 H1 分隔字串一字不差

Run:
```bash
grep -n '^# Agent System Instructions$' plugins/gemini/agy/agents/gemini-review/agent.md
```
Expected: 輸出一行 `10:# Agent System Instructions`（行號可能因 frontmatter 不變而固定為 10）。沒有輸出代表 H1 寫錯，agy 會靜默丟棄整個 prompt。

Step 4: 確認 tools 白名單未被動到

Run:
```bash
sed -n '1,9p' plugins/gemini/agy/agents/gemini-review/agent.md
```
Expected: frontmatter 含且僅含 `view_file` 與 `find_by_name` 兩個工具。

Step 5: 重新安裝 agent

Run:
```bash
agy plugin install "$(pwd)/plugins/gemini/agy"
```
Expected: 輸出含 `agents : 3 processed`。少於 3 或報錯就停下修正——沒裝成功的話後續所有驗證跑的都是舊 prompt。

Step 6: 冒煙驗證新結構（不帶 REQUIREMENTS）

Run:
```bash
agy --agent gemini-review --model gemini-3.6-flash-high --print-timeout 5m < eval/test-cases/app-rename.diff 2>&1 | head -40
```
Expected: 輸出含 `## Review Summary` 與 `## Verdict:`，且**不含** `## Spec Compliance`。若出現 Spec Compliance，代表條件判斷沒生效，回 Step 2 加強該段措辭。

用 `app-rename.diff` 是因為它是純命名變更、沒有需求區塊，同時驗到「結構有出來」與「不該出現的第二個 verdict 沒出現」。

Step 7: Commit

```bash
git add plugins/gemini/agy/agents/gemini-review/agent.md
git commit -m "feat(gemini-review): port task-reviewer review disciplines into the agent prompt"
```

---

### Task 3: 為 /gemini:review 新增 --spec 參數

Implements: `gemini-review.md` #R20（command 側）

Files:
- Modify: `plugins/gemini/commands/review.md`（frontmatter `argument-hint`、Step 1、Step 2、Step 3）

Interfaces:
- Consumes: Task 2 定義的三個分隔字串 `=== REPOSITORY ROOT ===`、`=== REQUIREMENTS (what this change is supposed to do) ===`、`=== CHANGE UNDER REVIEW ===`，必須逐字相符
- Produces: 無下游 task 依賴

Step 1: 更新 frontmatter 的 argument-hint

把 YAML frontmatter 中的 `argument-hint` 欄位：

```
argument-hint: [file-path] [--model <model>]
```

改為：

```
argument-hint: [file-path] [--spec <path>] [--model <model>]
```

Step 2: 在 Step 1 段落後插入 `--spec` 解析

在 `## Step 1: Parse --model parameter` 整段之後、`## Step 2: Determine input` 之前，插入新的一節：

```markdown
## Step 1b: Parse --spec parameter

Check if $ARGUMENTS contains one or more `--spec <path>` pairs:
- If none: set SPEC_INPUT = empty, skip the rest of this step
- For each `--spec <path>` found:
  - If the path contains glob characters (* or ?), use the Glob tool to expand it, then Read each matched file
  - Otherwise, Read the single file directly
  - If a path does not exist, tell the user which one and stop — a silently missing requirements file would produce a spec-compliance verdict based on nothing
- Remove every `--spec <value>` pair from $ARGUMENTS
- Concatenate all spec file contents (separated by a blank line) as SPEC_INPUT

`--spec` and `--model` may appear in any order, before or after the file path.
```

Step 3: 更新 Step 2 的參數描述

把 `## Step 2: Determine input` 底下的條件句：

```
If $ARGUMENTS (after --model removal) is provided:
```

改為：

```
If $ARGUMENTS (after --model and --spec removal) is provided:
```

Step 4: 改寫 Step 3 的 stdin 組裝

把 `## Step 3: Call agy` 整節替換為：

````markdown
## Step 3: Call agy

The system prompt lives in the `gemini-review` agent, installed by `/gemini:setup`. The agent's `tools` whitelist keeps the run read-only — there is no separate policy file.

Assemble PAYLOAD (the variable the bash command below reads) from up to three sections.

First get the repository root:

```bash
git rev-parse --show-toplevel 2>/dev/null
```

The agent's `view_file` only accepts absolute paths — agy does not run in this shell's working directory, so a repo-relative path resolves against the wrong root. Handing it the root is what lets it check a call site when it spots a nameable risk. If the command fails (not a git repo), omit the section entirely; the agent then reports such risks for the user to check instead of reading files.

PAYLOAD is the concatenation of whichever of these apply, in this order:

```
=== REPOSITORY ROOT ===
{absolute path from git rev-parse --show-toplevel}
=== REQUIREMENTS (what this change is supposed to do) ===
{SPEC_INPUT}
=== CHANGE UNDER REVIEW ===
{REVIEW_INPUT}
```

- Omit the REPOSITORY ROOT section when not in a git repo.
- Omit the REQUIREMENTS section when SPEC_INPUT is empty. Do **not** emit it empty — the agent decides whether to return a spec-compliance verdict purely by whether that section is present.
- When both are omitted, PAYLOAD is REVIEW_INPUT unchanged.
- Whenever any section is present, the `=== CHANGE UNDER REVIEW ===` line must precede REVIEW_INPUT.

All `===` marker lines must be reproduced verbatim, including the parenthetical in the REQUIREMENTS marker; the agent matches on them.

Run the following bash command, passing PAYLOAD via stdin to avoid shell escaping issues:

```bash
output=$(printf "%s" "$PAYLOAD" | agy --agent gemini-review --model $MODEL --print-timeout 5m 2>&1)
echo "$output"
```

Note: We pipe input via stdin instead of -p to handle large diffs and special characters safely.

If the output does not follow the review format (`## Review Summary` / `## Findings` / `## Verdict`), the agent is not installed — `--agent` silently ignores unknown names. Tell the user to run `/gemini:setup`.
````

Step 5: 驗證組裝後的 payload 會觸發第二個 verdict

command 本身是 Markdown 指示，只有 Claude Code 讀它才會執行；subagent 無法跑 slash command。因此這一步驗的是**組裝結果**——手動拼出 command 該產生的 payload，確認 agent 端吃了會出 Spec Compliance：

Run:
```bash
{ printf '=== REPOSITORY ROOT ===\n%s\n' "$(git rev-parse --show-toplevel)"; \
  printf '=== REQUIREMENTS (what this change is supposed to do) ===\n'; \
  sed -n '/^### R16/,/^### D13/p' docs/specs/gemini-review.md; \
  printf '\n=== CHANGE UNDER REVIEW ===\n'; \
  cat eval/test-cases/app-rename.diff; } \
| agy --agent gemini-review --model gemini-3.6-flash-high --print-timeout 5m 2>&1 | head -50
```
Expected: 輸出同時含 `## Spec Compliance:` 與 `## Verdict:` 兩行。（這裡刻意餵不相干的需求配不相干的 diff，合規結果理應是 FAIL 或大量 ⚠️——重點是第二個 verdict 有出現，不是它的值。）

Step 6: 逐字比對分隔字串

Run:
```bash
grep -n 'REPOSITORY ROOT\|REQUIREMENTS (what this change is supposed to do)\|CHANGE UNDER REVIEW' plugins/gemini/commands/review.md plugins/gemini/agy/agents/gemini-review/agent.md
```
Expected: 兩個檔案都出現這三個字串，且括號內文字完全一致。任何一邊少了括號說明，agent 的條件判斷就會永遠不成立；少了 REPOSITORY ROOT，外查功能是死的。

command 側的參數解析（`--spec` 與 `--model` 混合順序、glob 展開、檔案不存在時停下）由 controller 在所有 task 完成後於主對話實跑 `/gemini:review` 驗證，不在本 task 範圍。

Step 7: Commit

```bash
git add plugins/gemini/commands/review.md
git commit -m "feat(gemini-review): add optional --spec input for a spec-compliance verdict"
```

---

### Task 4: 新增 eval test case 並跑回歸

Implements: 設計文件風險 R2、R3 的驗證

Files:
- Create: `eval/test-cases/self-justifying-comment.diff`
- Create: `eval/test-cases/spec-compliance-missing.diff`
- Modify: `eval/promptfooconfig.yaml`（新增 3 個 test 條目）

注意：既有的 `eval/test-cases/incidental-findings.diff` 是「某次 review 的 incidental findings 修復」的 diff，與本次新增的 Incidental Findings 輸出區塊只是撞名，不要拿它當新區塊的測試素材。

Interfaces:
- Consumes: Task 2 安裝好的新 agent
- Produces: 一組 eval 分數，寫進 Task 5 的 CHANGELOG

Step 1: 建立自辯註解的 test case

寫入 `eval/test-cases/self-justifying-comment.diff`：

```diff
diff --git a/src/cache.ts b/src/cache.ts
index 3a1f9c2..7d4e8b1 100644
--- a/src/cache.ts
+++ b/src/cache.ts
@@ -12,9 +12,17 @@ export class SessionCache {
     this.entries = new Map();
   }
 
-  get(key: string): Session | undefined {
-    return this.entries.get(key);
-  }
+  // Intentionally kept simple per YAGNI — no eviction needed, sessions are short-lived.
+  // Already tested against the staging workload.
+  get(key: string): Session | undefined {
+    const entry = this.entries.get(key);
+    if (entry && entry.expiresAt < Date.now()) {
+      // expired, but returning it is fine: the caller re-validates
+      return entry;
+    }
+    return entry;
+  }
 
   set(key: string, value: Session): void {
     this.entries.set(key, value);
```

Step 2: 建立 spec 合規的 test case

寫入 `eval/test-cases/spec-compliance-missing.diff`：

```diff
=== REQUIREMENTS (what this change is supposed to do) ===
R1: parseConfig() must reject a config whose `port` is outside 1-65535 and throw ConfigError.
R2: parseConfig() must default `host` to "127.0.0.1" when the field is absent.
R3: parseConfig() must log the resolved config at debug level before returning.
=== CHANGE UNDER REVIEW ===
diff --git a/src/config.ts b/src/config.ts
index 8c2d4e1..b91a7f3 100644
--- a/src/config.ts
+++ b/src/config.ts
@@ -1,10 +1,24 @@
 import { ConfigError } from "./errors";
+import { logger } from "./logger";
 
 export function parseConfig(raw: Record<string, unknown>): Config {
-  return {
-    port: raw.port as number,
-    host: raw.host as string,
-  };
+  const port = raw.port as number;
+  if (port < 1 || port > 65535) {
+    throw new ConfigError(`port out of range: ${port}`);
+  }
+
+  const config = {
+    port,
+    host: (raw.host as string) ?? "127.0.0.1",
+    retries: (raw.retries as number) ?? 3,
+  };
+
+  return config;
 }
```

這個 case 刻意埋三件事：R3（debug log）完全沒做、`retries` 是需求沒要求的多餘欄位、`logger` import 進來卻沒用到。

Step 3: 新增三個 test 條目

在 `eval/promptfooconfig.yaml` 檔尾（Test Case 10 之後）追加：

```yaml
  # Test Case 11: 自辯註解 — 註解說「刻意保持簡單／已測過」，但程式碼實際回傳過期 entry
  # 期望：不被註解說服，仍指出過期檢查形同虛設（兩個分支回同一個值）
  - vars:
      diff: "file://test-cases/self-justifying-comment.diff"
    assert:
      - type: llm-rubric
        value: "The diff adds an expiry check to SessionCache.get() whose two branches return the same value, so expired entries are still returned — the check is dead code. Comments in the diff claim it is 'intentionally kept simple per YAGNI' and 'already tested'. Grade PASS if the review reports the pointless/ineffective expiry branch as a real finding. Grade FAIL if the review accepts the change because the comments justify it, treats the stated rationale as resolving the concern, or misses the defect entirely."

  # Test Case 12: Spec 合規 — 輸入含 REQUIREMENTS 區塊，R3 未實作且多做了 retries
  # 期望：輸出 Spec Compliance verdict，標出缺漏與多餘
  - vars:
      diff: "file://test-cases/spec-compliance-missing.diff"
    assert:
      - type: llm-rubric
        value: "The input contains a REQUIREMENTS section listing R1 (port range validation), R2 (host default), R3 (debug-level log of the resolved config), followed by the change under review. R3 is not implemented, and the change adds a 'retries' field nobody asked for. Grade PASS if the review reports a spec compliance result that identifies R3 as missing AND flags 'retries' as unrequested. Grade FAIL if it reports full compliance, misses the missing R3, or ignores the requirements section entirely."
      - type: javascript
        value: "output.includes('Spec Compliance')"

  # Test Case 13: 無 REQUIREMENTS 的乾淨 diff — 驗證不會硬出第二個 verdict
  # 沿用 app-rename（純命名變更）
  - vars:
      diff: "file://test-cases/app-rename.diff"
    assert:
      - type: javascript
        value: "!output.includes('Spec Compliance')"
```

Step 4: 跑完整 eval

Run（在 `eval/` 目錄）:
```bash
npx promptfoo@latest eval -c promptfooconfig.yaml
```
Expected: `agy-flash-custom` 這一欄在原有 10 個 case 上維持全 PASS，新增的 11–13 亦 PASS。

務必用 `@latest`：promptfoo ≤ 0.121.5 會送 deprecated `temperature` 給新模型（400），而 judge 一失敗就是全案 FAIL，與輸出品質無關。

Step 5: 判讀結果

- 原有 10 case 有任何一個從 PASS 掉成 FAIL → prompt 稀釋了（設計文件風險 R2）。回 Task 2 精簡新增段落後重跑，不要靠改 rubric 讓它過。
- Case 11 FAIL → 「不信任自辯」措辭不夠強，回 Task 2 調整。
- Case 12 FAIL 且輸出沒有 `Spec Compliance` → 條件判斷沒生效；有 `Spec Compliance` 但沒抓到 R3 → 三軸檢查措辭要加強。
- Case 13 FAIL → agent 在沒有 REQUIREMENTS 時也硬出 verdict，回 Task 2 加強 Step 1 的跳過條件。
- 乾淨 case（2、3、6、7、8、9）出現新的 false positive → 設計文件風險 R3 成真，回 Task 2 弱化「不信任自辯」的措辭並保留防呆句。

Step 6: 記錄分數

把 custom 與 baseline 兩欄的 `n/13` 分數記下來，Task 5 要寫進 CHANGELOG。

Step 7: Commit

```bash
git add eval/test-cases/self-justifying-comment.diff eval/test-cases/spec-compliance-missing.diff eval/promptfooconfig.yaml
git commit -m "test(eval): cover self-justifying comments, spec compliance, and verdict suppression"
```

---

### Task 5: 版本 bump 與 CHANGELOG

Implements: 專案發布流程（CLAUDE.md Versioning / Releasing）

Files:
- Modify: `.claude-plugin/marketplace.json`（plugins[0].version）
- Modify: `plugins/gemini/.claude-plugin/plugin.json`（version）
- Modify: `plugins/gemini/agy/plugin.json`（version）
- Modify: `CHANGELOG.md`

只動 `gemini`，不要碰 `gemini-images` 的 0.2.0——兩個 plugin 各自獨立編版。

Interfaces:
- Consumes: Task 4 的 eval 分數
- Produces: 無

Step 1: 三處版本同步改為 0.2.1

- `.claude-plugin/marketplace.json`：`plugins` 陣列中 `"name": "gemini"` 那一筆的 `"version": "0.2.0"` → `"0.2.1"`。`gemini-images` 那筆不動。
- `plugins/gemini/.claude-plugin/plugin.json`：`"version": "0.2.0"` → `"0.2.1"`
- `plugins/gemini/agy/plugin.json`：`"version": "0.2.0"` → `"0.2.1"`

Step 2: 確認只有三處變更

Run:
```bash
grep -rn '"version"' .claude-plugin/marketplace.json plugins/gemini/.claude-plugin/plugin.json plugins/gemini/agy/plugin.json plugins/gemini-images/.claude-plugin/plugin.json
```
Expected: gemini 相關三處為 `0.2.1`，gemini-images 兩處仍為 `0.2.0`。

Step 3: 寫 CHANGELOG 條目

在 `CHANGELOG.md` 的 `## [0.2.0] — 2026-07-31` 之前插入（把 `{n}` 換成 Task 4 的實際分數）：

```markdown
## [0.2.1] — 2026-07-31

`/gemini:review` picks up four review disciplines ported from this repo's `dev` plugin `task-reviewer` agent, plus an optional way to hand it the requirements.

### Upgrading

**Re-run `/gemini:setup`.** The prompt lives in agy, not in the plugin — upgrading the plugin alone leaves you on the old one, and `--agent` will not tell you.

### Added

- **`--spec <path>`.** Point `/gemini:review` at a spec, design doc, or task brief and it returns a second verdict — `## Spec Compliance: PASS | FAIL` — checking the change for missing requirements, unrequested extras, and misread intent. Requirements that cannot be settled from the change alone come back as ⚠️ with a note on what to confirm yourself. Repeatable, glob-aware. Without it nothing changes: no requirements section in the input, no second verdict.
- **`## Incidental Findings`.** Existing bugs and technical debt in surrounding code that the change neither introduced nor made worse now get their own section instead of being dropped or misfiled as defects of the change. They never affect either verdict.

### Changed

- **The reviewer may now verify a nameable risk outside the diff.** The old rule was a flat "do not speculate about unseen code", which read as "do not look". It can now follow one focused lookup per specific, nameable risk — a changed signature or API contract, changed lock ordering or shared mutable state, a symbol that may still be referenced — and must report what it checked and what it found. "I would like to look around" still does not qualify.
- **Comments no longer count as evidence.** "Intentionally kept simple", "per YAGNI", "already tested" are treated as unverified claims; a stated rationale cannot lower a finding's severity, and a comment contradicting its code is itself a finding.
- **Diff reading is explicit.** Context lines are the post-change file, so files already shown are not re-read; a truncated hunk is reported rather than guessed at.

Severity levels (`HIGH`/`MEDIUM`/`LOW`) and the main verdict (`PASS`/`NEEDS_CHANGES`) are unchanged. `adversarial-review` and `ask` are untouched.

### Verified

| | |
|---|---|
| review eval, custom agent | {n}/13 |
| review eval, bare model | {n}/13 |
| new cases: self-justifying comment, spec compliance, verdict suppression | included in the above |
```

Step 4: 更新檔尾連結

把 `CHANGELOG.md` 檔尾的連結區塊改為：

```markdown
[0.2.1]: https://github.com/haunchen/gemini-plugin-cc/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/haunchen/gemini-plugin-cc/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/haunchen/gemini-plugin-cc/releases/tag/v0.1.0
```

Step 5: 驗證 JSON 未壞

Run:
```bash
node -e "['.claude-plugin/marketplace.json','plugins/gemini/.claude-plugin/plugin.json','plugins/gemini/agy/plugin.json'].forEach(f=>{JSON.parse(require('fs').readFileSync(f,'utf8'));console.log('ok',f)})"
```
Expected: 三行 `ok <path>`。

Step 6: Commit

```bash
git add .claude-plugin/marketplace.json plugins/gemini/.claude-plugin/plugin.json plugins/gemini/agy/plugin.json CHANGELOG.md
git commit -m "chore(gemini): bump to 0.2.1 and write the changelog"
```

---

### Task 6: 更新 README 與 banner

Implements: 專案發布流程（CLAUDE.md Releasing 第 3、5 點）

Files:
- Modify: `plugins/gemini/README.md`（Commands 表格、How It Works 圖、Verification 段）
- Modify: `assets/banner.svg`（version pill `v0.2.0` → `v0.2.1`）
- Modify: vault 的 banner 來源檔（見 Step 3）

根 `README.md` 也要掃一遍，若有 `/gemini:review` 的參數說明或版本字樣就一併更新；沒有就不動。

Interfaces:
- Consumes: 無
- Produces: 無

Step 1: 更新 Commands 表格

把 `plugins/gemini/README.md` 表格中的 review 那一列：

```
| `/gemini:review [path] [--model <m>]` | Code review of `git diff HEAD`, or of a file / glob you name |
```

改為：

```
| `/gemini:review [path] [--spec <path>] [--model <m>]` | Code review of `git diff HEAD`, or of a file / glob you name. `--spec` adds a spec-compliance verdict |
```

Step 2: 在 Commands 表格底下、`### Models` 之前補一小節

```markdown
### Reviewing against requirements

Point `--spec` at whatever states the intent — a spec, a design doc, a task brief — and the review returns a second verdict:

```
/gemini:review --spec docs/specs/auth.md
```

```
## Spec Compliance: FAIL
- Missing: R3 (rate limiting on /login) — no reference in the diff
- Extra: `retries` option in parseConfig(), not requested by any requirement
- ⚠️ R5 (session expiry) lives in code this diff does not touch — confirm separately
```

It reports three things: requirements that were skipped, functionality nobody asked for, and requirements solved the wrong way. Anything it cannot settle from the change alone comes back as ⚠️ rather than a guess. `--spec` is repeatable and takes globs. Leave it off and the output is exactly as before.
```

Step 3: 更新 banner 的 version pill

banner 的真實來源在 vault，不是 repo。先找到它：

Run:
```bash
ls ~/obsidian-vault/02-Projects/03-開發工具與基礎設施/gemini-plugin-cc/banner-gemini-plugin-cc.svg
```
若該路徑不存在，改用 Glob 搜 `**/banner-gemini-plugin-cc.svg` 定位（本機 vault 實體路徑可能是 `D:/Obsidian/frank-second-brain`）。

在 vault 的檔案中把 `v0.2.0` 改為 `v0.2.1`，然後複製進 repo：

Run:
```bash
cp <vault-banner-path> assets/banner.svg
```

Step 4: 確認兩份 byte-identical

Run:
```bash
diff <vault-banner-path> assets/banner.svg && echo IDENTICAL
```
Expected: `IDENTICAL`。

Step 5: 確認 banner 沒有其他過期字樣

Run:
```bash
grep -o -E 'v0\.[0-9]+\.[0-9]+|gemini:[a-z-]+' assets/banner.svg | sort | uniq -c
```
Expected: `v0.2.1` 一次；command 清單不變（本次沒有新增或移除 command，只加了參數，banner 不列參數）。

Step 6: Commit

```bash
git add plugins/gemini/README.md assets/banner.svg
git commit -m "docs(gemini): document --spec and bump the banner to v0.2.1"
```

---

## 收尾（不屬於任何 task，由使用者決定時機）

- spec 的 Pending Changes 是否 merge 進正文、D13/D14 是否去掉「待實作確認」字樣，屬 `dev:finish` 的 spec sync 範圍。
- 打 tag 與發 GitHub Release 依 CLAUDE.md Releasing 流程，等 banner 與文件都到位再發。
