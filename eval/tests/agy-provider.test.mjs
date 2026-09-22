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
