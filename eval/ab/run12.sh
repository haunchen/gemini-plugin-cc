#!/usr/bin/env bash
# 確認階段的多數決：同一條宣稱獨立驗 3 次，2 票才算 CONFIRMED。
# 目標是壓下「關於執行期語意的錯誤宣稱」那 1/4 的誤確認，
# 同時確認正確的宣稱不會被一起壓掉——只測前者會被「一律駁回」騙過。
#
# 用法：AB_TARGET_ROOT=/path/to/repo ./run12.sh [trials] [votes-per-trial]
set -u
cd "$(dirname "$0")"
. ./lib.sh

TRIALS="${1:-4}"
VOTES="${2:-3}"
ROOT="$AB_TARGET_ROOT"
mkdir -p out/vote

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

vote_once() {
  local label="$1" claim="$2" t="$3" v="$4"
  local f="out/vote/${label}-t${t}-v${v}.md"
  printf '=== REPOSITORY ROOT ===\n%s\n=== CLAIMED DEFECT ===\n%s\n' "$ROOT" "$claim" \
    | agy --agent gemini-verify --model "$AB_MODEL" --add-dir "$ROOT" --print-timeout 5m \
    > "$f" 2>&1
  if grep -q "no output produced\|terminated due to error" "$f"; then echo DENIED; return; fi
  grep -oE '^## Verdict: [A-Z]+' "$f" | head -1 | sed 's/## Verdict: //'
}

run_set() {
  local label="$1" claim="$2" want="$3"
  echo "${label}（單票期望 ${want}，${VOTES} 票取多數）:"
  local agree=0
  for t in $(seq 1 "$TRIALS"); do
    local votes="" conf=0
    for v in $(seq 1 "$VOTES"); do
      local r; r=$(vote_once "$label" "$claim" "$t" "$v")
      votes="$votes $r"
      [ "$r" = CONFIRMED ] && conf=$((conf+1))
    done
    local majority=REJECTED
    [ "$conf" -ge 2 ] && majority=CONFIRMED
    [ "$majority" = "$want" ] && { agree=$((agree+1)); echo "  trial$t  OK      $majority   ($conf/${VOTES} confirm) [$votes ]"; } \
                              || echo "  trial$t  WRONG   $majority   ($conf/${VOTES} confirm) [$votes ]"
  done
  echo "  → ${agree}/${TRIALS} 正確"
}

run_set relpath  "$claim_relpath"  REJECTED
run_set encoding "$claim_encoding" CONFIRMED
