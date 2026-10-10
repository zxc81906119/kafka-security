# 維護指南:怎麼讀、怎麼改這套 Lab 腳本

給誰:會基本指令(docker、curl、基本 shell)、但不熟 bash 技巧的維運工程師。目標是**不用靠原作者也能看懂與維護**。

## 1. 先看這裡:目錄地圖

| 位置 | 是什麼 | 怎麼用 |
|---|---|---|
| `scenarios/chNN-*.sh` | 每一章的「劇本」:一連串步驟,每步執行指令並檢查結果 | `./demo.sh NN` 或 `./scenarios/chNN-*.sh` |
| `scripts/*.sh` | 章節裡呼叫的「實驗腳本」(停 broker、換憑證……) | 直接執行,`--help` 看說明 |
| `scripts/lib/` | **共用小工具**(白話說明、等待、查 Prometheus、Kafka 指令) | 腳本用 `source` 載入,見第 3 節 |
| `labguide/` | 產生 Word 手冊的程式與每個 Lab 的文字(`labs-extra.mjs`) | `node labguide/verify-doc.mjs chNN` 驗證手冊指令 |
| `docker-compose.yml`、`docker-compose.ha.yml` | 基礎環境、HA 環境 | `scripts/ha.sh on / off` 切換 |
| `RUNBOOK.md`、`DESIGN-BASIS.md` | 實測結果與設計依據 | 改了行為就要同步 |
| `LABS-ROADMAP.md` | 還要做哪些 Lab | |

怎麼看一個章節:先讀 `scenarios/chNN-*.sh`(每個 `step` 的第二個參數是中文說明),再看它呼叫的 `scripts/*.sh`,最後看 `scripts/lib/`。

## 2. 腳本的寫法(新腳本一律照這個)

1. **開頭放標頭樣板**(第 4 節),讓人 30 秒內知道這支腳本在做什麼、會改動什麼。
2. **一行一件事。** 不要把迴圈、判斷、管線塞成一行 300 字元。拆成有名字的函式。
3. **函式名稱用「動詞_受詞」**(`wait_healthy`、`kafka_topics`),每個函式上方寫一行「做什麼、為什麼」。
4. **每個動作前先 `say` 一句白話**(接下來做什麼、為什麼)。`EXPLAIN=0` 可關閉。小白跟著輸出就能看懂。
5. **所有等待都要有逾時**,用 `wait_until`。不要寫沒有上限的 `until`/`while` 迴圈(曾經有等待迴圈無聲跑了 9 小時)。
6. **解析 JSON 不要在 bash 裡內嵌 `node -e '...'`**。放進 `scripts/lib/*.mjs`,一個檔案做一件事。
7. **結果用 `verdict` 印「判定:…」一行。**章節腳本靠這行文字判斷成功與否,格式不要改。
8. **改了環境要還原。**實驗做完把停掉的容器啟動回來、移除臨時設定;標頭的「會改動什麼」要寫清楚。
9. **不要把密碼、金鑰寫進腳本或版本庫。**測試值是例外,但要在檔案裡註明是測試值;正式環境的密碼由 CyberArk 提供。
10. **設定值只定義一次。**broker 清單、帳密、埠都放在 `scripts/lib/*.sh` 的變數(可用環境變數覆蓋),不要每支腳本各寫一份。

## 3. 共用工具(`scripts/lib/`)

```bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"   # say、wait_until、wait_healthy、dcurl、verdict ……
source "$(dirname "${BASH_SOURCE[0]}")/lib/prom.sh"     # prom_query、alerts_firing、alert_is_firing ……
source "$(dirname "${BASH_SOURCE[0]}")/lib/kafka.sh"    # kafka_topics、kafka_configs、produce_test ……
```

| 函式 | 做什麼 |
|---|---|
| `say "白話說明"` | 印出「▶ …」,告訴讀的人接下來要做什麼 |
| `wait_until "描述" 秒數 指令…` | 每 5 秒試一次,成功就結束,逾時回傳 1 |
| `wait_healthy 容器…` | 等容器都 healthy |
| `prom_query 'PromQL'` | 查 Prometheus,印第一筆的值 |
| `alerts_firing [正規表示式]` | 列出正在觸發的告警 |
| `kafka_topics … / kafka_configs …` | 在容器內跑 Kafka 指令(一般路徑) |
| `kafka_configs_oob …` | 同上,但走**帶外路徑**(INTERNAL mTLS 埠),回退憑證時用 |
| `produce_test topic 筆數 acks` | 壓測寫入,印成功筆數 |

## 4. 標頭樣板(新腳本貼上即用)

```bash
#!/usr/bin/env bash
# ============================================================================
# my-lab.sh — 一句話說明這支腳本做什麼
# ----------------------------------------------------------------------------
# 白話:2 到 4 句,給完全沒看過的人。講「為什麼要做這件事」,不只是「做什麼」。
# 前置條件:例如「HA 模式(scripts/ha.sh on)、Prometheus 已啟動」
# 用法:
#   scripts/my-lab.sh 子命令1    這個子命令做什麼
#   scripts/my-lab.sh 子命令2    這個子命令做什麼
# 會改動什麼:例如「停止 broker3 再啟動回來;建立 topic xxx 並在最後刪除」
# 怎麼判斷成功:最後一行印「判定:…」
# 常見失敗:症狀 → 原因 → 處理
# ============================================================================
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
[ "${1:-}" = "--help" ] && { usage_from_header "$0"; exit 0; }
```

## 5. 已經踩過的坑(改腳本前先看)

| 症狀 | 原因 | 做法 |
|---|---|---|
| 腳本執行到一半**靜默結束**,沒有錯誤訊息 | `set -e` 加 `pipefail` 時,`grep -m1`、`head`、`diff` 回傳非 0(或對方被 SIGPIPE 中斷)會讓整個腳本結束 | 把結果先存進變數再判斷,或在該行加 `|| true`;新腳本不要用 `set -e` |
| 告警「沒有觸發」,其實是指令寫錯 | 過濾輸出的 `grep "Created|rror"` 把真正的錯誤吃掉了 | 建立資源失敗要明確印錯誤並結束,不要只過濾成功字樣 |
| 輪替/換設定後「重啟成功」卻沒生效 | `docker compose up` 在設定沒變時**不會重啟**容器 | 要重啟就用 `docker restart` 並等健康 |
| 容器重啟後 exporter 指標空了 2 分鐘 | 官方 JMX 設定 `startDelaySeconds: 120` | 等待時間要涵蓋這 2 分鐘 |
| compose `extends` 後埠號衝突 | `extends` 會把 `ports` 串接 | 用 `ports: !override` |
| Windows 上 `COMPOSE_FILE` 多檔失效 | Windows 的分隔符是 `;` | 同時設 `COMPOSE_PATH_SEPARATOR=,` |
| `docker` 收到的路徑被改壞、`node` 讀不到 `/tmp` | Git Bash 的路徑轉換 | `export MSYS_NO_PATHCONV=1`;傳給 node 的路徑用 Windows 路徑(`cygpath -m`) |
| `python3` 指令什麼都不做 | Windows 的 `python3` 是商店捷徑假檔 | 用 `node` |
| 用 heredoc 寫檔結果引號亂掉 | 巢狀引號、`$`、`\` 混用 | 用編輯器工具直接寫檔;批次修改用「找錨點取代」的小腳本,**確認錨點只出現一次、腳本只執行一次**(曾因執行兩次造成投影片重複) |
| 腳本跑一半被改壞 | bash 是邊讀邊執行,**不要編輯正在執行的腳本** | 等它結束再改 |
| 壓測後只讀分區 0 讀不到資料 | sticky partitioner 讓一批資料集中在同一個分區 | 檢查筆數要加總所有分區(`topic_message_count`) |
| 副本不足時 acks=1 看似成功卻讀不到 | 高水位不前進 | 重要資料用 `acks=all` 加 `min.insync.replicas` |
| 換憑證後連回退都失敗 | 回退走的 CLIENT 埠憑證正是被換壞的那個 | 回退一律走帶外路徑(`kafka_configs_oob`) |
| 換憑證的設定被拒:`Cannot update these configs at default cluster level` | keystore 設定只能設在單一 broker | 逐台設定(`--entity-name <broker id>`) |
| 金鑰輪替後 broker 起不來 | 密文檔與主金鑰不成對 | 兩者一起換、先備份舊的;見 Lab 18 |
| `confluent secret --passphrase @檔案` 解不開 | CLI 不讀檔,把 `@/路徑` 當成密碼字串 | passphrase 直接給字面值 |
| 刪除 SCRAM 帳號後 broker 起不來或登入全壞 | Apache Kafka KAFKA-20774 | 停用 = 覆寫成隨機密碼,不刪除 |
| 背景任務的輸出很久都沒出現 | 管線結束前不會刷新輸出 | 讓腳本把結果寫進檔案,再用有上限的迴圈讀取 |
| Prometheus 告警比預期慢 | telemetry 每 60 秒推送、規則每 60 秒評估 | 用 JMX exporter(每 15 秒抓)或等足夠久 |

## 6. 新增一個 Lab 的步驟

1. **先探索**:手動做一遍,記下實際輸出(不要預設結果)。
2. **寫實驗腳本** `scripts/xxx-lab.sh`(第 4 節樣板,每個子命令結尾印「判定:…」)。
3. **寫章節劇本** `scenarios/chNN-*.sh`:每個 `step` = 一段中文說明 + 顯示用指令 + 實際指令 + 判定用的正規表示式;最後 `ch_end`;在 `demo.sh` 註冊。
4. **跑整章**:0 失敗才往下。
5. **寫手冊內容**:`labguide/labs-extra.mjs`(步驟、為什麼、預期、警語)、`story.mjs`(故事段落,要接上前一個 Lab)、`labmap.mjs`(地圖)。
6. **手冊自檢**:`node labguide/verify-doc.mjs chNN`,0 不符合。
7. **同步文件**:`RUNBOOK.md`、`DESIGN-BASIS.md`、銀行導入手冊(`labguide/build-banking-handbook.cjs`);重產手冊與截圖。
8. **提交**:不要提交 `.env`、`deck/tpl/`、憑證與金鑰、下載的 jar。

## 7. 環境與驗證

- 基礎環境(Lab 0 到 20):`scripts/up.sh`;HA 環境(Lab 21 起):`scripts/ha.sh on`,回基礎:`scripts/ha.sh off`(都會清除資料)。
- 不要同時開 HA、cyberark、sr(記憶體不夠)。
- 每個實驗做完要把環境還原;出事時 `scripts/ha.sh on` 一定能重建出乾淨環境。
- 一次改動只改一個地方,改完立刻重跑相關章節;**不要一口氣改很多再一起測**。

## 8. 設計原則(做決定時用)

- **採用的做法必須比原本的更好**,不是「可以用」就換;寫出理由與沒選的替代方案。
- 先測再寫;測不到的明確標「未驗證」,不要寫成事實。
- 正式環境與測試環境的差異要寫清楚(測試值、單機、靜態 quorum 等)。
