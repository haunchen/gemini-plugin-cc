#!/usr/bin/env bash
# 條件對照：同一份 tc14 diff，唯一變因是 agent 能不能讀檔（--add-dir + ROOT 區塊）。
# 這是 0.2.2 之後 /gemini:review 的實際跑法，eval 一直沒有複製。
# 用法：./run8.sh <agent-name> <tag> [runs]
set -u
cd "$(dirname "$0")"
. ./lib.sh
AGENT="$1"
TAG="$2"
RUNS="${3:-4}"
MODEL="$AB_MODEL"
ROOT="$AB_TARGET_ROOT"
DIFF=../test-cases/migration-cli-entrypoint.diff
mkdir -p out

PAYLOAD="=== REPOSITORY ROOT ===
$ROOT
=== CHANGE UNDER REVIEW ===
$(cat "$DIFF")"

for i in $(seq 1 "$RUNS"); do
  f="out/${TAG}-$i.md"
  printf '%s' "$PAYLOAD" | agy --agent "$AGENT" --model "$MODEL" --add-dir "$ROOT" --print-timeout 5m > "$f" 2>&1
  if grep -q "no output produced\|terminated due to error" "$f"; then
    echo "run$i DENIED"
    continue
  fi
  g4=MISSED
  grep -qi "import.meta.url\|argv\[1\]\|pathToFileURL\|fileURLToPath" "$f" && g4=CAUGHT
  fk=$(grep -ci "default_account" "$f")
  echo "run$i  G4=$g4  FK-mentions=$fk  verdict=$(grep -oE '^## Verdict: .*' "$f" | head -1 | sed 's/## Verdict: //')"
done
