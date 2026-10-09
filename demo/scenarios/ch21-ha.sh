#!/usr/bin/env bash
# 第 21 章(進階):HA 叢集——3 台 controller、3 台 broker、副本 3、min.insync.replicas 2 的停機行為與滾動重啟
# 需要 HA 模式:scripts/ha.sh on(會清資料重建);做完用 scripts/ha.sh off 回到基礎環境。不在 `demo.sh all` 與 preflight 的基礎鏈內。
# 實測結果摘要(測試環境:副本 3、min.isr 2):
#   停 1 台 broker:寫入不中斷;停 2 台:acks=all 被擋,acks=1 看似成功但讀不到(高水位不前進);
#   停 1 台 controller:正常;停 2 台(失去多數):不能建 topic 與 describe,既有 topic 的讀寫仍可;
#   滾動重啟 3 broker + 3 controller(active 最後):背景寫入零失敗、零遺失。
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch21 "HA 叢集:3 controller、3 broker 的停機行為與滾動重啟"
HA="$DEMO_ROOT/scripts/ha-lab.sh"

step ha-quorum "【quorum】3 台 controller 都是 voter(投票成員),1 台是 leader;3 台 broker 是 observer。3 台可容忍 1 台故障(官方:正式環境至少 3 台、專用 controller)。這個測試環境用靜態 quorum(kraft.version 0)簡化;正式環境依官方建議用動態 quorum" \
  "kafka-metadata-quorum describe --status;kafka-features describe" \
  'bash "$HA" quorum 2>&1' '判定:3 個 controller 都是 voter'

step ha-topic "【副本 3】建立 RF=3、min.insync.replicas=2 的 topic,寫入 300 筆(acks=all)並比對筆數" \
  "kafka-topics --create --replication-factor 3 --config min.insync.replicas=2;kafka-producer-perf-test --producer-props acks=all" \
  'bash "$HA" topic 2>&1' '判定:副本 3、min.isr 2'

step ha-broker-down "【停 1 台 broker】剩 2 台:ISR 剩 2、仍滿足 min.isr 2,acks=all 寫入不中斷;URP(副本不足分區)大於 0 是要告警的訊號;恢復後補齊" \
  "docker stop broker3;kafka-topics --describe --under-replicated-partitions;寫入;docker start broker3" \
  'bash "$HA" broker-down 2>&1' '判定:停 1 台 broker 時寫入不中斷'

step ha-brokers-down "【停 2 台 broker】只剩 1 台:ISR 1 < min.isr 2。acks=all 被擋;acks=1 producer 回報成功,但 consumer 讀不到(高水位沒前進),恢復後才出現;consumer group 也加入不了" \
  "docker stop broker2 broker3;acks=all 與 acks=1 各寫 50 筆;比對 consumer 看得到的筆數" \
  'bash "$HA" brokers-down 2>&1' '判定:ISR 低於 min.isr 時'

step ha-ctrl-down "【停 1 台 controller】剩 2/3 仍有多數:建立 topic 與寫入都正常" \
  "docker stop controller3;kafka-topics --create;寫入;docker start controller3" \
  'bash "$HA" ctrl-down 2>&1' '判定:停 1 台 controller 仍有多數'

step ha-ctrls-down "【停 2 台 controller】失去多數:控制面(建 topic、describe、換 leader)停擺,但既有 topic 的讀寫(資料面)繼續;恢復多數後才恢復" \
  "docker stop controller2 controller3;kafka-topics --create(逾時);寫入與讀取既有 topic;docker start" \
  'bash "$HA" ctrls-down 2>&1' '判定:失去 controller 多數時'

step ha-rolling "【滾動重啟】背景持續寫入(acks=all、冪等、每秒 6 筆共 2400 筆),依序重啟 broker1 → broker2 → broker3 → 非 active controller → active controller;每台 broker 重啟後等 URP 回 0 才做下一台;比對送出筆數與 topic 實際筆數" \
  "docker restart <節點>(依序);kafka-producer-perf-test;kafka-get-offsets" \
  'bash "$HA" rolling 2>&1' '判定:滾動重啟 3 台 broker 與 3 台 controller 期間'

ch_end
