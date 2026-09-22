# 詞彙表

這個 repo 特有、解釋要一句話以上的詞。通用技術名詞不收。

## Eval

**罰誤報案例** — `eval/promptfooconfig.yaml` 裡那六個（TC2/3/6/7/8/9）。它們的 diff 本身是乾淨的，PASS 的意思是「reviewer 沒有無中生有」。判定是二元的。

**虛構關卡** — 掛在一份**有真缺陷**的 diff 上、針對特定錯誤宣稱的 assertion（如 `migration-cli-entrypoint.diff` 的 N1–N7）。與罰誤報案例的差別在素材：那邊沒有東西可報，這邊有東西可報但模型可能多報一條不存在的事實。兩者量的不是同一回事，不要互相代稱。
_Avoid_：把虛構關卡叫「誤報案例」。

**recall 點** — 一條「這份 diff 裡確實存在、該被報出來」的缺陷，對應一條 `llm-rubric`。一份 fixture 有幾個 recall 點由 ground truth 決定，不強求數量。

**tier** — 缺陷的偵測難度分層。L1 讀 diff 即見；L2 需要領域知識或跨 hunk 串接；L3 需要推理 diff 內看不到的事實（執行期資料形狀、未見的 schema）。標在 ground truth 上，不是 fixture 的屬性——同一份 fixture 的不同缺陷可以落在不同 tier。

**ground truth 檔** — `eval/ground-truth/<fixture>.md`。記 rubric 承載不了的東西：每條缺陷的證據來源（人工讀原始碼／上游追認／fan-out 查證）、tier、以及已證偽的誤報清單。rubric 只承載「怎麼判這一條」。

**紅格的三種成因** — promptfoo 報表裡一個失敗的格子可能是真失敗（judge 給出文字判決）、provider 錯誤（503／配額／權限拒絕）、或 judge 解析失敗（grading 呼叫自己壞了，而 `response.output` 其實有正常報告）。只有第一種是模型的問題。詳見 `CLAUDE.md`。

## Flagged ambiguities

**「誤報」有兩種用法**，在這個 repo 裡要分開講：素材面的「乾淨 diff 上報出東西」（罰誤報案例）與宣稱面的「把未查證的事實當成既成事實」（虛構關卡）。前者靠 fixture 本身乾淨來成立，後者靠逐條列出的錯誤宣稱來成立。D21 修正 Test Case 14 rubric 時處理的是後者。

**「漏報」不等於 verdict PASS**。一份報出三條真缺陷但判 PASS 的 review 不是漏報；一份判 NEEDS_CHANGES 卻只報出四條中的一條的 review 是。recall 量的是缺陷覆蓋，與 verdict 無關。
