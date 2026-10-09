#!/usr/bin/env bash
# 停用一個 SCRAM 帳號——不刪除憑證,改成覆寫成隨機密碼(沒人知道,等於不能再登入)。帳號本來就沒有 SCRAM 憑證時什麼都不做。
# 為什麼不刪:實測(2026-10-09,CP 8.3.2、KRaft)刪除 SCRAM 憑證後,下一次重啟 broker 會失敗——broker 啟動時 authorizer 的 client 連自己的 INTERNAL
#   listener 被拒 "Invalid user credentials with SASL mechanism SCRAM-SHA-512"。只建不刪、改密碼、controller 重啟都正常;刪除過的帳號事後重建也能救回。
#   刪一個「對不存在的帳號」也算(reset.sh 以前每次都這樣做)。官方 bug:KAFKA-20774(fix 4.5.0 未發行;CP 8.3.2 的 Kafka 4.3.x 受影響)。詳見 RUNBOOK 第 19 章。
# 用法: scripts/scram-disable.sh <帳號>
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
U="$1"
K=(./scripts/k.sh kafka-configs --bootstrap-server broker1:9094 --command-config /clients/token-bootstrap.properties --entity-type users --entity-name "$U")
if "${K[@]}" --describe 2>/dev/null | grep -q "SCRAM-SHA-512="; then
  PW=$(head -c 24 /dev/urandom | base64 | tr -d '\n=+/')
  "${K[@]}" --alter --add-config "SCRAM-SHA-512=[password=$PW]" 2>&1 | grep -E "Completed|Error" | sed "s/^/[scram-disable] /"
  echo "[scram-disable] $U 的密碼已覆寫成隨機值(憑證沒有刪除)"
else
  echo "[scram-disable] $U 沒有 SCRAM 憑證,略過"
fi
