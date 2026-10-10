#!/usr/bin/env bash
# ============================================================================
# broker-heal.sh — 最後手段:broker 重啟後起不來時,清空資料目錄重建(demo 專用)
# ----------------------------------------------------------------------------
# 白話:已查明 broker 重啟失敗的原因是「刪除過 SCRAM 憑證」(見 scripts/scram-disable.sh、RUNBOOK 第 19 章);
#   demo 的腳本已不再刪除 SCRAM 憑證,正常不會用到這支。若環境裡已經有人刪過 SCRAM 憑證,
#   先把被刪的帳號重新建立(任何密碼)即可,不必清資料;都不行時才用這支:
#   清空該 broker 的資料目錄後重建,資料從另一台補回來(RF=2)。
# 前置條件:demo 環境已啟動,且另一台 broker 是健康的(資料要從它補回來)
# 用法:
#   scripts/broker-heal.sh <broker1|broker2> [docker compose 的檔案 / profile 參數...]
#   例: scripts/broker-heal.sh broker2 -f docker-compose.yml -f docker-compose.cyberark.yml --profile cyberark
#   行為:broker 已 healthy 就什麼都不做;已結束(Exited)就清掉它的資料目錄,用同樣的 compose 參數重建,等 healthy。
#   RF=2 的 topic 會從另一台補回來。
# 會改動什麼:刪除該 broker 容器與其 /var/lib/kafka/data 的 volume(資料靠另一台副本補回),
#   再用 docker compose up -d --wait 重建;若設了環境變數 BROKER_HEAL_LOG,會把「時間 heal <broker>」追加到該檔。
# 怎麼判斷成功:印「[heal] <broker> 已重建且 healthy」;broker 本來就 healthy 則無輸出、結束碼 0。
# 常見失敗:compose 參數必須和當初啟動時一致(例如 cyberark 的 -f / --profile),否則重建出的服務組合不同;
#   重建等待逾時(300 秒)→ docker compose 回傳非 0,腳本(set -e)直接結束
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
B="$1"; shift
st=$(docker ps -a --format '{{.Status}}' -f "name=^$B$")
case "$st" in *"(healthy)"*) exit 0;; esac
for i in $(seq 1 6); do   # 剛啟動、還在 starting 的先給一點時間
  case "$st" in Exited*|"") break;; *"(healthy)"*) exit 0;; esac
  sleep 10; st=$(docker ps -a --format '{{.Status}}' -f "name=^$B$")
done
case "$st" in *"(healthy)"*) exit 0;; esac
echo "$(date +%T) heal $B" >> "${BROKER_HEAL_LOG:-/dev/null}"
echo "[heal] $B 沒有正常啟動($st),清空它的資料目錄並重建(從另一台 broker 重新同步)"
V=$(docker inspect "$B" --format '{{range .Mounts}}{{if eq .Destination "/var/lib/kafka/data"}}{{.Name}}{{end}}{{end}}' 2>/dev/null || true)
docker rm -f "$B" >/dev/null 2>&1 || true
[ -n "$V" ] && docker volume rm "$V" >/dev/null
if [ "$#" -gt 0 ]; then docker compose "$@" up -d --wait --wait-timeout 300 "$B" >/dev/null; else docker compose up -d --wait --wait-timeout 300 "$B" >/dev/null; fi
echo "[heal] $B 已重建並 healthy"
