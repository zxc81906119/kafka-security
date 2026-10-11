#!/usr/bin/env bash
# ============================================================================
# old-connection-test.sh — 實驗:停用 SCRAM 帳號時,「已經連著的」舊連線會怎樣?
# ----------------------------------------------------------------------------
# 白話:SCRAM 只在「建立連線」時驗證密碼,connections.max.reauth.ms 預設 0(不重新驗證),所以帳號停用了,
#   已經連著的舊連線可能照樣能寫。這支腳本用實驗證明:只停用憑證擋不擋得住舊連線?解除角色擋不擋得住?
#   答案決定了「帳號被偷時」該先做哪一步。
# 前置條件:demo 環境已啟動(scripts/up.sh)、CyberArk(Conjur)已啟動(scripts/conjur.sh up),
#   且 Conjur 的 svc-orders/credential 內容必須是 svc-orders 的帳密。
# 用法:
#   scripts/old-connection-test.sh [both|scram-only]
#     both(預設)   先隔離(解除角色),再停用(停用 SCRAM)
#     scram-only    只停用 SCRAM、角色保留(看「只停用憑證」能不能切斷舊連線)
# 流程:一個長連線 producer 每 2 秒用 svc-orders 寫一筆(共 14 筆,每筆帶隨機標記)→ 約 8 秒後隔離
#   (解除角色)→ 約 8 秒後停用(停用 SCRAM)→ 結束後讀回 topic,看每個階段寫進去幾筆。
# 會改動什麼:啟動一個臨時 producer 容器(結束即移除),寫入約 14 筆到 orders.events;
#   svc-orders 的角色被解除(both 模式)、SCRAM 憑證被覆寫成隨機密碼(不刪除)。**做完不會還原**,
#   請執行 scripts/rotate-with-conjur.sh restore 把 svc-orders 的原密碼與角色還原。
# 怎麼判斷成功:看最後的「判定:…」。both 預期「解除角色就切斷舊連線」(授權失敗次數 > 0、寫入少於 14 筆);
#   scram-only 預期「只停用 SCRAM 憑證擋不住已建立的連線」(14 筆全寫完);
#   出現「判定:非預期」代表結果與預期相反。
# 常見失敗:Conjur 的 svc-orders/credential 不是 svc-orders(例如上次輪替後沒還原)→ 實驗的帳號不對
#   → 先執行 scripts/rotate-with-conjur.sh restore。
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
D="$(pwd -W 2>/dev/null || pwd)"
MODE="${1:-both}"; RID="oc$RANDOM"; N=14; LOG=$(mktemp)
CRED=$(bash scripts/conjur.sh get-as svc-orders svc-orders/credential)
echo "起點:啟動長連線 producer(svc-orders,每 2 秒一筆,共 $N 筆,標記 $RID)"
( printf '%s\n' "$CRED" | docker run --rm -i --network cpsec_default -v "$D/certs:/etc/kafka/secrets:ro" -e KAFKA_OPTS="" -e KAFKA_HEAP_OPTS="-Xmx256m" -e RID="$RID" -e N="$N" --entrypoint bash confluentinc/cp-server:8.3.2 -c '
    IFS= read -r CRED
    u=$(python3 -c "import sys,json;print(json.loads(sys.argv[1])[\"u\"])" "$CRED"); p=$(python3 -c "import sys,json;print(json.loads(sys.argv[1])[\"p\"])" "$CRED"); unset CRED
    printf "security.protocol=SASL_SSL\nsasl.mechanism=SCRAM-SHA-512\nsasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username=\"%s\" password=\"%s\";\nssl.truststore.location=/etc/kafka/secrets/truststore.p12\nssl.truststore.type=PKCS12\nssl.truststore.password=changeit\nlinger.ms=0\nconnections.max.idle.ms=600000\n" "$u" "$p" > /dev/shm/c
    ( for i in $(seq 1 $N); do echo "$RID-$i"; sleep 2; done ) | kafka-console-producer --bootstrap-server broker1:9094 --producer.config /dev/shm/c --topic orders.events 2>&1' > "$LOG" 2>&1 ) &
BG=$!
sleep 9
if [ "$MODE" = both ]; then
  echo "約第 4 筆:隔離(解除角色)"; bash scripts/rotate-with-conjur.sh quarantine svc-orders >/dev/null 2>&1
else
  echo "約第 4 筆:(scram-only:角色保留,不隔離)"
fi
sleep 9; echo "約第 8 筆:停用(SCRAM 憑證覆寫成隨機密碼,不刪除)"
if [ "$MODE" = both ]; then
  bash scripts/rotate-with-conjur.sh finish svc-orders >/dev/null 2>&1
else
  bash scripts/scram-disable.sh svc-orders >/dev/null 2>&1
fi
wait "$BG" || true
echo "讀回 topic,看每個階段寫進去幾筆(標記 $RID):"
got=$(./scripts/k.sh kafka-console-consumer --bootstrap-server broker1:9094 --command-config /clients/token-bootstrap.properties --topic orders.events --group "ocread-$RID" --from-beginning --timeout-ms 15000 2>/dev/null | grep -a -o "$RID-[0-9]*" | sed "s/$RID-//" | sort -n | uniq)
max=$(echo "$got" | tail -1); cnt=$(echo "$got" | grep -c . || true)
auth=$(grep -ciE "SaslAuthenticationException|Authentication failed" "$LOG" || true); az=$(grep -ciE "TOPIC_AUTHORIZATION_FAILED|Topic authorization failed|Not authorized" "$LOG" || true)
echo "  共送出 $N 筆;topic 裡讀到 ${cnt:-0} 筆,最大編號 ${max:-無}"
echo "  producer 日誌:授權失敗 $az 次、認證失敗 $auth 次"
echo "  隔離約在第 4–5 筆之後、停用約在第 8–9 筆之後"
if [ "$MODE" = both ]; then
  if [ "${cnt:-0}" -lt "$N" ] && [ "$az" -gt 0 ]; then
    echo "判定:解除角色就切斷舊連線(連線還在,但之後每個請求都被授權擋下;停用憑證前這一步就已生效)"
  else
    echo "判定:非預期(角色解除後舊連線仍在寫入或沒有授權失敗紀錄)"
  fi
else
  if [ "${cnt:-0}" -eq "$N" ]; then echo "判定:只停用 SCRAM 憑證擋不住已建立的連線(它繼續寫完全部 $N 筆);要切斷舊連線必須解除角色"; else echo "判定:非預期(只停用憑證後舊連線也被切斷)"; fi
fi
rm -f "$LOG"
