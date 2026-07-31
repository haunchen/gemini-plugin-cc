# /gemini:review 移植 task-reviewer 審查紀律

日期：2026-07-31
狀態：設計已確認，待實作
Spec：`docs/specs/gemini-review.md`（R16–R20 + MODIFIED R4，Pending Changes）

## 背景

`dev` plugin 的 `task-reviewer` agent 是 dev:execute 工作流的單 task 閘門，讀一次 diff 回雙 verdict（spec 合規 + 實作品質）。它有四項紀律是現行 `gemini-review` agent 沒有的，且都能在 gemini-review 的無狀態單次呼叫情境下成立：

| task-reviewer 紀律 | gemini-review 現況 |
|---|---|
| 讀 diff 的方式（讀一次、context 行即變更後檔案、不重跑 git、不爬 codebase） | 只有一句 `Only report problems visible in the diff` |
| 具名風險才做聚焦外查 | 一律不看 diff 外（`Do not speculate about unseen code`，實際效果是「不准查」） |
| 不信任程式碼裡的自辯 | 無 |
| Incidental Findings 分區 | 無，這類問題只能丟棄或誤報成本次缺陷 |
| 雙 verdict（spec 合規 + 實作品質） | 單一 Verdict，且無需求原文可比對 |

不移植的一項：task-reviewer 的「列 issue 前先肯定做得好的地方」。現行 prompt 明寫 `Do NOT praise good code`，兩者直接衝突，決定維持現行。

## 改動範圍

| 檔案 | 改什麼 |
|---|---|
| `plugins/gemini/agy/agents/gemini-review/agent.md` | 主要戰場，五項紀律全寫在 system prompt |
| `plugins/gemini/commands/review.md` | 新增 `--spec <path>` 解析、讀檔、組裝 stdin |
| `docs/specs/gemini-review.md` | Pending Changes 寫 R16–R19 delta |
| 三處 version 檔 | `gemini` plugin bump PATCH 0.2.0 → 0.2.1 |

不動 `adversarial-review` 與 `ask`——它們的角色不是 diff 審查，套 task-reviewer 模式沒有意義。

### 刻意不動的兩件事

**嚴重度術語**維持 `HIGH / MEDIUM / LOW`，不改成 task-reviewer 的 `CRITICAL / IMPORTANT / MINOR`。D3 已把 verdict 與 severity 綁定，改術語要連帶動 spec R11 與 eval rubric，而三級對三級是純換名，換不到品質。

**Verdict 值域**維持 `PASS / NEEDS_CHANGES`。新增的 spec 合規 verdict 是獨立第二個 verdict（`PASS / FAIL`），不與現有那個合併。

## Agent 設計

現行結構是 `Process(Step 0/1/2)` → `Output Format` → `Severity Levels` → `Verdict Criteria` → `Rules`。改為在 Process 前插入紀律節、Process 內擴充、Output Format 加兩區。

### 1. Reading the Diff（收緊）

> 這份 diff 就是你對這次變更的完整視角。context 行即變更後的檔案內容——除非某個你必須判斷的 hunk 被截斷（截斷了就在報告裡明說），否則不要用 view_file 重讀已在 diff 裡的檔案。不要爬整個 codebase。

### 2. 具名風險的聚焦外查（定向放寬）

> 只在讀碼產生**具體可命名的風險**時，才用 view_file / find_by_name 檢查 diff 外的程式碼。一個風險一次聚焦檢查，並在 finding 裡同時寫出風險與你檢查了什麼、看到什麼。合理的具名風險：diff 改了函式或 API 契約、鎖順序、共享可變狀態、或刪改了可能仍有引用的符號——查呼叫點就是對的方法。「我想多看看」不是具名風險。

這兩節是一組的：前者收緊（不重讀已在 diff 的東西），後者定向放寬（只為驗證某個已成形的懷疑）。

連帶改寫現行 Rules 第一條 `Only report problems visible in the diff. Do not speculate about unseen code.`——它現在的效果是「不准看」，新版語意是「不准臆測，但可以去查證」。

### 3. Claims Are Not Evidence

> diff 裡的註解、commit message、PR 描述，都是關於程式碼的**未驗證宣稱**，不是程式碼的一部分。「刻意保持簡單」「per YAGNI 不抽象」「TODO: 之後補」「已測過」這類理由是作者自己給自己打分。照程式碼本身的優劣判斷——宣稱的理由永遠不降低 finding 的嚴重度。若註解與程式碼行為不符，那本身就是一條 finding。

配一句防呆，避免反向過頭：

> 這不代表把所有註解當可疑。只在註解替某段程式碼辯護、而你正在評估那段程式碼時適用。

### 4. Spec Compliance（僅在有需求輸入時執行）

三個檢查面向沿用 task-reviewer：缺漏、多餘、理解偏差。加 ⚠️ 逃生門：

> 若某需求無法只從這次變更驗證（落在未改動的程式碼、或屬於其他變更的範圍）→ 列為 ⚠️ 並說明使用者該自行確認什麼。不要為了驗證它去爬 codebase。

### 5. Incidental Findings

定義寫死在 prompt：**周圍未改動程式碼裡的既有 bug 或明顯技術債，本次 diff 沒有引入也沒有加重它**。無則整區省略。明寫「Incidental Findings 不計入 Verdict」——否則 gemini 會拿舊債擋掉 PASS。

這一區與「聚焦外查」是天然搭檔：外查時撞見的舊問題有地方放，不會被硬塞進本次 findings。

### Output Format（改動後全貌）

```
## Review Summary
{一句話：diff 意圖 + 整體評估}

## Spec Compliance: {PASS | FAIL}        ← 僅在有 REQUIREMENTS 區塊時輸出
- {缺漏 / 多餘 / 理解偏差，各附 file:line}
- ⚠️ {無法從這次變更驗證的需求 + 使用者該自行確認什麼}

## Findings
### [{SEVERITY}] {file_path}:{line_number}
- **Finding**: ...
- **Impact**: ...
- **Suggestion**: ...

## Verdict: {PASS | NEEDS_CHANGES}

## Incidental Findings                    ← 無則整區省略
- {file_path}:{line} — {既有問題描述}
```

## Command 設計

Step 1 多解析一個參數，與 `--model` 同層、順序無關：

```
/gemini:review --spec docs/specs/gemini-review.md
/gemini:review src/foo.ts --spec docs/plans/2026-07-31-x-design.md
```

`--spec` 可重複，每次一個路徑；支援 glob，走既有的 Glob 展開路徑。

讀完檔案後組裝 stdin，用顯式分隔避免 gemini 混淆兩段輸入：

```
=== REQUIREMENTS (what this change is supposed to do) ===
{spec 檔內容}
=== CHANGE UNDER REVIEW ===
{diff 或檔案內容}
```

沒帶 `--spec` 時**完全不輸出 REQUIREMENTS 區塊**。prompt 側以「有沒有這個區塊」決定要不要出第二個 verdict，不需要額外旗標。

## 風險與驗證

三個風險，都要實測而非假設。

### R1: `view_file` 在 review 情境是否真能運作

白名單裡有它，但從沒在 review 路徑上驗過——agy 執行時的工作目錄是 command 的 cwd，相對路徑能不能解析是未知數。若不能，「聚焦外查」就是一句空話。

最小驗證：餵一個改了函式簽章的 diff，看報告裡有沒有出現實際查到的呼叫點。查不到就把這條降級為「明確指出使用者該自己查什麼」。

### R2: prompt 變長導致品質退化

現行 flash-high 在 eval 拿 10/10，這是基準線。agent.md 從 80 行長到約 120 行，指令變多有稀釋風險。改完必跑 `eval/promptfooconfig*.yaml`，數字低於現行就回頭砍。

### R3: 「不信任自辯」推高 false positive

這條與現行 Step 2 的三題校準是拉扯關係——一個要求嚴、一個要求收。eval rubric 本來就評 calibration，會顯示。

### 新增 eval test case

1. 帶 `--spec` 且故意漏做一項需求 → 驗合規 FAIL
2. 不帶 `--spec` 的乾淨 diff → 驗不會硬出第二個 verdict
3. 含自辯註解但實為 bug 的 diff → 驗不被說服

### 收尾（漏了使用者拿到的就是舊 prompt）

- 重跑 `agy plugin install "$(pwd)/plugins/gemini/agy"`
- CHANGELOG 寫明「re-run `/gemini:setup`」

## 決策紀錄

待實作完成後於 `docs/specs/gemini-review.md` 補 D13（移植 task-reviewer 紀律）與 D14（`--spec` 可選需求輸入）。
