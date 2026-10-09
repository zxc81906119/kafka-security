#!/usr/bin/env bash
# 第 19 章(進階):帳號被偷之後 —— 讓被偷的帳號「撐不久、灌不大、被發現、不拖垮管理員」
# 對應第 18 章的發現(只停用 SCRAM 憑證擋不住舊連線)。六項:SASL 重新認證、認證失敗告警、TLS 套件限定、連線數上限、client quota、AD 帳號鎖定的反向影響。
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch19 "帳號被偷之後:失效、告警、限速、限連線、鎖定"
DC="$DEMO_ROOT/scripts/dcurl.sh"
KS="$DEMO_ROOT/scripts/k.sh"
BS="--bootstrap-server broker1:9094"

# ---------------- ① 重新認證 ----------------
step reauth-baseline "【失效 ①】基準設定:CLIENT listener 的 SASL 連線每 60 秒重新認證一次(demo 值;正式環境建議 1 小時。預設 0 = 連著就永遠有效,第 18 章實驗的就是這個狀況)" \
  "docker exec broker1 grep connections.max.reauth.ms /etc/kafka/kafka.properties" \
  'docker exec broker1 grep "connections.max.reauth.ms" /etc/kafka/kafka.properties; docker exec broker2 grep "connections.max.reauth.ms" /etc/kafka/kafka.properties' '60000'

step reauth-run "【失效 ②】實驗:停用一個「連著的」帳號(只停用 SCRAM 憑證,角色保留),看舊連線還能寫幾筆" \
  "scripts/reauth-test.sh run   # 對照第 18 章:同樣只停用憑證,當時 14/14 全寫入" \
  'bash "$DEMO_ROOT/scripts/reauth-test.sh" run 2>&1' '判定:60 秒內舊連線被切斷'

# ---------------- ② 告警 ----------------
step alert "【發現】連續認證失敗 → Prometheus 規則 KafkaAuthFailuresBurst 觸發 → 送到 Alertmanager(5 次錯誤登入:SCRAM 3 次、PLAIN 2 次)" \
  "PromQL: sum by (listener)(increase(io_confluent_kafka_server_socket_server_failed_authentication_total[5m])) > 3" \
  'for i in 1 2 3; do "$KS" kafka-topics $BS --command-config /clients/scram-svc-orders-wrong.properties --list >/dev/null 2>&1; done; for i in 1 2; do "$KS" kafka-topics $BS --command-config /clients/plain-yujie-wrong.properties --list >/dev/null 2>&1; done; echo "已製造 5 次認證失敗,等待規則評估(每 60 秒一次,指標每 60 秒送一次)…"; for i in $(seq 1 24); do r=$(bash "$DC" -u c3:prom-pw "https://prometheus:9090/api/v1/alerts" | head -1); echo "$r" | grep -q KafkaAuthFailuresBurst && break; sleep 15; done; echo "Prometheus:$(echo "$r" | grep -o "\"alertname\":\"KafkaAuthFailuresBurst\"\|\"state\":\"[a-z]*\"\|\"listener\":\"[A-Z]*\"" | tr "\n" " ")"; sleep 20; echo "Alertmanager:$(bash "$DC" -u c3:am-pw "https://alertmanager:9093/api/v2/alerts" | head -1 | grep -o "\"summary\":\"[^\"]*\"" | head -1)"' 'state":"firing"'

# ---------------- ③ TLS ----------------
step tls "【傳輸】TLS 只收 1.2 / 1.3 與 AEAD 套件:CBC + SHA-1 這類弱套件被拒(未設定前,broker 接受 ECDHE-RSA-AES128-SHA)" \
  "openssl s_client -connect broker1:9094 -tls1_2 -cipher <套件>" \
  'o=$( p() { r=$(docker run --rm --network cpsec_default --entrypoint sh alpine/openssl -c "echo | openssl s_client -connect broker1:9094 $1 2>&1 | grep -E \"Cipher is|alert handshake\" | head -1"); case "$r" in *"Cipher is (NONE)"*|*"alert handshake"*) echo "$2 → 拒絕";; *"Cipher is"*) echo "$2 → 接受($(echo "$r" | sed -E "s/.*Cipher is //"))";; *) echo "$2 → 拒絕";; esac; }; p "-tls1_2 -cipher ECDHE-RSA-AES256-GCM-SHA384" "TLS1.2 AES256-GCM"; p "-tls1_2 -cipher ECDHE-RSA-AES128-SHA" "TLS1.2 AES128-CBC-SHA1"; p "-tls1_2 -cipher AES128-SHA" "TLS1.2 RSA 金鑰交換 CBC"; p "-tls1_3" "TLS1.3"; ) ; echo "$o"; echo "$o" | grep -q "AES256-GCM → 接受" && echo "$o" | grep -q "AES128-CBC-SHA1 → 拒絕" && echo "判定:只收 AEAD 套件,CBC + SHA-1 被拒" || echo "判定:不符合"' '判定:只收 AEAD 套件'

# ---------------- ④ 連線數 ----------------
step connlimit "【限連線】單一來源 IP 最多 2 條連線(動態設定 max.connections.per.ip):同一來源開 4 條,後面的被 broker 拒絕;做完移除" \
  "kafka-configs --alter --entity-type brokers --entity-default --add-config max.connections.per.ip=2" \
  'C="$KS kafka-configs $BS --command-config /clients/token-bootstrap.properties --entity-type brokers --entity-default"; $C --alter --add-config max.connections.per.ip=2 2>&1 | tail -1; sleep 3; docker run --rm --network cpsec_default --entrypoint sh alpine/openssl -c "for i in 1 2 3 4; do (openssl s_client -connect broker1:9094 -quiet </dev/null >/dev/null 2>&1 &); sleep 0.7; done; sleep 3" ; n=$(docker logs broker1 --since 1m 2>&1 | grep -c "Rejected connection.*maximum of 2"); echo "broker1 日誌:被拒絕的連線 $n 條"; $C --alter --delete-config max.connections.per.ip 2>&1 | tail -1; [ "$n" -ge 1 ] && echo "判定:超過上限的連線被拒絕" || echo "判定:不符合"' '判定:超過上限的連線被拒絕'

# ---------------- ⑤ quota ----------------
step quota "【限速】client quota:被偷的帳號能灌多少流量?同一個動作,不限速 vs 套用 producer_byte_rate" \
  "kafka-configs --alter --entity-type users --entity-name <帳號> --add-config producer_byte_rate=100000" \
  'bash "$DEMO_ROOT/scripts/quota-test.sh" 2>&1' '判定:限速後吞吐量降為原來的 1/'

# ---------------- ⑥ AD 帳號鎖定 ----------------
step lockout-dos "【鎖定 ①】AD 的帳戶鎖定原則是雙面刃:攻擊者對 GARY 亂試 6 次 → GARY 被鎖,連用對的密碼也進不去(= 把管理員擋在外面);機器帳號與緊急路徑不受影響" \
  "scripts/ad-lockout.sh on;  curl -u gary:<錯密碼> ×6;  curl -u gary:<對的密碼>" \
  'bash "$DEMO_ROOT/scripts/ad-lockout.sh" on; for i in 1 2 3 4 5 6; do bash "$DC" -o /dev/null -u gary:bad-$i https://broker1:8091/security/1.0/authenticate | tail -1 | tr "\n" " "; done; echo; echo "GARY 用對的密碼 → $(bash "$DC" -o /dev/null -u gary:gary-pw https://broker1:8091/security/1.0/authenticate | tail -1)"; bash "$DEMO_ROOT/scripts/ad-lockout.sh" status GARY; echo "Kafka 上 GARY(PLAIN)→ $("$KS" kafka-topics $BS --command-config /clients/plain-gary.properties --list 2>&1 | grep -c "Authentication failed") 個認證失敗"; echo "緊急路徑(bootstrap 憑證)→ $("$KS" kafka-topics $BS --command-config /clients/token-bootstrap.properties --list 2>&1 | grep -vc "^WARNING\|SLF4J\|Authentication failed") 個 topic 可列出"; echo "判定:GARY 被鎖定,緊急路徑不受影響"' '判定:GARY 被鎖定,緊急路徑不受影響'

step lockout-recover "【鎖定 ②】恢復:管理員解鎖(對應 AD 的「解除鎖定帳戶」)→ GARY 立刻可登入;另一種是等鎖定時間(這裡 60 秒)過去自動解除。做完關閉鎖定,回到其他章節的狀態" \
  "scripts/ad-lockout.sh unlock GARY;  scripts/ad-lockout.sh off" \
  'bash "$DEMO_ROOT/scripts/ad-lockout.sh" unlock GARY; echo "GARY 用對的密碼 → $(bash "$DC" -o /dev/null -u gary:gary-pw https://broker1:8091/security/1.0/authenticate | tail -1)"; bash "$DEMO_ROOT/scripts/ad-lockout.sh" off; bash "$DEMO_ROOT/scripts/ad-lockout.sh" status GARY' 'HTTP 200'

# ---------------- ⑦ 刪除 SCRAM 帳號的坑(KAFKA-20774) ----------------
step scram-bug "【已知 bug】刪除 SCRAM 帳號(--delete-config)後重啟 broker:重放 metadata 時整組 SCRAM 使用者被丟掉,所有 SCRAM 登入失敗(KAFKA-20774,fix 在 Kafka 4.5.0 未發行;CP 8.3.2 受影響)。救回:重建被刪帳號再重啟。所以這個 demo 停用帳號一律覆寫隨機密碼、不刪除" \
  "scripts/scram-delete-bug.sh   # 新建→刪除→重啟 broker1→SCRAM 登入失敗→重建帳號→重啟→恢復" \
  'bash "$DEMO_ROOT/scripts/scram-delete-bug.sh" 2>&1' '判定:(已重現 KAFKA-20774|這次沒有重現)'

ch_end
