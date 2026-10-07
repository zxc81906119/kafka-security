#!/usr/bin/env bash
# 第 14 章(進階):broker 內建 Admin REST(/kafka/v3)的保護 —— 未設定時完全無認證;依官方 kafka.rest. 設定後依使用者身分授權
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch14 "broker 內建 Admin REST 的保護(匿名擋下、依使用者授權)"
DC="$DEMO_ROOT/scripts/dcurl.sh"
CID=XyZBQ3-GTvKH2qNfP7X33A
API="https://broker1:8091/kafka/v3/clusters/$CID"
JSONH='-H Content-Type:application/json'
brief() { grep -o -E '"kind":"[A-Za-z]+"|"data":\[\]|"error_code":[0-9]+|"message":"[^"]*"|"offset":[0-9]+|\[HTTP [0-9]+\]' | awk '!s[$0]++' | tr '\n' ' '; echo; }

step anon "【匿名】不帶任何身分呼叫 Admin REST → 401(沒設定保護時,這個呼叫會直接成功,甚至曾讓 broker 記憶體耗盡而崩潰)" \
  "curl https://broker1:8091/kafka/v3/clusters        # 不帶任何憑證" \
  'bash "$DC" https://broker1:8091/kafka/v3/clusters | brief' '\[HTTP 401\]'

step badpw "【錯誤密碼】AD 帳號但密碼錯 → 401" \
  "curl -u gary:bad https://broker1:8091/kafka/v3/clusters" \
  'bash "$DC" -u gary:bad https://broker1:8091/kafka/v3/clusters | brief' '\[HTTP 401\]'

step gary-topics "【管理員 gary】用 AD 帳密列出 topic → 200,看得到全部 topic" \
  "curl -u gary:*** $API/topics" \
  'bash "$DC" -u gary:gary-pw $API/topics | brief' '"kind":"KafkaTopicList".*\[HTTP 200\]'

step ming-topics "【無 role 的 ming】同一個呼叫 → 200 但清單是空的(只回他有權看的資源)" \
  "curl -u ming:*** $API/topics" \
  'bash "$DC" -u ming:ming-pw $API/topics | brief' '"data":\[\].*\[HTTP 200\]'

step ming-produce "【ming 寫入】透過 Admin REST produce → 內容回 40301 Not authorized(注意:HTTP 狀態碼仍是 200,錯誤在內容裡,監控要看 error_code)" \
  "curl -u ming:*** -X POST $API/topics/orders.events/records -d '{...}'" \
  'bash "$DC" -u ming:ming-pw -X POST $JSONH $API/topics/orders.events/records -d "{\"value\":{\"type\":\"JSON\",\"data\":{\"x\":1}}}" | brief' '"error_code":40301'

step gary-produce "【gary 寫入】同一個呼叫 → 成功,回傳 offset" \
  "curl -u gary:*** -X POST $API/topics/orders.events/records -d '{...}'" \
  'bash "$DC" -u gary:gary-pw -X POST $JSONH $API/topics/orders.events/records -d "{\"value\":{\"type\":\"JSON\",\"data\":{\"x\":1}}}" | brief' '"offset":[0-9]+'

ch_end
