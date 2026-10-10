#!/usr/bin/env bash
# ============================================================================
# lib/prom.sh — 查 Prometheus 與 Alertmanager 的小工具
# ----------------------------------------------------------------------------
# 前置:先 source lib/common.sh。Prometheus、Alertmanager 都是 HTTPS + Basic 帳密;
#   維運與腳本用 ops 帳號(測試值),Control Center 用 c3、telemetry 用 telemetry,不要混用。
# 帳密可用環境變數覆蓋(正式環境由 CyberArk 提供,不要寫進腳本):
#   PROM_AUTH(預設 ops:ops-prom-pw)、AM_AUTH(預設 ops:ops-am-pw)
# ============================================================================
PROM_AUTH="${PROM_AUTH:-ops:ops-prom-pw}"
AM_AUTH="${AM_AUTH:-ops:ops-am-pw}"
PROM_URL="https://prometheus:9090"
AM_URL="https://alertmanager:9093"

# prom_query <PromQL>:執行一個 PromQL 查詢,印出第一筆結果的值(沒有結果印「無」)。
prom_query() { dcurl -u "$PROM_AUTH" -G --data-urlencode "query=$1" "$PROM_URL/api/v1/query" 2>/dev/null | node "$LIB_DIR/prom-value.mjs"; }

# alerts_firing [名稱正規表示式] [排除正規表示式]:列出目前正在觸發的告警(逗號分隔;沒有印「-」)。
alerts_firing() { dcurl -u "$PROM_AUTH" "$PROM_URL/api/v1/alerts" 2>/dev/null | node "$LIB_DIR/prom-alerts.mjs" "$@"; }

# alert_is_firing <告警名稱[@instance]> [名稱正規表示式]:該告警正在觸發就回傳 0(給 wait_until 用)。
alert_is_firing() { case ",$(alerts_firing "${2:-.}")," in *",$1,"*) return 0;; *) return 1;; esac; }

# alert_is_cleared <告警名稱[@instance]> [名稱正規表示式]:該告警「沒有」在觸發就回傳 0(給 wait_until 用)。
alert_is_cleared() { ! alert_is_firing "$@"; }

# am_has_alert <告警名稱>:Alertmanager 有收到這個告警就印 1,否則印 0。
am_has_alert() { dcurl -u "$AM_AUTH" "$AM_URL/api/v2/alerts" 2>/dev/null | grep -c "\"alertname\":\"$1\"" | sed 's/^[1-9].*$/1/'; }

# prom_rules_count <規則群組名稱>:印「規則數 health=ok 的規則數」(例如 "7 7")。
prom_rules_count() { dcurl -u "$PROM_AUTH" "$PROM_URL/api/v1/rules" 2>/dev/null | node "$LIB_DIR/prom-rules.mjs" "$1" count; }

# prom_rules_list <規則群組名稱>:每條規則印一行「名稱 health state」。
prom_rules_list() { dcurl -u "$PROM_AUTH" "$PROM_URL/api/v1/rules" 2>/dev/null | node "$LIB_DIR/prom-rules.mjs" "$1" list; }
