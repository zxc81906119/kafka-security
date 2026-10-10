#!/usr/bin/env bash
# ============================================================================
# lib/common.sh — 所有 Lab 腳本共用的小工具(白話說明、等待、檢查環境)
# ----------------------------------------------------------------------------
# 怎麼用:在腳本開頭  source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
# 這個檔案只定義函式,不會執行任何動作。每個函式上方都有一行說明。
# 風格規則與踩坑清單見 demo/CONTRIBUTING.md。
# ============================================================================

# 本專案根目錄(demo/);不管從哪個目錄執行腳本,都以它為基準
DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# 給 node 用的 lib 目錄路徑(Windows 的 node 讀不懂 /c/… 這種路徑,要轉成 C:/…;Linux/RHEL 上 cygpath 不存在,原樣使用)
# shellcheck disable=SC2034  # 其他腳本會用到
LIB_DIR="$(cygpath -m "$DEMO_DIR/scripts/lib" 2>/dev/null || echo "$DEMO_DIR/scripts/lib")"
# Windows 的 Git Bash 會把 /xxx 路徑自作聰明改寫,傳給 docker 的路徑會壞掉;關掉它
export MSYS_NO_PATHCONV=1
# 白話說明模式:EXPLAIN=1(預設)每個動作前先印一句中文說明;EXPLAIN=0 關閉(只留結果)
EXPLAIN="${EXPLAIN:-1}"

# say <一句白話>:告訴讀的人「接下來要做什麼、為什麼」。EXPLAIN=0 時不印。
say() { [ "$EXPLAIN" = 0 ] || printf '▶ %s\n' "$*"; }

# note <說明>:印出一行結果或觀察(不受 EXPLAIN 影響,一定會印)。
note() { printf '   %s\n' "$*"; }

# die <訊息>:印出錯誤並結束腳本(結束碼 1)。
die() { printf '✘ %s\n' "$*" >&2; exit 1; }

# verdict <訊息>:印出「判定:…」這一行。章節腳本靠這行文字判斷這一步有沒有成功,所以格式不要改。
verdict() { printf '判定:%s\n' "$*"; }

# usage_from_header <腳本路徑>:把腳本開頭的說明區塊(第一段 # 開頭的註解)當成 --help 印出來。
usage_from_header() { sed -n '2,/^# =\{20,\}$/p' "$1" | sed '1d;$d; s/^# \{0,1\}//'; }

# need_ha_mode:確認目前是 HA 模式(3 controller + 3 broker),不是就提示怎麼切換並結束。
need_ha_mode() {
  grep -q '^COMPOSE_FILE=.*docker-compose.ha.yml' "$DEMO_DIR/.env" 2>/dev/null \
    || die "目前不是 HA 模式。先執行:scripts/ha.sh on(會清除資料並重建,約 2 分鐘)"
}

# need_container <名稱>:確認某個容器正在執行,沒有就提示怎麼啟動並結束。
need_container() {
  docker ps --format '{{.Names}}' | grep -qx "$1" || die "容器 $1 沒有在跑。${2:-}"
}

# wait_until <描述> <最多等幾秒> <指令...>:每 5 秒執行一次指令,成功(回傳 0)就結束;逾時回傳 1。
# 所有「等某件事發生」都用它,保證不會無限等下去。成功時印出等了幾秒。
wait_until() {
  local desc="$1" max="$2" t0; shift 2; t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt "$max" ]; do
    if "$@" >/dev/null 2>&1; then note "$(( $(date +%s) - t0 )) 秒後:$desc"; return 0; fi
    sleep 5
  done
  note "等了 $max 秒仍未達成:$desc"; return 1
}

# container_healthy <名稱>:該容器的狀態是 healthy 就回傳 0(給 wait_until 用)。
container_healthy() { docker ps --format '{{.Names}} {{.Status}}' | grep -q "^$1 .*(healthy)"; }

# wait_healthy <名稱...>:等所有容器都 healthy(每個最多等 150 秒);有任何一個等不到就回傳 1。
wait_healthy() { local c rc=0; for c in "$@"; do wait_until "$c 健康" 150 container_healthy "$c" || rc=1; done; return $rc; }

# stop_containers <名稱...> / start_containers <名稱...>:停止或啟動容器(安靜執行)。
stop_containers()  { docker stop "$@"  >/dev/null; }
start_containers() { docker start "$@" >/dev/null; }

# dcurl <curl 參數...>:在 demo 的 docker 網路內跑 curl,信任行內 CA;最後一行印出 [HTTP 狀態碼](連不上是 000)。
dcurl() { bash "$DEMO_DIR/scripts/dcurl.sh" "$@"; }
