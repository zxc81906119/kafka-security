#!/usr/bin/env bash
# ============================================================================
# rack-setup.sh — 設定或移除 broker 的機架(第 35 章的前置)
# ----------------------------------------------------------------------------
# 白話:broker.rack 告訴 Kafka「這台 broker 在哪個機架」,建立 topic 時副本會盡量分散到不同機架,整個機架斷電時才不會一次失去
#   同一個分區的多份副本。這支腳本把 docker-compose.rack.yml 加進 .env 的 COMPOSE_FILE,依序重建 broker(一次一台)。
# 前置條件:叢集已啟動(scripts/up.sh)。
# 用法:
#   scripts/rack-setup.sh two       2 個機架:broker1、2 = rack-a;broker3、4 = rack-b
#   scripts/rack-setup.sh three     3 個機架:broker1、2 = rack-a;broker3 = rack-b;broker4 = rack-c
#   scripts/rack-setup.sh off       移除機架設定(回到基線),依序重建 broker
#   scripts/rack-setup.sh status    每台 broker 目前的機架
# 會改動什麼:.env 的 COMPOSE_FILE 與 RACK_B1~RACK_B4;broker1~4 依序重建(資料保留)。
# 怎麼判斷成功:最後印 [rack] 完成,status 列出每台的機架。
# ============================================================================
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/kafka.sh"
[ "${1:-}" = "--help" ] && { usage_from_header "$0"; exit 0; }
cd "$DEMO_DIR" || exit 1

# set_env <名稱> <值>:寫入 .env(沒有就新增)。
set_env() { sed -i "/^$1=/d" .env; printf '%s=%s\n' "$1" "$2" >> .env; }

# 把 rack 檔加進 / 移出 COMPOSE_FILE(共用函式,可與第 32 章的 tier 檔並存)。
add_rack_file() { compose_file_add docker-compose.rack.yml; }
remove_rack_file() { compose_file_remove docker-compose.rack.yml; sed -i '/^RACK_B[1-4]=/d' .env; }

# 依序重建 broker1~4(一次一台,等 healthy 與 URP 歸零才做下一台)。
roll_brokers() {
  local n
  for n in broker1 broker2 broker3 broker4; do
    say "重建 $n"
    docker compose up -d --no-deps --force-recreate "$n" >/dev/null 2>&1
    wait_healthy "$n" >/dev/null || die "$n 重建後沒有 healthy:docker logs $n"
    wait_until "副本補齊(沒有副本不足的分區)" 300 no_urp >/dev/null || note "$n:等待副本補齊逾時,繼續"
    note "$n 已 healthy(機架 $(docker exec "$n" bash -c 'grep -h "^broker.rack" /etc/kafka/kafka.properties 2>/dev/null' | cut -d= -f2))"
  done
}

# 給 wait_until 用:沒有副本不足的分區。
no_urp() { [ -z "$(kafka_topics --describe --under-replicated-partitions 2>/dev/null | grep -v '^$')" ]; }

# 每台 broker 的機架(從 broker 的 API 回應:id: 11 rack: rack-a)。
rack_status() {
  "$DEMO_DIR/scripts/k.sh" kafka-broker-api-versions --bootstrap-server "$KAFKA_BOOTSTRAP" --command-config "$KAFKA_ADMIN_CONFIG" 2>/dev/null \
    | grep -oE 'id: [0-9]+ rack: [^)]*' | sort -u
}

case "${1:-status}" in
  two|three)
    if [ "$1" = two ]; then r=(rack-a rack-a rack-b rack-b); else r=(rack-a rack-a rack-b rack-c); fi
    say "設定機架:broker1=${r[0]} broker2=${r[1]} broker3=${r[2]} broker4=${r[3]}"
    add_rack_file
    set_env RACK_B1 "${r[0]}"; set_env RACK_B2 "${r[1]}"; set_env RACK_B3 "${r[2]}"; set_env RACK_B4 "${r[3]}"
    roll_brokers
    note "[rack] 完成:"; rack_status ;;
  off)
    say "移除機架設定,依序重建 broker"
    remove_rack_file
    roll_brokers
    note "[rack] 已移除:"; rack_status ;;
  status) rack_status ;;
  *) usage_from_header "$0"; exit 1 ;;
esac
