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
  assert.match(r.error, /agy did not return a response/);
  assert.match(r.error, /Agent execution terminated/);
});

test('外殼解析不出來且不像基礎設施失敗時，仍回 error 並附原始文字', () => {
  const r = parseAgyResult('some unstructured chatter', '', 0);
  assert.equal(r.output, undefined);
  assert.match(r.error, /agy returned an unparseable envelope/);
  assert.match(r.error, /some unstructured chatter/);
});

test('stdout 是合法外殼、stderr 非空時仍正確取出 response', () => {
  const r = parseAgyResult(envelope(), 'warning: something\n', 0);
  assert.equal(r.error, undefined);
  assert.match(r.output, /## Verdict: PASS/);
  assert.equal(r.metadata.num_turns, 1);
});

test('stdout 在 envelope 前有一行噪音時仍正確取出 response', () => {
  const r = parseAgyResult(`Notice: a new version of agy is available.\n${envelope()}`, '', 0);
  assert.equal(r.error, undefined);
  assert.match(r.output, /## Verdict: PASS/);
  assert.equal(r.metadata.num_turns, 1);
});

test('stdout 在 envelope 後有一行噪音時仍正確取出 response', () => {
  const r = parseAgyResult(`${envelope()}\nagy: session closed.`, '', 0);
  assert.equal(r.error, undefined);
  assert.match(r.output, /## Verdict: PASS/);
  assert.equal(r.metadata.num_turns, 1);
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

test('envelope 可解析但 response 欄位缺失或非字串時判為不可解析', () => {
  const r = parseAgyResult(envelope({ response: 42 }), '', 0);
  assert.equal(r.output, undefined);
  assert.match(r.error, /agy returned an unparseable envelope/);
});

test('envelope.usage 缺失時 metadata.output_tokens 為 undefined 而不拋錯', () => {
  const raw = JSON.stringify({
    conversation_id: 'c1',
    status: 'SUCCESS',
    response: '## Review Summary\nfine\n\n## Verdict: PASS',
    duration_seconds: 1.5,
    num_turns: 1,
  });
  const r = parseAgyResult(raw, '', 0);
  assert.equal(r.error, undefined);
  assert.equal(r.metadata.output_tokens, undefined);
});
