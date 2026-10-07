#!/usr/bin/env bash
# 以命令列調整 LDAP(模擬 AD)群組成員 —— 現場 demo 用網頁介面做同樣的事。
# 用法: scripts/ldap-group.sh add|remove <user> <group>
# 使用者名稱 = CN(不分大小寫);成員值用使用者的完整 DN(使用者分散在多層 OU)。
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
