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
      // assert-set nesting gets flattened by promptfoo into this same array,
      // alongside an aggregate entry representing the whole assert-set that
      // carries no `assertion` field of its own. Skip it — it is not a real
      // assertion, and counting it would add a spurious "unlabelled" row.
      if (!c?.assertion) continue;
      out.push({
        metric: c.assertion.metric ?? 'unlabelled',
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
