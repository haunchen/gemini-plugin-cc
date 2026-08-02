#!/usr/bin/env bash
# 查證階段的證偽測試：一條假宣稱、一條真宣稱，各跑 N 次，帶檔案存取。
# 假的必須被 REJECTED，真的必須被 CONFIRMED——只看其中一邊會被「一律駁回」的查證器騙過。
set -u
cd "$(dirname "$0")"
. ./lib.sh
RUNS="${1:-4}"
MODEL="$AB_MODEL"
ROOT="$AB_TARGET_ROOT"
mkdir -p out/verify

# 假宣稱：schema.ts 內 users.default_account 為純 BIGINT，無 REFERENCES
FALSE_CLAIM='=== REPOSITORY ROOT ===
'"$ROOT"'
=== CLAIMED DEFECT ===
File: backend/scripts/migrate-sqlite-to-pg.mjs:23
Claim: `users` is listed first in TABLES and is inserted before `accounts`. Because
`users.default_account` is a foreign key referencing `accounts(id)`, inserting any user
row with a non-null `default_account` before `accounts` is populated will fail with a
foreign key constraint violation and abort the whole migration transaction.'

# 真宣稱：import.meta.url 與 file://${process.argv[1]} 字串比對不成立
TRUE_CLAIM='=== REPOSITORY ROOT ===
'"$ROOT"'
=== CLAIMED DEFECT ===
File: backend/scripts/migrate-sqlite-to-pg.mjs (CLI entry point guard)
Claim: the entry point is guarded by `import.meta.url === `file://${process.argv[1]}``.
That comparison is unsound: process.argv[1] is a plain path, not a percent-encoded file
URL, and is relative when invoked via `pnpm db:migrate-from-sqlite`. The condition is
therefore false and the script exits 0 having migrated nothing and printed nothing.'

run_one() {
  local label="$1" payload="$2" want="$3" i="$4"
  local f="out/verify/${label}-$i.md"
  printf '%s' "$payload" | agy --agent gemini-verify --model "$MODEL" \
    --add-dir "$ROOT" --print-timeout 5m > "$f" 2>&1
  if grep -q "no output produced\|terminated due to error" "$f"; then
    echo "  $label#$i  DENIED"; return
  fi
  local v
  v=$(grep -oE '^## Verdict: [A-Z]+' "$f" | head -1 | sed 's/## Verdict: //')
  if [ "$v" = "$want" ]; then echo "  $label#$i  OK        ($v)"
  else echo "  $label#$i  WRONG     (got ${v:-none}, want $want)"; fi
}

echo "假宣稱（期望 REJECTED）:"
for i in $(seq 1 "$RUNS"); do run_one false-fk "$FALSE_CLAIM" REJECTED "$i"; done
echo "真宣稱（期望 CONFIRMED）:"
for i in $(seq 1 "$RUNS"); do run_one true-cli "$TRUE_CLAIM" CONFIRMED "$i"; done
