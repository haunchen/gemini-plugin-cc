// promptfoo provider for agy (Antigravity CLI).
//
// Replaces the old `exec: bash ./run-agy.sh ...` provider, which passed the
// prompt as a shell argument. On the way through the shell that argument lost
// one level of backslash escaping: a diff containing
//
//   cmdName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
//
// reached the model as
//
//   cmdName.replace(/[.*+?^${}()|[\]\]/g, "\$&")
//
// which is genuinely broken code. The model then correctly reported an
// unterminated character class — a finding that looks like a hallucination,
// reproduces every run, and is really the harness feeding it different source
// than the file on disk. Only test cases containing consecutive backslashes are
// affected, so it corrupts one or two rows rather than failing outright.
//
// Here the prompt goes over stdin and never touches a shell. argv carries only
// flag values (agent name, model slug, paths), none of which contain
// backslashes. `shell: true` is therefore safe and is what lets Windows resolve
// `agy.exe` from PATH.
//
// Usage in a config:
//
//   providers:
//     - id: file://agy-provider.js
//       label: "flash-custom"
//       config:
//         agent: gemini-review      # omit for the bare model (no system prompt)
//         model: gemini-3.6-flash-high
//         addDir: /path/to/repo     # optional; grants file reads
//         timeout: 5m               # optional, passed to --print-timeout
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

const { spawn } = require('node:child_process');

const DEFAULT_TIMEOUT = '5m';

// agy reports infrastructure failures on stdout/stderr with exit 0: a 503, an
// exhausted quota, a headless permission denial that discarded the turn. Handed
// back as `output` they get graded, and the rubric — correctly — fails them for
// not containing a review. That silently converts an outage into a quality
// score. Measured: a 503 on one case cost 3.7 a point on the hard set, and two
// permission denials cost the bare-3.7 arm two points on the main suite.
//
// Returning `error` instead puts them in promptfoo's error column, where they
// are visible and excluded from the pass rate.
const INFRA_FAILURE = [
  /^Error:\s/, // agy's own fatal errors
  /Eligibility check failed/,
  /no output produced/, // headless permission denial; discards the whole turn
];

// Looser tokens, only trusted for short outputs — a real review can legitimately
// discuss a 429 or quota handling in the code under review.
const INFRA_TOKENS = /\b(RESOURCE_EXHAUSTED|UNAVAILABLE|DEADLINE_EXCEEDED)\b|\b(429|503)\b/;
const SHORT_OUTPUT = 1000;

function infraFailure(output) {
  if (INFRA_FAILURE.some((re) => re.test(output))) return true;
  return output.length < SHORT_OUTPUT && INFRA_TOKENS.test(output);
}

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

// Kill the child if agy blows past its own --print-timeout. Parses the same
// suffix format agy accepts so the two cannot drift apart.
function timeoutToMs(value) {
  const match = /^(\d+)(ms|s|m|h)$/.exec(String(value).trim());
  if (!match) return null;
  const n = Number(match[1]);
  return n * { ms: 1, s: 1000, m: 60000, h: 3600000 }[match[2]];
}

class AgyProvider {
  constructor(options = {}) {
    this.config = options.config || {};
    this.label = options.label;
    if (!this.config.model) {
      throw new Error('agy-provider: config.model is required (run `agy models` for slugs)');
    }
  }

  // Every provider in a config points at this same file, so the id has to come
  // from the config or promptfoo cannot tell two arms apart in its results.
  id() {
    return `agy:${this.config.agent || 'bare'}:${this.config.model}`;
  }

  async callApi(prompt) {
    const timeout = this.config.timeout || DEFAULT_TIMEOUT;
    const args = [];
    if (this.config.agent) args.push('--agent', this.config.agent);
    args.push('--model', this.config.model);
    args.push('--print-timeout', timeout);
    args.push('--output-format', 'json');
    if (this.config.addDir) args.push('--add-dir', this.config.addDir);

    return new Promise((resolve) => {
      const child = spawn('agy', args, { shell: true });

      let stdout = '';
      let stderr = '';
      let settled = false;

      const finish = (result) => {
        if (settled) return;
        settled = true;
        clearTimeout(killer);
        resolve(result);
      };

      // agy's own timeout should fire first; this is the backstop for a child
      // that hangs without honouring it.
      const graceMs = timeoutToMs(timeout);
      const killer = setTimeout(
        () => {
          child.kill();
          finish({ error: `agy did not exit within ${timeout} (killed)` });
        },
        graceMs ? graceMs + 30000 : 600000,
      );

      child.stdout.on('data', (d) => {
        stdout += d;
      });
      child.stderr.on('data', (d) => {
        stderr += d;
      });

      child.on('error', (err) => finish({ error: `agy failed to start: ${err.message}` }));

      child.on('close', (code) => {
        finish(parseAgyResult(stdout, stderr, code));
      });

      child.stdin.on('error', () => {
        /* child exited before reading stdin; close handler reports it */
      });
      child.stdin.end(prompt);
    });
  }
}

AgyProvider.parseAgyResult = parseAgyResult;

module.exports = AgyProvider;
