#!/usr/bin/env bash
# REST Proxy 設多台 MDS 的實際行為:停掉其中一台 broker(內含 MDS)時,legacy app(憑證)與人(Basic)的請求還通不通、多慢。在 demo/ 目錄執行。
# REST Proxy 的設定(docker-compose.yml):confluent.metadata.bootstrap.server.urls=https://broker1:8091,https://broker2:8092
#                                       Kafka client 登入的 metadataServerUrls 同樣兩台
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/../.."; export DEMO_ROOT="$PWD"; D="$(pwd -W 2>/dev/null || pwd)"
source scripts/rbac-lib.sh
BODY='{"records":[{"value":{"order":"F-1"}}]}'
C=rp-client
docker rm -f $C >/dev/null 2>&1
docker run -d --name $C --network cpsec_default -v "$D/certs:/certs:ro" --entrypoint sleep curlimages/curl:latest 7200 >/dev/null

req() { # req <cert|basic> ;印 [HTTP 碼 耗時]
  local a=(-s --cacert /certs/ca.pem -o /dev/null -w "%{http_code}/%{time_total}s" --max-time 60 -X POST -H "Content-Type: application/vnd.kafka.json.v2+json" -d "$BODY")
  if [ "$1" = cert ]; then a+=(--cert /certs/client-legacy-orders.pem --key /certs/client-legacy-orders.key); else a+=(-u gary:gary-pw); fi
  docker exec $C curl "${a[@]}" https://restproxy:8086/topics/orders.events
}
burst() { # burst <次數>:交錯送 cert 與 basic
  local i out=""; for i in $(seq 1 "$1"); do out+="c:$(req cert) b:$(req basic)  "; done; echo "  $out"
}
mdscount() { # mdscount <起點時間 UTC>:各 broker 的 MDS 收到 restproxy 的請求數
  local b; for b in broker1 broker2; do printf '  %s: ' $b; docker logs --since "$1" $b 2>&1 | grep -E ' - restproxy \[.*"(POST /security/1.0/impersonate|GET /security/1.0/authenticate|POST /security/1.0/authorize)' | sed -E 's/.*"(POST|GET) (\/security\/1.0\/[a-z]+).*/\2/' | sort | uniq -c | tr '\n' ' '; echo; done
}
wait_healthy() { local n="$1" i; for i in $(seq 1 60); do [ "$(docker inspect -f '{{.State.Health.Status}}' "$n" 2>/dev/null)" = healthy ] && return 0; sleep 5; done; return 1; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

rbac_bind cert bootstrap User:legacy-orders DeveloperWrite Topic orders. PREFIXED >/dev/null; sleep 6

echo "== [0] 兩台都在:基線"; T0=$(now); burst 4; mdscount $T0

echo "== [1] 停 broker1(它的 MDS 是設定裡的第一台)"; docker stop broker1 >/dev/null; T1=$(now); sleep 20
echo "  停止後 20 秒,連送 8 組(c=憑證、b=Basic;碼/耗時):"; burst 8; mdscount $T1

echo "== [2] broker1 仍停著,重啟 REST Proxy(啟動時的 Kafka client 登入也要拿 token)"; docker restart restproxy >/dev/null; T2=$(now)
if wait_healthy restproxy; then echo "  restproxy 重啟後 healthy"; else echo "  restproxy 120 秒內沒有 healthy"; fi
sleep 10; burst 6; mdscount $T2
docker logs --since "$T2" restproxy 2>&1 | grep -iE 'ERROR|WARN.*(metadata|8091|token)|Connection refused|UnknownHost' | head -5 | cut -c1-200

echo "== [3] 啟動 broker1,停 broker2"; docker start broker1 >/dev/null; wait_healthy broker1; sleep 20; docker stop broker2 >/dev/null; T3=$(now); sleep 20
burst 8; mdscount $T3

echo "== [4] 全部恢復"; docker start broker2 >/dev/null; wait_healthy broker2; sleep 20; T4=$(now); burst 4; mdscount $T4
rbac_unbind cert bootstrap User:legacy-orders DeveloperWrite Topic orders. PREFIXED >/dev/null
docker rm -f $C >/dev/null 2>&1
