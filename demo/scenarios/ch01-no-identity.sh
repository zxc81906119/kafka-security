#!/usr/bin/env bash
# 第 1 章:沒有身分就進不來(建立「預設全拒絕」的基準)
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch01 "沒有身分就進不來:預設全拒絕"
./scripts/reset.sh >/dev/null 2>&1   # 回到「還沒有任何授權」的起點

step no-cred-rest "未帶任何帳密呼叫 REST Proxy → 401" \
  "curl https://restproxy:8086/topics            # 無 Authorization 標頭" \
  'rp none GET /topics' '\[HTTP 401\]'

step wrong-pw-rest "帳號正確、密碼錯誤 → 401(AD 驗證失敗)" \
  "curl -u yujie:<錯誤密碼> https://restproxy:8086/topics" \
  'rp yujie:bad GET /topics' '\[HTTP 401\]'

step wrong-pw-broker "用 AD 帳號直連 broker,密碼錯誤 → 認證失敗" \
  "kafka-topics --bootstrap-server broker1:9094 --command-config yujie-錯誤密碼.properties --list" \
  'K kafka-topics --bootstrap-server $BOOT --command-config /clients/plain-yujie-wrong.properties --list' 'Authentication failed'

step valid-no-perm "帳密正確(AD 登入成功)但尚未授權 → 看得到的 topic 是 0 個" \
  "kafka-topics --bootstrap-server broker1:9094 --command-config ming.properties --list | grep -v -E '^(__|_confluent)' | wc -l   # 已認證、未授權" \
  'as_list ming | grep -v -E "^(__|_confluent)" | wc -l | sed "s/^/可見的業務 topic 數: /"' '可見的業務 topic 數: 0'
ch_end
