#!/usr/bin/env bash
# ============================================================================
# alertmanager-probe.sh — 證明 Alertmanager 要認證才能寫入
# ----------------------------------------------------------------------------
# 白話:Alertmanager 若沒擋住未認證的寫入,任何人都能建立「靜音」把告警壓掉。這支腳本用同一個請求
#   各打一次:不帶憑證建立靜音應被擋(401);帶 Basic 帳密才成功。測試用,做完即刪除。
# 前置條件:demo 環境已啟動(scripts/up.sh),alertmanager 容器在跑
# 用法:
#   scripts/alertmanager-probe.sh      不需參數
# 會改動什麼:帶帳密(ops)時會建立一筆 alertname=probe 的靜音(1 分鐘後生效、3 分鐘後結束),隨即 DELETE 刪除,做完已還原。
# 怎麼判斷成功:最後一行「不帶憑證建立靜音 → [HTTP 401] ;帶 Basic 帳密建立 → [HTTP 2xx] ;清除 → [HTTP 2xx]」。
# ============================================================================
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."
AM=https://alertmanager:9093
S=$(date -u -d "+1 minute" +%Y-%m-%dT%H:%M:%SZ); E=$(date -u -d "+3 minutes" +%Y-%m-%dT%H:%M:%SZ)
BODY="{\"matchers\":[{\"name\":\"alertname\",\"value\":\"probe\",\"isRegex\":false}],\"startsAt\":\"$S\",\"endsAt\":\"$E\",\"createdBy\":\"probe\",\"comment\":\"probe\"}"
N=$(./scripts/dcurl.sh -X POST $AM/api/v2/silences -H "Content-Type: application/json" -d "$BODY" | tail -1)
R=$(./scripts/dcurl.sh -u ops:ops-am-pw -X POST $AM/api/v2/silences -H "Content-Type: application/json" -d "$BODY")
A=$(echo "$R" | tail -1)
ID=$(echo "$R" | grep -o '"silenceID":"[^"]*"' | cut -d'"' -f4)
B=$(./scripts/dcurl.sh -u ops:ops-am-pw -X DELETE "$AM/api/v2/silence/$ID" | tail -1)
echo "不帶憑證建立靜音 → $N ;帶 Basic 帳密建立 → $A ;清除 → $B"
