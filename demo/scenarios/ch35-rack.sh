#!/usr/bin/env bash
# ============================================================================
# ch35-rack.sh — 第 35 章:多機架——整個機架斷電時,資料還寫得進去嗎?
# ----------------------------------------------------------------------------
# 白話:前面停的是「一台」broker。機房歲修常常是「一整個機架」一起斷電。broker.rack 讓副本分散到不同機架,
#   但能不能撐過整個機架故障,取決於機架數:這一章用 2 個機架與 3 個機架各做一次,實測差在哪裡。
# 前置條件:叢集已啟動(scripts/up.sh)。
# 用法:
#   ./demo.sh 35                  經由講解控制台跑這一章(DEMO_PAUSE=0 不暫停)
#   ./scenarios/ch35-rack.sh      直接跑
# 會改動什麼:.env 加 rack 疊加檔與 RACK_B1~4;broker 依序重建三輪(2 個機架、3 個機架、還原);建立 topic rack2.t、rack3.t;
#   暫停並恢復 broker。結束時還原成不設機架的基線。整章約 25 分鐘。
# 怎麼判斷成功:每一步印「✔ 符合預期」,最後一行「第 35 章完成(失敗 0 項)」
# ============================================================================
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch35 "多機架:整個機架斷電時,資料還寫得進去嗎"
RS="$DEMO_ROOT/scripts/rack-setup.sh"; RL="$DEMO_ROOT/scripts/rack-lab.sh"

step rack-two "【2 個機架】broker1、2 在 rack-a,broker3、4 在 rack-b;依序重建 broker 讓 broker.rack 生效" \
  "scripts/rack-setup.sh two" \
  'bash "$RS" two 2>&1 | tail -6' 'rack: rack-b'

step rack-two-placement "【副本分布】新建 topic(副本 3):每個分區橫跨 2 個機架,所以一定有一個機架放 2 份" \
  "kafka-topics --create --topic rack2.t --partitions 6 --replication-factor 3;kafka-topics --describe" \
  'bash "$RL" placement rack2.t 2>&1' '判定:共 2 個機架'

step rack-two-down "【rack-b 斷電】放 2 份在 rack-b 的分區只剩 1 份 < min.insync.replicas 2:這些分區 acks=all 寫不進去" \
  "docker stop broker3 broker4;acks=all 寫 600 筆;docker start broker3 broker4" \
  'bash "$RL" rack-down rack2.t rack-b 2>&1' '撐不過整個機架故障'

step rack-three "【3 個機架】broker1、2 在 rack-a,broker3 在 rack-b,broker4 在 rack-c(官方建議各機架台數相同;這裡只為實證機架數的影響)" \
  "scripts/rack-setup.sh three" \
  'bash "$RS" three 2>&1 | tail -6' 'rack: rack-c'

step rack-three-placement "【副本分布】新建 topic:每個分區的 3 份副本各在一個機架" \
  "kafka-topics --create --topic rack3.t --partitions 6 --replication-factor 3;kafka-topics --describe" \
  'bash "$RL" placement rack3.t 2>&1' '判定:共 3 個機架'

step rack-three-down "【rack-a 斷電(2 台)】每個分區還有 2 份同步副本:全部照常寫入" \
  "docker stop broker1 broker2;acks=all 寫 600 筆;docker start broker1 broker2" \
  'bash "$RL" rack-down rack3.t rack-a 2>&1' '撐得過整個機架故障'

step rack-off "【還原】移除機架設定(客戶機架配置確定後再設);既有 topic 的副本位置不會自動重排,要用重新指派或 Self-Balancing" \
  "scripts/rack-setup.sh off" \
  'bash "$RS" off 2>&1 | tail -6; kc_del(){ "$DEMO_ROOT/scripts/k.sh" kafka-topics --bootstrap-server "$BOOT" --command-config /clients/token-bootstrap.properties --delete --if-exists --topic "$1" >/dev/null 2>&1; }; kc_del rack2.t; kc_del rack3.t; echo "已刪除 rack2.t、rack3.t"' '已移除'

ch_end
