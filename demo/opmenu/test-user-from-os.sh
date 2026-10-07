#!/usr/bin/env bash
# 測 OPMENU_USER_FROM_OS:在一個 Linux 容器裡以作業系統使用者 gary 執行選單(vm 後端,只用 curl 呼叫 MDS),
# 檢查 (1) 帳號取自作業系統、OPMENU_USER 被忽略 (2) 密碼仍要驗證 (3) 開關關閉時行為不變。
cd "$(dirname "$0")"
D="$(cd .. && { pwd -W 2>/dev/null || pwd; })"
export MSYS_NO_PATHCONV=1
docker run --rm --network cpsec_default -v "$D/opmenu:/opmenu:ro" -v "$D/certs:/certs:ro" alpine:3.20 sh -c '
apk add --no-cache -q bash curl >/dev/null
adduser -D gary
echo changeit > /tmp/tp; chmod 644 /tmp/tp
mkdir -p /tmp/om && cp -r /opmenu/* /tmp/om/ && : > /tmp/om/empty.conf && chown -R gary /tmp/om
E="OPMENU_CONF=/tmp/om/empty.conf OPMENU_ALLOW_ENV_OVERRIDE=1 OPMENU_BROKER_SERVICES=broker1:confluent-server OPMENU_BACKEND=vm OPMENU_ENV_LABEL=OSTEST OPMENU_MDS_URL=https://broker1:8091 OPMENU_CA_PEM=/certs/ca.pem OPMENU_TRUSTSTORE_PASSWORD_FILE=/tmp/tp OPMENU_KAFKA_CLUSTER_ID=XyZBQ3-GTvKH2qNfP7X33A OPMENU_LOG=/tmp/om/log/t.log"
echo "== (1) 開關開(vm 預設),OPMENU_USER=ming 應被忽略,以 gary 登入 → 41 應 OK"
su gary -c "cd /tmp/om && env $E OPMENU_USER=ming OPMENU_PASS=gary-pw ./opmenu.sh --run 41 User:svc-orders" 2>&1 | grep -v "^$" | head -4
echo "== (2) 密碼給 ming 的 → 應 登入失敗"
su gary -c "cd /tmp/om && env $E OPMENU_PASS=ming-pw ./opmenu.sh --run 41 User:svc-orders" 2>&1 | grep -v "^$" | tail -1
echo "== (3) 開關關,OPMENU_USER=ming + ming 密碼 → 以 ming 登入 OK"
su gary -c "cd /tmp/om && env $E OPMENU_USER_FROM_OS=0 OPMENU_USER=ming OPMENU_PASS=ming-pw ./opmenu.sh --run 41 User:svc-orders" 2>&1 | grep -v "^$" | head -2
echo "== 紀錄(操作者欄)"; cat /tmp/om/log/t.log
'
