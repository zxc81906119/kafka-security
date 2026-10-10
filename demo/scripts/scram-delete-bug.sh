#!/usr/bin/env bash
# ============================================================================
# scram-delete-bug.sh — 第 19 章實驗:重現 KAFKA-20774——刪除一個 SCRAM 帳號後重啟 broker,SCRAM 使用者表被丟掉;再示範怎麼救回
# ----------------------------------------------------------------------------
# 白話:這是 Kafka 的已知 bug,也是 demo「停用帳號一律覆寫隨機密碼、不刪除」的原因。
#   腳本實際刪一個 SCRAM 帳號、重啟 broker1,看 SCRAM 登入會不會全壞,再示範救回方法。
# bug:broker 重放 metadata 時,REMOVE 紀錄的對象不在目前 image 裡,整個 SCRAM 機制的使用者表被清空
#   (fix 在 Kafka 4.5.0,未發行;CP 8.3.2 的 Kafka 4.3.x 受影響)。
# 症狀依內部通道而異:內部通道用 SCRAM 時 broker 直接起不來;內部通道用 mTLS(本 demo 現況)時 broker 起得來,
#   但 CLIENT 埠的 SCRAM 帳號全部登入失敗。
# 救回:把被刪的帳號重新建立(任何密碼)再重啟 broker——重放時 REMOVE 之後有對應的 UPSERT。
# 前置條件:demo 環境已啟動(scripts/up.sh);broker1 以外的 broker2 要在線(腳本透過 broker2 管理帳號)。
# 用法:
#   scripts/scram-delete-bug.sh      只動 broker1(重啟兩次,每次最多等約 140 秒)
# 會改動什麼:建立並刪除 SCRAM 帳號 svc-bugtest,再重新建立;broker1 重啟兩次。
#   做完帳號 svc-bugtest 留著,密碼是隨機值(沒有還原成「不存在」)。
# 怎麼判斷成功:最後的「判定:已重現 KAFKA-20774 …」。若印「判定:這次沒有重現」:此 bug 取決於 metadata 重放的狀態
#   ——全新叢集 100% 重現,跑過很多章節、已有 metadata 快照的環境不一定;沒重現不代表安全,
#   停用帳號仍一律覆寫隨機密碼、不刪除。印「判定:不符合(重啟後 …、救回後 …)」代表救回後仍無法登入。
# 常見失敗:步驟②或③顯示「Exited(起不來)」→ broker1 沒起來(典型症狀:內部通道用 SCRAM 時刪帳號後重啟)
#   → 查 docker logs broker1;「逾時」→ 超過約 140 秒仍未 healthy。
# ============================================================================
set -uo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
U=svc-bugtest
K="./scripts/k.sh kafka-configs --bootstrap-server broker2:9094 --command-config /clients/token-bootstrap.properties --entity-type users --entity-name $U"
login() { # login <broker>:印 成功/失敗
  local n; n=$(./scripts/k.sh kafka-topics --bootstrap-server "$1:9094" --command-config /clients/scram-svc-orders.properties --list 2>&1 | grep -c "Authentication failed")
  [ "$n" -gt 0 ] && echo "失敗" || echo "成功"
}
restart1() { # 重啟 broker1,等 healthy 或 Exited;印狀態
  docker restart broker1 >/dev/null 2>&1
  local s; for i in $(seq 1 14); do sleep 10; s=$(docker ps -a --format '{{.Status}}' -f name=^broker1$); case "$s" in *"(healthy)"*) echo "healthy"; return 0;; Exited*) echo "Exited(起不來)"; return 1;; esac; done; echo "逾時($s)"; return 1
}
echo "① 新建 SCRAM 帳號 $U,再刪除它(--delete-config)"
$K --alter --add-config "SCRAM-SHA-512=[password=bug-$RANDOM]" 2>&1 | grep -E "Completed|Error"
$K --alter --delete-config SCRAM-SHA-512 2>&1 | grep -E "Completed|Error"
echo "② 重啟 broker1(重放 metadata):$(restart1)"
sleep 10
a=$(login broker1); echo "   svc-orders 用 SCRAM 登入 broker1 → $a;登入 broker2(沒重啟)→ $(login broker2)"
echo "③ 救回:把被刪的 $U 重新建立(任何密碼),再重啟 broker1"
$K --alter --add-config "SCRAM-SHA-512=[password=restore-$RANDOM]" 2>&1 | grep -E "Completed|Error"
r=$(restart1); echo "   重啟 broker1:$r"; sleep 10
b=$(login broker1); echo "   svc-orders 用 SCRAM 登入 broker1 → $b"
if [ "$a" = "失敗" ] && [ "$b" = "成功" ]; then echo "判定:已重現 KAFKA-20774——刪除 SCRAM 帳號後重啟,SCRAM 登入全部失敗;重建被刪帳號再重啟即恢復"
elif [ "$a" = "成功" ] && [ "$b" = "成功" ]; then echo "判定:這次沒有重現(重啟後 $a)——此 bug 取決於 metadata 重放的狀態:全新叢集 100% 重現,跑過很多章節、已有 metadata 快照的環境不一定。沒重現不代表安全,停用帳號仍一律覆寫隨機密碼、不刪除"
else echo "判定:不符合(重啟後 $a、救回後 $b)"; fi
