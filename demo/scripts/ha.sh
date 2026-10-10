#!/usr/bin/env bash
# ============================================================================
# ha.sh — 在「基礎環境」與「HA 環境」之間切換
# ----------------------------------------------------------------------------
# 白話:基礎環境是 1 台 controller + 2 台 broker(Lab 0 到 20 用);HA 環境是 3 台 controller + 3 台 broker、
#   副本 3(Lab 21 起用)。切換的方式是在 .env 加上或移除 COMPOSE_FILE,之後所有 `docker compose` 與腳本
#   都會自動帶上 docker-compose.ha.yml。
# 用法:
#   scripts/ha.sh on  [up.sh 參數]    清掉現有資料 → 以 HA 設定重建(例:scripts/ha.sh on --with-c3)
#   scripts/ha.sh off [up.sh 參數]    清掉現有資料 → 回到基礎環境重建
#   scripts/ha.sh status              顯示目前是哪一種模式
# 會改動什麼:`docker compose down -v`(清除所有資料,含 Conjur);改寫 .env 的 COMPOSE_FILE 兩行;
#   HA 模式會準備 JMX exporter(scripts/jmx-setup.sh)並產生 config/c3/jmx_scrape.yml。
# 注意:HA 模式不要同時開 cyberark / sr profile(記憶體不夠)。
# 怎麼判斷成功:最後印「[ha] 已切換為 ha」(或 base)。
# 常見失敗:卡在重建 → 看 scripts/up.sh 的輸出;Windows 要同時設 COMPOSE_PATH_SEPARATOR=,(本腳本已處理)。
# ============================================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
[ "${1:-}" = "--help" ] && { usage_from_header "$0"; exit 0; }
cd "$DEMO_DIR"

# 目前模式:.env 裡有指向 docker-compose.ha.yml 的 COMPOSE_FILE 就是 ha。
current_mode() {
  if grep -q '^COMPOSE_FILE=.*docker-compose.ha.yml' .env 2>/dev/null; then echo ha; else echo base; fi
}

# 清除所有 profile 的容器與資料(失敗也繼續,可能本來就沒有)。
remove_everything() {
  docker compose --profile c3 --profile restproxy --profile cyberark --profile sr --profile grafana --profile observability --profile connect down -v >/dev/null 2>&1 || true
}

# 改 .env:HA 模式加上 COMPOSE_FILE(兩個 compose 檔疊加);基礎模式移除。
set_compose_files() {
  sed -i '/^COMPOSE_PATH_SEPARATOR=/d;/^COMPOSE_FILE=/d' .env
  if [ "$1" = ha ]; then
    printf 'COMPOSE_PATH_SEPARATOR=,\nCOMPOSE_FILE=docker-compose.yml,docker-compose.ha.yml\n' >> .env
  fi
}

# Prometheus 抓 JMX exporter 的設定只在 HA 模式存在。
set_jmx_scrape_config() {
  if [ "$1" = ha ]; then cp config/c3/jmx-scrape.ha.tpl config/c3/jmx_scrape.yml; else rm -f config/c3/jmx_scrape.yml; fi
  rm -f config/c3/grafana_scrape.yml     # 重建後 Grafana 相關容器不在了,抓取設定要等 scripts/grafana.sh on 才產生(否則會有 up==0 的目標與告警)
}

case "${1:-status}" in
  status)
    echo "目前模式:$(current_mode)" ;;
  on|off)
    want=$([ "$1" = on ] && echo ha || echo base)
    echo "[ha] 目前 $(current_mode) → 切到 $want(會清除所有資料)"
    if [ "$want" = ha ]; then bash scripts/jmx-setup.sh; fi
    remove_everything
    set_compose_files "$want"
    set_jmx_scrape_config "$want"
    shift
    bash scripts/up.sh "$@"
    echo "[ha] 已切換為 $(current_mode)" ;;
  *)
    usage_from_header "$0"; exit 1 ;;
esac
