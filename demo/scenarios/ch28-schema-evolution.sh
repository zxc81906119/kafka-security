#!/usr/bin/env bash
# ============================================================================
# ch28-schema-evolution.sh — 第 28 章:Schema 演進與資料契約——相容性、命名策略、規則
# ----------------------------------------------------------------------------
# 白話:producer 與 consumer 是不同團隊、不同時間上線的程式,靠 schema 約定欄位。這一章實測 schema 怎麼改才不會讓另一端壞掉:相容性模式、transitive、授權與相容性兩道關卡、命名策略、資料契約規則。
# 前置條件:需要 Schema Registry(scripts/sr-setup.sh);HA 或基礎環境皆可(記憶體吃緊時先 scripts/observability.sh off、docker stop control-center)
# 用法:
#   ./demo.sh 28                  經由講解控制台跑這一章(DEMO_PAUSE=0 不暫停)
#   ./scenarios/ch28-schema-evolution.sh    直接跑
# 會改動什麼:建立並刪除 subject sch.* 與 orders.sch.*;建立 topic orders.strat、orders.contract 並寫入測試資料、替 svc-orders 補 Write 的 ACL。
# 怎麼判斷成功:每一步印「✔ 符合預期」,最後一行「第 28 章完成(失敗 0 項)」
# 實測結果摘要:
#   BACKWARD:加有預設值的欄位過;加必填欄位、改型別 409(訊息指出欄位);相容性檢查 API 可先問
#   三種模式對 X(加預設欄位)/Y(刪欄位)/Z(加必填欄位):BACKWARD 擋 Z、FORWARD 擋 Y、FULL 擋 Y 和 Z
#   TRANSITIVE:BACKWARD 只比最新版,BACKWARD_TRANSITIVE 比全部舊版(檢查要用 /versions 不是 /versions/latest)
#   授權(403)與相容性(409)是兩道獨立的關卡;RecordNameStrategy 的 subject 脫離 topic,前綴授權失效
#   資料契約 CEL 規則:amount=-5 在寫入端被擋(Rule failed),規則是 client 端強制,不是 broker 端
# ============================================================================
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch28 "Schema 演進與資料契約"
SL="$DEMO_ROOT/scripts/schema-lab.sh"

step sch-setup "【啟動】確認 Schema Registry 在跑且授權就緒(沿用第 20 章的設定)" \
  "scripts/sr-setup.sh" \
  'bash "$DEMO_ROOT/scripts/sr-setup.sh" 2>&1 | tail -2' '就緒'

step sch-evolve "【演進】BACKWARD 下:加有預設值的欄位過、加必填欄位與改型別被擋(409)、相容性檢查 API 先問" \
  "POST /subjects/<subject>/versions;POST /compatibility/subjects/<subject>/versions/latest" \
  'bash "$SL" evolve 2>&1' '判定:BACKWARD 下'

step sch-modes "【三種模式】同樣三種改法在 BACKWARD / FORWARD / FULL 下的結果不同" \
  "PUT /config/<subject>;POST /compatibility/subjects/<subject>/versions/latest" \
  'bash "$SL" modes 2>&1' '判定:三種模式對同樣的改法結果不同'

step sch-trans "【TRANSITIVE】BACKWARD 只比最新版,漏掉更早的版本;BACKWARD_TRANSITIVE 比全部舊版" \
  "POST /compatibility/subjects/<subject>/versions(不加 /latest)" \
  'bash "$SL" transitive 2>&1' '判定:BACKWARD 只比最新版'

step sch-gates "【兩道關卡】授權(403)與相容性(409)獨立:有權限也不能改壞,相容也不能越權" \
  "yujie(orders-write)註冊 orders.* 與 payments.* 的 subject" \
  'bash "$SL" gates 2>&1' '判定:授權與相容性是兩道獨立的關卡'

step sch-naming "【命名策略】TopicNameStrategy 的 subject 跟著 topic,前綴授權有效;RecordNameStrategy 的 subject 是記錄全名,前綴授權失效" \
  "kafka-avro-console-producer --property value.subject.name.strategy=…RecordNameStrategy" \
  'bash "$SL" naming 2>&1' '判定:TopicNameStrategy 的 subject'

step sch-contract "【資料契約】schema 掛 CEL 規則 amount >= 0:amount=100 寫得進去,amount=-5 在寫入端被擋" \
  "POST /subjects/…/versions(帶 ruleSet);kafka-avro-console-producer(use.latest.version=true)" \
  'bash "$SL" contract 2>&1' '判定:資料契約規則生效'

ch_end
