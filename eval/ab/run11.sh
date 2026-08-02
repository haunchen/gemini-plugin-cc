#!/usr/bin/env bash
# 查證器的機制檢查：三條宣稱，結論真假與機制真假的組合不同。
#   fk       機制假、結論假        → 期望 REJECTED
#   relpath  機制假、結論真        → 期望 REJECTED（並在 Adjacent 說出真正成立的是什麼）
#   encoding 機制真、結論真        → 期望 CONFIRMED
set -u
cd "$(dirname "$0")"
. ./lib.sh
RUNS="${1:-4}"
MODEL="$AB_MODEL"
ROOT="$AB_TARGET_ROOT"
mkdir -p out/verify2

claim_fk='File: backend/scripts/migrate-sqlite-to-pg.mjs:23
Claim: `users` is inserted before `accounts`. Because `users.default_account` is a foreign
key referencing `accounts(id)`, inserting any user row with a non-null `default_account`
before `accounts` is populated fails with a foreign key constraint violation.'

claim_relpath='File: backend/scripts/migrate-sqlite-to-pg.mjs (CLI entry point guard)
Claim: the guard is `import.meta.url === `file://${process.argv[1]}``. When the script is
run with a relative path such as `node scripts/migrate-sqlite-to-pg.mjs`, process.argv[1]
stays relative, so `file://${process.argv[1]}` yields `file://scripts/migrate-sqlite-to-pg.mjs`,
which never equals import.meta.url. The CLI therefore exits 0 without migrating anything.'

claim_encoding='File: backend/scripts/migrate-sqlite-to-pg.mjs (CLI entry point guard)
Claim: the guard is `import.meta.url === `file://${process.argv[1]}``. process.argv[1] is a
filesystem path while import.meta.url is a URL, so the two diverge whenever the path needs
percent-encoding (a space or any non-ASCII character) or is reached through a symlink, which
import.meta.url resolves and argv[1] does not. In those cases the CLI exits 0 without
migrating anything and without printing anything.'

run_set() {
  local label="$1" claim="$2" want="$3"
  echo "${label}（期望 ${want}）:"
  for i in $(seq 1 "$RUNS"); do
    local f="out/verify2/${label}-$i.md"
    printf '=== REPOSITORY ROOT ===\n%s\n=== CLAIMED DEFECT ===\n%s\n' "$ROOT" "$claim" \
      | agy --agent gemini-verify --model "$MODEL" --add-dir "$ROOT" --print-timeout 5m \
      > "$f" 2>&1
    if grep -q "no output produced\|terminated due to error" "$f"; then
      echo "  #$i  DENIED"; continue
    fi
    local v adj
    v=$(grep -oE '^## Verdict: [A-Z]+' "$f" | head -1 | sed 's/## Verdict: //')
    adj=$(grep -q '^## Adjacent' "$f" && echo " +adjacent" || echo "")
    [ "$v" = "$want" ] && echo "  #$i  OK        ($v)$adj" || echo "  #$i  WRONG     (got ${v:-none}, want $want)$adj"
  done
}

run_set fk       "$claim_fk"       REJECTED
run_set relpath  "$claim_relpath"  REJECTED
run_set encoding "$claim_encoding" CONFIRMED
