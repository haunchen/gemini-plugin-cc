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
import { pathToFileURL } from 'node:url';

// Only `results.results` is a shape actually observed on a real run (Task 1
// Step 4). `results` itself being the array is tolerated but unverified. If
// neither shape holds an array, this is not "zero rows" — it means the input
// JSON does not look like promptfoo output at all, so fail loudly instead of
// silently reporting an empty, all-clear table.
function resultRows(json) {
  if (Array.isArray(json?.results?.results)) return json.results.results;
  if (Array.isArray(json?.results)) return json.results;
  const keys = json && typeof json === 'object' ? Object.keys(json) : [];
  throw new Error(
    `resultRows: expected results.results or results to be an array, got ${typeof json}` +
      (keys.length ? ` with top-level keys [${keys.join(', ')}]` : ' with no top-level keys') +
      '. This looks like the wrong input file, not a run with zero rows.',
  );
}

// Rubric ids (G9, AS2, DR1, ...) live at the start of `assertion.value`, e.g.
// "AS2. Grade PASS if ...". Assertions that carry no such id (the `javascript`
// check on spec-section-present has no rubric prose to parse) fall back to
// the metric name, so every row in the per-ID report still has something to
// key on.
function idFromValue(value) {
  const m = /^([A-Z]+\d+)\./.exec(String(value ?? ''));
  return m ? m[1] : null;
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
      const metric = c.assertion.metric ?? 'unlabelled';
      out.push({
        id: idFromValue(c.assertion.value) ?? metric,
        metric,
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
  // perId is the per-round, per-assertion-id verdict — 'pass' | 'fail' |
  // 'provider-error' | 'judge-error'. It is additive: rounds/excluded keep
  // their existing shape and values, this is a parallel view of the same
  // classification keyed by id instead of metric.
  const perId = [];

  for (const json of runs) {
    const byMetric = {};
    const byId = {};
    for (const a of readAssertions(json)) {
      const verdict = classify(a);
      byId[a.id] = verdict;
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
    perId.push(byId);
  }

  return { rounds, excluded, perId };
}

// Marks for the per-ID table. The two error verdicts get their own labels
// rather than being folded into FAIL — otherwise excluding them from the
// per-metric denominators above and then printing them as FAIL here would
// quietly smuggle them back into the read as if they were model failures.
const ID_MARK = { pass: 'PASS', fail: 'FAIL', 'provider-error': 'ERR(provider)', 'judge-error': 'ERR(judge)' };

function report(files) {
  const runs = files.map((f) => JSON.parse(readFileSync(f, 'utf8')));
  const { rounds, excluded, perId } = aggregate(runs);

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

  // The tier/metric aggregates above are direction-only: individual ids flip
  // between rounds (agy has no sampling controls), so a tier total moving is
  // not itself readable as a prompt-change effect. Per-ID is the only grain
  // that is — see docs/plans/2026-09-22-eval-recall-cases-design.md Baseline.
  console.log('');
  console.log('per-ID (the only reliable read across rounds — see design doc Baseline section):');
  const ids = [...new Set(perId.flatMap((r) => Object.keys(r)))].sort();
  const idHeader = ['id', ...files.map((_, i) => `r${i + 1}`)].join('\t');
  console.log(idHeader);
  for (const id of ids) {
    const cells = perId.map((r) => (r[id] ? ID_MARK[r[id]] : '-'));
    console.log([id, ...cells].join('\t'));
  }
}

const argvPath = process.argv[1];
const isMain = argvPath
  ? import.meta.url === pathToFileURL(argvPath).href || argvPath.endsWith('score-recall.mjs')
  : false;

if (isMain) {
  const files = process.argv.slice(2);
  if (files.length === 0) {
    console.error('usage: node score-recall.mjs <promptfoo-output.json> [...]');
    process.exit(1);
  }
  report(files);
}
