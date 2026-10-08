#!/usr/bin/env bash
# Confluent Secret Protection(官方功能):把 broker 設定檔裡的密碼加密,主金鑰放到 CyberArk(Conjur),broker 啟動時才取。
# 用法:
#   scripts/secret-protection.sh setup     產生主金鑰 → 存進 Conjur(kafka/broker/master-key)→ 加密 AD 查詢帳號的密碼 → 寫出 certs/security.properties
#   scripts/secret-protection.sh apply     以加密設定重建 broker2(docker-compose.cyberark.yml 覆蓋;啟動前向 Conjur 取主金鑰)
#   scripts/secret-protection.sh summon-setup   準備 CyberArk 官方工具 summon + summon-conjur(下載到 config/conjur/bin、校驗 SHA256)與 broker 的 /etc/conjur.identity
#   scripts/secret-protection.sh apply-summon   同 apply,但取主金鑰改用 summon(正式環境的 systemd ExecStart 一行:summon -p summon-conjur -f secrets.yml kafka-server-start …)
#   scripts/secret-protection.sh revert    broker2 回到原本的明文設定
#   scripts/secret-protection.sh show      看 broker2 生效的設定裡那個值長什麼樣(佔位符,不是密碼)
# 主金鑰只存在 Conjur 與 broker 程序的環境變數,不寫入任何檔案。
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
D="$(pwd -W 2>/dev/null || pwd)"
CLI() { docker run --rm -v "$D/certs:/sec" "$@" --entrypoint confluent confluentinc/confluent-cli:latest; }
case "${1:-}" in
setup)
  [ -f config/conjur/keys/broker.key ] || { echo "先執行 scripts/conjur.sh up"; exit 1; }
  work=$(mktemp -d "$D/certs/sp.XXXX"); wn=$(basename "$work")
  printf '%s\n' "$(openssl rand -hex 16 2>/dev/null || date +%s%N)" > "$work/passphrase.txt"
  printf 'ldap.java.naming.security.credentials=ldap-bind-pw\n' > "$work/server.properties"     # 要加密的那一行(值 = AD 查詢帳號的密碼,demo 測試值)
  rm -f certs/security.properties
  MK=$(docker run --rm -v "$D/certs:/sec" --entrypoint confluent confluentinc/confluent-cli:latest secret master-key generate --local-secrets-file /sec/security.properties --passphrase "@/sec/$wn/passphrase.txt" 2>&1 | grep -oE '[A-Za-z0-9+/=]{40,}' | tail -1)
  [ -n "$MK" ] || { echo "產生主金鑰失敗"; exit 1; }
  docker run --rm -v "$D/certs:/sec" -e CONFLUENT_SECURITY_MASTER_KEY="$MK" --entrypoint confluent confluentinc/confluent-cli:latest secret file encrypt \
    --config-file "/sec/$wn/server.properties" --local-secrets-file /sec/security.properties --remote-secrets-file /etc/kafka/secrets/security.properties \
    --config ldap.java.naming.security.credentials >/dev/null
  bash scripts/conjur.sh set broker/master-key "$MK" >/dev/null
  unset MK; rm -rf "$work"
  echo "[secret-protection] 主金鑰已存入 Conjur(kafka/broker/master-key),不在任何檔案裡"
  echo "[secret-protection] certs/security.properties(加密後的密碼):"; grep '^server.properties' certs/security.properties | cut -c1-110
  ;;
apply)
  docker compose -f docker-compose.yml -f docker-compose.cyberark.yml --profile cyberark up -d --wait --wait-timeout 240 broker2 >/dev/null || bash scripts/broker-heal.sh broker2 -f docker-compose.yml -f docker-compose.cyberark.yml --profile cyberark
  echo "[secret-protection] broker2 已用加密設定重啟;啟動紀錄:"; docker logs broker2 2>&1 | grep -m1 'secret-protection'
  ;;
summon-setup)   # CyberArk 官方工具 summon + summon-conjur:下載(校驗 SHA256)到 config/conjur/bin,並產生 broker 的 /etc/conjur.identity
  B=config/conjur/bin; mkdir -p "$B" config/conjur/identity-broker
  dl() { # dl <repo> <tag> <檔名> <解出的執行檔>
    local repo="$1" tag="$2" f="$3" bin="$4" base="https://github.com/cyberark/$1/releases/download/$2" want have
    [ -f "$B/$bin" ] && return 0
    echo "[summon] 下載 $repo $tag($f)"
    curl -sSL --retry 3 -o "$B/$f" "$base/$f"
    want=$(curl -sSL "$base/SHA256SUMS.txt" | grep " $f\$" | awk '{print $1}'); have=$(sha256sum "$B/$f" | awk '{print $1}')
    [ -n "$want" ] && [ "$want" = "$have" ] || { echo "SHA256 不符或取不到校驗值:$f"; rm -f "$B/$f"; exit 1; }
    tar xzf "$B/$f" -C "$B" "$bin" && rm -f "$B/$f"
  }
  dl summon v0.13.1 summon-linux-amd64.tar.gz summon
  dl summon-conjur v0.9.3 summon-conjur-linux-amd64.tar.gz summon-conjur
  [ -f config/conjur/keys/broker.key ] || { echo "先執行 scripts/conjur.sh up"; exit 1; }
  printf 'machine https://conjur/authn login host/kafka/broker password %s\n' "$(cat config/conjur/keys/broker.key)" > config/conjur/identity-broker/conjur.identity   # netrc 格式(一行或三行皆可);不進版本庫
  echo "[summon] 就緒:$B/summon、$B/summon-conjur;broker 身分 → config/conjur/identity-broker/conjur.identity"
  ;;
apply-summon)   # 同 apply,但主金鑰改由 summon 向 Conjur 取(docker-compose.cyberark-summon.yml)
  docker compose -f docker-compose.yml -f docker-compose.cyberark-summon.yml --profile cyberark up -d --wait --wait-timeout 240 broker2 >/dev/null || bash scripts/broker-heal.sh broker2 -f docker-compose.yml -f docker-compose.cyberark-summon.yml --profile cyberark
  echo "[secret-protection] broker2 已用加密設定重啟(主金鑰由 summon 向 Conjur 取);broker2 的啟動指令:"; docker inspect broker2 --format '{{join .Config.Cmd " "}}'
  ;;
revert)
  { docker compose up -d --wait --wait-timeout 240 broker2 >/dev/null || bash scripts/broker-heal.sh broker2; } && echo "[secret-protection] broker2 已回到原本設定"
  ;;
show)
  echo "broker2 的 /etc/kafka/kafka.properties 裡 AD 查詢密碼那一行:"; docker exec broker2 grep '^ldap.java.naming.security.credentials' /etc/kafka/kafka.properties
  echo "broker2 的環境裡有沒有明文密碼:$(docker exec broker2 env | grep -c 'ldap-bind-pw' || true) 處"
  ;;
*) sed -n 2,11p "$0"; exit 1 ;;
esac
