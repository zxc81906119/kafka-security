#!/usr/bin/env bash
# ============================================================================
# ch32-tiered-storage.sh — 第 32 章:Tiered Storage(舊資料放到物件儲存 MinIO)
# ----------------------------------------------------------------------------
# 白話:舊 segment 上傳到物件儲存,broker 本機只留最近一段;讀舊資料時 broker 從物件儲存取回。
#   這一章驗證:資料真的上傳、本機真的變小、從頭讀還是讀得到全部、broker 重啟後仍在,以及物件儲存的存取保護。
# 前置條件:叢集已啟動(scripts/up.sh);第一步會執行 scripts/tier-setup.sh on(啟動 MinIO、broker 依序重建)
# 冪等:是。第一步 scripts/chapter-start.sh 確認起點(本章不需要前面的章節),重跑結果相同。
# 用法:
#   ./demo.sh 32                  經由講解控制台跑這一章(DEMO_PAUSE=0 不暫停)
#   ./scenarios/ch32-tiered-storage.sh    直接跑
# 會改動什麼:config/tier/ 產生密碼與憑證副本(不進版本庫);.env 的 COMPOSE_FILE 多 docker-compose.tier.yml;啟動 minio;
#   broker 依序重建;建立 topic tier.demo;restart 步驟重啟 broker1。結束後保留 tier 啟用狀態(scripts/tier-setup.sh off 還原)。
# 怎麼判斷成功:每一步印「✔ 符合預期」,最後一行「第 32 章完成(失敗 0 項)」
# 實測結果摘要:見各步驟證據檔(evidence/ch32)
# ============================================================================
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch32 "Tiered Storage:舊資料放到物件儲存(MinIO)"
TS="$DEMO_ROOT/scripts/tier-setup.sh"
TL="$DEMO_ROOT/scripts/tier-lab.sh"

step prepare "【起點準備】這一章不需要額外準備,確認環境可直接開始(冪等:可單獨從這一章開始,也可重跑)" \
  "scripts/chapter-start.sh ch32" \
  'bash "$DEMO_ROOT/scripts/chapter-start.sh" ch32 2>&1' '\[起點\] ch32 就緒'

step tier-on "【啟用】MinIO(HTTPS)+ 專用帳號與 bucket + broker 載入 Tiered Storage 設定(依序重建)" \
  "scripts/tier-setup.sh on" \
  'bash "$TS" on 2>&1 | tail -3' '\[tier\] 完成'

step tier-produce "【寫入】建立啟用 tier 的 topic(segment 5 MB、本機只留 60 秒)並寫入約 100 MB" \
  "kafka-topics --create --config confluent.tier.enable=true --config confluent.tier.local.hotset.ms=60000" \
  'bash "$TL" produce 2>&1' '判定:寫入完成'

step tier-archive "【上傳】舊 segment 上傳到物件儲存" \
  "mc ls --recursive local/kafka-tier(MinIO 管理帳號)" \
  'bash "$TL" archive 2>&1' '判定:舊 segment 已上傳'

step tier-evict "【本機清理】hotset 到期後,broker 本機只留最近的 segment" \
  "kafka-log-dirs --describe(前後比較)" \
  'bash "$TL" evict 2>&1' '判定:本機從'

step tier-read "【從頭讀】舊資料從物件儲存取回,筆數不變" \
  "kafka-consumer-perf-test --topic tier.demo(新 group,從頭)" \
  'bash "$TL" read 2>&1' '判定:從頭讀到全部'

step tier-restart "【重啟 broker】重啟 broker1 後仍讀到全部資料" \
  "docker restart broker1;再讀一次" \
  'bash "$TL" restart 2>&1' '判定:broker1 重啟後仍讀到全部'

step tier-security "【物件儲存的保護】匿名被拒、專用帳號只能動這個 bucket、只收 HTTPS、密碼不在日誌與環境變數" \
  "curl(匿名)、mc(專用帳號)、docker logs / env" \
  'bash "$TL" security 2>&1' '判定:物件儲存只收 HTTPS'

ch_end
