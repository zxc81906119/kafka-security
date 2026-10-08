#!/usr/bin/env bash
# 模擬行內 CyberArk(Conjur OSS):建立、載入 policy、存取秘密。正式環境這些動作由 CyberArk 管理員在 PVWA / CLI 做。
# 用法:
#   scripts/conjur.sh up                       啟動(產生 data key、建立帳戶、載入 policy、產生各 host 的 API key)
#   scripts/conjur.sh load                     重新載入 policy(config/conjur/policy/kafka.yml)並補齊缺少的 API key
#   scripts/conjur.sh set <變數> <值>          管理員寫入秘密,例如 set svc-orders/password orders-secret-v1
#   scripts/conjur.sh set-cred <host> <帳號> <密碼>  把「帳號與密碼」一次寫進同一個變數(JSON),應用一次取得;輪替用這個
#   scripts/conjur.sh get-as <host> <變數>     以某個 host 的身分取秘密(REST:API key → token → 取值);成功印值,失敗印 [HTTP code]
#   scripts/conjur.sh probe-as <host> <變數>   同上,但永遠印出 HTTP 狀態與內容(示範用)
#   scripts/conjur.sh rotate-key <host>        重新產生某個 host 的 API key(存到 config/conjur/keys/<host>.key)
#   scripts/conjur.sh down                     停掉並清除 Conjur(資料一併清除)
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
ACC=demo                                   # Conjur 帳戶名稱
C=config/conjur
HOSTS="svc-orders legacy-orders rogue-app opmenu broker"   # 與 policy/kafka.yml 一致
D="$(pwd -W 2>/dev/null || pwd)"
dc() { docker compose --profile cyberark "$@"; }
cli() { docker exec -i conjur-cli conjur "$@"; }
# 以 host 身分呼叫 Conjur REST;API key 以唯讀掛載給容器(不放環境變數、不出現在行程清單),token 只存在容器記憶體,不落地
rest_as() { # rest_as <host> <變數> <mode: value|probe>
  local h="$1" v="$2" mode="$3" keyf="$C/keys/$1.key"
  [ -f "$keyf" ] || { echo "沒有 $h 的 API key($keyf);先執行 scripts/conjur.sh rotate-key $h" >&2; return 1; }
  docker run --rm --network cpsec_default -v "$D/certs/ca.pem:/ca.pem:ro" -v "$D/$keyf:/key:ro" -e ACC="$ACC" -e H="$h" -e V="$v" -e MODE="$mode" --entrypoint sh curlimages/curl:latest -c '
    auth=$(curl -s --cacert /ca.pem -o /tmp/t -w "%{http_code}" -X POST --data "$(cat /key)" "https://conjur/authn/$ACC/host%2Fkafka%2F$H/authenticate")
    if [ "$auth" != 200 ]; then [ "$MODE" = probe ] && echo "authenticate → [HTTP $auth]"; [ "$MODE" = value ] && echo "[HTTP $auth]"; exit 1; fi
    tok=$(base64 -w0 /tmp/t)
    code=$(curl -s --cacert /ca.pem -o /tmp/v -w "%{http_code}" -H "Authorization: Token token=\"$tok\"" "https://conjur/secrets/$ACC/variable/kafka%2F$(echo "$V" | sed "s#/#%2F#g")")
    if [ "$MODE" = probe ]; then echo "authenticate → [HTTP $auth];取 $V → [HTTP $code]"; [ "$code" = 200 ] && echo "(取得秘密,長度 $(wc -c < /tmp/v) 字元;內容不顯示)"; exit 0; fi
    if [ "$code" = 200 ]; then cat /tmp/v; else echo "[HTTP $code]"; exit 1; fi'
}

case "${1:-}" in
up)
  if [ ! -f "$C/conjur.env" ]; then
    key=$(docker run --rm cyberark/conjur:latest data-key generate | tr -d '\r\n')
    printf 'CONJUR_DATA_KEY=%s\n' "$key" > "$C/conjur.env"
    echo "[conjur] 產生 data key → $C/conjur.env"
  fi
  dc up -d --wait --wait-timeout 300 conjur-db conjur-server conjur conjur-cli
  if [ ! -f "$C/admin.key" ]; then
    docker exec conjur-server conjurctl account create "$ACC" > "$C/admin.out" 2>&1 || { cat "$C/admin.out"; exit 1; }
    grep -i 'API key for admin' "$C/admin.out" | awk '{print $NF}' | tr -d '\r' > "$C/admin.key"; rm -f "$C/admin.out"
    echo "[conjur] 帳戶 $ACC 已建立,admin API key → $C/admin.key"
  fi
  cli init oss -u https://conjur -a "$ACC" --ca-cert /etc/ssl/certs/demo-ca.pem --force --force-netrc >/dev/null 2>&1 \
    || { echo y | cli init oss -u https://conjur -a "$ACC" --self-signed --force --force-netrc >/dev/null; }
  cli login -i admin -p "$(cat "$C/admin.key")" >/dev/null
  "$0" load
  echo "[conjur] 完成:https://conjur(容器網路內);policy 已載入,host API key 在 $C/keys/"
  ;;
load)
  cli login -i admin -p "$(cat "$C/admin.key")" >/dev/null
  cli policy load -b root -f /policy/kafka.yml > "$C/policy.out"
  mkdir -p "$C/keys"
  for h in $HOSTS; do [ -f "$C/keys/$h.key" ] || "$0" rotate-key "$h"; done
  echo "[conjur] policy 已載入;host:$HOSTS"
  ;;
rotate-key)
  mkdir -p "$C/keys"
  cli host rotate-api-key -i "kafka/$2" | tr -d '\r\n' > "$C/keys/$2.key"
  echo "[conjur] $2 的 API key 已更新 → $C/keys/$2.key"
  ;;
set)   # 值用 stdin 傳(不出現在行程清單)
  printf '%s' "$3" | cli variable set -i "kafka/$2" -f - >/dev/null && echo "[conjur] 已寫入 kafka/$2"
  ;;
set-cred)   # set-cred <host> <帳號> <密碼>:一個變數放整組,寫入是單一操作(原子)
  printf '{"u":"%s","p":"%s"}' "$3" "$4" | cli variable set -i "kafka/$2/credential" -f - >/dev/null && echo "[conjur] 已寫入 kafka/$2/credential(帳號 $3)"
  ;;
get-as)   rest_as "$2" "$3" value ;;
probe-as) rest_as "$2" "$3" probe ;;
probe-bad)   # 用錯誤的 API key 冒充某個 host(示範認證失敗)
  mkdir -p "$C/keys"; printf 'wrong-api-key' > "$C/keys/_bad.key"
  docker run --rm --network cpsec_default -v "$D/certs/ca.pem:/ca.pem:ro" -e ACC="$ACC" -e H="$2" --entrypoint sh curlimages/curl:latest -c '
    code=$(curl -s --cacert /ca.pem -o /dev/null -w "%{http_code}" -X POST --data "wrong-api-key" "https://conjur/authn/$ACC/host%2Fkafka%2F$H/authenticate"); echo "authenticate(錯誤 API key)→ [HTTP $code]"'
  rm -f "$C/keys/_bad.key" ;;
down)
  dc rm -sfv conjur-cli conjur conjur-server conjur-db >/dev/null 2>&1 || true
  rm -f "$C/admin.key" "$C/policy.out"; rm -rf "$C/keys"
  echo "[conjur] 已清除(保留 $C/conjur.env)"
  ;;
*) sed -n 2,10p "$0"; exit 1 ;;
esac
