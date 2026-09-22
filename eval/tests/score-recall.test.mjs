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

test('readAssertions 跳過 assert-set 攤平後留下的聚合項（沒有 assertion 欄位）', () => {
  // promptfoo 把 assert-set 的巢狀結果攤平進同一個 componentResults[]，
  // 但聚合項本身（代表整個 assert-set 的分數）不帶 assertion 欄位，
  // 混在裡面會被誤算成一條多出來的 assertion。
  const rows = readAssertions(
    run([
      { pass: true, reason: 'Aggregate score 1.00 ≥ 0 threshold', componentResults: [] },
      { pass: false, reason: 'missed it', assertion: { type: 'llm-rubric', metric: 'recall-L3' } },
    ]),
  );
  assert.equal(rows.length, 1);
  assert.deepEqual(
    rows.map((r) => r.metric),
    ['recall-L3'],
  );
});

test('readAssertions 支援 results 本身就是陣列的形狀', () => {
  // 寬容接受的第二種形狀：未經 Task 1 實測驗證，但仍應正確解析。
  const json = {
    results: [
      {
        response: { output: '## Review Summary\nsomething' },
        gradingResult: {
          componentResults: [{ pass: true, reason: 'ok', assertion: { type: 'llm-rubric', metric: 'recall-L1' } }],
        },
      },
    ],
  };
  const rows = readAssertions(json);
  assert.equal(rows.length, 1);
  assert.deepEqual(
    rows.map((r) => [r.metric, r.pass]),
    [['recall-L1', true]],
  );
});

test('readAssertions 在兩種形狀都不成立時 throw，而不是靜默回空表', () => {
  assert.throws(() => readAssertions({ foo: 'bar' }), /results/);
  assert.throws(() => readAssertions(null), /results/);
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
