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
    this.label = options.label;
  }

  // Every provider in a config points at this same file, so the id has to
  // come from the caller's label or promptfoo cannot tell two arms apart in
  // its results (same reasoning as agy-provider.js's id()).
  id() {
    return `stub:${this.label || 'default'}`;
  }

  async callApi() {
    return { output: this.config.output || '' };
  }
}

module.exports = StubProvider;
