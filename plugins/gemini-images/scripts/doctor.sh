#!/bin/bash
# Environment diagnostic for gemini-images plugin.
# Usage: doctor.sh [--verbose]

set -uo pipefail

VERBOSE=0
for arg in "$@"; do
  case "$arg" in
    --verbose|-v) VERBOSE=1 ;;
  esac
done

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PLUGIN_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
STATUS=0

# Resolve the same env vars the runtime code respects (image-describe.mjs,
# intercept-image-read.sh), so the diagnostics check what will actually run
# rather than always the default.
AGY_BIN="${AGY_BIN:-agy}"
OCR_BIN="${OCR_BIN:-tesseract}"

ok()   { echo "[OK]   $1"; }
fail() { echo "[FAIL] $1"; STATUS=1; }
warn() { echo "[WARN] $1"; }

check_required_cmd() {
  if command -v "$1" >/dev/null 2>&1; then
    ok "command: $1"
  else
    fail "command: $1 not found"
  fi
}

check_optional_cmd() {
  if command -v "$1" >/dev/null 2>&1; then
    ok "optional: $1"
  else
    warn "optional: $1 not found ($2)"
  fi
}

check_file() {
  if [ -f "$1" ]; then
    ok "file: $1"
  else
    fail "file: $1 missing"
  fi
}

echo "== Required =="
check_required_cmd "$AGY_BIN"
check_required_cmd node
check_required_cmd jq
check_file "$PLUGIN_DIR/.claude-plugin/plugin.json"
check_file "$PLUGIN_DIR/hooks/intercept-image-read.sh"
check_file "$PLUGIN_DIR/hooks/image-describe.mjs"
check_file "$PLUGIN_DIR/agy/agents/gemini-image-describe/agent.md"

if command -v "$AGY_BIN" >/dev/null 2>&1; then
  if "$AGY_BIN" --help >/dev/null 2>&1; then
    ok "agy runnable"
  else
    fail "agy installed but fails to run (check OAuth)"
  fi
  # --agent silently ignores unknown names, so a missing agent install shows up
  # as a generic description rather than an error. Check the file instead.
  if [ -f "${GEMINI_CONFIG_DIR:-$HOME/.gemini}/config/plugins/gemini-images-agents/agents/gemini-image-describe/agent.md" ]; then
    ok "agent installed: gemini-image-describe"
  else
    fail "agent missing: run 'agy plugin install $PLUGIN_DIR/agy'"
  fi
fi

echo
echo "== Optional =="
check_optional_cmd magick "image resize/convert; install via 'brew install imagemagick' or 'winget install ImageMagick.ImageMagick'"
check_optional_cmd sips "macOS native image tool; no install needed on macOS, skipped on Windows"
if [ "$OCR_BIN" = "none" ]; then
  ok "OCR: disabled (OCR_BIN=none)"
else
  check_optional_cmd "$OCR_BIN" "OCR supplement; install via 'brew install tesseract tesseract-lang' or 'winget install UB-Mannheim.TesseractOCR'"
fi

# The chi_tra language-pack check only makes sense for tesseract itself, not
# for an arbitrary OCR_BIN override (a custom binary may not support
# --list-langs at all).
if [ "$OCR_BIN" = "tesseract" ] && command -v "$OCR_BIN" >/dev/null 2>&1; then
  if "$OCR_BIN" --list-langs 2>&1 | grep -q '^chi_tra$'; then
    ok "tesseract language: chi_tra"
  else
    warn "tesseract language: chi_tra not installed (Chinese OCR unavailable)"
  fi
fi

if [ "$VERBOSE" = "1" ]; then
  echo
  echo "== Environment =="
  echo "PLUGIN_DIR: $PLUGIN_DIR"
  echo "AGY_MODEL: ${AGY_MODEL:-gemini-3.6-flash-high (default)}"
  echo "MAX_WIDTH: ${MAX_WIDTH:-1568 (default)}"
  echo "OCR_BIN: $OCR_BIN"
  echo "AGY_BIN: $AGY_BIN"
  echo "TMPDIR: ${TMPDIR:-/tmp (default)}"
  echo "OS: $(uname -s)"
  if command -v "$AGY_BIN" >/dev/null 2>&1; then
    echo "agy version: $("$AGY_BIN" --version 2>/dev/null | head -1)"
  fi
  if command -v node >/dev/null 2>&1; then
    echo "node version: $(node --version)"
  fi
fi

echo
if [ "$STATUS" -ne 0 ]; then
  echo "Required checks failed. See README Troubleshooting for fixes."
else
  echo "See README Troubleshooting for fixes if you hit runtime issues."
fi

exit "$STATUS"
