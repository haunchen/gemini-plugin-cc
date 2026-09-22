# doctor-agy-bin.diff

本 repo 自己的 commit `64f5c42`（`feat(gemini-images)!: describe images through agy`，
6 檔、Node hook + bash）。不需去識別化，內容就是本 repo 的歷史。

## 真缺陷（recall 點）

| ID | tier | 缺陷 | 證據 |
|----|------|------|------|
| DR1 | L2 | `scripts/doctor.sh` 完全不吃 `AGY_BIN`。診斷輸出那一行印出 `AGY_BIN: ${AGY_BIN:-agy (default)}`，但實際的檢查、執行與版本查詢全部硬編碼 `agy`；同一個 commit 裡的 `hooks/image-describe.mjs` 用的是 `process.env.AGY_BIN \|\| "agy"`。設了 `AGY_BIN` 的使用者會拿到與 hook 不一致的診斷結果 | 第 47/55/56/94/95 行硬編碼、第 91 行印出該變數，是 commit `64f5c42` 當時（即本 fixture diff 內）的行號，不是 HEAD 的行號。2026-08-02 由 fan-out 原型找出後人工複查確認。該 commit 當時存在，已於本分支的 `f574a49` 修復（HEAD 已改用 `${AGY_BIN:-agy}`，同時查證並修了 `OCR_BIN` 的同型問題）——fixture diff（`eval/test-cases/doctor-agy-bin.diff`）本身未改動，這兩條缺陷在 diff 裡仍原樣存在，recall eval 不受影響 |
| DR2 | L2 | doctor 檢查 agent 是否安裝時硬編碼 `$HOME/.gemini/config/plugins/...`，未走 `GEMINI_CONFIG_DIR`。agy 在其他平台的 config 路徑未經實測，猜錯會讓 doctor 對已正確安裝的使用者回報 `agent missing` | 第 63 行，是 commit `64f5c42` 當時（即本 fixture diff 內）的行號，不是 HEAD 的行號。同 repo 的 `plugins/gemini/hooks/check-agent-version.sh:13` 用的是 `${GEMINI_CONFIG_DIR:-$HOME/.gemini}`，是相反的作法（該 hook 晚於本 commit，故 commit 當下 repo 內尚無先例）。證據強度低於 DR1：來自 fan-out 第二輪回收。該 commit 當時存在，已於本分支的 `f574a49` 修復（HEAD 已改用 `${GEMINI_CONFIG_DIR:-$HOME/.gemini}`，與 `check-agent-version.sh` 一致）——fixture diff 本身未改動，缺陷在 diff 裡仍原樣存在，recall eval 不受影響 |

## 不收進 recall 的疑慮

- **移除 `@path` 的空白跳脫**。commit message 主張「agy takes a plain path, so the
  space-escaping workaround is no longer needed」。這是 commit message 裡的宣稱，未經
  實測驗證，因此不進 ground truth。若日後實測證實含空白的路徑會壞，再補成 recall 點。
