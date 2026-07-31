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
check_required_cmd agy
check_required_cmd node
check_required_cmd jq
check_file "$PLUGIN_DIR/.claude-plugin/plugin.json"
check_file "$PLUGIN_DIR/hooks/intercept-image-read.sh"
check_file "$PLUGIN_DIR/hooks/image-describe.mjs"
check_file "$PLUGIN_DIR/agy/agents/gemini-image-describe/agent.md"

if command -v agy >/dev/null 2>&1; then
  if agy --help >/dev/null 2>&1; then
    ok "agy runnable"
  else
    fail "agy installed but fails to run (check OAuth)"
  fi
  # --agent silently ignores unknown names, so a missing agent install shows up
  # as a generic description rather than an error. Check the file instead.
  if [ -f "$HOME/.gemini/config/plugins/gemini-images-agents/agents/gemini-image-describe/agent.md" ]; then
    ok "agent installed: gemini-image-describe"
  else
    fail "agent missing: run 'agy plugin install $PLUGIN_DIR/agy'"
  fi
fi

echo
echo "== Optional =="
check_optional_cmd magick "image resize/convert; install via 'brew install imagemagick' or 'winget install ImageMagick.ImageMagick'"
check_optional_cmd sips "macOS native image tool; no install needed on macOS, skipped on Windows"
check_optional_cmd tesseract "OCR supplement; install via 'brew install tesseract tesseract-lang' or 'winget install UB-Mannheim.TesseractOCR'"

if command -v tesseract >/dev/null 2>&1; then
  if tesseract --list-langs 2>&1 | grep -q '^chi_tra$'; then
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
  echo "OCR_BIN: ${OCR_BIN:-tesseract (default)}"
  echo "AGY_BIN: ${AGY_BIN:-agy (default)}"
  echo "TMPDIR: ${TMPDIR:-/tmp (default)}"
  echo "OS: $(uname -s)"
  if command -v agy >/dev/null 2>&1; then
    echo "agy version: $(agy --version 2>/dev/null | head -1)"
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
