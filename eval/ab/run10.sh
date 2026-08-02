#!/usr/bin/env bash
# Fan-out 原型：平行 scan ×N（無檔案存取）→ 去重 → 平行 verify（有檔案存取）→ 匯總。
# 用法：./run10.sh [scans] [verify-concurrency]
set -u
cd "$(dirname "$0")"
. ./lib.sh
SCANS="${1:-3}"
PAR="${2:-6}"
MODEL="$AB_MODEL"
ROOT="$AB_TARGET_ROOT"
DIFF=../test-cases/migration-cli-entrypoint.diff
OUT=out/fan
rm -rf "$OUT"; mkdir -p "$OUT/claims" "$OUT/verdicts"

SCAN_PAYLOAD="=== CHANGE UNDER REVIEW ===
$(cat "$DIFF")"

echo "[1/4] scan ×${SCANS}（平行，無檔案存取）"
for i in $(seq 1 "$SCANS"); do
  printf '%s' "$SCAN_PAYLOAD" | agy --agent gemini-scan --model "$MODEL" \
    --print-timeout 5m > "$OUT/scan-$i.txt" 2>&1 &
done
wait
for i in $(seq 1 "$SCANS"); do
  echo "      scan-$i: $(grep -c '^CANDIDATE:' "$OUT/scan-$i.txt" || true) 個候選"
done

echo "[2/4] 去重"
# 同一個 file:line 只留第一條。刻意保守：寧可多驗，不要把不同缺陷併成一條。
grep -h '^CANDIDATE:' "$OUT"/scan-*.txt \
  | sed 's/^CANDIDATE:[[:space:]]*//' \
  | awk -F' \\| ' '!seen[$1]++' > "$OUT/candidates.txt"
TOTAL=$(grep -hc '^CANDIDATE:' "$OUT"/scan-*.txt | paste -sd+ - | bc)
UNIQ=$(wc -l < "$OUT/candidates.txt" | tr -d ' ')
echo "      $TOTAL 條 → $UNIQ 條唯一"

echo "[3/4] verify ×${UNIQ}（平行度 ${PAR}，有檔案存取）"
n=0
while IFS= read -r line; do
  n=$((n+1))
  loc="${line%% | *}"; claim="${line#* | }"
  printf '=== REPOSITORY ROOT ===\n%s\n=== CLAIMED DEFECT ===\nFile: %s\nClaim: %s\n' \
    "$ROOT" "$loc" "$claim" > "$OUT/claims/$n.txt"
done < "$OUT/candidates.txt"

seq 1 "$UNIQ" | xargs -P "$PAR" -I{} sh -c \
  'agy --agent gemini-verify --model '"$MODEL"' --add-dir '"$ROOT"' --print-timeout 5m \
     < '"$OUT"'/claims/{}.txt > '"$OUT"'/verdicts/{}.md 2>&1'

echo "[4/4] 結果"
printf '\n%-11s %-48s %s\n' VERDICT LOCATION CLAIM
n=0
while IFS= read -r line; do
  n=$((n+1))
  loc="${line%% | *}"; claim="${line#* | }"
  f="$OUT/verdicts/$n.md"
  if grep -q "no output produced\|terminated due to error" "$f" 2>/dev/null; then v=DENIED
  else v=$(grep -oE '^## Verdict: [A-Z]+' "$f" 2>/dev/null | head -1 | sed 's/## Verdict: //'); fi
  sev=$(grep -oE '^## Severity: [A-Z]+' "$f" 2>/dev/null | head -1 | sed 's/## Severity: //')
  printf '%-11s %-48s %s\n' "${v:-none}${sev:+/$sev}" "$loc" "$(echo "$claim" | cut -c1-70)"
done < "$OUT/candidates.txt"

echo
echo "確認: $(grep -l '^## Verdict: CONFIRMED' "$OUT"/verdicts/*.md 2>/dev/null | wc -l | tr -d ' ')  駁回: $(grep -l '^## Verdict: REJECTED' "$OUT"/verdicts/*.md 2>/dev/null | wc -l | tr -d ' ')  無法查證: $(grep -l '^## Verdict: UNVERIFIABLE' "$OUT"/verdicts/*.md 2>/dev/null | wc -l | tr -d ' ')"
