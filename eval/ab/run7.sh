#!/usr/bin/env bash
# 誤報迴歸關卡：六個「乾淨 diff」案例，任何 HIGH/MEDIUM 或 NEEDS_CHANGES 都算退步。
# 條件與 eval 一致（promptfoo 的 prompt 模板、不帶 --add-dir）。
# 用法：./run7.sh <agent-name> <tag> [runs-per-case]
set -u
cd "$(dirname "$0")"
AGENT="$1"
TAG="$2"
RUNS="${3:-2}"
MODEL=gemini-3.6-flash-high
mkdir -p out/fp

CASES="remove-any prompt-rewrite refactor-display-logic deps-upgrade-agent-sdk ci-memory-optimization app-rename"

clean=0
total=0
for c in $CASES; do
  for i in $(seq 1 "$RUNS"); do
    f="out/fp/${TAG}-${c}-$i.md"
    PROMPT="Review the following code diff for bugs, security issues, and code quality problems:

$(cat "../test-cases/$c.diff")"
    printf '%s' "$PROMPT" | agy --agent "$AGENT" --model "$MODEL" --print-timeout 5m > "$f" 2>&1
    total=$((total+1))
    if grep -q "no output produced\|terminated due to error" "$f"; then
      echo "$c#$i  FAIL"
      continue
    fi
    sev=$(grep -oE '^### \[(HIGH|MEDIUM)\]' "$f" | wc -l | tr -d ' ')
    verdict=$(grep -oE '^## Verdict: [A-Z_]+' "$f" | head -1 | sed 's/## Verdict: //')
    if [ "$sev" = "0" ] && [ "$verdict" = "PASS" ]; then
      clean=$((clean+1))
      echo "$c#$i  CLEAN"
    else
      echo "$c#$i  REGRESS  (hi/med=$sev verdict=${verdict:-none})"
    fi
  done
done
echo "$TAG: $clean/$total clean"
