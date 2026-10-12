#!/usr/bin/env bash
# ============================================================================
# ch23-cert-rotation.sh — 第 23 章:憑證到期監控與不停機換憑證
# ----------------------------------------------------------------------------
# 白話:憑證過期是常見的停機原因。這一章用 blackbox 探測各端點「實際送出」的憑證算剩餘天數,並實測不重啟 broker 的換憑證流程(預檢、金絲雀、帶外回退),以及 SAN 不對、換成別的 CA 簽的憑證會發生什麼事。
# 前置條件:需要 Prometheus、Alertmanager、blackbox-exporter:docker compose --profile c3 up -d prometheus alertmanager blackbox-exporter
# 冪等:是。第一步 scripts/chapter-start.sh 確認起點(本章不需要前面的章節),重跑結果相同。
# 用法:
#   ./demo.sh 23                  經由講解控制台跑這一章(DEMO_PAUSE=0 不暫停)
#   ./scenarios/ch23-cert-rotation.sh    直接跑
# 會改動什麼:在 certs/ 產生測試用憑證與 keystore(不進版本庫);對 broker 設定動態 keystore(cleanup 步驟會移除);persist 步驟會重啟 broker1;rotate 建立並刪除 topic cert.roll。
# 怎麼判斷成功:每一步印「✔ 符合預期」,最後一行「第 23 章完成(失敗 0 項)」
# 實測結果摘要:
#   監控:blackbox 探測 22 個端點(對外 TLS 15:broker、MDS、REST Proxy、SR、Connect、C3;內部 mTLS 7)的「實際送出」憑證;telemetry 的 mtls_earliest_cert_expiration_ms 全部回報 Long.MAX_VALUE(沒填值),不採用
#   換憑證:動態 keystore 重載(不重啟)比滾動重啟好;Kafka 規定 keystore 設定只能設在單一 broker,所以「預檢 → 金絲雀 → 其餘」;MDS 不在動態重載範圍
#   事故:SAN 不同被 broker 拒絕;別的 CA 簽的憑證 broker 會接受但 client 全部失敗 → 回退要走帶外路徑(INTERNAL mTLS 埠)
# ============================================================================
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch23 "憑證到期監控與不停機換憑證"
CL="$DEMO_ROOT/scripts/cert-lab.sh"

step prepare "【起點準備】這一章不需要額外準備,確認環境可直接開始(冪等:可單獨從這一章開始,也可重跑)" \
  "scripts/chapter-start.sh ch23" \
  'bash "$DEMO_ROOT/scripts/chapter-start.sh" ch23 2>&1' '\[起點\] ch23 就緒'

step cert-baseline "【現況】各端點「實際送出」的憑證 vs 磁碟檔案;OP menu 第 17 項(檔案巡檢)現在會顯示剩餘時間分級(已過期 / 不到 7 天 / 不到 30 天 / 不到 90 天)" \
  "openssl s_client -connect <端點>;openssl x509 -noout -serial -enddate;opmenu.sh --run 17" \
  'bash "$CL" baseline 2>&1' '判定:現況各端點送出的憑證與磁碟檔案是同一張'

step cert-monitor "【到期監控】blackbox exporter 對 22 個端點做 TLS 探測(對外 15 個、內部 mTLS 7 個;生態系元件也用同一張 server 憑證,全部要探測):剩餘天數與基準狀態。內部 mTLS 埠用一張「無權限」的 client 憑證完成握手——不能把 super user 的內部憑證私鑰放進探測容器" \
  "Prometheus: probe_ssl_earliest_cert_expiry、probe_success(job tls-expiry、tls-expiry-mtls)" \
  'bash "$CL" monitor 2>&1' '判定:22 個 TLS 端點'

step cert-expiring "【快到期】模擬 CLIENT 埠換成只剩 20 天效期的憑證 → KafkaTlsCertExpiringSoon 觸發。MDS(8091)仍是舊憑證:它不在動態重載範圍" \
  "kafka-configs --entity-type brokers --entity-name <id> --alter --add-config listener.name.client.ssl.keystore.location=…" \
  'bash "$CL" expiring 2>&1' '判定:CLIENT 埠換成 20 天效期的憑證後'

step cert-rotate "【不停機換憑證】預檢 → 先換 broker1 當金絲雀並用 client 角度驗證 → 再換其餘 3 台。背景持續寫入 300 筆:序號變了、broker 沒重啟、零失敗、到期告警解除" \
  "openssl verify -CAfile;kafka-configs(逐台);openssl s_client -verify_return_error" \
  'bash "$CL" rotate 2>&1' '判定:不重啟換成新憑證'

step cert-reject-san "【SAN 不同】新憑證的 SAN 與現有不同(防止被塞進不同身分的憑證)→ broker 拒絕這次動態更新" \
  "kafka-configs --alter(新憑證 SAN 多了 evil.example.com)" \
  'bash "$CL" reject-san 2>&1' '判定:SAN 與現有不同的憑證被 broker 拒絕'

step cert-reject-ca "【別的 CA 簽的憑證】預檢攔得下來;故意不理預檢只換一台:broker 接受,但 client 驗證失敗(影響限於金絲雀);回退要走不經 CLIENT 埠的帶外路徑(INTERNAL mTLS 埠),不能依賴剛弄壞的連線" \
  "openssl verify(失敗);kafka-configs 先 broker1;回退用 --bootstrap-server broker:9092 --command-config internal.properties" \
  'bash "$CL" reject-ca 2>&1' '判定:別的 CA 簽的憑證通得過'

step cert-persist "【重啟後】動態設定存在叢集 metadata:重啟 broker1 後仍是動態設定的憑證。所以靜態設定檔也必須同步指向新檔,否則兩處不一致,日後移除動態設定會「換回舊憑證」" \
  "docker restart broker1;比對重啟前後送出的序號" \
  'bash "$CL" persist 2>&1' '判定:重啟後仍是動態設定的憑證'

step cert-cleanup "【清理】移除動態設定,回到靜態檔的憑證" \
  "kafka-configs --alter --delete-config listener.name.client.ssl.keystore.*(逐台,走帶外路徑)" \
  'bash "$CL" cleanup 2>&1' '判定:已回到靜態檔的憑證'

ch_end
