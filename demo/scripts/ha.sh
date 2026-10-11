#!/usr/bin/env bash
# ============================================================================
# ha.sh — 全新重建整個環境(清除所有資料後依 scripts/up.sh 啟動)
# ----------------------------------------------------------------------------
# 白話:以前有「基礎環境」與「HA 環境」兩種模式要用這支腳本切換。現在叢集一開始就是 3 controller + 4 broker、副本 3,
#   不再有模式之分;這支腳本只剩「清掉一切、從零重建」的用途,保留名稱是因為手冊與其他腳本都這樣稱呼。
# 用法:
#   scripts/ha.sh on  [up.sh 參數]    清掉現有資料 → 全新重建(例:scripts/ha.sh on --with-c3 --with-restproxy)
#   scripts/ha.sh off [up.sh 參數]    同 on(舊名稱,相容用)
#   scripts/ha.sh status              顯示目前拓樸(controller 與 broker 數量)
# 會改動什麼:`docker compose down -v`(清除所有 profile 的容器與資料,含 Conjur);移除 .env 裡舊的 COMPOSE_FILE / SBC_ENABLE;
#   重置 Conjur 的金鑰檔;之後執行 scripts/up.sh。
# 怎麼判斷成功:最後印「[ha] 已重建」。
# 常見失敗:卡在重建 → 看 scripts/up.sh 的輸出;記憶體不足 → Docker Desktop / WSL 至少 11 GB,可選元件分批啟動。
# ============================================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
[ "${1:-}" = "--help" ] && { usage_from_header "$0"; exit 0; }
cd "$DEMO_DIR"

# 清除所有 profile 的容器與資料(失敗也繼續,可能本來就沒有)。
remove_everything() {
  docker compose --profile c3 --profile restproxy --profile sr --profile cyberark --profile grafana --profile observability \
    --profile connect --profile mail --profile tier --profile sbc --profile quorum down -v >/dev/null 2>&1 || true
  # Conjur 的資料卷已清掉,舊的 admin.key / 各 host 的 API key 就失效了;不清的話第 18 章會『Unable to authenticate』(conjur.env 的 data key 保留)
  rm -f config/conjur/admin.key config/conjur/policy.out; rm -rf config/conjur/keys
}

# 清掉 .env 裡實驗用的覆蓋設定(COMPOSE_FILE 疊 tier 檔、SBC_ENABLE),回到乾淨基線。
reset_env_overrides() {
  sed -i '/^COMPOSE_PATH_SEPARATOR=/d;/^COMPOSE_FILE=/d;/^SBC_ENABLE=/d' .env
}

case "${1:-status}" in
  status)
    echo "controller:$(docker ps --format '{{.Names}}' | grep -c '^controller[0-9]*$') 台;broker:$(docker ps --format '{{.Names}}' | grep -c '^broker[0-9]*$') 台" ;;
  on|off)
    shift
    echo "[ha] 清除所有資料並全新重建(3 controller + 4 broker、副本 3)"
    remove_everything
    reset_env_overrides
    bash scripts/up.sh "$@"
    echo "[ha] 已重建" ;;
  *)
    usage_from_header "$0"; exit 1 ;;
esac
