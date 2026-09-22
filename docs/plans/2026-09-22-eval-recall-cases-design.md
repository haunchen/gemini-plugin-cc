# 補 eval 的罰漏報案例

**日期**: 2026-09-22
**狀態**: 設計完成，待實作
**相關 spec**: `docs/specs/gemini-review.md`（Pending Changes: R22–R24、D26–D28）

## 問題

`eval/promptfooconfig.yaml` 現行 13 案裡，6 個罰誤報（TC2/3/6/7/8/9）是二元判定，其餘正向案例每個只要求找到它那一個缺陷。結果是「之前報 4 個缺陷、現在報 1 個」會全部 PASS——沒有東西能衡量 reviewer 變安靜的代價。TC10（5 項 incidental findings 要求認出 ≥3）是唯一有計數的。

這個缺口卡住的不只是數字好不好看。D21/D22 已經量到調 prompt 只在搬移失效模式：收窄 LOW 上限就多抓一條真缺陷、同時多虛構一條外鍵，總量不變。沒有罰漏報的錨點，就無法判斷任何 prompt 改動是改善還是把誤報換回來——`docs/specs/gemini-review.md` 的 D20 把這件事列為改 prompt 的前置，MyMoneyBook issue #26 的複查也把它列為四條存活方向的共同卡點。

## 實測前提：原訂的結構化輸出方案不成立

原始構想是把 `eval/agy-provider.js` 改成 `--output-format json` ＋ `--json-schema`，讓計數變確定性。本機實測（agy 1.2.7、`gemini-3.6-flash-high`）推翻了後半：

| 組合 | 結果 |
|---|---|
| `--output-format json`（無 agent） | 可用。外殼為 `{conversation_id, status, response, duration_seconds, num_turns, usage}` |
| `--json-schema` ＋ `--agent gemini-review` | schema 被無聲忽略。吐 markdown、`num_turns: 4`、同一份報告重複四次、6461 output tokens。兩次跑皆然 |
| `--json-schema` 不帶 agent（裸模型） | 吐 JSON，但 `response` 內是兩個串接的 JSON 物件，直接 `JSON.parse` 會炸；且多出 schema 沒有的 `toolAction` / `toolSummary` 鍵 |

原因幾乎確定是 agent prompt 的 `## Output Format` 段與 schema 打架。也就是說結構化輸出在裸模型臂勉強可用、在出貨 agent 臂完全不可用——而後者正是計數型要量的對象。

另一項也未獲證實：外殼沒有 `denied_actions` 欄位。本機亦無法重現權限拒絕（`--agent gemini-review` 直接 `view_file` 讀檔成功），因此拒絕時的 payload 形狀仍屬未知。

## 設計

### 計分模型：每缺陷一條 rubric

每個埋在 fixture 裡的缺陷掛一條獨立 `llm-rubric`，用 promptfoo 的 `metric` 欄位分流彙總：

```yaml
- vars:
    diff: "file://test-cases/migration-cli-entrypoint.diff"
  assert:
    - type: llm-rubric
      metric: recall-L2
      value: "PASS iff the review reports that comparing import.meta.url
        against `file://${process.argv[1]}` is unreliable ..."
    - type: llm-rubric
      metric: fabrication
      value: "FAIL iff the review asserts users.default_account carries a
        foreign key to accounts(id) as established fact — rating it
        MEDIUM/HIGH or letting it drive the verdict. A LOW explicitly
        marked not verifiable from this diff is a PASS."
```

這個形狀解掉的是 judge 偶發解析失敗吃掉訊號的問題（實測 39 格中 4 格，併發降到 2 仍有 1 格）：一次解析失敗只損失 1/N，而且看得出是哪一格，不像單一 rubric 數 findings 那樣整案歸零。代價是每個 cell 的 judge 呼叫數等於缺陷數。

虛構那條的措辭沿用 D21 修正 Test Case 14 rubric 的判準：只罰當成既成事實——斷言、評 MEDIUM/HIGH、或讓它左右 verdict；標明「not verifiable from this diff」的 LOW 明確放行。罰它等於把 prompt 推回沉默，恰是加案例要修的那個單向偏斜。

### 難度分層是標註，不是新案例

門檻型不另造帶梯度的 diff。ground truth 裡給每條缺陷標 tier，score 腳本按 tier 彙總 recall：

- **L1** — 讀 diff 即見，不需額外知識
- **L2** — 需要領域知識或跨 hunk 串接
- **L3** — 需要推理 diff 內看不到的事實（執行期資料形狀、未見的 schema）

`migration-cli-entrypoint.diff` 本身就是現成梯度（G9 明顯 / G4、G10 中等 / G8 需推 schema），`snowflake-filter.diff` 的 `Number()` 精度是現有 fixture 裡另一個 L3。這樣不必憑空造缺陷，且每加一份 fixture 都自動進梯度讀數。

D22 量到的那個 trade-off 正好落在這個維度上：arm N 的「不得臆測未見程式碼」同時擋掉虛構的外鍵與 snowflake 精度，兩者都是 L3。tier 切分讓下次改 prompt 時看得出是不是又在兩種失效模式之間搬運。

### recall 與 fabrication 分開彙總

同一份 fixture 上同時掛兩組 assertion，但兩個數字各自彙總、不平均成一個分數：

```
migration-cli-entrypoint.diff
  recall       G4 G8 G9 G10
  fabrication  N1 N2 N3 N4 N5 N6 N7
報表：recall 3/4 · fabrication 1/7
```

理由是 D21/D22 的核心發現——兩種失效互為代價。只記 recall 會誘導把 prompt 推向亂報。N1–N7 的 ground truth 只在這份 diff 上成立，搬到別處沒有意義，所以不另開第三份 config；另開就得對同一份 diff 跑兩次 review，而 agy 無 sampling 控制，兩次是不同的 sample，配對關係會消失。

新 config 獨立於 `promptfooconfig.yaml`：誤報案例的 PASS 是「沒有多報」，漏報案例的分數是「報出比例」，混在一起算平均會讓兩邊都讀不出來。現行那份維持不動當回歸網。

### provider 變更

`eval/agy-provider.js` 只加 `--output-format json`，不加 `--json-schema`。基礎設施失敗的判別順序：

1. 外殼 `status !== "SUCCESS"` → `error`
2. 外殼解析不出來 → 拿原始文字走現有 `INFRA_FAILURE` regex，走不通則當 `error` 回報並附原始文字
3. 外殼正常但 `response` 命中現有 regex → 維持現行行為

第 2、3 條是保留而非替換。拒絕時 `status` 的值尚未觀測到，在看到一次真實拒絕的 payload 之前，現有 regex 是唯一被驗證過的判別，拆掉它等於用沒驗證的換掉驗證過的。baseline 三輪若跑出拒絕，再依實際 payload 決定是否簡化。

外殼的 `num_turns`、`usage.output_tokens`、`duration_seconds` 放進 provider 回傳的 `metadata`，作為 issue #26 那張「65KB diff → 447 bytes 報告」表的機器版。只記錄，不進任何 assertion——長度不得成為判準（見下）。

### score-recall.mjs

讀 `--output` 的 JSON，把 `CLAUDE.md` 的「一個紅格有三種成因」自動化，逐條 assertion 分類：

- **真失敗** — judge 給出文字判決
- **provider 錯誤** — result 帶 `error`，output 為空
- **judge 解析失敗** — reason 為 `Could not extract JSON from llm-rubric response` 或 `No output`，而 `response.output` 有正常報告

後兩類移出 recall 分母並單獨列計數。不自動化的話三輪跑完就會偷懶，而一個沒扣掉這兩類的分數會低估倒楣的那一臂——服務中斷就是這樣變成捏造的品質退步。

## Fixture 與 ground truth

ground truth 獨立成檔（`eval/ground-truth/<fixture>.md`），記 rubric 承載不了的東西：每條缺陷的證據來源、tier、以及已證偽的誤報清單。rubric 只承載「怎麼判這一條」。

### 計數型

| fixture | 來源 | 真缺陷 | 虛構關卡 |
|---|---|---|---|
| `migration-cli-entrypoint.diff` | `experiment/review-prompt-ab` 分支撿回，連同 `eval/ab/ground-truth.md` | G9 (L1)、G4 (L2)、G10 (L2)、G8 (L3) | N1–N7 |
| `doctor-agy-bin.diff` | 本 repo commit `64f5c42`（13KB，Node hook + bash） | 人工篩，已知至少 `AGY_BIN` 硬編碼一條 | — |
| `large-migration-task.diff` | MyMoneyBook Task 4（25KB） | 人工篩，起點是 issue #26 記載的越界檔 | — |
| `rest-route-async.diff` | MyMoneyBook，D24 用過的 commit（3 檔 68 行） | DELETE 兩寫入未包交易 (L2) | — |

`large-migration-task.diff` 選 Task 4 而非更大的 Task 1，是因為它是唯一同時有兩種量法的：issue #26 記載 gemini 的 Spec Compliance 段寫「無 Missing、Extra 或 Misread 項目」，但該 diff 確實含 task brief `Files:` 清單以外的 `lib/middleware/index.ts`。帶 `=== REQUIREMENTS (what this change is supposed to do) ===` 區塊跑，就能同時量 findings recall 與 spec compliance 的越界檔漏報。

`rest-route-async.diff` 只有一條確認缺陷仍然收：D24 量到 single-shot 帶檔案存取跑兩次皆 PASS 零 finding，這是極少數「確定會漏」的錨點，當敏感度計量器比條數重要。

篩到幾條算幾條，不足 4 條不補 fixture。決定性來自跨 fixture 加總與三輪重複，不來自單份 fixture 的條數。

### 門檻型（沿用現有 fixture，補次級缺陷計分）

| fixture | 主缺陷 | 次級缺陷 |
|---|---|---|
| `hard-cache-key.diff` | key 缺維度 (L2) | 項目永不清除 (L2) |
| `hard-lock-early-return.diff` | early return 繞過 finally (L2) | `_store.load` 在 try 外 (L2) |
| `attribute-shadowing.diff` | `self.update` 遮蔽方法 (L1) | `self.message is not None` 守衛缺漏 (L2) |
| `refactor-display-logic.diff` | 「顯示前 10 個」誤導文案 (L2) | — |
| `snowflake-filter.diff` | `Number()` 精度 (L3) | — |

四條次級缺陷是 3.6 與 3.7 pairwise 實測互相漏掉對方抓到的那組（3.6 抓到 3.7 全漏：`self.message` 守衛、誤導文案；3.7 抓到 3.6 全漏：`_store.load`、快取永不清除）。它們坐在偵測門檻附近，才當得了敏感度計量器——太明顯的缺陷不退化到完全壞掉都會 PASS，量不出東西。

`refactor-display-logic.diff` 同時是現行 config 的 TC6（罰誤報）。兩邊不衝突：TC6 只在報成 HIGH 或安全漏洞時 FAIL，這裡要的是把誤導文案報成 LOW/MEDIUM。但它是唯一在兩份 config 都出現的 fixture，改它要兩邊一起看。

### 跨 repo 素材的取得

MyMoneyBook 為 private 且本機無 checkout。clone 到 scratchpad（不進專案目錄），`git show <sha>` 抽出 diff——那取的是不可變的 commit object，不受分支後續變動影響，不需要 worktree——依既有規則剝掉 commit header 後只把 `.diff` 進版控。clone 本身不進版控。

`large-migration-task.diff` 多一道：`=== REQUIREMENTS (what this change is supposed to do) ===` 與 `=== CHANGE UNDER REVIEW ===` 兩個 marker 寫在檔案開頭，REQUIREMENTS 區塊逐字取自來源 repo 的 task brief。marker 放檔案裡而不是靠 prompt 模板組，是沿用 `spec-compliance-missing.diff` 的既有作法——那是本 repo 唯一驗證過可行的路徑，且讓全域 `prompts:` 對九個案例維持同一份。剝掉 commit header 在這一份尤其要緊：`ea34cad` 的 commit message 主動交代了那個越界檔案的理由，留著等於把答案交給模型。

## 執行順序

硬順序，前一步沒過不往下：

0. **stub provider 空轉**——確認 `assertion.metric` 真的出現在 promptfoo 的輸出 JSON 裡、且逐條 assertion 的結果找得到。這一項才是載重的：`score-recall.mjs` 自己從 `gradingResult.componentResults[]` 加總，不靠 promptfoo 摘要表的具名 metric 欄，但 metric 標籤沒被寫進輸出就沒有東西可以分組，整個計分模型要換形狀。順便量摘要表的彙總行為與 `assert-set` 配 `threshold: 0`，成本為零、不擋計畫（config 沒用到 `assert-set`）。不呼叫 agy，不花 quota
1. `agy-provider.js` 改 `--output-format json`
2. clone MyMoneyBook、worktree 釘 commit、抽 diff、去識別化
3. 寫 ground truth 與 `eval/promptfooconfig-recall.yaml`
4. baseline 三輪

```bash
for r in 1 2 3; do
  npx promptfoo@latest eval -c promptfooconfig-recall.yaml \
    --no-cache --max-concurrency 2 --output "out/recall-r$r.json"
done
node score-recall.mjs out/recall-r*.json
```

三次獨立呼叫而非 `--repeat 3`：要看的是「掉分題目每輪都不一樣」，那需要逐輪對照，塞在同一份輸出裡分不出輪次。

單臂跑——`gemini-review` ＋ `gemini-3.6-flash-high`。不加裸模型或 3.7 對照臂：這份 config 的用途是回歸基準線不是 A/B，兩臂讓三輪成本翻倍而換不到判讀價值。concurrency 固定 2（`CLAUDE.md` 記載 4 時 judge 解析失敗 4/39，降到 2 仍 1/39，再往下換不到東西）。judge 沿用現行 `defaultTest` 的 `claude-sonnet-5`，promptfoo 用 `@latest`。

只有三輪方向一致的數字才寫進 spec 當基準線；單輪波動記在本文件的觀測欄。agy 無任何 sampling 控制，單輪數字不能當基準線。

## 明確不做

兩項都有實測反證：

1. **不加長度下限，也不叫 reviewer「列出 diff 觸及的檔案並與 Files 清單比對」。** 0.2.2 的 A/B 已否決：system prompt 內與 diff 後附加兩處都試過，帶清單 5 次 0 findings、不帶 4 次 2 findings，因此未出貨（D19）。加長度下限與它同族、同受該反證。判準必須是「有沒有報出指定缺陷」，不能是「報告有多長」。provider 記錄的 `output_tokens` 只作觀測，不得進 assertion
2. **不罰明確標示「not verifiable from this diff」的 LOW。** 那正是現行 prompt LOW 上限規則要求的行為（R/D15），罰它等於把 prompt 推回沉默

## 檔案佈局

```
eval/
  promptfooconfig-recall.yaml     新增，現行那份不動
  agy-provider.js                 改：加 --output-format json
  score-recall.mjs                新增
  stub-provider.js                新增，只供機制驗證用，不參與計分
  ground-truth/
    migration-cli-entrypoint.md
    doctor-agy-bin.md
    rest-route-async.md
    large-migration-task.md
    existing-fixtures.md          五份既有 fixture 的次級缺陷與 tier
  test-cases/
    migration-cli-entrypoint.diff 從 experiment 分支撿回
    doctor-agy-bin.diff           本 repo 64f5c42
    rest-route-async.diff         MyMoneyBook 7051d0e
    large-migration-task.diff     MyMoneyBook ea34cad，Task 4，含 spec marker
```

## 決策編號

新決策從 D26 起。D19–D25 保留給 `experiment/review-prompt-ab` 分支上已寫、尚未合併的條目，避免兩邊各自從 D19 開始而在合併時撞號。新 requirement 從 R22 起（master 與該分支目前皆到 R21）。

## Baseline

`gemini-review` ＋ `gemini-3.6-flash-high`，三次獨立呼叫，`--max-concurrency 2`，
promptfoo `@latest`，judge `claude-sonnet-5`。日期：2026-09-22。

```
metric	r1	r2	r3
fabrication	6/7	7/7	7/7
recall-L1	1/2	1/2	1/2
recall-L2	7/12	6/12	7/12
recall-L3	1/2	1/2	1/2
recall-spec	0/1	0/1	0/1
spec-section-present	1/1	1/1	1/1

excluded — provider errors: 0, judge parse failures: 0
These are not quality regressions. They are out of every denominator above.
```

判讀（依 CLAUDE.md「一個紅格有三種成因」）：

- 排除的 provider 錯誤 0 筆、judge 解析失敗 0 筆，已不在上表任何分母內。三輪合計 75 條 assertion（25 條 × 3 輪）全數乾淨。`CLAUDE.md` 記載過歷史上一輪 39 格裡 4 格 judge 解析失敗、併發降到 2 仍 1 格；這次三輪 concurrency 同樣是 2，結果零筆——這是三輪的觀察，不是保證，不代表這個失效模式已解決。

- 三輪方向一致的 metric（可當基準線）：
  - **recall-L1 三輪皆 1/2**：`G9` 三輪皆漏、`AS1` 三輪皆中。`G9` 標的是 L1（讀 diff 即見，不需額外知識）卻三輪全漏，是這次 baseline 最值得注意的一格——tier 標的是所需知識門檻，不是實際命中率，兩者不是單調對應的。
  - **recall-L3 三輪皆 1/2**：`G8` 三輪皆漏、`SF1` 三輪皆中。
  - **recall-spec 三輪皆 0/1**：`LT1` 三輪全漏。這正是 MyMoneyBook issue #26 記載的原始症狀（大 diff 上的空 PASS、Spec Compliance 段漏報越界檔）在本 eval 內的複現。
  - **spec-section-present 三輪皆 1/1**。
  - recall-L2 內部方向一致的個別條目：`G4`、`HC1`、`HC2`、`HL1` 三輪皆中；`RR1`、`LT2` 三輪皆漏。`RR1` 三輪全漏，與 spec D24 記載的「同一份 diff 交給 single-shot 跑兩次、兩次皆 PASS 零 finding」完全吻合——那個錨點複現了。`LT2` 三輪全漏。
  - fabrication 內部方向一致的個別條目：`N2`–`N7`（六條）三輪皆中，僅 `N1` 一條在 r1 失手一次（見下方跳動）。誤報方向幾乎沒有問題，漏報方向才是這次 baseline 的主要失分來源——那正是 S9 要能讀出的那個組合。

- 三輪之間跳動的 metric（抽樣變異，不得單獨引用）：`G10`（recall-L2，X o o）、`DR1`（recall-L2，X X o）、`DR2`（recall-L2，o X X）、`HL2`（recall-L2，o X X）、`AS2`（recall-L2，o X X）、`RD1`（recall-L2，X o o）、`N1`（fabrication，X o o）。25 條裡有 7 條會翻面，其中 6 條落在 recall-L2（使 recall-L2 的彙總數字本身也跟著在 7/12、6/12、7/12 之間跳動，不能單獨引用彙總值當基準線，只有上面列出的個別一致條目可用）、1 條落在 fabrication（`N1`，使 fabrication 彙總在 6/7 與 7/7 之間跳動）。四條選來當敏感度計量點的 pairwise 次級缺陷（`HC2`、`HL2`、`AS2`、`RD1`）裡有三條（`HL2`、`AS2`、`RD1`）落在這個跳動區，只有 `HC2` 三輪全過——它們確實坐在偵測門檻附近，符合當初選它們的理由。

基準線只採三輪方向一致的數字。

注記：AS2 的 rubric 於本 baseline 跑完後（2026-09-22，全分支 Final Review 之後）改寫——
原判準宣稱的機制被 `attribute-shadowing.diff` 自身推翻，詳見
`eval/ground-truth/existing-fixtures.md`。因此上表 AS2 一格的三輪讀數（recall-L2，`o X X`）
反映的是已被取代的判準，不得沿用；下一輪重跑才會得到新判準下的數字。
