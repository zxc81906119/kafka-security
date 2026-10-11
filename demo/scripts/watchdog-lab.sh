#!/usr/bin/env bash
# ============================================================================
# watchdog-lab.sh — 第 34 章的實驗:監控本身壞掉時,看門狗多久發現
# ----------------------------------------------------------------------------
# 白話:三種「告警系統自己壞掉」的情況,一般告警都送不出去;看門狗靠「心跳停了」發現:
#   stop-prom   停 Prometheus:Alertmanager 手上的 Watchdog 要等過期才停止重送(約 4 分鐘),再加看門狗逾時 → 量測發現時間
#   stop-am     停 Alertmanager:心跳立刻停 → 約逾時時間內發現
#   misconfig   兩者都健康,但送心跳的密碼設錯(模擬設定改壞、憑證過期、防火牆):HA 察覺不到,看門狗發現
# 前置條件:scripts/watchdog-setup.sh on,且 status 是 OK。
# 用法:
#   scripts/watchdog-lab.sh baseline | stop-prom | stop-am | misconfig
# 會改動什麼:暫停並恢復 prometheus / alertmanager 容器;misconfig 會暫時改 config/c3/watchdog-am.pw,結束時改回。
# 怎麼判斷成功:各子命令以「判定:…」結尾,含量測到的秒數。
# ============================================================================
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
[ "${1:-}" = "--help" ] && { usage_from_header "$0"; exit 0; }
cd "$DEMO_DIR" || exit 1
export MSYS_NO_PATHCONV=1
need_container watchdog "先執行:scripts/watchdog-setup.sh on"

WD_USER="$(cat config/watchdog/secrets/user 2>/dev/null)"
PW_FILE=config/c3/watchdog-am.pw

# wd_status:看門狗狀態 JSON。wd_state:只取 state 欄位。
wd_status() {
  docker run --rm --network cpsec_default -v "$(pwd -W 2>/dev/null || pwd)/certs:/c:ro" curlimages/curl:latest -s --cacert /c/ca.pem \
    -u "$WD_USER" https://watchdog:9443/status
}
wd_state() { wd_status | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{try{console.log(JSON.parse(s).state)}catch{console.log('?')}})"; }
wd_last_events() { wd_status | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{try{JSON.parse(s).events.slice(-3).forEach(e=>console.log('   '+e))}catch{}})"; }

# wait_state <狀態> <最多秒數>:等看門狗變成指定狀態,印出等了幾秒;逾時回傳 1。
wait_state() {
  local want="$1" max="$2" t0; t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt "$max" ]; do
    [ "$(wd_state)" = "$want" ] && { echo $(( $(date +%s) - t0 )); return 0; }
    sleep 10
  done
  return 1
}

case "${1:-}" in
  baseline)
    say "正常狀態:Alertmanager 每 60 秒送一次 Watchdog 心跳,看門狗狀態 OK"
    wd_status; echo
    [ "$(wd_state)" = OK ] && verdict "看門狗狀態 OK(心跳正常)" ;;
  stop-prom)
    say "停 Prometheus:沒有人算規則,也就沒有任何告警(包含 Watchdog)"
    docker stop prometheus >/dev/null; echo "已停止 prometheus($(date +%T))"
    if secs=$(wait_state FAILED 900); then
      echo "停 Prometheus 後 $secs 秒,看門狗判定失效:"; wd_last_events
      docker start prometheus >/dev/null; wait_healthy prometheus >/dev/null
      rec=$(wait_state OK 300) || rec="?"
      echo "恢復 Prometheus 後 $rec 秒,心跳恢復"
      verdict "停 Prometheus 後 $secs 秒看門狗判定監控鏈路失效(Alertmanager 手上的 Watchdog 要等過期才停止重送,再加 180 秒逾時);恢復後 $rec 秒回到 OK"
    else
      docker start prometheus >/dev/null; echo "判定:不符合(900 秒內看門狗沒有判定失效)"
    fi ;;
  stop-am)
    say "停 Alertmanager:告警算得出來,但送不出去"
    docker stop alertmanager >/dev/null; echo "已停止 alertmanager($(date +%T))"
    if secs=$(wait_state FAILED 600); then
      echo "停 Alertmanager 後 $secs 秒,看門狗判定失效:"; wd_last_events
      docker start alertmanager >/dev/null; wait_healthy alertmanager >/dev/null
      rec=$(wait_state OK 300) || rec="?"
      echo "恢復 Alertmanager 後 $rec 秒,心跳恢復"
      verdict "停 Alertmanager 後 $secs 秒看門狗判定監控鏈路失效;恢復後 $rec 秒回到 OK"
    else
      docker start alertmanager >/dev/null; echo "判定:不符合(600 秒內看門狗沒有判定失效)"
    fi ;;
  misconfig)
    say "Prometheus 與 Alertmanager 都健康,但送心跳的密碼設錯(模擬設定改壞、密碼或憑證過期、防火牆)"
    cp "$PW_FILE" "$PW_FILE.good"; printf 'wrong-password' > "$PW_FILE"
    echo "Prometheus:$(docker inspect -f '{{.State.Health.Status}}' prometheus);Alertmanager:$(docker inspect -f '{{.State.Health.Status}}' alertmanager)(兩者都健康,HA 不會切換)"
    if secs=$(wait_state FAILED 600); then
      echo "密碼設錯後 $secs 秒,看門狗判定失效:"; wd_last_events
      echo "Alertmanager 日誌(送 webhook 失敗):"; docker logs alertmanager --since 5m 2>&1 | grep -iE "watchdog.*(401|unauthorized|error)" | tail -1 | cut -c1-180 | sed 's/^/   /'
      mv -f "$PW_FILE.good" "$PW_FILE"
      rec=$(wait_state OK 300) || rec="?"
      echo "改回正確密碼後 $rec 秒,心跳恢復"
      verdict "元件都健康、只是設定錯時,看門狗 $secs 秒後判定監控鏈路失效(HA 察覺不到這類問題);改回後 $rec 秒回到 OK"
    else
      mv -f "$PW_FILE.good" "$PW_FILE"; echo "判定:不符合(600 秒內看門狗沒有判定失效)"
    fi ;;
  *) usage_from_header "$0"; exit 1 ;;
esac
