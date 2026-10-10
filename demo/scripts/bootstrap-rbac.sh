#!/usr/bin/env bash
# ============================================================================
# bootstrap-rbac.sh — 建立第一批 RBAC role binding(bootstrap)
# ----------------------------------------------------------------------------
# 白話:叢集剛建好時沒有任何 role binding,只有 super.users 的 bootstrap 身分能建第一批。
#   bootstrap 身分 = client 憑證 CN=bootstrap(非 AD 帳號、非任何人的帳號)。
#   這支腳本用它把管理權限綁給 AD 群組(7 組,對齊簡報)與平台元件,之後管理權交給 AD 群組。
#   沒有任何人日常是 SystemAdmin,SystemAdmin 只給 breakglass,平常是空的。
# 前置條件:demo 環境已啟動且 MDS 可用(scripts/up.sh),certs/ 內有 bootstrap 的 client 憑證
# 用法:
#   scripts/bootstrap-rbac.sh      不需參數
# 會改動什麼:透過 MDS 新增 role binding(rbac_bind,定義在 scripts/rbac-lib.sh):breakglass、cluster-admin、rbac-admin、
#   topic-admin、security、ops 等群組,以及平台元件 User:c3(SystemAdmin)、User:restproxy(讀寫 _confluent-command)。
#   不刪除任何東西。
# 怎麼判斷成功:每個 binding 印一行「bind <principal> <role> … -> …[HTTP 2xx]」,最後印「[bootstrap] 完成。」
#   之後 AD 群組 rbac-admin 的成員(GARY)在 C3 操作;orders-read / orders-write 的授權在各 Lab 示範。
# ============================================================================
set -euo pipefail
source "$(dirname "$0")/rbac-lib.sh"
echo "[bootstrap] 以 bootstrap 憑證建立第一批 role binding"
# ── 人:AD 群組(role 綁在群組;沒有任何人日常是 SystemAdmin,SystemAdmin 只給 breakglass,平常是空的)──
rbac_bind cert bootstrap Group:breakglass SystemAdmin              # 緊急用
rbac_bind cert bootstrap Group:cluster-admin ClusterAdmin          # 建 SCRAM、quota、quorum 等叢集層級作業
rbac_bind cert bootstrap Group:rbac-admin UserAdmin                # 只管授權,不能碰 topic 與資料
rbac_bind cert bootstrap Group:topic-admin ResourceOwner Topic '*' LITERAL   # topic 與 consumer group 管理
rbac_bind cert bootstrap Group:topic-admin ResourceOwner Group '*' LITERAL
rbac_bind cert bootstrap Group:security SecurityAdmin              # 查授權、audit 設定
rbac_bind cert bootstrap Group:security AuditAdmin
rbac_bind cert bootstrap Group:security DeveloperRead Topic confluent-audit-log-events LITERAL   # 讀 audit topic(實測:光有 AuditAdmin 讀不到)
rbac_bind cert bootstrap Group:security DeveloperRead Group audit- PREFIXED
rbac_bind cert bootstrap Group:ops Operator                        # 維運:看叢集、不碰資料
# ── 平台元件(client 憑證)──
rbac_bind cert bootstrap User:c3 SystemAdmin                      # C3 向 MDS 的身分(CN=c3 憑證;官方要求 SystemAdmin)
# REST Proxy 自身(憑證式 OAUTHBEARER,身分 = User:restproxy):官方範例給 license topic 的讀寫權
rbac_bind cert bootstrap User:restproxy DeveloperRead Topic _confluent-command LITERAL
rbac_bind cert bootstrap User:restproxy DeveloperWrite Topic _confluent-command LITERAL
echo "[bootstrap] 完成。之後角色指派由 AD 群組 rbac-admin 的成員(GARY)在 C3 操作;orders-read / orders-write 的授權在各 Lab 示範。"
