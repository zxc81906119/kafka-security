#!/usr/bin/env bash
# 叢集剛建好時沒有任何 role binding,只有 super.users 的 bootstrap 身分能建第一批。
# bootstrap 身分 = client 憑證 CN=bootstrap(非 AD 帳號、非任何人的帳號),建完後管理權交給 AD 群組(7 組,對齊簡報)。
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
