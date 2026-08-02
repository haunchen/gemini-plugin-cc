#!/usr/bin/env bash
# Test Case 14 命中率：任一 agent 對 migration-cli-entrypoint.diff 抓到 CLI 進入點缺陷的頻率。
# 條件與 eval 一致（promptfoo 的 prompt 模板、不帶 --add-dir）。
# 用法：./run6.sh <agent-name> <tag> [runs]
set -u
cd "$(dirname "$0")"
AGENT="$1"
TAG="$2"
RUNS="${3:-4}"
MODEL=gemini-3.6-flash-high
DIFF=../test-cases/migration-cli-entrypoint.diff
mkdir -p out

PROMPT="Review the following code diff for bugs, security issues, and code quality problems:

$(cat "$DIFF")"

hit=0
for i in $(seq 1 "$RUNS"); do
  f="out/${TAG}-$i.md"
  printf '%s' "$PROMPT" | agy --agent "$AGENT" --model "$MODEL" --print-timeout 5m > "$f" 2>&1
  if grep -q "no output produced\|terminated due to error" "$f"; then
    echo "run$i FAIL     ($(head -c 120 "$f" | tr '\n' ' '))"
  elif grep -qi "import.meta.url\|argv\[1\]\|pathToFileURL\|fileURLToPath" "$f"; then
    hit=$((hit+1))
    echo "run$i CAUGHT   ($(wc -c < "$f") bytes)"
  else
    echo "run$i MISSED   ($(wc -c < "$f") bytes)"
  fi
done
echo "$TAG: $hit/$RUNS caught"
