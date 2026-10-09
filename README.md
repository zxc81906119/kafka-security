# Confluent Platform 安全 Lab(練習用)

這個分支只放練習需要的東西:docker demo 環境與兩本手冊。

| 檔案 | 用途 |
|---|---|
| `Confluent-Security-Lab-Story-Guide-v2.docx` | 完整版手冊(含每步的實際輸出與畫面) |
| `Confluent-Security-Lab-Story-Guide-v2-精簡版.docx` | 精簡版(指令與預期結果;上課時放在手邊照做) |
| `demo/` | Lab 環境:`docker-compose.yml`、腳本、章節腳本、Postman、OP menu |

## 開始之前

請先看手冊最前面的「課前準備(開課前一天完成)」,摘要如下:

```bash
cd demo
bash scripts/up.sh --with-restproxy --with-c3   # 第一次會下載映像(約 7 GB)
./preflight.sh                                  # 通過 18 / 失敗 0
bash scripts/setup-e2e.sh                       # 瀏覽器自動化(各 Lab 的截圖步驟用)
```

需求:Docker Desktop(記憶體 10 GB 以上)、Git Bash、Node.js 24。憑證(`demo/certs/`)與 CyberArk(Conjur)的金鑰不在版本庫,第一次執行時會自動產生。

## Lab 18(CyberArk 整合)

Lab 18 用 CyberArk 的開源版 Conjur,要多下載約 1.2 GB 映像;第一步 `bash scripts/conjur.sh up` 會啟動它(profile `cyberark`,4 個容器)。Lab 18.20 第一次執行 `scripts/secret-protection.sh summon-setup` 會再從 GitHub(cyberark 官方 release)下載 summon 與 summon-conjur 約 10 MB(校驗 SHA256)。PAM 側(代登入、錄影、輪替主機帳號)本機無法重現,手冊附錄 E 有說明。

## Lab 19、Lab 20

- Lab 19(帳號被偷之後)不用多下載東西,但會暫時改 AD 的鎖定原則(做完自動關回去)、並在 Prometheus 載入一組告警規則。
- Lab 20(Schema Registry)第一步 `bash scripts/sr-setup.sh` 會啟動 profile `sr` 的 Schema Registry,第一次要多下載約 1.5 GB 映像。欄位級加密(CSFLE)需要企業版加購授權,Lab 20 只驗證到授權為止,手冊有說明。
- **已知問題(已查明)**:刪除 SCRAM 憑證(`kafka-configs --delete-config SCRAM-SHA-512`)之後,下一次重啟 broker 會失敗。這個 demo 的腳本已改成「把憑證覆寫成隨機密碼」來停用帳號(`scripts/scram-disable.sh`),請不要自己用 `--delete-config` 刪 SCRAM 憑證。如果已經刪了、broker 起不來:把被刪的帳號重新建立(任何密碼)再啟動;不行時用 `bash scripts/broker-heal.sh broker1`(或 broker2)清空該 broker 的資料目錄重建。

## 練習時

- 每個 Lab 的編號就是 `./demo.sh N` 的章節編號;要回到起點執行 `./demo.sh reset`。
- 所有帳號密碼都是 demo 測試值(見手冊「本手冊的角色」),只能用在本機的練習環境。
