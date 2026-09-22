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
