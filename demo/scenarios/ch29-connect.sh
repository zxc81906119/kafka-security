#!/usr/bin/env bash
# ============================================================================
# ch29-connect.sh — 第 29 章:Kafka Connect 的安全與可靠性——RBAC、連接器各用自己的身分、壞資料(DLQ)、密碼不落地(config provider)
# ----------------------------------------------------------------------------
# 白話:Connect 的連接器長期在背景跑、手上常握著別的系統的帳密。這一章實測它的安全與可靠性:誰能管連接器(RBAC)、連接器用自己的最小權限身分、壞資料不拖垮整個連接器(DLQ)、密碼不寫在設定裡(config provider)。
# 前置條件:叢集已啟動(scripts/up.sh);記憶體吃緊時先 scripts/observability.sh off、docker stop control-center schema-registry
# 冪等:是。第一步 scripts/chapter-start.sh 確認起點(本章不需要前面的章節),重跑結果相同。
# 用法:
#   ./demo.sh 29                  經由講解控制台跑這一章(DEMO_PAUSE=0 不暫停)
#   ./scenarios/ch29-connect.sh    直接跑
# 會改動什麼:產生 client 憑證 CN=connect、在模擬 AD 新增服務帳號 SVC-ORDERS-SINK、建立 topic orders.sink / orders.sink.dlq 與角色綁定、下載 connect-file 外掛、啟動 connect 容器;建立並刪除連接器 orders-*。
# 怎麼判斷成功:每一步印「✔ 符合預期」,最後一行「第 29 章完成(失敗 0 項)」
# 實測結果摘要:
#   RBAC:AD 群組決定誰能建立、看到連接器(yujie 只能管 orders- 開頭;ming 空清單、403;沒帳密 401)
#   身分:連接器用自己的 AD 服務帳號 SVC-ORDERS-SINK(只能讀 orders.sink);用 worker 身分或讀沒授權的 topic 都 TopicAuthorizationException
#   DLQ:沒容錯的連接器遇第一筆壞資料就 FAILED;errors.tolerance=all + DLQ 好的照寫、壞的進 DLQ 並附錯誤標頭
#   密碼:用 ${file:…} 引用密碼檔,connect-configs topic 裡沒有密碼;直接寫進設定的以明文存在 topic
#   外掛:Confluent 映像不含 FileStream 連接器,用 Apache Kafka 的 connect-file(Maven Central,校驗 SHA-1)
# ============================================================================
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch29 "Kafka Connect 的安全與可靠性"
CS="$DEMO_ROOT/scripts/connect-setup.sh"
CL="$DEMO_ROOT/scripts/connect-lab.sh"

step prepare "【起點準備】這一章不需要額外準備,確認環境可直接開始(冪等:可單獨從這一章開始,也可重跑)" \
  "scripts/chapter-start.sh ch29" \
  'bash "$DEMO_ROOT/scripts/chapter-start.sh" ch29 2>&1' '\[起點\] ch29 就緒'

step connect-on "【啟動】備妥 worker 的憑證與角色、連接器的 AD 服務帳號與角色、使用者(群組)對連接器的角色、外掛與密碼檔,啟動 Connect worker(REST 走 HTTPS,RBAC)" \
  "scripts/connect-setup.sh on" \
  'bash "$CS" on 2>&1 | tail -3' '\[connect\] 就緒'

step connect-rbac "【誰能管連接器】AD 群組決定:yujie 只能管 orders- 開頭的連接器;ming 看不到也建不了;沒帳密 401" \
  "POST /connectors(yujie / ming);GET /connectors" \
  'bash "$CL" rbac 2>&1' '判定:連接器的建立、查看依 AD 群組授權'

step connect-identity "【連接器的身分】每個連接器用自己的 AD 服務帳號(最小權限);用 worker 身分或讀沒授權的 topic 都被擋" \
  "consumer.override.sasl.jaas.config(連接器自己的帳號);GET /connectors/<名稱>/status" \
  'bash "$CL" identity 2>&1' '判定:連接器各用自己的最小權限身分'

step connect-dlq "【壞資料】沒有容錯的連接器遇到第一筆壞資料就 FAILED;errors.tolerance=all 加 DLQ,好的照寫、壞的進 DLQ 並附錯誤原因" \
  "errors.tolerance=all;errors.deadletterqueue.topic.name;errors.deadletterqueue.context.headers.enable=true" \
  'bash "$CL" dlq 2>&1' '判定:沒有容錯的連接器遇到第一筆壞資料就 FAILED'

step connect-secrets "【密碼不落地】用 \${file:…} 引用密碼檔:connect-configs topic 沒有密碼;直接寫進設定的密碼以明文存在 topic" \
  "config.providers=file(FileConfigProvider);kafka-console-consumer --topic connect-configs" \
  'bash "$CL" secrets 2>&1' '判定:用 config provider 引用密碼檔'

ch_end
