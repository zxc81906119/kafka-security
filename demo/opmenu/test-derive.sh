#!/usr/bin/env bash
# 設定推算的回歸測試(docker 後端,需要 demo 叢集在跑與 AD 帳號 gary)。
cd "$(dirname "$0")"
export MSYS_NO_PATHCONV=1
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then echo "  PASS  $1"; pass=$((pass+1)); else echo "  FAIL  $1(預期 [$3],實際 [$2])"; fail=$((fail+1)); fi; }
has() { if printf '%s' "$2" | grep -q -- "$3"; then echo "  PASS  $1"; pass=$((pass+1)); else echo "  FAIL  $1(找不到 [$3])"; fail=$((fail+1)); fi; }
run19() { env OPMENU_CONF="$PWD/$1" OPMENU_USER=gary OPMENU_PASS=gary-pw OPMENU_YES=1 timeout 120 ./opmenu.sh --run 19 </dev/null 2>&1; }
val() { printf '%s\n' "$1" | awk -v k="$2" '$1==k {print $2 "|" $3}'; }

echo "== 1 精簡設定檔(只填 bootstrap、broker 與輔助服務、controller)"
out=$(run19 test-minimal.conf)
ok "MDS_URL 由 bootstrap 推算" "$(val "$out" MDS_URL)" "derived|https://broker1:8091,https://broker2:8091"
real=$(docker run --rm --network cpsec_default -v "$(pwd -W 2>/dev/null || pwd)/../certs:/certs:ro" --entrypoint curl curlimages/curl:latest -s --cacert /certs/ca.pem https://broker1:8091/v1/metadata/id | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)
ok "cluster ID = MDS 回報的值" "$(val "$out" KAFKA_CLUSTER_ID)" "derived|$real"
ok "HOSTS = broker + 輔助服務 + controller" "$(val "$out" HOSTS)" "derived|broker1"   # 只比第一欄,完整清單下一行比
has "HOSTS 含全部主機" "$out" "broker1 broker2 restproxy control-center controller1"
ok "副本數降到 broker 數" "$(val "$out" REPLICATION)" "derived|2"
ok "BROKER_SERVICES 是 conf(不推算)" "$(val "$out" BROKER_SERVICES)" "conf|broker1"

echo "== 2 conf 有填的優先(demo 的 opmenu.conf 明確填了 MDS_URL)"
out=$(run19 opmenu.conf)
ok "MDS_URL 來源是 conf" "$(val "$out" MDS_URL)" "conf|https://broker1:8091"
ok "cluster ID 仍由推算補上" "$(val "$out" KAFKA_CLUSTER_ID)" "derived|$real"

echo "== 3 少了必填的 BROKER_SERVICES → 登入階段明確報錯"
cat > /tmp/opm-nobroker.conf <<'EOC'
OPMENU_BACKEND=docker
OPMENU_BOOTSTRAP='broker1:9094,broker2:9094'
OPMENU_ALLOW_ENV_OVERRIDE=1
EOC
cp /tmp/opm-nobroker.conf ./.nobroker.conf
out=$(env OPMENU_CONF="$PWD/.nobroker.conf" OPMENU_USER=gary OPMENU_PASS=gary-pw OPMENU_YES=1 timeout 120 ./opmenu.sh --run 19 </dev/null 2>&1); rm -f ./.nobroker.conf /tmp/opm-nobroker.conf
has "報錯指出要設定 OPMENU_BROKER_SERVICES" "$out" "OPMENU_BROKER_SERVICES"

echo "== 4 純本機推算(不連叢集,直接載入 defaults.sh)"
d() { OPMENU_HOME="$PWD" bash -c ". lib/defaults.sh; $1" 2>/dev/null; }
ok "憑證檔名跟著 CERT_DIR" "$(OPMENU_CERT_DIR=/x d 'echo $OPMENU_TRUSTSTORE $OPMENU_TRUSTSTORE_PASSWORD_FILE $OPMENU_CA_PEM')" "/x/truststore.p12 /x/truststore_creds /x/ca.pem"
ok "個別設定優先於 CERT_DIR" "$(OPMENU_CERT_DIR=/x OPMENU_CA_PEM=/y/ca.pem d 'echo $OPMENU_CA_PEM')" "/y/ca.pem"
ok "MDS 位址去重並用 MDS_PORT" "$(OPMENU_BOOTSTRAP='a:9094,b:9094,a:9094' OPMENU_MDS_PORT=8090 d 'echo $OPMENU_MDS_URL')" "https://a:8090,https://b:8090"
ok "MDS_URL 有填就不推算" "$(OPMENU_BOOTSTRAP='a:9094' OPMENU_MDS_URL=https://m:1 d 'echo $OPMENU_MDS_URL ${OP_SRC[OPMENU_MDS_URL]}')" "https://m:1 conf"

echo; echo "== 結果:PASS $pass / FAIL $fail"; [ "$fail" = 0 ]
