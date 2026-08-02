# A/B 實驗檯

調 review 品質時用的量測工具，不隨 plugin 出貨，也不參與任何 CI。這裡的 agent 定義都是實驗臂，`plugins/` 底下的才是正式的。

主要 eval 在上一層（`promptfooconfig.yaml`），用 llm-rubric 打分、涵蓋 14 個案例。這裡放的是 rubric 量不到的東西：同一個 prompt 跑 N 次的變異、單一措辭改動的效果、以及 fan-out 架構的原型。

## 為什麼要有這個

agy 沒有 sampling 控制，同一份輸入重跑的結果差異很大。單跑一輪的 promptfoo 分數不足以判斷一個 prompt 改動是真的有效還是抽到好籤——這一輪就發生過現行 prompt 在同一個案例上一次 1/4、一次 3/4 的情形。這裡的腳本一律跑多次並印出逐次結果。

## 設定

```bash
export AB_TARGET_ROOT=/path/to/checkout   # 被查證的 repo，必填
export AB_MODEL=gemini-3.6-flash-high     # 選填
agy plugin install "$(pwd)/agy-plugin"    # 安裝實驗臂
agy agents                                # 確認裝進去了——--agent 對未知名稱靜默忽略
```

`AB_TARGET_ROOT` 要指向 `eval/test-cases/migration-cli-entrypoint.diff` 的來源 repo。那是一個私有專案，不在本 repo 內；沒有它的話 `run8`–`run12` 沒有東西可查證，`run6`／`run7` 則不需要它。

## 腳本

| 腳本 | 量什麼 | 需要 target repo |
|------|--------|------------------|
| `run6.sh <agent> <tag> [n]` | Test Case 14 的 G4 命中率，條件與 eval 一致（不帶 `--add-dir`） | 否 |
| `run7.sh <agent> <tag> [n]` | 六個罰誤報案例的迴歸關卡 | 否 |
| `run8.sh <agent> <tag> [n]` | 同上但帶檔案存取，即 0.2.2 之後的實際跑法 | 是 |
| `run9.sh [n]` | 查證階段的證偽測試：一條假宣稱、一條真宣稱 | 是 |
| `run10.sh [scans] [par]` | fan-out 原型：scan ×N → 去重 → 平行 verify | 是 |
| `run11.sh [n]` | 查證器的機制檢查：機制真假 × 結論真假三種組合 | 是 |
| `run12.sh [trials] [votes]` | 確認階段的多數決 | 是 |

`run7.sh` 的判準是「verdict 為 PASS 且無 HIGH/MEDIUM」，這對沒有輸出格式的實驗臂（例如 `gemini-review-h`）沒有意義——它會全數判為退步，那是掛在缺少 `## Verdict:` 上，不是誤報。

## 實驗臂

| agent | 內容 |
|-------|------|
| `gemini-review-h` | 六行最小 prompt，無輸出格式 |
| `gemini-review-i` | 現行 prompt，LOW 上限按「缺陷長在哪」收窄 |
| `gemini-review-j` | 同 I 但砍到 81 行 |
| `gemini-review-k` | 同 J 但保留原本未收窄的 LOW 上限 |
| `gemini-review-l` | 現行 prompt，LOW 上限改按「這個 finding 靠什麼成立」收窄 |
| `gemini-review-m` | 現行 prompt 移除規格審查 |
| `gemini-review-n` | v0.2.0 原樣（79 行，無規格審查、無 Incidental Findings） |
| `gemini-scan` | fan-out 的生成階段：只列候選、不判斷、無工具 |
| `gemini-verify` | fan-out 的查證階段：一次驗一條宣稱、有檔案存取 |

I 到 N 的結論記在 `docs/specs/gemini-review.md` 的 D21 與 D22。

早期的 A–G 臂用的 payload 內含來源專案的 spec，未進版控，故那幾臂無法從這個目錄重跑；其結論記在 D19 與 D20。

## 沒有進版控的東西

`.gitignore` 排除兩個目錄：

- `out/` — 所有跑出來的原始輸出，內含絕對路徑與第三方程式碼
- `local/` — 早期實驗的 payload、來源專案的 spec，以及依賴它們的 `run.sh`–`run5.sh`

換一個 `AB_TARGET_ROOT` 時要注意：`run9`–`run12` 裡的 claim 文字是針對特定 repo 寫死的，換 repo 就要一併改寫，否則查證結果沒有意義。

## 跑 A/B 版的 promptfoo

主 config 的 provider 寫死 `gemini-review`。要比對實驗臂，複製一份到 `eval/`（`file://` 相對於 config 所在目錄解析，放到別處會找不到測試案例），改掉 provider 兩行即可：

```yaml
providers:
  - id: "exec: bash ./run-agy.sh gemini-review gemini-3.6-flash-high"
    label: "shipped"
  - id: "exec: bash ./run-agy.sh gemini-review-l gemini-3.6-flash-high"
    label: "arm-L"
```

```bash
npx promptfoo@latest eval -c promptfooconfig-ab.yaml --no-cache --repeat 4
```

複製出來的 config 不進版控——它只是兩行差異，留著會跟主 config 漂開。
