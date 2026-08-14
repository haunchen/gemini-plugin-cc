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

      child.stdin.on('error', () => {
        /* child exited before reading stdin; close handler reports it */
      });
      child.stdin.end(prompt);
    });
  }
}

module.exports = AgyProvider;
