#!/usr/bin/env bash
# 切換環境模式:基礎(1 controller + 2 broker)↔ HA(3 controller + 3 broker,副本 3,第 21 章起使用)。
#   scripts/ha.sh on  [up.sh 參數]    清掉現有資料 → 以 HA 設定重建(例:scripts/ha.sh on --with-c3)
#   scripts/ha.sh off [up.sh 參數]    清掉現有資料 → 回到基礎環境重建
#   scripts/ha.sh status              顯示目前是哪一種模式
# 做法:在 .env 加或移除 COMPOSE_FILE(讓所有 `docker compose` 與腳本自動帶上 docker-compose.ha.yml)。
# 注意:切換會 down -v 清除所有資料(含 Conjur);HA 模式不要同時開 cyberark / sr profile(記憶體)。
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
mode() { grep -q '^COMPOSE_FILE=.*docker-compose.ha.yml' .env 2>/dev/null && echo ha || echo base; }
case "${1:-status}" in
  status) echo "目前模式:$(mode)";;
  on|off)
    want=$([ "$1" = on ] && echo ha || echo base)
    echo "[ha] 目前 $(mode) → 切到 $want(會清除所有資料)"
    docker compose --profile c3 --profile restproxy --profile cyberark --profile sr down -v >/dev/null 2>&1 || true
    sed -i '/^COMPOSE_PATH_SEPARATOR=/d;/^COMPOSE_FILE=/d' .env
    if [ "$want" = ha ]; then printf 'COMPOSE_PATH_SEPARATOR=,\nCOMPOSE_FILE=docker-compose.yml,docker-compose.ha.yml\n' >> .env; fi
    shift; bash scripts/up.sh "$@"
    echo "[ha] 已切換為 $(mode)";;
  *) sed -n 2,8p "$0"; exit 1;;
esac
