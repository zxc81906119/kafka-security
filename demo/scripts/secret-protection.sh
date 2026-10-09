#!/usr/bin/env bash
# Confluent Secret Protection(官方功能):把 broker 設定檔裡的密碼加密,主金鑰放到 CyberArk(Conjur),broker 啟動時才取。
# 用法:
#   scripts/secret-protection.sh setup     產生主金鑰 → 存進 Conjur(kafka/broker/master-key)→ 加密 AD 查詢帳號的密碼 → 寫出 certs/security.properties
#   scripts/secret-protection.sh apply     以加密設定重建 broker2(docker-compose.cyberark.yml 覆蓋;啟動前向 Conjur 取主金鑰)
#   scripts/secret-protection.sh summon-setup   準備 CyberArk 官方工具 summon + summon-conjur(下載到 config/conjur/bin、校驗 SHA256)與 broker 的 /etc/conjur.identity
#   scripts/secret-protection.sh apply-summon   同 apply,但取主金鑰改用 summon(正式環境的 systemd ExecStart 一行:summon -p summon-conjur -f secrets.yml kafka-server-start …)
#   scripts/secret-protection.sh rotate-master   輪替主金鑰(新 passphrase → 重包資料金鑰 → 換檔 + 更新 Conjur → 重啟 broker2);舊的存在 broker/master-key-previous 以便退回
#   scripts/secret-protection.sh rotate-master-rollback   退回輪替前的檔與主金鑰
#   scripts/secret-protection.sh rotate-data     輪替資料金鑰(所有值重新加密;主金鑰不變 → Conjur 不用動)→ 換檔 → 重啟 broker2
#   scripts/secret-protection.sh mismatch-demo  故意讓「檔」與「主金鑰」不成對(換回輪替前的舊檔)重啟 broker2 → 起不來;再換回成對的檔 → 恢復
#   scripts/secret-protection.sh check           檢查 certs/security.properties 與 Conjur 的主金鑰是不是一對(解得開)
#   scripts/secret-protection.sh join-broker1  讓 broker1 也套用(與 broker2 共用同一把主金鑰、同一份檔)→ 之後輪替會「滾動」重啟兩台
#   scripts/secret-protection.sh revert    broker2 回到原本的明文設定
#   scripts/secret-protection.sh show      看 broker2 生效的設定裡那個值長什麼樣(佔位符,不是密碼)
# 主金鑰只存在 Conjur 與 broker 程序的環境變數,不寫入任何檔案。
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
D="$(pwd -W 2>/dev/null || pwd)"
CLI() { docker run --rm -v "$D/certs:/sec" "$@" --entrypoint confluent confluentinc/confluent-cli:latest; }
# --- 輪替用的小工具:管理員從 Conjur 取值(用管理員的 conjur-cli,不是 broker 的身分)---
adm_get() { docker exec conjur-cli conjur variable get -i "kafka/$1" | tr -d '\r\n'; }
spcli() { # spcli <主金鑰或空字串> <參數...>  在 certs 目錄上跑 confluent secret
  local mk="$1"; shift
  docker run --rm -v "$D/certs:/sec" -e CONFLUENT_SECURITY_MASTER_KEY="$mk" --entrypoint confluent confluentinc/confluent-cli:latest "$@"
}
# 檔與金鑰是不是一對:用金鑰解 certs 下指定的 secrets 檔(config 檔只放引用,不含明文)
can_decrypt() { # can_decrypt <secrets檔名> <主金鑰>
  local t tn out rc; t=$(mktemp -d "$D/certs/chk.XXXX"); tn=$(basename "$t")
  printf '%s\n' 'ldap.java.naming.security.credentials = ${securepass:/etc/kafka/secrets/security.properties:server.properties/ldap.java.naming.security.credentials}' 'config.providers = securepass' 'config.providers.securepass.class = io.confluent.kafka.security.config.provider.SecurePassConfigProvider' > "$t/server.properties"
  cp "certs/$1" "$t/s.properties"
  out=$(spcli "$2" secret file decrypt --config-file "/sec/$tn/server.properties" --local-secrets-file "/sec/$tn/s.properties" --output-file "/sec/$tn/o.properties" 2>&1); rc=$?
  if [ $rc -eq 0 ] && grep -q 'ldap-bind-pw' "$t/o.properties" 2>/dev/null; then rm -rf "$t"; return 0; fi
  echo "$out" | grep -iE 'error' | head -1 | sed 's/^/   /'; rm -rf "$t"; return 1
}
in_summon() { docker inspect -f '{{join .Config.Cmd " "}}' "$1" 2>/dev/null | grep -q summon; }
mds_port() { [ "$1" = broker1 ] && echo 8091 || echo 8092; }
restart_one() { # restart_one <broker>:重啟並等健康;起不來回傳 1(不自動清資料)
  docker restart "$1" >/dev/null 2>&1
  local st i; for i in $(seq 1 28); do sleep 5; st=$(docker ps -a --format '{{.Status}}' -f name=^$1$); case "$st" in *"(healthy)"*) return 0;; Exited*) return 1;; esac; done; return 1
}
restart_check() { # 滾動重啟:所有用 summon 的 broker 依序一台一台重啟,每台健康後才做下一台,並用 gary 經該台登入驗證
  local b code rc=0
  for b in broker1 broker2; do
    in_summon "$b" || continue
    if restart_one "$b"; then
      code=$(bash scripts/dcurl.sh -o /dev/null -u gary:gary-pw https://$b:$(mds_port $b)/security/1.0/authenticate | tail -1)
      echo "[secret-protection] 重啟 $b → 健康;gary 經 $b 登入 → $code"; [ "$code" = "[HTTP 200]" ] || rc=1
    else
      echo "[secret-protection] 重啟 $b → 起不來($(docker ps -a --format '{{.Status}}' -f name=^$b$))"; rc=1; break
    fi
  done
  return $rc
}
case "${1:-}" in
setup)
  [ -f config/conjur/keys/broker.key ] || { echo "先執行 scripts/conjur.sh up"; exit 1; }
  work=$(mktemp -d "$D/certs/sp.XXXX"); wn=$(basename "$work")
  PP=$(openssl rand -hex 16 2>/dev/null || date +%s%N)     # 此版 confluent CLI 的 --passphrase 只吃字面值(@檔案 會被當成字串,實測);正式環境在受控的管理主機上執行,避免被旁人從行程清單看到
  printf 'ldap.java.naming.security.credentials=ldap-bind-pw\n' > "$work/server.properties"     # 要加密的那一行(值 = AD 查詢帳號的密碼,demo 測試值)
  rm -f certs/security.properties
  MK=$(docker run --rm -v "$D/certs:/sec" --entrypoint confluent confluentinc/confluent-cli:latest secret master-key generate --local-secrets-file /sec/security.properties --passphrase "$PP" 2>&1 | grep -oE '[A-Za-z0-9+/=]{40,}' | tail -1)
  [ -n "$MK" ] || { echo "產生主金鑰失敗"; exit 1; }
  docker run --rm -v "$D/certs:/sec" -e CONFLUENT_SECURITY_MASTER_KEY="$MK" --entrypoint confluent confluentinc/confluent-cli:latest secret file encrypt \
    --config-file "/sec/$wn/server.properties" --local-secrets-file /sec/security.properties --remote-secrets-file /etc/kafka/secrets/security.properties \
    --config ldap.java.naming.security.credentials >/dev/null
  bash scripts/conjur.sh set broker/master-key "$MK" >/dev/null
  bash scripts/conjur.sh set broker/master-key-passphrase "$PP" >/dev/null
  unset MK PP; rm -rf "$work"
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
rotate-master)
  OLDPW=$(adm_get broker/master-key-passphrase); OLDMK=$(adm_get broker/master-key)
  NEWPW=$(openssl rand -hex 16 2>/dev/null || date +%s%N)
  cp certs/security.properties certs/security.properties.old
  cp certs/security.properties certs/security.properties.new
  # 輪替必須同時給「目前的 passphrase」與「新的 passphrase」;新主金鑰只會印一次
  NEWMK=$(spcli "$OLDMK" secret file rotate --local-secrets-file /sec/security.properties.new --master-key --passphrase "$OLDPW" --passphrase-new "$NEWPW" 2>&1 | grep -oE '[A-Za-z0-9+/=]{40,}' | tail -1) || true
  [ -n "$NEWMK" ] || { echo "輪替失敗(取不到新主金鑰)"; rm -f certs/security.properties.new; exit 1; }
  echo "[secret-protection] ① 新檔(security.properties.new)只有主金鑰那一層被重包,值的密文沒有變:"
  diff <(grep -v '^_metadata' certs/security.properties.old) <(grep -v '^_metadata' certs/security.properties.new) >/dev/null && echo "   資料金鑰以外的行(各個值的密文)完全相同"
  echo "[secret-protection] ② 檔與金鑰必須成對——交叉驗證:"
  can_decrypt security.properties.new "$NEWMK" && echo "   新檔 + 新主金鑰 → 解得開" || echo "   新檔 + 新主金鑰 → 解不開(異常)"
  can_decrypt security.properties.new "$OLDMK" && echo "   新檔 + 舊主金鑰 → 解得開(異常)" || echo "   新檔 + 舊主金鑰 → 解不開(預期)"
  can_decrypt security.properties.old "$NEWMK" && echo "   舊檔 + 新主金鑰 → 解得開(異常)" || echo "   舊檔 + 新主金鑰 → 解不開(預期)"
  echo "[secret-protection] ③ 切換:先保存舊主金鑰(退回用)→ 換檔 → 更新 Conjur 的主金鑰與 passphrase → 重啟 broker2"
  bash scripts/conjur.sh set broker/master-key-previous "$OLDMK" >/dev/null
  mv certs/security.properties.new certs/security.properties
  bash scripts/conjur.sh set broker/master-key "$NEWMK" >/dev/null
  bash scripts/conjur.sh set broker/master-key-passphrase "$NEWPW" >/dev/null
  unset OLDMK NEWMK OLDPW NEWPW
  restart_check && echo "判定:主金鑰已輪替——檔與新主金鑰成對,broker2 重啟後正常(值的密文沒變,只有資料金鑰被重包)"
  ;;
rotate-master-rollback)
  PREV=$(adm_get broker/master-key-previous)
  [ -f certs/security.properties.old ] && [ -n "$PREV" ] || { echo "沒有可退回的舊檔或舊主金鑰"; exit 1; }
  cp certs/security.properties.old certs/security.properties
  bash scripts/conjur.sh set broker/master-key "$PREV" >/dev/null; unset PREV
  echo "[secret-protection] 已退回輪替前的檔與主金鑰(passphrase 也要退回,見 RUNBOOK;此 demo 之後以 setup 重建)"
  restart_check
  ;;
rotate-data)
  PW=$(adm_get broker/master-key-passphrase); MK=$(adm_get broker/master-key)
  cp certs/security.properties certs/security.properties.before-data
  # 輪替資料金鑰只需要「目前的 passphrase」;主金鑰不變
  spcli "$MK" secret file rotate --local-secrets-file /sec/security.properties --data-key --passphrase "$PW" >/dev/null 2>&1 || { echo "輪替失敗"; exit 1; }
  echo "[secret-protection] 輪替資料金鑰:值的密文與資料金鑰都換了;主金鑰與 Conjur 不用動"
  { diff certs/security.properties.before-data certs/security.properties || true; } | grep -c '^>' | sed 's/^/   新檔變動行數:/'
  can_decrypt security.properties "$MK" && echo "   新檔 + 原本的主金鑰 → 解得開" || echo "   新檔 + 原本的主金鑰 → 解不開(異常)"
  unset MK PW
  restart_check && echo "判定:資料金鑰已輪替——所有值重新加密、主金鑰不變、Conjur 不用動,broker2 重啟後正常"
  ;;
mismatch-demo)
  [ -f certs/security.properties.old ] || { echo "先執行 rotate-master(才有輪替前的舊檔)"; exit 1; }
  cp certs/security.properties certs/security.properties.good
  cp certs/security.properties.old certs/security.properties
  echo "[secret-protection] 已把 certs/security.properties 換回「輪替前的舊檔」,但 Conjur 的主金鑰是新的 → 檔與金鑰不成對,重啟 broker2:"
  docker restart broker2 >/dev/null 2>&1
  st=""; for i in $(seq 1 12); do sleep 5; st=$(docker ps -a --format '{{.Status}}' -f name=^broker2$); case "$st" in Exited*) break;; esac; done
  echo "   broker2 狀態:$st"
  { docker logs broker2 2>&1 | grep -m1 'Failed to unwrap the data key' || true; } | sed 's/^\[[^]]*\] //' | cut -c1-150 | sed 's/^/   /'
  cp certs/security.properties.good certs/security.properties; rm -f certs/security.properties.good
  echo "[secret-protection] 換回成對的檔(新檔 + 新主金鑰)後重啟 broker2:"
  restart_check && case "$st" in Exited*) echo "判定:檔與主金鑰不成對時 broker2 起不來(Failed to unwrap the data key);換回成對的檔就恢復";; *) echo "判定:不符合(不成對時 broker2 狀態 $st)";; esac
  ;;
check)
  MK=$(adm_get broker/master-key)
  can_decrypt security.properties "$MK" && echo "[secret-protection] certs/security.properties 與 Conjur 的主金鑰是一對(解得開)" || { echo "[secret-protection] 檔與主金鑰不成對:broker 重啟會起不來"; exit 1; }
  ;;
join-broker1)   # broker1 也改用 summon + 加密設定(與 broker2 共用同一把主金鑰、同一份 security.properties)
  docker compose -f docker-compose.yml -f docker-compose.cyberark-summon.yml --profile cyberark up -d --wait --wait-timeout 240 broker1 >/dev/null || bash scripts/broker-heal.sh broker1 -f docker-compose.yml -f docker-compose.cyberark-summon.yml --profile cyberark
  code=$(bash scripts/dcurl.sh -o /dev/null -u gary:gary-pw https://broker1:8091/security/1.0/authenticate | tail -1)
  echo "[secret-protection] broker1 已用加密設定重啟(與 broker2 同一把主金鑰、同一份檔);gary 經 broker1 登入 → $code"
  [ "$code" = "[HTTP 200]" ] && echo "判定:broker1 與 broker2 共用同一把主金鑰、同一份 security.properties"
  ;;
revert)
  { docker compose up -d --wait --wait-timeout 240 broker1 broker2 >/dev/null || { bash scripts/broker-heal.sh broker1; bash scripts/broker-heal.sh broker2; }; } && echo "[secret-protection] broker1、broker2 已回到原本設定"
  ;;
show)
  echo "broker2 的 /etc/kafka/kafka.properties 裡 AD 查詢密碼那一行:"; docker exec broker2 grep '^ldap.java.naming.security.credentials' /etc/kafka/kafka.properties
  echo "broker2 的環境裡有沒有明文密碼:$(docker exec broker2 env | grep -c 'ldap-bind-pw' || true) 處"
  ;;
*) sed -n 2,11p "$0"; exit 1 ;;
esac
