#!/usr/bin/env bash
# ============================================================================
# ldap-group.sh — 以命令列調整 LDAP(模擬 AD)群組成員
# ----------------------------------------------------------------------------
# 白話:現場 demo 用網頁介面做同樣的事;這支是命令列版本,用來把人加進或移出群組,
#   再看 RBAC 權限是否跟著群組變動。
#   使用者名稱 = CN(不分大小寫);成員值用使用者的完整 DN(使用者分散在多層 OU)。
# 前置條件:demo 環境已啟動(scripts/up.sh),openldap 容器在跑
# 用法:
#   scripts/ldap-group.sh add|remove <user> <group>
# 會改動什麼:在 cn=<group>,ou=groups 加入(add)或移除(remove)該使用者的 member;不會自動還原,要還原請反向再執行一次。
# 怎麼判斷成功:印「[LDAP] add|remove <user> -> <group>  (時間)」。
# 常見失敗:
#   「使用者名稱格式不符」→ 只允許英數與 . _ -
#   「找不到使用者 CN=xxx」→ CN 打錯或不在 ou=users 底下
# ============================================================================
set -euo pipefail
export MSYS_NO_PATHCONV=1
act="$1"; user="$2"; grp="$3"
BASE="dc=corp,dc=demo"
case "$act" in
  add) op="add" ;;
  remove) op="delete" ;;
  *) echo "usage: $0 add|remove <user> <group>"; exit 1 ;;
esac
[[ "$user" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "使用者名稱格式不符"; exit 1; }
dn=$(docker exec openldap ldapsearch -x -LLL -D "cn=admin,$BASE" -w adminpw -b "ou=users,$BASE" "(cn=$user)" dn | sed -n 's/^dn: //p' | head -1)
[ -n "$dn" ] || { echo "找不到使用者 CN=$user"; exit 1; }
printf 'dn: cn=%s,ou=groups,%s\nchangetype: modify\n%s: member\nmember: %s\n' "$grp" "$BASE" "$op" "$dn" \
  | docker exec -i openldap ldapmodify -x -D "cn=admin,$BASE" -w adminpw >/dev/null
echo "[LDAP] $act $user -> $grp  ($(date +%T))"
