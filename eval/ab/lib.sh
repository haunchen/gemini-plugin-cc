#!/usr/bin/env bash
# 共用設定。這些腳本要在一個真實 repo 上驗證宣稱，那個 repo 不隨本專案出貨。
#
#   AB_TARGET_ROOT  被查證的 repo 的絕對路徑（必填）
#   AB_MODEL        agy model slug（預設 gemini-3.6-flash-high）
#
# 例：AB_TARGET_ROOT=/path/to/checkout ./run11.sh 4
#
# 這些宣稱是針對 eval/test-cases/migration-cli-entrypoint.diff 的來源 repo 寫的，
# 換一個 repo 就要一併改寫 claim 內容，否則查證結果沒有意義。

: "${AB_TARGET_ROOT:?請設定 AB_TARGET_ROOT 為被查證 repo 的絕對路徑}"
: "${AB_MODEL:=gemini-3.6-flash-high}"

if [ ! -d "$AB_TARGET_ROOT" ]; then
  echo "AB_TARGET_ROOT 不是一個目錄：$AB_TARGET_ROOT" >&2
  exit 1
fi
