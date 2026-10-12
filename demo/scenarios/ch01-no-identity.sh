#!/usr/bin/env bash
# ============================================================================
# ch01-no-identity.sh — 第 1 章:沒有身分就進不來(建立「預設全拒絕」的基準)
# ----------------------------------------------------------------------------
# 白話:先證明沒有身分(沒帳密、密碼錯)連 REST Proxy / broker 都進不來;而帳密正確但還沒被授權的人,
#       雖然登入成功,卻一個業務 topic 都看不到。這是後面所有「授權」章節的對照基準。
# 前置條件:環境已建好(scripts/up.sh);腳本一開始會跑 scripts/reset.sh 回到「還沒有任何授權」的起點
# 冪等:是。第一步 scripts/chapter-start.sh 把環境收斂到本章起點(不必先跑前面的章節),重跑結果相同。
# 用法:
#   ./demo.sh 1                       經由講解控制台跑這一章
#   ./scenarios/ch01-no-identity.sh   直接跑(DEMO_PAUSE=0 不暫停)
# 會改動什麼:只呼叫 reset.sh(AD 群組、RBAC 綁定、服務帳號還原到第 0 章狀態);其餘步驟都是唯讀的連線測試
# 怎麼判斷成功:每一步印『✔ 符合預期』,最後一行『第 01 章完成(失敗 0 項)』
# 實測結果摘要:
#   無 Authorization 呼叫 REST Proxy → HTTP 401;帳號對密碼錯 → HTTP 401(AD 驗證失敗)
#   AD 帳號直連 broker 密碼錯 → Authentication failed
#   ming 帳密正確但未授權 → 可見的業務 topic 數為 0(已認證不等於已授權)
# ============================================================================
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch01 "沒有身分就進不來:預設全拒絕"

step prepare "【起點準備】回到還沒有任何授權的起點(scripts/reset.sh)(冪等:已正確的不動;可單獨從這一章開始,也可重跑)" \
  "scripts/chapter-start.sh ch01" \
  'bash "$DEMO_ROOT/scripts/chapter-start.sh" ch01 2>&1' '\[起點\] ch01 就緒'
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
