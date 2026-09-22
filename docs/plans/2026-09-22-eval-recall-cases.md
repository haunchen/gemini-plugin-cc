# Eval 罰漏報案例 Implementation Plan

Goal: 新增一份獨立的 eval config，用「每缺陷一條 rubric」量出 reviewer 漏報的代價，並把 recall 與 fabrication 兩個數字分開彙總。

Architecture: `eval/promptfooconfig-recall.yaml` 為第二份 config，現行 `promptfooconfig.yaml` 不動當回歸網。每份 fixture 配一份 `eval/ground-truth/<fixture>.md` 記缺陷的證據來源與難度 tier，config 裡每條缺陷掛一條獨立 `llm-rubric` 並以 promptfoo 的 `metric` 欄位分流。`eval/agy-provider.js` 改帶 `--output-format json` 取結構化外殼，`eval/score-recall.mjs` 讀 promptfoo 的 JSON 輸出把三種紅格成因分類後彙總。

Tech Stack: promptfoo（`npx promptfoo@latest`）、Node.js 內建 `node:test`（repo 無 package.json，不引入任何相依）、agy 1.2.x、bash。

Spec: `docs/specs/gemini-review.md`（Pending Changes: R22–R24、S9–S10、D26–D28）

Context: `CONTEXT.md`

## Global Constraints

- 判準一律是「有沒有報出指定缺陷」。任何以報告長度、findings 總數、或檢查清單完整度為判準的 assertion 均不得加入——0.2.2 的 A/B 已否決（帶清單 5 次 0 findings、不帶 4 次 2 findings），見 spec D19。
- 不罰明確標示「not verifiable from this diff」的 LOW。只罰把未查證的事實當成既成事實：斷言、評 MEDIUM/HIGH、或讓它左右 verdict。見 spec D15、D21。
- `eval/promptfooconfig.yaml` 全程不得修改。
- `eval/agy-provider.js` 不得加 `--json-schema`。實測 agy 1.2.7 配 `--agent gemini-review` 時 schema 被無聲忽略、跑 4 turns、報告重複四次。見 spec D26。
- ground truth 只收人工查證或上游追認過的缺陷。推測、未驗證的疑慮一律不進 ground truth，也不進 assertion。
- eval 用的模型固定 `gemini-3.6-flash-high`、agent 固定 `gemini-review`，單臂，不加對照臂。
- promptfoo 一律用 `@latest`；judge 用 `claude-sonnet-5`；`--max-concurrency 2`。
- repo 沒有 package.json 也沒有測試框架。新增的測試一律用 Node 內建 `node --test`，不得新增任何 npm 相依或 package.json。
- 本次變更只動 `eval/`、`docs/` 與根目錄的 `CLAUDE.md`，依 `CLAUDE.md` 的 Versioning 表屬於「Docs, eval configs, CI」，不 bump 任何版本，也不動 `assets/banner.svg`。
- 純資料檔（`.diff` fixture、ground truth `.md`）的跨 task 相依以各 task 的 `Files: Create:` 清單為準，不另寫 `Interfaces` 區塊。只有程式碼與簽章的相依才寫 `Interfaces`。
- MyMoneyBook 的 clone 與 worktree 一律留在 scratchpad（`D:/UserData/Temp/claude/D--UserData-Documents-Code-gemini-plugin-cc/e8660515-3184-4d88-84c6-5a7dc92ce277/scratchpad/`），不得進入專案目錄或版控。只有抽出來的 `.diff` 進版控。
- fixture 的產生規則：`git show <sha> | sed -n '/^diff --git/,$p'`，即剝掉 commit header 只留 diff 本體，不改寫路徑、不改寫內容。這是既有 `migration-cli-entrypoint.diff` 的作法，新 fixture 沿用。
- 唯一例外是需要 spec 合規判定的 fixture：`=== REQUIREMENTS (what this change is supposed to do) ===` 與 `=== CHANGE UNDER REVIEW ===` 兩個 marker 直接寫進 `.diff` 檔開頭，整包由 `{{diff}}` 帶進 prompt。這是既有 `spec-compliance-missing.diff`（`promptfooconfig.yaml` 的 TC12）的作法，且是唯一被驗證過可行的。全域 `prompts:` 模板不得改成條件式——那會讓九個案例共用一個帶分支的模板，而其中八個根本不需要 marker。marker 字串逐字照抄，括號內的說明是字串的一部分（見 spec D16 與 `CLAUDE.md`）。

---

### Task 1: 驗證 promptfoo 的具名 metric 與 assert-set 行為

Implements: `gemini-review.md` #R22

這是整份計畫的前置 spike。真正載重的只有一件事：**`assertion.metric` 必須出現在 promptfoo 的輸出 JSON 裡，且逐條 assertion 的結果找得到**。`score-recall.mjs` 自己從 `gradingResult.componentResults[]` 加總，不依賴 promptfoo 摘要表的具名 metric 欄；但若 `metric` 根本沒被寫進輸出，就沒有東西可以分組，整個計分模型要換形狀。

另外兩項（摘要表是否分開累加、`assert-set` 配 `threshold: 0` 的行為）順便一起量，成本為零。它們不擋計畫：Task 8 的 config 沒有用到 `assert-set`，摘要表也只是方便人眼看。量它們是為了把「文件這樣寫」與「這台機器上的 promptfoo 真的這樣做」分開記下來。

這一步不呼叫 agy，不花 quota。

Files:
- Create: `eval/stub-provider.js`
- Create: `eval/promptfooconfig-metric-probe.yaml`

Interfaces:
- Produces: `eval/stub-provider.js` 匯出一個 promptfoo JS provider class，`config.output` 指定要回傳的字串；後續 task 不依賴它，但它留在 repo 供重新驗證
- Produces: `out/metric-probe.json`（promptfoo 的原始輸出，Task 3 用它確認 JSON 結構）

Step 1: 建立 stub provider

`eval/stub-provider.js`：

```js
// promptfoo provider that returns a fixed string without calling anything.
//
// Exists to verify harness behaviour — named metric aggregation and
// assert-set thresholds — without spending agy quota or introducing model
// variance. Not used by any scoring config.
//
// Usage:
//
//   providers:
//     - id: file://stub-provider.js
//       label: "stub"
//       config:
//         output: "ALPHA BETA"

class StubProvider {
  constructor(options = {}) {
    this.config = options.config || {};
  }

  id() {
    return `stub:${this.config.label || 'default'}`;
  }

  async callApi() {
    return { output: this.config.output || '' };
  }
}

module.exports = StubProvider;
```

Step 2: 建立探針 config

`eval/promptfooconfig-metric-probe.yaml`：

```yaml
description: "Harness probe — named metric aggregation and assert-set threshold. No model calls."

providers:
  - id: file://stub-provider.js
    label: "stub"
    config:
      output: "ALPHA BETA"

prompts:
  - "{{diff}}"

tests:
  # P1: 兩個 metric 各一條通過、一條失敗，確認兩個 metric 分開累加
  - vars:
      diff: "probe-1"
    assert:
      - type: javascript
        metric: recall-L1
        value: "output.includes('ALPHA')"
      - type: javascript
        metric: recall-L2
        value: "output.includes('BETA')"
      - type: javascript
        metric: fabrication
        value: "!output.includes('GAMMA')"

  # P2: 同樣三個 metric，但 recall-L2 與 fabrication 刻意失敗。
  # 若 metric 真的跨 test case 累加，彙總應為 recall-L1 2/2、recall-L2 1/2、fabrication 1/2
  - vars:
      diff: "probe-2"
    assert:
      - type: javascript
        metric: recall-L1
        value: "output.includes('ALPHA')"
      - type: javascript
        metric: recall-L2
        value: "output.includes('ZULU')"
      - type: javascript
        metric: fabrication
        value: "output.includes('GAMMA')"

  # P3: 同樣的失敗包進 threshold 0 的 assert-set，確認整列不記 FAIL
  # 但個別 assertion 的 metric 照樣進彙總
  - vars:
      diff: "probe-3"
    assert:
      - type: assert-set
        threshold: 0
        assert:
          - type: javascript
            metric: recall-L3
            value: "output.includes('ZULU')"
```

Step 3: 跑探針

Run: `cd eval && npx promptfoo@latest eval -c promptfooconfig-metric-probe.yaml --no-cache --output out/metric-probe.json`

Expected: 指令跑完不報錯，產出 `eval/out/metric-probe.json`。

Step 4: 判讀探針結果並記錄

檢查三件事，逐項記錄實際觀察到的值：

1. 終端摘要或 `out/metric-probe.json` 裡是否出現 `recall-L1` / `recall-L2` / `fabrication` 三個具名 metric，且數字為 `recall-L1 2/2`、`recall-L2 1/2`、`fabrication 1/2`。
2. P3 那一列的整列 pass/fail：`threshold: 0` 是否讓它記為 PASS。
3. `out/metric-probe.json` 的實際結構——逐條 assertion 的結果掛在哪個欄位路徑下（預期是每筆 result 的 `gradingResult.componentResults[]`，每項含 `pass`、`score`、`reason`、`assertion.metric`）。

Run: `node -e "const j=require('./out/metric-probe.json'); const rows=j.results?.results??j.results??[]; console.log('rows:',rows.length); console.log(JSON.stringify(rows[1]?.gradingResult,null,2).slice(0,1200)); console.log('namedScores:',JSON.stringify(rows[1]?.namedScores??null));"`（在 `eval/` 下跑）

Expected: 印出每列的 `gradingResult.componentResults` 陣列，每項帶 `assertion.metric`。

決策規則：

- 第 3 點成立（逐條 assertion 找得到，且帶 `assertion.metric`）→ 照計畫往下走，把實際觀察到的欄位路徑寫進 Task 3 的 `readAssertions()`。Task 3 的程式碼已對兩種常見形狀做回退，若實際是第三種，以觀察到的為準改。
- 第 3 點不成立（輸出 JSON 裡沒有 `assertion.metric`，或逐條結果根本不在輸出裡）→ **停下回報使用者**，不要往下走。這是唯一會擋住計畫的分支：沒有 metric 標籤就無法把 recall 與 fabrication 分開，整個計分模型要換形狀。
- 第 1、2 點與預期不符 → 不擋，照實記在本 task 的 commit message 裡。Task 8 本來就不用 `assert-set`，摘要表的數字也只是人眼參考，一切以 `score-recall.mjs` 的彙總為準。

Step 5: Commit

Run: `git add eval/stub-provider.js eval/promptfooconfig-metric-probe.yaml && git commit -m "test(eval): 加 stub provider 與具名 metric 探針"`

`eval/out/` 不進版控（見 Task 8 的 `.gitignore` 步驟；若此時 `eval/.gitignore` 尚未建立，本步驟只 add 上述兩個檔案，不要 `git add eval/`）。

---

### Task 2: agy-provider 改吃結構化外殼

Implements: `gemini-review.md` #R24

Files:
- Modify: `eval/agy-provider.js`
- Create: `eval/tests/agy-provider.test.mjs`

Interfaces:
- Produces: `eval/agy-provider.js` 除 default export 的 `AgyProvider` class 外，另掛 `AgyProvider.parseAgyResult`，簽章為 `parseAgyResult(stdout: string, stderr: string, exitCode: number|null): { output?: string, error?: string, metadata?: { num_turns: number, output_tokens: number, duration_seconds: number } }`
- Consumes: 無

Step 1: 寫失敗的測試

`eval/tests/agy-provider.test.mjs`（新建目錄 `eval/tests/`）：

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import AgyProvider from '../agy-provider.js';

const { parseAgyResult } = AgyProvider;

function envelope(extra = {}) {
  return JSON.stringify({
    conversation_id: 'c1',
    status: 'SUCCESS',
    response: '## Review Summary\nfine\n\n## Verdict: PASS',
    duration_seconds: 1.5,
    num_turns: 1,
    usage: { input_tokens: 100, output_tokens: 42, total_tokens: 142 },
    ...extra,
  });
}

test('成功的外殼取出 response 並帶上 metadata', () => {
  const r = parseAgyResult(envelope(), '', 0);
  assert.equal(r.error, undefined);
  assert.match(r.output, /## Verdict: PASS/);
  assert.equal(r.metadata.num_turns, 1);
  assert.equal(r.metadata.output_tokens, 42);
  assert.equal(r.metadata.duration_seconds, 1.5);
});

test('status 不是 SUCCESS 一律回 error', () => {
  const r = parseAgyResult(envelope({ status: 'DENIED' }), '', 0);
  assert.equal(r.output, undefined);
  assert.match(r.error, /DENIED/);
});

test('外殼解析不出來時回退到既有 regex 判別', () => {
  const r = parseAgyResult('Error: Agent execution terminated due to error.', '', 0);
  assert.equal(r.output, undefined);
  assert.match(r.error, /Agent execution terminated/);
});

test('外殼解析不出來且不像基礎設施失敗時，仍回 error 並附原始文字', () => {
  const r = parseAgyResult('some unstructured chatter', '', 0);
  assert.equal(r.output, undefined);
  assert.match(r.error, /some unstructured chatter/);
});

test('外殼正常但 response 命中既有 regex 仍判為 error', () => {
  const r = parseAgyResult(
    envelope({ response: 'jetski: no output produced — a tool required the "read_file" permission' }),
    '',
    0,
  );
  assert.equal(r.output, undefined);
  assert.match(r.error, /no output produced/);
});

test('完全沒有輸出時回 error 並帶 exit code', () => {
  const r = parseAgyResult('', '', 3);
  assert.equal(r.output, undefined);
  assert.match(r.error, /exit 3/);
});
```

Step 2: 跑測試確認失敗

Run: `node --test eval/tests/agy-provider.test.mjs`

Expected: FAIL（`parseAgyResult` 尚未存在，六個測試全數失敗）

Step 3: 實作

`eval/agy-provider.js` 的修改分三處。

第一處，在檔案頂端的 usage 註解之後、`const { spawn }` 之前，把說明 `--json-schema` 為何不用的段落補進頭部註解。找到這一段：

```js
//   providers:
//     - id: file://agy-provider.js
//       label: "flash-custom"
//       config:
//         agent: gemini-review      # omit for the bare model (no system prompt)
//         model: gemini-3.6-flash-high
//         addDir: /path/to/repo     # optional; grants file reads
//         timeout: 5m               # optional, passed to --print-timeout
```

在其後插入：

```js
//
// The call carries --output-format json, which wraps the reply in
// {conversation_id, status, response, duration_seconds, num_turns, usage}.
// `status` is the first thing checked: it is a field agy sets, not a string
// we pattern-match out of prose.
//
// It deliberately does NOT carry --json-schema. Measured on agy 1.2.7 with
// --agent gemini-review: the schema is silently ignored, the reply comes back
// as markdown, num_turns is 4, and the same report is repeated four times for
// 6461 output tokens. The agent prompt's "## Output Format" section wins.
// Without --agent the bare model does emit JSON, but `response` then holds two
// concatenated JSON objects. The arm that works is not the arm being measured.
```

第二處，在 `function infraFailure(output)` 之後、`function timeoutToMs(value)` 之前，插入新函式：

```js
// Parse agy's --output-format json envelope.
//
// Three layers, in order, because only the first one is new and the other two
// are the only detection that has actually been verified:
//   1. envelope.status !== "SUCCESS"
//   2. envelope unparseable -> fall back to the regex heuristics on raw text
//   3. envelope fine but response matches the heuristics (e.g. the one-line
//      "no output produced" a discarded turn leaves behind)
//
// Layer 1 alone is not enough: a permission denial could not be reproduced on
// the machine this was written on (--agent gemini-review read a file fine), so
// what `status` holds for a denial is unknown. Dropping layers 2 and 3 would
// trade verified detection for unverified detection.
function parseAgyResult(stdout, stderr, exitCode) {
  const raw = `${stdout}${stderr}`.trim();
  if (!raw) {
    return { error: `agy produced no output (exit ${exitCode})` };
  }

  let envelope = null;
  try {
    envelope = JSON.parse(raw);
  } catch {
    envelope = null;
  }

  if (!envelope || typeof envelope !== 'object' || typeof envelope.response !== 'string') {
    if (infraFailure(raw)) {
      return { error: `agy did not return a response: ${raw.slice(0, 300)}` };
    }
    return { error: `agy returned an unparseable envelope: ${raw.slice(0, 300)}` };
  }

  if (envelope.status !== 'SUCCESS') {
    return { error: `agy returned status ${envelope.status}: ${raw.slice(0, 300)}` };
  }

  const output = envelope.response.trim();
  if (!output) {
    return { error: `agy returned an empty response (exit ${exitCode})` };
  }
  if (infraFailure(output)) {
    return { error: `agy did not return a response: ${output.slice(0, 300)}` };
  }

  return {
    output,
    metadata: {
      num_turns: envelope.num_turns,
      output_tokens: envelope.usage && envelope.usage.output_tokens,
      duration_seconds: envelope.duration_seconds,
    },
  };
}
```

第三處，`callApi` 內加上 flag 並改用新函式。把這兩段：

```js
    args.push('--model', this.config.model);
    args.push('--print-timeout', timeout);
    if (this.config.addDir) args.push('--add-dir', this.config.addDir);
```

改為：

```js
    args.push('--model', this.config.model);
    args.push('--print-timeout', timeout);
    args.push('--output-format', 'json');
    if (this.config.addDir) args.push('--add-dir', this.config.addDir);
```

把 `child.on('close', ...)` 整個 handler：

```js
      child.on('close', (code) => {
        const output = `${stdout}${stderr}`.trim();
        if (!output) {
          finish({ error: `agy produced no output (exit ${code})` });
          return;
        }
        if (infraFailure(output)) {
          finish({ error: `agy did not return a response: ${output.slice(0, 300)}` });
          return;
        }
        finish({ output });
      });
```

改為：

```js
      child.on('close', (code) => {
        finish(parseAgyResult(stdout, stderr, code));
      });
```

最後把檔尾：

```js
module.exports = AgyProvider;
```

改為：

```js
AgyProvider.parseAgyResult = parseAgyResult;

module.exports = AgyProvider;
```

Step 4: 跑測試確認通過

Run: `node --test eval/tests/agy-provider.test.mjs`

Expected: PASS，6 個測試全過。

Step 5: 對真實 agy 做一次端對端確認

Run（在 `eval/` 下）：

```bash
node -e "
const P = require('./agy-provider.js');
const p = new P({ config: { agent: 'gemini-review', model: 'gemini-3.6-flash-high', timeout: '5m' } });
const fs = require('fs');
p.callApi('Review this diff:\n\n' + fs.readFileSync('test-cases/self-justifying-comment.diff','utf8'))
  .then(r => console.log('error:', r.error, '| meta:', JSON.stringify(r.metadata), '| head:', (r.output||'').slice(0,120)));
"
```

Expected: `error: undefined`，`meta` 有 `num_turns`/`output_tokens`/`duration_seconds` 三個數字，`head` 是 `## Review Summary` 開頭的 markdown。若回 error，先確認 agy 可用（`agy --version`、`agy agents` 有 `gemini-review`），不要改測試去配合。

Step 6: Commit

Run: `git add eval/agy-provider.js eval/tests/agy-provider.test.mjs && git commit -m "feat(eval): provider 改吃 --output-format json 的結構化外殼"`

---

### Task 3: score-recall.mjs

Implements: `gemini-review.md` #R24, #S10

Files:
- Create: `eval/score-recall.mjs`
- Create: `eval/tests/score-recall.test.mjs`

Interfaces:
- Consumes: Task 1 Step 4 觀察到的 promptfoo 輸出 JSON 結構
- Produces: `eval/score-recall.mjs` 匯出
  - `function readAssertions(json: object): Array<{ metric: string, pass: boolean, reason: string, hasOutput: boolean }>`
  - `function classify(a: { pass: boolean, reason: string, hasOutput: boolean }): 'pass' | 'fail' | 'provider-error' | 'judge-error'`
  - `function aggregate(runs: Array<object>): { rounds: Array<Record<string, {pass:number,total:number}>>, excluded: { providerError: number, judgeError: number } }`
  - 以 `node score-recall.mjs <file...>` 執行時印出報表

Step 1: 寫失敗的測試

`eval/tests/score-recall.test.mjs`：

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readAssertions, classify, aggregate } from '../score-recall.mjs';

function run(components) {
  return {
    results: {
      results: [
        {
          response: { output: '## Review Summary\nsomething' },
          gradingResult: { componentResults: components },
        },
      ],
    },
  };
}

test('classify 認得真失敗', () => {
  assert.equal(classify({ pass: false, reason: 'The review never mentions the lock', hasOutput: true }), 'fail');
});

test('classify 認得 provider 錯誤', () => {
  assert.equal(
    classify({ pass: false, reason: 'agy did not return a response: 503', hasOutput: false }),
    'provider-error',
  );
});

test('classify 認得 judge 解析失敗', () => {
  assert.equal(
    classify({ pass: false, reason: 'Could not extract JSON from llm-rubric response', hasOutput: true }),
    'judge-error',
  );
  assert.equal(classify({ pass: false, reason: 'No output', hasOutput: true }), 'judge-error');
});

test('classify 認得通過', () => {
  assert.equal(classify({ pass: true, reason: 'ok', hasOutput: true }), 'pass');
});

test('readAssertions 取出 metric 與判定', () => {
  const rows = readAssertions(
    run([
      { pass: true, reason: 'ok', assertion: { type: 'llm-rubric', metric: 'recall-L1' } },
      { pass: false, reason: 'missed it', assertion: { type: 'llm-rubric', metric: 'recall-L2' } },
    ]),
  );
  assert.equal(rows.length, 2);
  assert.deepEqual(
    rows.map((r) => [r.metric, r.pass]),
    [
      ['recall-L1', true],
      ['recall-L2', false],
    ],
  );
  assert.equal(rows[0].hasOutput, true);
});

test('readAssertions 對沒有 metric 的 assertion 給 unlabelled', () => {
  const rows = readAssertions(run([{ pass: true, reason: 'ok', assertion: { type: 'javascript' } }]));
  assert.equal(rows[0].metric, 'unlabelled');
});

test('aggregate 逐輪彙總並把兩類非模型紅格移出分母', () => {
  const r1 = run([
    { pass: true, reason: 'ok', assertion: { metric: 'recall-L1' } },
    { pass: false, reason: 'missed it', assertion: { metric: 'recall-L2' } },
    { pass: false, reason: 'Could not extract JSON from llm-rubric response', assertion: { metric: 'recall-L2' } },
  ]);
  const out = aggregate([r1]);
  assert.equal(out.rounds.length, 1);
  assert.deepEqual(out.rounds[0]['recall-L1'], { pass: 1, total: 1 });
  assert.deepEqual(out.rounds[0]['recall-L2'], { pass: 0, total: 1 });
  assert.equal(out.excluded.judgeError, 1);
  assert.equal(out.excluded.providerError, 0);
});
```

Step 2: 跑測試確認失敗

Run: `node --test eval/tests/score-recall.test.mjs`

Expected: FAIL（`score-recall.mjs` 不存在，無法 import）

Step 3: 實作

`eval/score-recall.mjs`：

```js
#!/usr/bin/env node
// Read promptfoo JSON output and report recall / fabrication per round.
//
// Exists because a red cell in promptfoo has three possible causes and only
// one of them is the model (see CLAUDE.md). Picking the other two out by hand
// every round is the kind of chore that gets skipped, and a score reported
// without excluding them understates whichever arm got unlucky — which is how
// a service outage turns into a fabricated quality regression.
//
// Usage: node score-recall.mjs out/recall-r1.json out/recall-r2.json ...

import { readFileSync } from 'node:fs';

// promptfoo has moved this path around between versions; accept both shapes
// and fail loudly rather than silently scoring zero rows.
function resultRows(json) {
  const rows = json?.results?.results ?? json?.results ?? [];
  if (!Array.isArray(rows)) return [];
  return rows;
}

export function readAssertions(json) {
  const out = [];
  for (const row of resultRows(json)) {
    const hasOutput = Boolean(row?.response?.output);
    const components = row?.gradingResult?.componentResults ?? [];
    for (const c of components) {
      out.push({
        metric: c?.assertion?.metric ?? 'unlabelled',
        pass: Boolean(c?.pass),
        reason: String(c?.reason ?? ''),
        hasOutput,
      });
    }
  }
  return out;
}

const JUDGE_ERROR = /Could not extract JSON from llm-rubric response|^No output$/;
const PROVIDER_ERROR = /agy did not return a response|agy produced no output|agy returned status|agy returned an unparseable envelope|agy failed to start|agy did not exit within/;

export function classify(a) {
  if (a.pass) return 'pass';
  if (PROVIDER_ERROR.test(a.reason) || !a.hasOutput) return 'provider-error';
  if (JUDGE_ERROR.test(a.reason.trim())) return 'judge-error';
  return 'fail';
}

export function aggregate(runs) {
  const rounds = [];
  const excluded = { providerError: 0, judgeError: 0 };

  for (const json of runs) {
    const byMetric = {};
    for (const a of readAssertions(json)) {
      const verdict = classify(a);
      if (verdict === 'provider-error') {
        excluded.providerError += 1;
        continue;
      }
      if (verdict === 'judge-error') {
        excluded.judgeError += 1;
        continue;
      }
      byMetric[a.metric] ??= { pass: 0, total: 0 };
      byMetric[a.metric].total += 1;
      if (verdict === 'pass') byMetric[a.metric].pass += 1;
    }
    rounds.push(byMetric);
  }

  return { rounds, excluded };
}

function report(files) {
  const runs = files.map((f) => JSON.parse(readFileSync(f, 'utf8')));
  const { rounds, excluded } = aggregate(runs);

  const metrics = [...new Set(rounds.flatMap((r) => Object.keys(r)))].sort();
  const header = ['metric', ...files.map((_, i) => `r${i + 1}`)].join('\t');
  console.log(header);
  for (const m of metrics) {
    const cells = rounds.map((r) => (r[m] ? `${r[m].pass}/${r[m].total}` : '-'));
    console.log([m, ...cells].join('\t'));
  }

  console.log('');
  console.log(`excluded — provider errors: ${excluded.providerError}, judge parse failures: ${excluded.judgeError}`);
  console.log('These are not quality regressions. They are out of every denominator above.');
}

if (import.meta.url === `file://${process.argv[1]}` || process.argv[1]?.endsWith('score-recall.mjs')) {
  const files = process.argv.slice(2);
  if (files.length === 0) {
    console.error('usage: node score-recall.mjs <promptfoo-output.json> [...]');
    process.exit(1);
  }
  report(files);
}
```

Step 4: 跑測試確認通過

Run: `node --test eval/tests/score-recall.test.mjs`

Expected: PASS，7 個測試全過。

Step 5: 對 Task 1 的真實輸出跑一次

Run: `node eval/score-recall.mjs eval/out/metric-probe.json`

Expected: 印出含 `recall-L1`、`recall-L2`、`fabrication`、`recall-L3` 四列的表，`recall-L1` 為 `2/2`、`recall-L2` 為 `1/2`、`fabrication` 為 `1/2`、`recall-L3` 為 `0/1`；excluded 兩項皆為 0。

若印出空表，代表 `readAssertions()` 的欄位路徑與實際不符——以 Task 1 Step 4 記錄的實際路徑就地修正 `readAssertions()` 與對應測試，不要改 `aggregate()`。

Step 6: Commit

Run: `git add eval/score-recall.mjs eval/tests/score-recall.test.mjs && git commit -m "feat(eval): 加 score-recall，分類三種紅格成因並逐輪彙總"`

---

### Task 4: migration-cli-entrypoint fixture 與 ground truth

Implements: `gemini-review.md` #R22, #R23

這份 fixture 與它的 ground truth 已存在於 `experiment/review-prompt-ab` 分支，不重新產生，直接取回。

Files:
- Create: `eval/test-cases/migration-cli-entrypoint.diff`（從分支取回，18610 bytes）
- Create: `eval/ground-truth/migration-cli-entrypoint.md`

Step 1: 取回 fixture

Run:

```bash
mkdir -p eval/ground-truth
git show origin/experiment/review-prompt-ab:eval/test-cases/migration-cli-entrypoint.diff > eval/test-cases/migration-cli-entrypoint.diff
wc -c eval/test-cases/migration-cli-entrypoint.diff
```

Expected: `18610`（若分支後續有變動則數字不同，以檔案內容以 `diff --git a/backend/package.json` 開頭為準）

Step 2: 寫 ground truth

`eval/ground-truth/migration-cli-entrypoint.md`：

```markdown
# migration-cli-entrypoint.diff

一支 SQLite → PostgreSQL 的一次性搬遷腳本及其測試。來源為私有專案，不隨本 repo 出貨；
本檔的內容原出自 `experiment/review-prompt-ab` 分支的 `eval/ab/ground-truth.md`，
隨 fixture 一併移到這裡，因為 recall 計分需要它。

下列每一項都對照來源 repo 的實際檔案驗證過，不是從 diff 推測的。

## 真缺陷（recall 點）

| ID | tier | 缺陷 | 證據 |
|----|------|------|------|
| G9 | L1 | `better-sqlite3` 列在 `devDependencies`，但搬遷腳本在執行期 import 它。未安裝 dev 相依的環境會 `Cannot find package` | diff 內同時可見 devDependencies 與 import，不需外部知識 |
| G4 | L2 | CLI 進入點的 `import.meta.url === \`file://${process.argv[1]}\`` 不可靠。`argv[1]` 是檔案系統路徑、`import.meta.url` 是 URL，路徑需 percent-encoding（含空白或非 ASCII）或經過 symlink 時兩者發散。此時 CLI 靜默 exit 0，不搬移也不印訊息。應改用 `pathToFileURL(process.argv[1]).href` | 實測 Node v22.22.2，三種路徑形狀的比對結果記於下方「已證偽的機制」 |
| G10 | L2 | SQLite handle 在 `try` 之前建立。若 `pool.connect()` 拋錯，`finally` 內的 `src.close()` 不會執行，檔案 handle 洩漏 | 讀 diff 可見，但要串接 try 的起點與 finally 的內容 |
| G8 | L3 | `settlement_account_id` 的第二輪回填沒有檢查參照的帳戶是否存在。schema 中該欄有 `REFERENCES accounts(id)`，來源資料若有懸空參照會觸發外鍵違反並中止整個 transaction | schema 不在 diff 內。2026-08-02 由 fan-out 原型找出，查證階段開 schema 確認該欄確有 `REFERENCES`；所有 single-shot 跑法都沒報出 |

G9 的嚴重度有爭議。查證階段判過 HIGH，但這是一支手動執行的一次性腳本，失敗是啟動時
立刻可見的 module not found，不是資料損失。severity 不進 rubric 判準，只判有沒有報出來。

## 虛構關卡（fabrication 點）

下列宣稱經查證為假。判準只罰「當成既成事實」——斷言、評 MEDIUM/HIGH、或讓它左右 verdict。
明確標示「not verifiable from this diff」的 LOW 一律視為通過（見 spec D15、D21）。

| ID | 常見誤報 | 為何不成立 |
|----|----------|-----------|
| N1 | `users.default_account` 是指向 `accounts` 的前向外鍵，插入順序有問題 | 該欄為純 `BIGINT`，沒有 `REFERENCES`。真正的約束方向相反（`accounts.user_id REFERENCES users(id)`），現行順序反而是對的 |
| N2 | 帶原 id 顯式 insert 會被 identity 擋 | 主鍵是 `GENERATED BY DEFAULT AS IDENTITY`，合法 |
| N3 | `setval` 的 `GREATEST(max, 1)` 會讓空表從 2 開始 | 第三參數 `is_called` 在空表時為 false，下一個 id 為 1，正確 |
| N4 | 測試用 SQLite 的 `?` 佔位符，PostgreSQL 會語法錯誤 | DB 層的 `queryOne` 會先過 `toPositional(sql)`，把 `?` 改寫成 `$1` |
| N5 | `TRUNCATE ... CASCADE` 沒有防呆 | spec 明文要求「可重複執行（每次先清空目標表）」，防呆從未被要求 |
| N6 | 硬編碼欄位清單會靜默丟欄 | 清單與 schema 的八張表逐欄比對一致 |
| N7 | 只驗 `SUM(balance)` 不足以保證逐帳戶一致 | 資料是帶原 id、全欄位、單一 transaction 內直接複製，不存在能產生「SUM 相等但逐筆不等」的機制 |

N5–N7 曾被列為真缺陷，2026-08-02 查證後移到此處，見 `docs/specs/gemini-review.md` 的 D19 Correction。

## 已證偽的機制（結論對但理由錯）

G4 常見的錯誤說法是「透過 `pnpm` 或相對路徑呼叫時 `argv[1]` 維持相對，所以比對失敗」。
實測 Node v22.22.2：

```
node sub/probe.mjs        argv1 = /private/tmp/argvtest/sub/probe.mjs      naive eq = true
含空白的路徑               meta.url 內是 my%20dir                           naive eq = false
經 symlink 的路徑          argv1 = /tmp/...  meta.url = /private/tmp/...    naive eq = false
```

Node 一律把 `argv[1]` 正規化成絕對路徑，故相對呼叫不會讓比對失敗。G4 的 rubric 不要求
模型講對機制，只要求它指出這個比對不可靠——機制講錯不扣分，但也不因此加分。
```

Step 3: 確認兩個檔案都在

Run: `ls -l eval/test-cases/migration-cli-entrypoint.diff eval/ground-truth/migration-cli-entrypoint.md && head -1 eval/test-cases/migration-cli-entrypoint.diff`

Expected: 兩檔存在；diff 第一行為 `diff --git a/backend/package.json b/backend/package.json`

Step 4: Commit

Run: `git add eval/test-cases/migration-cli-entrypoint.diff eval/ground-truth/migration-cli-entrypoint.md && git commit -m "test(eval): 取回 migration-cli-entrypoint fixture 與其 ground truth"`

---

### Task 5: doctor-agy-bin fixture 與 ground truth

Implements: `gemini-review.md` #R22, #R23

Files:
- Create: `eval/test-cases/doctor-agy-bin.diff`
- Create: `eval/ground-truth/doctor-agy-bin.md`

Step 1: 產生 fixture

Run:

```bash
git show 64f5c42 | sed -n '/^diff --git/,$p' > eval/test-cases/doctor-agy-bin.diff
wc -c eval/test-cases/doctor-agy-bin.diff
grep -c '^diff --git' eval/test-cases/doctor-agy-bin.diff
```

Expected: 檔案約 12–13 KB；`grep -c` 回 6（該 commit 動了 6 個檔案）。

Step 2: 寫 ground truth

`eval/ground-truth/doctor-agy-bin.md`：

```markdown
# doctor-agy-bin.diff

本 repo 自己的 commit `64f5c42`（`feat(gemini-images)!: describe images through agy`，
6 檔、Node hook + bash）。不需去識別化，內容就是本 repo 的歷史。

## 真缺陷（recall 點）

| ID | tier | 缺陷 | 證據 |
|----|------|------|------|
| DR1 | L2 | `scripts/doctor.sh` 完全不吃 `AGY_BIN`。診斷輸出那一行印出 `AGY_BIN: ${AGY_BIN:-agy (default)}`，但實際的檢查、執行與版本查詢全部硬編碼 `agy`；同一個 commit 裡的 `hooks/image-describe.mjs` 用的是 `process.env.AGY_BIN \|\| "agy"`。設了 `AGY_BIN` 的使用者會拿到與 hook 不一致的診斷結果 | HEAD 仍存在：`plugins/gemini-images/scripts/doctor.sh` 第 47/55/56/94/95 行硬編碼，第 91 行印出該變數。2026-08-02 由 fan-out 原型找出後人工複查確認，待獨立修復 |
| DR2 | L2 | doctor 檢查 agent 是否安裝時硬編碼 `$HOME/.gemini/config/plugins/...`，未走 `GEMINI_CONFIG_DIR`。agy 在其他平台的 config 路徑未經實測，猜錯會讓 doctor 對已正確安裝的使用者回報 `agent missing` | HEAD 第 63 行。同 repo 的 `plugins/gemini/hooks/check-agent-version.sh:13` 用的是 `${GEMINI_CONFIG_DIR:-$HOME/.gemini}`，是相反的作法（該 hook 晚於本 commit，故 commit 當下 repo 內尚無先例）。證據強度低於 DR1：來自 fan-out 第二輪回收 |

## 不收進 recall 的疑慮

- **移除 `@path` 的空白跳脫**。commit message 主張「agy takes a plain path, so the
  space-escaping workaround is no longer needed」。這是 commit message 裡的宣稱，未經
  實測驗證，因此不進 ground truth。若日後實測證實含空白的路徑會壞，再補成 recall 點。
```

Step 3: 確認

Run: `ls -l eval/test-cases/doctor-agy-bin.diff eval/ground-truth/doctor-agy-bin.md && head -1 eval/test-cases/doctor-agy-bin.diff && grep -n 'AGY_BIN' eval/test-cases/doctor-agy-bin.diff | head -3`

Expected: 兩檔存在；diff 第一行以 `diff --git a/plugins/gemini-images/` 開頭；grep 找得到 `AGY_BIN` 的行。

Step 4: Commit

Run: `git add eval/test-cases/doctor-agy-bin.diff eval/ground-truth/doctor-agy-bin.md && git commit -m "test(eval): 加 doctor-agy-bin fixture 與其 ground truth"`

---

### Task 6: 跨 repo 抽出兩份 fixture

Implements: `gemini-review.md` #R22, #R23

來源 repo 為私有的 `haunchen/MyMoneyBook`，本機無 checkout。clone 與 worktree 一律留在
scratchpad，只有抽出來的 `.diff` 進版控。

兩個來源 commit 已定位完成，不需再找：

- `7051d0e refactor(api): accounts route 改為非同步查詢` — 3 檔、68 insertions，即 spec D24 量測用的那份
- `ea34cad feat(idempotency): 佔位收斂為單語句條件式 upsert，解除單連線假設` — 5 檔、23003 bytes，即 MyMoneyBook issue #26 表中的 Task 4

Files:
- Create: `eval/test-cases/rest-route-async.diff`
- Create: `eval/test-cases/large-migration-task.diff`
- Create: `eval/ground-truth/rest-route-async.md`
- Create: `eval/ground-truth/large-migration-task.md`

Step 1: clone 並抽出 rest-route fixture

Run（`$SCRATCH` 代入本 session 的 scratchpad 路徑；repo 若已 clone 過則跳過 clone）：

```bash
SCRATCH="D:/UserData/Temp/claude/D--UserData-Documents-Code-gemini-plugin-cc/e8660515-3184-4d88-84c6-5a7dc92ce277/scratchpad"
[ -d "$SCRATCH/mmb" ] || gh repo clone haunchen/MyMoneyBook "$SCRATCH/mmb"
git -C "$SCRATCH/mmb" show 7051d0e | sed -n '/^diff --git/,$p' > eval/test-cases/rest-route-async.diff
wc -c eval/test-cases/rest-route-async.diff
```

Expected: 約 17.7 KB（略小於 `git show` 的完整輸出，因為剝掉了 commit header）。

`git show <sha>` 取的是不可變的 commit object，不受分支後續變動影響，因此不需要建 worktree。

Step 2: 組裝 large-migration-task fixture（帶 spec marker）

這一份與其他 fixture 不同：它要帶 `=== REQUIREMENTS (what this change is supposed to do) ===`
與 `=== CHANGE UNDER REVIEW ===` 兩個 marker，整包由 `{{diff}}` 帶進 prompt。這是
`spec-compliance-missing.diff`（`promptfooconfig.yaml` 的 TC12）已在用的作法，也是本 repo
唯一驗證過可行的作法——全域 `prompts:` 模板維持只插值 `{{diff}}`，不改成條件式。

REQUIREMENTS 區塊的內容逐字取自來源 repo 的 task brief：
`git -C "$SCRATCH/mmb" show 55e8420:docs/plans/2026-08-01-postgres-migration.md | sed -n '1288,1310p'`

Run：

```bash
SCRATCH="D:/UserData/Temp/claude/D--UserData-Documents-Code-gemini-plugin-cc/e8660515-3184-4d88-84c6-5a7dc92ce277/scratchpad"
{
cat <<'BRIEF'
=== REQUIREMENTS (what this change is supposed to do) ===
### Task 4: 冪等佔位改為單語句原子操作

Implements: `postgres-migration.md` #R3, #R4

Files:
- Modify: `backend/lib/middleware/idempotency.ts`（整檔重寫）
- Test: `backend/tests/middleware/idempotency.test.ts`（整檔重寫）
- Test: `backend/tests/middleware/idempotency-release.test.ts`（改 async）
- Test: `backend/tests/db/idempotency-schema.test.ts`（整檔重寫）

Interfaces:
- Consumes: Task 1 的 `Db`、Task 3 的 `createTestDb` / `createTestUser`
- Produces: `lib/middleware/idempotency.ts` 匯出
  - `const EXPIRY_SECONDS: number`（值為 300）
  - `function hashBody(text: string): string`
  - `type IdempotencyClaim = { type: 'claimed' } | { type: 'replay'; response: string; status: number } | { type: 'in_progress' } | { type: 'conflict' }`
  - `async function claimIdempotency(db: Db, userId: number, key: string, bodyHash: string): Promise<IdempotencyClaim>`
  - `async function finalizeIdempotency(db: Db, userId: number, key: string, response: string, status: number): Promise<void>`
  - `async function releaseIdempotency(db: Db, userId: number, key: string): Promise<void>`
  - `async function cleanExpiredKeys(db: Db): Promise<void>`
=== CHANGE UNDER REVIEW ===
BRIEF
git -C "$SCRATCH/mmb" show ea34cad | sed -n '/^diff --git/,$p'
} > eval/test-cases/large-migration-task.diff
wc -c eval/test-cases/large-migration-task.diff
```

Expected: 約 23.7 KB（diff 本體約 22.5 KB 加上 brief 約 1.2 KB）。

Step 3: 確認兩份 fixture 的形狀

Run:

```bash
head -1 eval/test-cases/rest-route-async.diff
head -1 eval/test-cases/large-migration-task.diff
grep -n '^=== ' eval/test-cases/large-migration-task.diff
grep -c '^commit \|^Author: ' eval/test-cases/rest-route-async.diff eval/test-cases/large-migration-task.diff
grep -c 'lib/middleware/index.ts' eval/test-cases/large-migration-task.diff
```

Expected:

- `rest-route-async.diff` 第一行為 `diff --git a/backend/...`
- `large-migration-task.diff` 第一行為 `=== REQUIREMENTS (what this change is supposed to do) ===`，且 `grep -n '^=== '` 只印出兩行：第 1 行的 REQUIREMENTS 與 CHANGE UNDER REVIEW 那一行。只能有這兩個 marker，多出來的會被 agent 當成受審內容（spec D16）
- `grep -c '^commit \|^Author: '` 對兩檔都回 `0`
- `grep -c 'lib/middleware/index.ts'` 回非零——那是 LT1 要判的越界檔，必須真的在 diff 裡

剝掉 commit header 是必要的，不只是為了乾淨：commit message 裡有作者姓名與 email，且
`ea34cad` 的 commit message 主動交代了那個越界檔案的理由——留著會讓模型直接讀到答案，
LT1 那條 assertion 就失去意義。

Step 4: 寫 rest-route-async 的 ground truth

`eval/ground-truth/rest-route-async.md`：

```markdown
# rest-route-async.diff

來源專案的 REST route 非同步化重構，3 檔 68 行。來源為私有專案，不隨本 repo 出貨。

## 真缺陷（recall 點）

| ID | tier | 缺陷 | 證據 |
|----|------|------|------|
| RR1 | L2 | DELETE 處理內兩個連續寫入未包在交易中：先 `UPDATE accounts SET is_active = 0`，再 `UPDATE users SET default_account = NULL`。第二個失敗則帳戶已停用而 `users.default_account` 仍指向它。上游的 `referenced` 檢查到更新之間亦未序列化 | 經人工讀原始碼確認，且該檔自該 commit 起未再變動。上游追認：該專案後續在 `reconcile` 與 `transactions` 兩處各自修掉同一類問題（讀改寫包進單一交易並鎖列），accounts route 未被涵蓋 |

## 為什麼只有一條也要收

spec D24 記載：同一份 diff 交給 single-shot（同樣帶 `--add-dir`）跑兩次，兩次皆 PASS 零
finding。這是極少數「確定會漏」的錨點，當敏感度計量器比條數重要。

## 不收進 recall 的疑慮

- 另兩條 fan-out 確認過的是測試檔內的 non-null assertion（LOW），實務上偏噪音，不進 recall 點。
```

Step 5: 寫 large-migration-task 的 ground truth

`eval/ground-truth/large-migration-task.md`：

```markdown
# large-migration-task.diff

來源專案 SQLite → PostgreSQL 遷移計畫的 Task 4（冪等佔位改為單語句原子操作），5 檔、
約 22.5 KB。這是 MyMoneyBook issue #26 那張表裡的 Task 4——當時 gemini flash 對它回出
439 bytes 的報告、零 findings、Verdict PASS。這份 fixture 是全套素材裡唯一能重現該症狀的。

本 fixture 的檔案開頭寫死 `=== REQUIREMENTS (what this change is supposed to do) ===`
與 `=== CHANGE UNDER REVIEW ===` 兩個 marker，因此同時量 findings recall 與 spec 合規的
越界檔漏報。REQUIREMENTS 區塊逐字取自來源 repo 的 task brief
（`docs/plans/2026-08-01-postgres-migration.md` 的 Task 4 標頭）。

marker 寫在 fixture 裡而不是靠 prompt 模板組，是沿用 `spec-compliance-missing.diff`
的既有作法——那是本 repo 唯一驗證過可行的路徑，且讓全域 `prompts:` 對九個案例維持同一份。

## 真缺陷（recall 點）

| ID | tier | 缺陷 | 證據 |
|----|------|------|------|
| LT1 | L1（spec 軸） | 變更了 `backend/lib/middleware/index.ts`，該檔不在 task brief 的 `Files:` 清單內。brief 只列 `lib/middleware/idempotency.ts` 與三個測試檔 | 逐字比對 brief 的 Files 清單與 commit 的檔案清單。issue #26 記載當時 gemini 的 Spec Compliance 段寫「無 Missing、Extra 或 Misread 項目」，是可查證的誤述；改派內建 reviewer 重跑同一份 diff 則正確指出 |
| LT2 | L2 | `tests/middleware/idempotency-release.test.ts` 新增的 `vi.mock('@/lib/middleware/external-id')` 與 `vi.mock('@/lib/audit')` 是為了繞過尚未轉換的旁枝依賴。這兩個模組在下一個 task 就會轉成 async，屆時 mock 不會失敗、只會停止反映真實行為——測試變成假綠燈 | 上游追認：下一個 commit（`refactor(middleware): middleware/external-id/audit 改為非同步 PostgreSQL 查詢`）從該測試檔刪掉 12 行，正是把這兩個 mock 拿掉。issue #26 記載內建 reviewer 當時就抓到這條 |

## 不收進 recall 的疑慮

逐條讀過但證據不足，不進 ground truth，也不得用來扣分：

- `claimIdempotency` 的 upsert 用 `created_at <= now - EXPIRY_SECONDS` 接管過期列，而
  `cleanExpiredKeys` 用 `created_at < cutoff`。邊界差一秒，且兩者用途不同，判不出是缺陷。
- `claimIdempotency` 多了第五個帶預設值的參數 `retried`，brief 的 Interfaces 區只列四個參數。
  有預設值故不破壞呼叫端，且這是遞迴重試的實作細節，算不算 Interfaces 偏離無定論。
- 函式註解宣稱「後續 SELECT 無競態：能被讀到的列必然未過期，未過期就不可能被任何人接管」。
  嚴格說該列可能在 upsert 與 SELECT 之間跨過過期界線而被他人接管，但冪等窗是 5 分鐘，
  這個窗口極窄，構不成可描述的失效情境。
```

Step 6: 確認四個檔案

Run: `ls -l eval/test-cases/rest-route-async.diff eval/test-cases/large-migration-task.diff eval/ground-truth/rest-route-async.md eval/ground-truth/large-migration-task.md`

Expected: 四檔皆存在且非空。

Step 7: Commit

Run: `git add eval/test-cases/rest-route-async.diff eval/test-cases/large-migration-task.diff eval/ground-truth/rest-route-async.md eval/ground-truth/large-migration-task.md && git commit -m "test(eval): 加跨 repo 的 rest-route 與大 diff fixture"`

---

### Task 7: 既有 fixture 的 ground truth

Implements: `gemini-review.md` #R23

五份 fixture 已在 repo 內，不動 diff，只補 ground truth。四條次級缺陷是 3.6 與 3.7
pairwise 實測互相漏掉對方抓到的那組，坐在偵測門檻附近，是敏感度計量器的主要來源。

Files:
- Create: `eval/ground-truth/existing-fixtures.md`

單一檔案而非五個：這五份 fixture 每份只有一到兩條缺陷，各自成檔會讓目錄裡塞滿三行的檔。

Step 1: 寫 ground truth

`eval/ground-truth/existing-fixtures.md`：

```markdown
# 既有 fixture 的 recall 點

這五份 diff 原本就在 `eval/test-cases/`，由 `promptfooconfig.yaml` 以「找到那一個缺陷」
的形式計分。這裡補的是它們埋著、但沒有任何 assertion 在看的缺陷，以及 tier 標註。

四條次級缺陷來自 3.6 與 3.7 的 pairwise 實測——兩代模型互相漏掉對方抓到的那一組。
它們坐在偵測門檻附近，才當得了敏感度計量器；太明顯的缺陷不退化到完全壞掉都會 PASS。

## hard-cache-key.diff

| ID | tier | 缺陷 | 證據 |
|----|------|------|------|
| HC1 | L2 | `buildQuote` 的 module-level Map 只以 `input.customerId` 為 key，而回傳的報價還取決於 sku、quantity、currency。同一客戶換 SKU 會拿到前一次的報價 | 主缺陷，`promptfooconfig.yaml` 的 H2 已在看 |
| HC2 | L2 | 快取項目永不清除，沒有 TTL 也沒有上限，長跑進程會單調成長 | 3.7 抓到、3.6 全漏。`promptfooconfig-hard.yaml` 的 H2 rubric 明文把它列為「extras」不計分，這裡把它獨立成 recall 點 |

## hard-lock-early-return.diff

| ID | tier | 缺陷 | 證據 |
|----|------|------|------|
| HL1 | L2 | 兩個 early return 加在取得 lock 與 `try` 之間，繞過 `finally` 的釋放，該 job_id 之後永久死鎖 | 主缺陷，`promptfooconfig-hard.yaml` 的 H3 已在看 |
| HL2 | L2 | `_store.load` 同樣在 `try` 之外，它拋錯時 lock 也不會釋放——與 early return 是同一個機制的第二個出口 | 3.7 抓到、3.6 全漏 |

## attribute-shadowing.diff

| ID | tier | 缺陷 | 證據 |
|----|------|------|------|
| AS1 | L1 | 把 Telegram Update 物件存成 `self.update`，遮蔽了類別的 `update()` 方法，`pm.update('text')` 會在執行期炸掉 | 主缺陷，`promptfooconfig.yaml` 的 TC5 已在看 |
| AS2 | L2 | 新增的 `__aexit__` try/except 少了 `self.message is not None` 的守衛 | 3.6 抓到、3.7 全漏 |

## refactor-display-logic.diff

| ID | tier | 缺陷 | 證據 |
|----|------|------|------|
| RD1 | L2 | 顯示限制的文案宣稱「顯示前 10 個」，與實際被截斷的內容不符，使用者會以為看到的是全部 | 3.6 抓到、3.7 全漏 |

注意：這份 diff 同時是 `promptfooconfig.yaml` 的 TC6（罰誤報）。兩邊不衝突——TC6 只在
報成 HIGH 或安全漏洞時 FAIL，這裡要的是把誤導文案報成 LOW 或 MEDIUM。它是唯一在兩份
config 都出現的 fixture，改它要兩邊一起看。

## snowflake-filter.diff

| ID | tier | 缺陷 | 證據 |
|----|------|------|------|
| SF1 | L3 | `Number()` 對 17–19 位的 Discord snowflake ID 會超過 `MAX_SAFE_INTEGER` 而失去精度 | 主缺陷，`promptfooconfig.yaml` 的 TC1 已在看。列在這裡是因為它是現有 fixture 裡除 G8 之外唯一的 L3——需要推理 diff 內看不到的執行期資料形狀（Discord ID 的位數）。spec D22 量到 arm N 在這題四次僅一次命中、現行 prompt 四次全中，Fisher p=0.029 |
```

Step 2: 確認

Run: `ls -l eval/ground-truth/existing-fixtures.md && ls eval/test-cases/hard-cache-key.diff eval/test-cases/hard-lock-early-return.diff eval/test-cases/attribute-shadowing.diff eval/test-cases/refactor-display-logic.diff eval/test-cases/snowflake-filter.diff`

Expected: ground truth 存在，五份 diff 也都在。

Step 3: Commit

Run: `git add eval/ground-truth/existing-fixtures.md && git commit -m "test(eval): 補既有 fixture 的次級缺陷與 tier 標註"`

---

### Task 8: 寫 promptfooconfig-recall.yaml

Implements: `gemini-review.md` #R22, #R23, #S9

Files:
- Create: `eval/promptfooconfig-recall.yaml`
- Create: `eval/.gitignore`

Interfaces:
- Consumes: Task 4–7 的九份 fixture 與四份 ground truth；Task 2 的 provider

Step 1: 排除輸出目錄

`eval/.gitignore`：

```
out/
```

Step 2: 寫 config

`eval/promptfooconfig-recall.yaml`：

```yaml
# 罰漏報的 eval。與 promptfooconfig.yaml 分家而不合併：誤報案例的 PASS 是「沒有多報」，
# 漏報案例的分數是「報出比例」，混在一起算平均會讓兩邊都讀不出來。現行那份是回歸網。
#
# 每個埋在 fixture 裡的缺陷掛一條獨立 llm-rubric，以 metric 欄位分流。一條 judge 解析
# 失敗只損失 1/N 而不是整案歸零，而且看得出是哪一格。
#
# 判準一律是「有沒有報出指定缺陷」，不是「報告有多長」——0.2.2 的 A/B 已否決長度與檢查
# 清單那條路（spec D19）。fabrication 只罰把未查證的事實當成既成事實；標明
# 「not verifiable from this diff」的 LOW 一律放行（spec D15、D21）。
#
# ground truth 在 eval/ground-truth/。判讀用 node score-recall.mjs out/recall-r*.json。

description: "Recall eval — 量 reviewer 漏報的代價（gemini-review @ 3.6-flash-high）"

providers:
  - id: file://agy-provider.js
    label: "3.6-flash-custom"
    config:
      agent: gemini-review
      model: gemini-3.6-flash-high
      timeout: 5m

prompts:
  - "Review the following code diff for bugs, security issues, and code quality problems:\n\n{{diff}}"

defaultTest:
  options:
    provider:
      id: anthropic:messages:claude-sonnet-5
      config:
        apiKeyRequired: false

tests:
  # ── 計數型 ────────────────────────────────────────────────────────────────
  # migration-cli-entrypoint：4 個 recall 點 + 7 個 fabrication 關卡
  - vars:
      diff: "file://test-cases/migration-cli-entrypoint.diff"
    assert:
      - type: llm-rubric
        metric: recall-L1
        value: "G9. Grade PASS if the review reports that better-sqlite3 is declared in devDependencies while the migration script imports it at runtime, so the script fails with a missing-package error in an environment without dev dependencies installed. Any severity is acceptable. Grade FAIL if the review does not raise this dependency placement at all."
      - type: llm-rubric
        metric: recall-L2
        value: "G4. Grade PASS if the review reports that the CLI entry-point guard comparing import.meta.url against a string built from process.argv[1] is unreliable, so the script can silently do nothing. It need not get the mechanism right — any concrete objection to comparing those two values, or a recommendation to use pathToFileURL, counts. Grade FAIL if the review does not question that comparison at all."
      - type: llm-rubric
        metric: recall-L2
        value: "G10. Grade PASS if the review reports that the SQLite handle is opened before the try block, so if the PostgreSQL connection throws, the finally that closes it never runs and the handle leaks. Grade FAIL if the review does not raise the placement of that open relative to the try."
      - type: llm-rubric
        metric: recall-L3
        value: "G8. Grade PASS if the review reports that the second-pass backfill of settlement_account_id does not check that the referenced account exists, so a dangling reference in the source data raises a foreign key violation that aborts the whole transaction. Grade FAIL if the review does not raise the unchecked reference in that backfill."
      - type: llm-rubric
        metric: fabrication
        value: "N1. Grade FAIL if the review states as established fact that users.default_account is a foreign key referencing accounts(id), or rates a finding that depends on that claim as MEDIUM or HIGH, or lets it drive the verdict. Grade PASS if the review does not raise it, or raises it explicitly as unverifiable from this diff at LOW severity — that is exactly what the reviewer is instructed to do with a risk it could not check."
      - type: llm-rubric
        metric: fabrication
        value: "N2. Grade FAIL if the review states as established fact that inserting explicit id values will be rejected by the identity column, or rates such a finding MEDIUM/HIGH, or lets it drive the verdict. The primary keys are GENERATED BY DEFAULT AS IDENTITY, so explicit ids are legal. Grade PASS if not raised, or raised as an unverifiable LOW."
      - type: llm-rubric
        metric: fabrication
        value: "N3. Grade FAIL if the review states as established fact that setval with GREATEST(max, 1) makes an empty table start at 2, or rates such a finding MEDIUM/HIGH, or lets it drive the verdict. The is_called third argument is false for an empty table, so the next id is 1. Grade PASS if not raised, or raised as an unverifiable LOW."
      - type: llm-rubric
        metric: fabrication
        value: "N4. Grade FAIL if the review states as established fact that the tests' use of ? placeholders will cause a PostgreSQL syntax error, or rates such a finding MEDIUM/HIGH, or lets it drive the verdict. The DB layer rewrites ? to $1 before execution. Grade PASS if not raised, or raised as an unverifiable LOW."
      - type: llm-rubric
        metric: fabrication
        value: "N5. Grade FAIL if the review states as established fact that the TRUNCATE ... CASCADE needs a confirmation guard and that its absence is a defect, or rates such a finding MEDIUM/HIGH, or lets it drive the verdict. Re-runnability by truncating first is the stated requirement; a guard was never asked for. Grade PASS if not raised, or raised as an unverifiable LOW."
      - type: llm-rubric
        metric: fabrication
        value: "N6. Grade FAIL if the review states as established fact that the hardcoded column lists silently drop columns, or rates such a finding MEDIUM/HIGH, or lets it drive the verdict. The lists match the schema column for column. Grade PASS if not raised, or raised as an unverifiable LOW."
      - type: llm-rubric
        metric: fabrication
        value: "N7. Grade FAIL if the review states as established fact that verifying only SUM(balance) can pass while per-account rows differ, or rates such a finding MEDIUM/HIGH, or lets it drive the verdict. Rows are copied with original ids, all columns, inside one transaction, so no mechanism produces that divergence. Grade PASS if not raised, or raised as an unverifiable LOW."

  # doctor-agy-bin：本 repo 自己的 commit，2 個 recall 點
  - vars:
      diff: "file://test-cases/doctor-agy-bin.diff"
    assert:
      - type: llm-rubric
        metric: recall-L2
        value: "DR1. Grade PASS if the review reports that doctor.sh prints AGY_BIN in its diagnostic output but never uses it — the command check, the runnability check and the version query all hardcode `agy` — while the Node hook in the same commit resolves the binary through process.env.AGY_BIN. Reporting only that doctor.sh hardcodes the binary, without mentioning the hook, still counts. Grade FAIL if the review does not raise the hardcoded binary at all."
      - type: llm-rubric
        metric: recall-L2
        value: "DR2. Grade PASS if the review reports that the agent-installed check hardcodes a path under $HOME/.gemini rather than honouring a configurable config directory, so it can report the agent as missing on a machine where agy stores its config elsewhere. Grade FAIL if the review does not raise that hardcoded path."

  # rest-route-async：1 個 recall 點，single-shot 實測兩次皆 PASS 零 finding
  - vars:
      diff: "file://test-cases/rest-route-async.diff"
    assert:
      - type: llm-rubric
        metric: recall-L2
        value: "RR1. Grade PASS if the review reports that the DELETE handler performs two consecutive writes — deactivating the account and clearing the user's default account reference — without wrapping them in a transaction, so a failure between them leaves a deactivated account still referenced. Raising it as a missing transaction, a partial-failure window, or a read-modify-write race all count. Grade FAIL if the review does not raise the unwrapped writes in the DELETE path."

  # large-migration-task：REQUIREMENTS 與 CHANGE UNDER REVIEW 兩個 marker 寫在 fixture
  # 檔案開頭（Task 6 Step 2 組裝的），整包由 {{diff}} 帶入，與 spec-compliance-missing.diff
  # 同一作法。這裡不需要也不得另加 vars——全域 prompts 只插值 {{diff}}。
  - vars:
      diff: "file://test-cases/large-migration-task.diff"
    assert:
      - type: llm-rubric
        metric: recall-spec
        value: "LT1. The REQUIREMENTS section lists a Files list that names lib/middleware/idempotency.ts and three test files, and nothing else. The change also modifies lib/middleware/index.ts. Grade PASS if the review's Spec Compliance section flags that file as outside the declared Files list (as Extra, as an undeclared change, or as scope creep). Grade FAIL if the Spec Compliance section reports no Missing/Extra/Misread items, or omits that file."
      - type: llm-rubric
        metric: recall-L2
        value: "LT2. Grade PASS if the review reports that the vi.mock calls added to the idempotency-release test stub out modules that this change has not yet converted, so once those modules are converted the mocks will keep passing without reflecting real behaviour — a test that stops testing. Raising it as a stale mock, a false green, or mocks that must be removed when the dependency is migrated all count. Grade FAIL if the review does not raise the added mocks at all."
      - type: javascript
        metric: spec-section-present
        value: "output.includes('Spec Compliance')"

  # ── 門檻型 ────────────────────────────────────────────────────────────────
  - vars:
      diff: "file://test-cases/hard-cache-key.diff"
    assert:
      - type: llm-rubric
        metric: recall-L2
        value: "HC1. Grade PASS if the review reports that the cache key uses only customerId while the returned quote also depends on sku, quantity or currency, so the same customer gets a stale quote for a different request. Grade FAIL if the review only raises TTL, unbounded growth or staleness without the wrong-key defect."
      - type: llm-rubric
        metric: recall-L2
        value: "HC2. Grade PASS if the review reports that cache entries are never evicted — no TTL and no size bound — so the map grows without limit in a long-running process. Grade FAIL if the review does not raise the unbounded lifetime of cache entries."
  - vars:
      diff: "file://test-cases/hard-lock-early-return.diff"
    assert:
      - type: llm-rubric
        metric: recall-L2
        value: "HL1. Grade PASS if the review reports that the early returns added between acquiring the lock and entering the try bypass the finally that releases it, leaving that job_id locked for subsequent runs. Grade FAIL if the review approves the change or only comments on logging or status semantics."
      - type: llm-rubric
        metric: recall-L2
        value: "HL2. Grade PASS if the review reports that the store load call also sits outside the try, so if it throws the lock is likewise never released — the same leak through a second exit. Grade FAIL if the review only raises the early returns and never mentions the load call's placement."
  - vars:
      diff: "file://test-cases/attribute-shadowing.diff"
    assert:
      - type: llm-rubric
        metric: recall-L1
        value: "AS1. Grade PASS if the review recognises that storing the Telegram Update object as self.update shadows the class's update() method and causes a runtime failure when that method is called, and that renaming it resolves the collision. Grade FAIL if the review misses the shadowing."
      - type: llm-rubric
        metric: recall-L2
        value: "AS2. Grade PASS if the review reports that the exception-handling path added in __aexit__ is missing a check that the message attribute is not None before using it, so it can fail on the error path. Grade FAIL if the review does not raise that missing guard."
  - vars:
      diff: "file://test-cases/refactor-display-logic.diff"
    assert:
      - type: llm-rubric
        metric: recall-L2
        value: "RD1. Grade PASS if the review reports that the display-limit wording tells the user they are seeing the first ten items when that does not match what is actually shown, so the user believes a truncated list is complete. Any severity counts. Grade FAIL if the review does not raise the wording of the truncation message."
  - vars:
      diff: "file://test-cases/snowflake-filter.diff"
    assert:
      - type: llm-rubric
        metric: recall-L3
        value: "SF1. Grade PASS if the review identifies a numeric precision risk in using Number() on large integer ID strings — Discord snowflake IDs are 17 to 19 digits and exceed JavaScript's safe integer range. Framing it as a bug in the old approach, a limitation of the new one, or a general precision concern all count. Grade FAIL if the review misses the precision issue."
```

Step 3: 驗證 YAML 可解析且 fixture 路徑都在

Run:

```bash
cd eval && for f in $(grep -o 'test-cases/[a-z0-9-]*\.diff' promptfooconfig-recall.yaml | sort -u); do test -f "$f" && echo "ok $f" || echo "MISSING $f"; done
```

Expected: 九行 `ok`，零行 `MISSING`。

Run: `cd eval && npx promptfoo@latest validate -c promptfooconfig-recall.yaml 2>&1 | tail -5`

Expected: 驗證通過。若該子指令在當前 promptfoo 版本不存在，改跑 `npx promptfoo@latest eval -c promptfooconfig-recall.yaml --filter-first-n 0 2>&1 | tail -5`，確認它讀得進 config 而不是報 YAML 錯。

Step 4: 確認 spec marker 真的送進了 prompt

這是唯一一個 marker 沒送到就會靜默失敗的地方——`LT1` 與 `spec-section-present` 兩條會
不分模型好壞地固定失敗，而畫面上看起來就只是「模型沒抓到」。跑單一案例確認一次：

Run（在 `eval/` 下）：

```bash
npx promptfoo@latest eval -c promptfooconfig-recall.yaml --no-cache \
  --filter-pattern large-migration-task --output out/spec-marker-check.json
node -e "
const j=require('./out/spec-marker-check.json');
const rows=j.results?.results??j.results??[];
const p=JSON.stringify(rows[0]?.prompt??rows[0]?.vars??'');
console.log('REQUIREMENTS marker in prompt:', p.includes('=== REQUIREMENTS (what this change is supposed to do) ==='));
console.log('CHANGE marker in prompt:', p.includes('=== CHANGE UNDER REVIEW ==='));
console.log('has Spec Compliance in output:', String(rows[0]?.response?.output??'').includes('Spec Compliance'));
"
```

Expected: 前兩行皆為 `true`。第三行反映的是模型行為，不是組態正確性——`false` 代表模型
沒輸出該區塊（是真失敗），但只有在前兩行為 `true` 的前提下這個判讀才成立。

若 `--filter-pattern` 在當前 promptfoo 版本不支援，改為暫時把 config 的 `tests:` 註解到
只剩該案例跑一次，確認後還原；不要因為不好跑就跳過這一步。

Step 5: Commit

Run: `git add eval/promptfooconfig-recall.yaml eval/.gitignore && git commit -m "test(eval): 加 promptfooconfig-recall，每缺陷一條 rubric"`

---

### Task 9: 跑 baseline 三輪

Implements: `gemini-review.md` #S9

Files:
- Modify: `docs/plans/2026-09-22-eval-recall-cases-design.md`（在文末追加「## Baseline」一節）

三輪用三次獨立呼叫而非 `--repeat 3`：要看的是「掉分題目每輪都不一樣」，那需要逐輪對照，
塞在同一份輸出裡分不出輪次。agy 無任何 sampling 控制，單輪數字不能當基準線。

Step 1: 跑三輪

Run（在 `eval/` 下，預估每輪十餘次 agy 呼叫與四十餘次 judge 呼叫）：

```bash
mkdir -p out
for r in 1 2 3; do
  npx promptfoo@latest eval -c promptfooconfig-recall.yaml \
    --no-cache --max-concurrency 2 --output "out/recall-r$r.json"
done
```

Expected: 三份 `out/recall-r{1,2,3}.json` 產生。中途若某輪整批報 provider 錯誤（配額用盡），
停下回報使用者，不要重跑到湊滿三輪——那會讓三輪落在不同的服務狀態下。

Step 2: 彙總

Run: `node score-recall.mjs out/recall-r1.json out/recall-r2.json out/recall-r3.json`

Expected: 印出以 metric 為列、三輪為欄的表，外加 excluded 兩項計數。

Step 3: 記錄

在 `docs/plans/2026-09-22-eval-recall-cases-design.md` 文末追加：

```markdown
## Baseline

`gemini-review` ＋ `gemini-3.6-flash-high`，三次獨立呼叫，`--max-concurrency 2`，
promptfoo `@latest`，judge `claude-sonnet-5`。日期：<實際執行日期>。

<貼上 score-recall.mjs 的完整輸出>

判讀（依 CLAUDE.md「一個紅格有三種成因」）：

- 排除的 provider 錯誤 N 筆、judge 解析失敗 N 筆，已不在上表任何分母內
- 三輪方向一致的 metric：<逐項列出，含三輪的數字>
- 三輪之間跳動的 metric：<逐項列出>。這些是抽樣變異，不是能力差距，不得單獨引用

基準線只採三輪方向一致的數字。
```

Step 4: Commit

Run: `git add docs/plans/2026-09-22-eval-recall-cases-design.md && git commit -m "docs(eval): 記錄 recall baseline 三輪結果"`

---

### Task 10: 更新 CLAUDE.md 的 Eval suite 段

Implements: `gemini-review.md` #R22, #R24

Files:
- Modify: `CLAUDE.md`（Testing → Eval suite 小節）

Step 1: 改寫該小節

找到 `CLAUDE.md` 中 `### Eval suite` 小節開頭這一段：

```markdown
`eval/` ships promptfoo configs comparing the custom agent against the bare model. Both arms go through `agy-provider.js`, a promptfoo JS provider — each arm is `id: file://agy-provider.js` plus a `config:` block naming `model` and, for the custom arm, `agent` (omit `agent` for the bare model). Optional `addDir` and `timeout` map to the matching agy flags. Invoke with `npx promptfoo@latest eval -c <config>`.
```

在其後插入：

```markdown
**There are two scoring configs, and they measure opposite failures.** `promptfooconfig.yaml` is the regression net: six of its thirteen cases punish false positives, and their diffs are clean, so a PASS there means "did not invent anything". `promptfooconfig-recall.yaml` punishes the other direction — each planted defect gets its own `llm-rubric` tagged with a `metric`, and the score is the fraction reported. They are kept apart because averaging "did not over-report" with "reported this fraction" makes both unreadable.

Three things about the recall config are load-bearing:

- **The ground truth lives in `eval/ground-truth/`, not in the rubrics.** Each entry records where the defect was verified (read the source, confirmed upstream, found by the fan-out prototype) and its tier — L1 visible in the diff, L2 needing domain knowledge or cross-hunk reasoning, L3 needing a fact the diff does not contain. `score-recall.mjs` splits recall by tier, so you can see which layer a prompt change dropped rather than only that the total moved.
- **`migration-cli-entrypoint.diff` carries both directions at once.** Four recall points and seven fabrication gates on the same diff, aggregated as two separate numbers. That pairing is the point: D21/D22 measured that tightening the LOW cap buys one more real defect and one more invented foreign key, and a recall-only score would read that trade as pure progress.
- **The fabrication gates never punish a hedged LOW.** A risk marked "not verifiable from this diff" is exactly what the shipped prompt asks for (D15). Only asserting it as fact, rating it MEDIUM/HIGH, or letting it drive the verdict fails.

Read a run with `node eval/score-recall.mjs eval/out/recall-r*.json`, which classifies every assertion as a real failure, a provider error, or a judge parse failure and drops the latter two from the denominators. Run three independent invocations rather than `--repeat 3` — agy has no sampling controls, so a single round is not a baseline, and you need per-round output to tell variance from a real drop.
```

Step 2: 修正結構化輸出的敘述

在同一小節找到這一段：

```markdown
agy exposes no sampling controls, so eval runs vary more than the pre-0.2.0 numbers, which were pinned to `temperature: 0` via a `.gemini/settings.json` that no longer applies.
```

在其後插入：

```markdown
**`--json-schema` is not a way out of that variance, and it was measured.** The provider carries `--output-format json` for the envelope (`status` is a deterministic infrastructure check, unlike pattern-matching prose) but deliberately not `--json-schema`. On agy 1.2.7 with `--agent gemini-review` the schema is silently ignored: markdown comes back, `num_turns` is 4, and the same report repeats four times for 6461 output tokens — the agent prompt's `## Output Format` section wins. Without `--agent` the bare model does emit JSON, but `response` then holds two concatenated JSON objects. The arm that works is not the arm being measured, and changing the agent's output format to suit the harness would measure a prompt nobody ships (D19/D21/D22 all measured that output-format changes move the finding count).
```

Step 3: 確認沒有動到其他小節

Run: `git diff --stat CLAUDE.md`

Expected: 只有 `CLAUDE.md` 一個檔案，增加約 15–20 行，刪除 0 行。

Step 4: Commit

Run: `git add CLAUDE.md && git commit -m "docs: CLAUDE.md 補 recall config 與結構化輸出的實測結論"`
