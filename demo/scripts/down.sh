#!/usr/bin/env bash
# ============================================================================
# down.sh — 停掉並清除整個 demo(所有 profile 的容器與資料卷),映像保留
# ----------------------------------------------------------------------------
# 白話:課前準備的最後一步、或要從零重建前用。各章會啟動不同 profile 的元件(Conjur、Grafana、MinIO…),
#   只寫 docker compose down 會漏掉沒列出的 profile;這支一次全部清掉。下次 scripts/up.sh 從零建立(不會重新下載映像)。
# 用法:
#   scripts/down.sh
# 會改動什麼:`docker compose down -v`(所有 profile);刪除 Conjur 的 admin.key 與各 host 的 API key(資料卷清掉後就失效);
#   移除 .env 裡實驗用的覆蓋設定(COMPOSE_FILE 疊 tier 檔、SBC_ENABLE)。
# 怎麼判斷成功:最後印「[down] 已清除」;docker ps 看不到 demo 的容器。
# ============================================================================
set -uo pipefail
cd "$(dirname "$0")/.."

docker compose --profile full --profile c3 --profile restproxy --profile sr --profile cyberark --profile grafana --profile observability \
  --profile connect --profile mail --profile tier --profile sbc --profile quorum down -v --remove-orphans >/dev/null 2>&1 || true
# Conjur 的資料卷已清掉,舊的 admin.key / 各 host 的 API key 就失效了;不清的話第 18 章會『Unable to authenticate』(conjur.env 的 data key 保留)
rm -f config/conjur/admin.key config/conjur/policy.out; rm -rf config/conjur/keys
# 實驗用的覆蓋設定(第 31、32 章):回到乾淨基線
[ -f .env ] && sed -i '/^COMPOSE_PATH_SEPARATOR=/d;/^COMPOSE_FILE=/d;/^SBC_ENABLE=/d' .env
echo "[down] 已清除(映像保留;重建:bash scripts/up.sh)"
