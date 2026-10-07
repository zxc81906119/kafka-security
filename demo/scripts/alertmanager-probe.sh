#!/usr/bin/env bash
# 證明 Alertmanager 要認證才能寫入:不帶憑證建立靜音被擋(401);帶 Basic 帳密才成功(測試用,做完即刪除)。
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."
AM=https://alertmanager:9093
S=$(date -u -d "+1 minute" +%Y-%m-%dT%H:%M:%SZ); E=$(date -u -d "+3 minutes" +%Y-%m-%dT%H:%M:%SZ)
BODY="{\"matchers\":[{\"name\":\"alertname\",\"value\":\"probe\",\"isRegex\":false}],\"startsAt\":\"$S\",\"endsAt\":\"$E\",\"createdBy\":\"probe\",\"comment\":\"probe\"}"
N=$(./scripts/dcurl.sh -X POST $AM/api/v2/silences -H "Content-Type: application/json" -d "$BODY" | tail -1)
R=$(./scripts/dcurl.sh -u c3:am-pw -X POST $AM/api/v2/silences -H "Content-Type: application/json" -d "$BODY")
A=$(echo "$R" | tail -1)
ID=$(echo "$R" | grep -o '"silenceID":"[^"]*"' | cut -d'"' -f4)
B=$(./scripts/dcurl.sh -u c3:am-pw -X DELETE "$AM/api/v2/silence/$ID" | tail -1)
echo "不帶憑證建立靜音 → $N ;帶 Basic 帳密建立 → $A ;清除 → $B"
