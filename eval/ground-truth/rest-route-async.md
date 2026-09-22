# rest-route-async.diff

來源專案的 REST route 非同步化重構，3 檔 68 行。來源為私有專案，不隨本 repo 出貨。

## 真缺陷（recall 點）

| ID | tier | 缺陷 | 證據 |
|----|------|------|------|
| RR1 | L2 | DELETE 處理內兩個連續寫入未包在交易中：先 `UPDATE accounts SET is_active = 0`，再 `UPDATE users SET default_account = NULL`。第二個失敗則帳戶已停用而 `users.default_account` 仍指向它。上游的 `referenced` 檢查到更新之間亦未序列化 | 經人工讀原始碼確認，且該檔自該 commit 起未再變動。上游追認：該專案後續在 `reconcile` 與 `transactions` 兩處各自修掉同一類問題（讀改寫包進單一交易並鎖列），accounts route 未被涵蓋 |

## 為什麼只有一條也要收

spec D24 記載：同一份 diff 交給 single-shot（同樣帶 `--add-dir`）跑兩次，兩次皆 PASS 零
finding。這是極少數「確定會漏」的錨點，當敏感度計量器比條數重要。

## 不收進 recall 的疑慮

- 另兩條 fan-out 確認過的是測試檔內的 non-null assertion（LOW），實務上偏噪音，不進 recall 點。
