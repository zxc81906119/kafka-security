#!/usr/bin/env bash
# ============================================================================
# watchdog-setup.sh — 啟用或關閉第 34 章的看門狗(監控本身失效時也要有人知道)
# ----------------------------------------------------------------------------
# 白話:Prometheus、Alertmanager 各只有一台;它們自己壞掉時,不會有任何告警送出。看門狗的做法:
#   ① Prometheus 加一條永遠在觸發的告警 Watchdog(config/c3/watchdog_rules.yml)
#   ② Alertmanager 把 Watchdog 走獨立路由,每 60 秒送一次 webhook(HTTPS + Basic)給外部看門狗
#   ③ 外部看門狗(watchdog 容器,代表行內既有的企業監控平台)超過 180 秒沒收到,就判定「監控鏈路失效」
# 前置條件:叢集已啟動(scripts/up.sh),Prometheus 與 Alertmanager 在跑。
# 用法:
#   scripts/watchdog-setup.sh on       備妥並啟用(可重複執行;第 30 章換過郵件版設定後也要再執行一次)
#   scripts/watchdog-setup.sh off      移除路由與規則、停掉看門狗
#   scripts/watchdog-setup.sh status   顯示看門狗狀態(JSON)
# 會改動什麼:config/watchdog/secrets/(隨機密碼,不進版本庫);config/c3/prometheus-generated.yml 的 rule_files 加一行;
#   config/c3/alertmanager-generated.yml 加入以 # >>> watchdog / # <<< watchdog 標記的路由與 receiver;重啟 prometheus、alertmanager;
#   啟動 watchdog 容器。
# 怎麼判斷成功:最後印 [watchdog] 完成,status 的 state 變成 OK(第一次心跳約 1 分鐘內)。
# ============================================================================
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
[ "${1:-}" = "--help" ] && { usage_from_header "$0"; exit 0; }
cd "$DEMO_DIR" || exit 1
export MSYS_NO_PATHCONV=1

SEC=config/watchdog/secrets
PROM_CONF=config/c3/prometheus-generated.yml
AM_CONF=config/c3/alertmanager-generated.yml

# Alertmanager 的 Watchdog 路由與 receiver(以標記包住,方便移除;郵件版與基本版都適用)
patch_am() {
  node - "$AM_CONF" <<'EOF'
const fs = require('fs'); const f = process.argv[2]; let s = fs.readFileSync(f, 'utf8');
s = s.replace(/[ \t]*# >>> watchdog[\s\S]*?# <<< watchdog\n/g, '');                 // 先移除舊的(可重複執行)
if (process.env.MODE === 'off') { s = s.replace(/routes:\n(?!\s+-)/, 'routes: []\n'); fs.writeFileSync(f, s); process.exit(0); }
const route = [
  '    # >>> watchdog(第 34 章:心跳路由放第一條,不落到其他 receiver)',
  '    - receiver: watchdog',
  '      matchers:',
  '        - alertname="Watchdog"',
  '      group_wait: 0s',
  '      group_interval: 1m',
  '      repeat_interval: 1m',
  '    # <<< watchdog', ''].join('\n');
const ind = ((s.match(/\nreceivers:\n([ \t]*)- /) || [])[1]) || '';      // 依原檔 receivers 清單的縮排(基本版 0 格、郵件版 2 格)
const recv = [
  '# >>> watchdog(外部看門狗;HTTPS + Basic,密碼放檔案)',
  '- name: watchdog',
  '  webhook_configs:',
  '    - url: https://watchdog:9443/heartbeat',
  '      send_resolved: false',
  '      http_config:',
  '        basic_auth:',
  '          username: alertmanager',
  '          password_file: /mnt/config/watchdog-am.pw',
  '        tls_config:',
  '          ca_file: /etc/tls/ca.pem',
  '# <<< watchdog'].map(l => ind + l).join('\n') + '\n';
if (/routes: \[\]/.test(s)) s = s.replace(/routes: \[\]\n/, 'routes:\n' + route);
else s = s.replace(/(\n  routes:\n)/, (m) => m + route);
s = s.replace(/(\nreceivers:\n)/, (m) => m + recv);
fs.writeFileSync(f, s);
EOF
}

case "${1:-status}" in
  on)
    say "備妥看門狗的帳密(Alertmanager 用來送心跳;隨機產生,不進版本庫)"
    mkdir -p "$SEC"
    [ -s "$SEC/am-password" ] || head -c 18 /dev/urandom | base64 | tr -d '\n=+/' > "$SEC/am-password"
    printf 'alertmanager:%s\n' "$(cat "$SEC/am-password")" > "$SEC/user"
    cp "$SEC/am-password" config/c3/watchdog-am.pw
    chmod 644 "$SEC"/* config/c3/watchdog-am.pw
    say "Prometheus 載入 Watchdog 規則;Alertmanager 加入心跳路由"
    grep -q "watchdog_rules.yml" "$PROM_CONF" || sed -i "/^rule_files:/a\\  # 第 34 章:看門狗(永遠在觸發的心跳)\n  - 'watchdog_rules.yml'" "$PROM_CONF"
    patch_am
    docker compose --profile watchdog up -d --wait --wait-timeout 120 watchdog >/dev/null 2>&1 || die "watchdog 沒有起來:docker logs watchdog"
    docker restart prometheus alertmanager >/dev/null
    wait_healthy prometheus alertmanager >/dev/null || die "prometheus / alertmanager 重啟後沒有 healthy"
    note "[watchdog] 完成:第一次心跳約 1 分鐘內送到;scripts/watchdog-setup.sh status 看狀態" ;;
  off)
    say "移除 Watchdog 路由與規則,停掉看門狗"
    MODE=off patch_am
    sed -i "/# 第 34 章:看門狗(永遠在觸發的心跳)/d;/'watchdog_rules.yml'/d" "$PROM_CONF"
    docker restart prometheus alertmanager >/dev/null; wait_healthy prometheus alertmanager >/dev/null
    docker compose --profile watchdog rm -sf watchdog >/dev/null 2>&1
    rm -f config/c3/watchdog-am.pw
    note "[watchdog] 已關閉" ;;
  status)
    docker run --rm --network cpsec_default -v "$(pwd -W 2>/dev/null || pwd)/certs:/c:ro" curlimages/curl:latest -s --cacert /c/ca.pem \
      -u "$(cat "$SEC/user" 2>/dev/null)" https://watchdog:9443/status ;;
  *) usage_from_header "$0"; exit 1 ;;
esac
