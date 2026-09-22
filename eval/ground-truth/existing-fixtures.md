# 既有 fixture 的 recall 點

這五份 diff 原本就在 `eval/test-cases/`，由 `promptfooconfig.yaml` 以「找到那一個缺陷」
的形式計分。這裡補的是它們埋著、但沒有任何 assertion 在看的缺陷，以及 tier 標註。

四條次級缺陷來自 3.6 與 3.7 的 pairwise 實測——兩代模型互相漏掉對方抓到的那一組。
它們坐在偵測門檻附近，才當得了敏感度計量器；太明顯的缺陷不退化到完全壞掉都會 PASS。

## hard-cache-key.diff

| ID | tier | 缺陷 | 證據 |
|----|------|------|------|
| HC1 | L2 | `buildQuote` 的 module-level Map 只以 `input.customerId` 為 key，而回傳的報價還取決於 sku、quantity、currency。同一客戶換 SKU 會拿到前一次的報價 | 主缺陷，`promptfooconfig.yaml` 的 H2 已在看 |
| HC2 | L2 | 快取項目永不清除，沒有 TTL 也沒有上限，長跑進程會單調成長 | 3.7 抓到、3.6 全漏。`promptfooconfig-hard.yaml` 的 H2 rubric 明文把它列為「extras」不計分，這裡把它獨立成 recall 點 |

## hard-lock-early-return.diff

| ID | tier | 缺陷 | 證據 |
|----|------|------|------|
| HL1 | L2 | 兩個 early return 加在取得 lock 與 `try` 之間，繞過 `finally` 的釋放，該 job_id 之後永久死鎖 | 主缺陷，`promptfooconfig-hard.yaml` 的 H3 已在看 |
| HL2 | L2 | `_store.load` 同樣在 `try` 之外，它拋錯時 lock 也不會釋放——與 early return 是同一個機制的第二個出口 | 3.7 抓到、3.6 全漏 |

## attribute-shadowing.diff

| ID | tier | 缺陷 | 證據 |
|----|------|------|------|
| AS1 | L1 | 把 Telegram Update 物件存成 `self.update`，遮蔽了類別的 `update()` 方法，`pm.update('text')` 會在執行期炸掉 | 主缺陷，`promptfooconfig.yaml` 的 TC5 已在看 |
| AS2 | L2 | 新增的 `__aexit__` try/except 少了 `self.message is not None` 的守衛 | 3.6 抓到、3.7 全漏 |

## refactor-display-logic.diff

| ID | tier | 缺陷 | 證據 |
|----|------|------|------|
| RD1 | L2 | 警告／資訊區塊的標題文案固定宣稱「顯示前 10 個」，但截斷只在總數超過 10 時才發生；總數 ≤ 10 時全部項目都會被顯示，標題仍宣告一個並未生效的上限，與實際呈現的內容不符 | `refactor-display-logic.diff`：標題文案（第 53 行，infos 第 66 行）不論數量固定寫死「顯示前 10 個」；`.slice(0, 10)`（第 54 行，infos 第 67 行）巢狀在外層 `if (warnings.length > 0)`／`if (infos.length > 0)`（第 52、65 行）內，無條件執行，總數 ≤ 10 時是 no-op；只有「還有 N 個未顯示」的揭露（第 59–60 行，infos 第 72–73 行）才真正被 `length > 10` 把關。pairwise 實測來源：3.6 抓到、3.7 全漏 |

注意：這份 diff 同時是 `promptfooconfig.yaml` 的 TC6（罰誤報）。兩邊不衝突——TC6 只在
報成 HIGH 或安全漏洞時 FAIL，這裡要的是把誤導文案報成 LOW 或 MEDIUM。它是唯一在兩份
config 都出現的 fixture，改它要兩邊一起看。

RD1 措辭曾於 2026-09-22 修正：原描述宣稱「使用者會以為看到的是全部」，但這句被 diff
本身推翻——標題會印出總數、結尾也明講還有幾個沒顯示，截斷是被完整揭露的，不存在使用者
誤以為看到全部的機制。實際成立的缺陷方向相反：當總數 ≤ 10 時，標題仍照樣寫「顯示前
10 個」，宣告了一個根本沒生效的上限。缺陷本身沒有消失，只是機制說反了；pairwise 實測
（3.6 抓到、3.7 全漏）觀察到的正是這條「誤導的『顯示前 10 個』文案」。

## snowflake-filter.diff

| ID | tier | 缺陷 | 證據 |
|----|------|------|------|
| SF1 | L3 | `Number()` 對 17–19 位的 Discord snowflake ID 會超過 `MAX_SAFE_INTEGER` 而失去精度 | 主缺陷，`promptfooconfig.yaml` 的 TC1 已在看。列在這裡是因為它是現有 fixture 裡除 G8 之外唯一的 L3——需要推理 diff 內看不到的執行期資料形狀（Discord ID 的位數）。spec D22 量到 arm N 在這題四次僅一次命中、現行 prompt 四次全中，Fisher p=0.029 |
