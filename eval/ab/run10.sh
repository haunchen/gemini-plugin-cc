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

echo "[1/5] scan ×${SCANS}（平行，無檔案存取）"
for i in $(seq 1 "$SCANS"); do
  printf '%s' "$SCAN_PAYLOAD" | agy --agent gemini-scan --model "$MODEL" \
    --print-timeout 5m > "$OUT/scan-$i.txt" 2>&1 &
done
wait
for i in $(seq 1 "$SCANS"); do
  echo "      scan-$i: $(grep -c '^CANDIDATE:' "$OUT/scan-$i.txt" || true) 個候選"
done

echo "[2/5] 語意去重"
# 正式 command 裡這一步由 Claude Code 做。原型用一支 agent 代打，好讓這個目錄
# 能自己跑完整條流水線——它的品質是下界，不是正式做法的預期值。
# 合併鍵是「位置＋機制」而非位置：查證器會檢查機制，同一行不同理由是兩條宣稱。
grep -h '^CANDIDATE:' "$OUT"/scan-*.txt > "$OUT/raw.txt"
TOTAL=$(wc -l < "$OUT/raw.txt" | tr -d ' ')
agy --agent gemini-merge --model "$MODEL" --print-timeout 5m \
  < "$OUT/raw.txt" > "$OUT/merged.txt" 2>&1
if ! grep -q '^CANDIDATE:' "$OUT/merged.txt"; then
  echo "      合併失敗，退回 file:line 去重" >&2
  cp "$OUT/raw.txt" "$OUT/merged.txt"
fi
sed 's/^CANDIDATE:[[:space:]]*//' "$OUT/merged.txt" \
  | awk -F' \\| ' 'NF && !seen[$0]++' > "$OUT/candidates.txt"
UNIQ=$(wc -l < "$OUT/candidates.txt" | tr -d ' ')
echo "      $TOTAL 條 → $UNIQ 條"

echo "[3/5] verify ×${UNIQ}（平行度 ${PAR}，有檔案存取）"
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

verdict_of() {
  if grep -q "no output produced\|terminated due to error" "$1" 2>/dev/null; then echo DENIED
  else grep -oE '^## Verdict: [A-Z]+' "$1" 2>/dev/null | head -1 | sed 's/## Verdict: //'; fi
}

# 只對第一票判 CONFIRMED 的追加兩票，2/3 才算確認。駁回方向的可靠度另外量過
# （run11/run12），這裡不重驗；代價是真宣稱若在第一票被誤駁就沒有第二次機會。
CONF=$(for n in $(seq 1 "$UNIQ"); do
  [ "$(verdict_of "$OUT/verdicts/$n.md")" = CONFIRMED ] && echo "$n"; done)
NCONF=$(echo "$CONF" | grep -c . || true)
echo "[4/5] 對 ${NCONF} 條確認追加兩票"
mkdir -p "$OUT/votes"
for v in 2 3; do
  echo "$CONF" | grep . | xargs -P "$PAR" -I{} sh -c \
    'agy --agent gemini-verify --model '"$MODEL"' --add-dir '"$ROOT"' --print-timeout 5m \
       < '"$OUT"'/claims/{}.txt > '"$OUT"'/votes/{}-v'"$v"'.md 2>&1'
done

# 回收 Adjacent：查證器駁回一條宣稱時，若認為程式碼另有問題，會用同樣的
# CANDIDATE 格式寫下來。那是 scan 提錯機制時唯一能救回缺陷的路徑，不回收就丟掉。
echo "[5/6] 回收 Adjacent"
for f in "$OUT"/verdicts/*.md; do
  sed -n '/^## Adjacent/,$p' "$f" | grep '^CANDIDATE:'
done 2>/dev/null | sed 's/^CANDIDATE:[[:space:]]*//' \
  | awk -F' \\| ' 'NF && !seen[$0]++' > "$OUT/adjacent.txt"
# 與第一輪候選逐字重複的不必再驗
grep -vxF -f "$OUT/candidates.txt" "$OUT/adjacent.txt" > "$OUT/round2.txt" || true
NADJ=$(wc -l < "$OUT/round2.txt" | tr -d ' ')
echo "      $NADJ 條新候選"
if [ "$NADJ" -gt 0 ]; then
  mkdir -p "$OUT/claims2" "$OUT/verdicts2" "$OUT/votes2"
  m=0
  while IFS= read -r line; do
    m=$((m+1))
    loc="${line%% | *}"; claim="${line#* | }"
    printf '=== REPOSITORY ROOT ===\n%s\n=== CLAIMED DEFECT ===\nFile: %s\nClaim: %s\n' \
      "$ROOT" "$loc" "$claim" > "$OUT/claims2/$m.txt"
  done < "$OUT/round2.txt"
  seq 1 "$NADJ" | xargs -P "$PAR" -I{} sh -c \
    'agy --agent gemini-verify --model '"$MODEL"' --add-dir '"$ROOT"' --print-timeout 5m \
       < '"$OUT"'/claims2/{}.txt > '"$OUT"'/verdicts2/{}.md 2>&1'
  CONF2=$(for m in $(seq 1 "$NADJ"); do
    [ "$(verdict_of "$OUT/verdicts2/$m.md")" = CONFIRMED ] && echo "$m"; done)
  NCONF2=$(echo "$CONF2" | grep -c . || true)
  for v in 2 3; do
    echo "$CONF2" | grep . | xargs -P "$PAR" -I{} sh -c \
      'agy --agent gemini-verify --model '"$MODEL"' --add-dir '"$ROOT"' --print-timeout 5m \
         < '"$OUT"'/claims2/{}.txt > '"$OUT"'/votes2/{}-v'"$v"'.md 2>&1'
  done
else
  NCONF2=0
fi

echo "[6/6] 結果"
printf '\n%-16s %-46s %s\n' VERDICT LOCATION CLAIM
final_conf=0; final_rej=0
n=0
while IFS= read -r line; do
  n=$((n+1))
  loc="${line%% | *}"; claim="${line#* | }"
  v1=$(verdict_of "$OUT/verdicts/$n.md")
  if [ "$v1" != CONFIRMED ]; then
    final_rej=$((final_rej+1))
    printf '%-16s %-46s %s\n' "${v1:-none}" "$loc" "$(echo "$claim" | cut -c1-64)"
    continue
  fi
  yes=1
  for v in 2 3; do
    [ "$(verdict_of "$OUT/votes/$n-v$v.md")" = CONFIRMED ] && yes=$((yes+1))
  done
  sev=$(grep -oE '^## Severity: [A-Z]+' "$OUT/verdicts/$n.md" 2>/dev/null | head -1 | sed 's/## Severity: //')
  if [ "$yes" -ge 2 ]; then
    final_conf=$((final_conf+1))
    printf '%-16s %-46s %s\n' "CONFIRMED/${sev:-?} ${yes}/3" "$loc" "$(echo "$claim" | cut -c1-64)"
  else
    final_rej=$((final_rej+1))
    printf '%-16s %-46s %s\n' "投票駁回 ${yes}/3" "$loc" "$(echo "$claim" | cut -c1-64)"
  fi
done < "$OUT/candidates.txt"

if [ "$NADJ" -gt 0 ]; then
  echo "  ── 第二輪（回收自 Adjacent）──"
  m=0
  while IFS= read -r line; do
    m=$((m+1))
    loc="${line%% | *}"; claim="${line#* | }"
    v1=$(verdict_of "$OUT/verdicts2/$m.md")
    if [ "$v1" != CONFIRMED ]; then
      final_rej=$((final_rej+1))
      printf '%-16s %-46s %s\n' "${v1:-none}" "$loc" "$(echo "$claim" | cut -c1-64)"
      continue
    fi
    yes=1
    for v in 2 3; do
      [ "$(verdict_of "$OUT/votes2/$m-v$v.md")" = CONFIRMED ] && yes=$((yes+1))
    done
    sev=$(grep -oE '^## Severity: [A-Z]+' "$OUT/verdicts2/$m.md" 2>/dev/null | head -1 | sed 's/## Severity: //')
    if [ "$yes" -ge 2 ]; then
      final_conf=$((final_conf+1))
      printf '%-16s %-46s %s\n' "CONFIRMED/${sev:-?} ${yes}/3" "$loc" "$(echo "$claim" | cut -c1-64)"
    else
      final_rej=$((final_rej+1))
      printf '%-16s %-46s %s\n' "投票駁回 ${yes}/3" "$loc" "$(echo "$claim" | cut -c1-64)"
    fi
  done < "$OUT/round2.txt"
fi

echo
echo "最終確認: $final_conf  駁回: $final_rej"
echo "呼叫數: scan $SCANS + merge 1 + verify $UNIQ + votes $((NCONF*2)) + 第二輪 $((NADJ+NCONF2*2)) = $((SCANS+1+UNIQ+NCONF*2+NADJ+NCONF2*2))"
