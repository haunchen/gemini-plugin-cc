# large-migration-task.diff

來源專案 SQLite → PostgreSQL 遷移計畫的 Task 4（冪等佔位改為單語句原子操作），5 檔、
約 22.5 KB。這是 MyMoneyBook issue #26 那張表裡的 Task 4——當時 gemini flash 對它回出
439 bytes 的報告、零 findings、Verdict PASS。這份 fixture 是全套素材裡唯一能重現該症狀的。

本 fixture 的檔案開頭寫死 `=== REQUIREMENTS (what this change is supposed to do) ===`
與 `=== CHANGE UNDER REVIEW ===` 兩個 marker，因此同時量 findings recall 與 spec 合規的
越界檔漏報。REQUIREMENTS 區塊逐字取自來源 repo 的 task brief
（`docs/plans/2026-08-01-postgres-migration.md` 的 Task 4 標頭）。

marker 寫在 fixture 裡而不是靠 prompt 模板組，是沿用 `spec-compliance-missing.diff`
的既有作法——那是本 repo 唯一驗證過可行的路徑，且讓全域 `prompts:` 對九個案例維持同一份。

## 真缺陷（recall 點）

| ID | tier | 缺陷 | 證據 |
|----|------|------|------|
| LT1 | spec | 變更了 `backend/lib/middleware/index.ts`，該檔不在 task brief 的 `Files:` 清單內。brief 只列 `lib/middleware/idempotency.ts` 與三個測試檔 | 逐字比對 brief 的 Files 清單與 commit 的檔案清單。issue #26 記載當時 gemini 的 Spec Compliance 段寫「無 Missing、Extra 或 Misread 項目」，是可查證的誤述；改派內建 reviewer 重跑同一份 diff 則正確指出 |

LT1 走的是 `metric: recall-spec`，不進 `recall-L1`／`recall-L2`／`recall-L3` 的 tier 彙總——
`CONTEXT.md` 對 tier 的定義只有 L1/L2/L3 一條難度軸，沒有「軸」的概念，這裡的 `spec` 是
獨立於該軸的另一個 metric，不是 L1 的子類。
| LT2 | L2 | `tests/middleware/idempotency-release.test.ts` 新增的 `vi.mock('@/lib/middleware/external-id')` 與 `vi.mock('@/lib/audit')` 是為了繞過尚未轉換的旁枝依賴。這兩個模組在下一個 task 就會轉成 async，屆時 mock 不會失敗、只會停止反映真實行為——測試變成假綠燈 | 上游追認：下一個 commit（`refactor(middleware): middleware/external-id/audit 改為非同步 PostgreSQL 查詢`）從該測試檔刪掉 12 行，正是把這兩個 mock 拿掉。issue #26 記載內建 reviewer 當時就抓到這條 |

## 不收進 recall 的疑慮

逐條讀過但證據不足，不進 ground truth，也不得用來扣分：

- `claimIdempotency` 的 upsert 用 `created_at <= now - EXPIRY_SECONDS` 接管過期列，而
  `cleanExpiredKeys` 用 `created_at < cutoff`。邊界差一秒，且兩者用途不同，判不出是缺陷。
- `claimIdempotency` 多了第五個帶預設值的參數 `retried`，brief 的 Interfaces 區只列四個參數。
  有預設值故不破壞呼叫端，且這是遞迴重試的實作細節，算不算 Interfaces 偏離無定論。
- 函式註解宣稱「後續 SELECT 無競態：能被讀到的列必然未過期，未過期就不可能被任何人接管」。
  嚴格說該列可能在 upsert 與 SELECT 之間跨過過期界線而被他人接管，但冪等窗是 5 分鐘，
  這個窗口極窄，構不成可描述的失效情境。
