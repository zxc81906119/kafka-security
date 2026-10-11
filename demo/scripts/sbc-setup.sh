#!/usr/bin/env bash
# ============================================================================
# sbc-setup.sh — 啟用或關閉 Self-Balancing(第 31 章的前置)
# ----------------------------------------------------------------------------
# 白話:Self-Balancing 是 Confluent 內建的「自動搬分區」功能:新 broker 加進來會自動分到資料、
#   broker 掛太久會自動把它的資料補到別台、負載不均也能自動調。
#   KRaft 下它跑在 active controller 上,所以 confluent.balancer.enable 要在『每台 controller 與每台 broker』設定;
#   只用 kafka-configs 動態開 broker 不夠(實測:狀態仍是 DISABLED)。這支腳本依序重建 controller、broker 讓設定生效。
# 前置條件:叢集已啟動(scripts/ha.sh on --with-c3)
# 用法:
#   scripts/sbc-setup.sh on       .env 設 SBC_ENABLE=true,controller 與 broker 依序重建(一次一台,等 healthy)
#   scripts/sbc-setup.sh off      還原 SBC_ENABLE=false,同樣依序重建;並移除第 5 台 broker(若存在)
#   scripts/sbc-setup.sh status   顯示 .env 設定與 balancer 狀態
# 會改動什麼:改 .env 的 SBC_ENABLE;重建 controller1-3、broker1-4(資料在匿名 volume,重建後保留);
#   off 會停掉並移除 broker5。
# 怎麼判斷成功:最後印 [sbc] 完成,且 balancer 狀態不再是 DISABLED。
# 常見失敗:重建後 broker 不 healthy → docker logs <名稱>;狀態一直是 DISABLED → 確認 docker exec controller1 env | grep BALANCER_ENABLE
# ============================================================================
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/kafka.sh"
[ "${1:-}" = "--help" ] && { usage_from_header "$0"; exit 0; }
cd "$DEMO_DIR" || exit 1
need_ha_mode

# 寫入 .env 的 SBC_ENABLE(沒有就新增)。
set_sbc_env() {
  sed -i '/^SBC_ENABLE=/d' .env
  printf 'SBC_ENABLE=%s\n' "$1" >> .env
}

# 依序重建 controller 與 broker(一次一台,等 healthy 才做下一台),讓新的 .env 生效。
roll_all() {
  local n list="controller1 controller2 controller3 broker1 broker2 broker3 broker4"
  # 第 5 台在跑就一起重建:設定要全部一致,否則 balancer 的指標視窗會不一致(實測:之後偵測器反覆報錯、移除 broker 失敗)
  docker ps --format '{{.Names}}' | grep -qx broker5 && list="$list broker5"
  for n in $list; do
    say "重建 $n(讀新的 SBC_ENABLE)"
    docker compose up -d --no-deps --force-recreate "$n" >/dev/null 2>&1
    wait_healthy "$n" >/dev/null || die "$n 重建後沒有 healthy:docker logs $n"
    note "$n 已 healthy"
  done
}

# balancer 狀態(一行):例如「Balancer status: ENABLED」。
balancer_status() {
  "$DEMO_DIR/scripts/k.sh" kafka-rebalance-cluster --bootstrap-server "$KAFKA_BOOTSTRAP" --command-config "$KAFKA_ADMIN_CONFIG" --status 2>&1 \
    | grep -E 'Balancer status' | head -1
}

# 給 wait_until 用:balancer 狀態不是 DISABLED(也不是空的)。
balancer_started() { local s; s=$(balancer_status); [ -n "$s" ] && ! echo "$s" | grep -q DISABLED; }

case "${1:-status}" in
  on)
    say "在 .env 設 SBC_ENABLE=true,依序重建 controller 與 broker"
    set_sbc_env true
    roll_all
    wait_until "balancer 啟動(狀態不是 DISABLED)" 180 balancer_started || die "balancer 沒有啟動:docker logs controller1 | grep -i balancer"
    note "[sbc] 完成:$(balancer_status)" ;;
  off)
    say "停掉第 5 台 broker(若有),SBC_ENABLE 還原為 false,依序重建"
    docker compose --profile sbc stop broker5 >/dev/null 2>&1; docker compose --profile sbc rm -f broker5 >/dev/null 2>&1
    # 容器移除不等於離開叢集:node 15 的註冊若還在,之後新建的 topic 可能把副本放上去(實測:broker5 啟動失敗後,新 topic 有副本落在 15)
    "$DEMO_DIR/scripts/k.sh" kafka-cluster unregister --bootstrap-server "$KAFKA_BOOTSTRAP" --command-config "$KAFKA_ADMIN_CONFIG" --id 15 >/dev/null 2>&1 || true
    set_sbc_env false
    roll_all
    note "[sbc] 已關閉" ;;
  status)
    echo ".env:$(grep '^SBC_ENABLE=' .env 2>/dev/null || echo 'SBC_ENABLE 未設定(預設 false)')"
    echo "balancer:$(balancer_status)" ;;
  *) usage_from_header "$0"; exit 1 ;;
esac
