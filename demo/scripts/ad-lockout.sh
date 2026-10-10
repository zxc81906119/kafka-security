#!/usr/bin/env bash
# ============================================================================
# ad-lockout.sh — 第 19 章:模擬 AD 的「帳戶鎖定原則」(連續輸錯密碼就鎖帳號)
# ----------------------------------------------------------------------------
# 白話:真實 AD 會在密碼連續輸錯後鎖住帳號,第 19 章要驗證這種情況下登入的行為。
#   demo 的 openldap 用 ppolicy overlay 模擬這個原則(up.sh 已載入,鎖定預設關閉);
#   這支腳本負責開關鎖定、查看某帳號的鎖定狀態、以及手動解鎖。
# 前置條件:demo 環境已啟動(scripts/up.sh),openldap 容器在跑
# 用法:
#   scripts/ad-lockout.sh on               打開鎖定(連續 5 次失敗鎖 60 秒)
#   scripts/ad-lockout.sh off              關閉鎖定(其他章節的狀態)
#   scripts/ad-lockout.sh status <帳號>    看該帳號有沒有被鎖、失敗次數
#   scripts/ad-lockout.sh unlock <帳號>    管理員手動解鎖(對應 AD 的「解除鎖定帳戶」)
#   <帳號> 是 CN(不分大小寫),腳本會先到 ou=users 底下搜尋完整 DN。
# 會改動什麼:on/off 修改 openldap 的 ppolicy 設定(cn=default,ou=policies 的 pwdLockout 設為 TRUE/FALSE);
#   unlock 清掉該帳號的 pwdAccountLockedTime、pwdFailureTime;status 只查詢。做完不會自動還原,用完請執行 off。
# 怎麼判斷成功:on/off/unlock 印「[ad-lockout] 已打開…/已關閉/已解除…」;status 印「<帳號>:未鎖定;最近失敗 N 次」、
#   「<帳號>:已鎖定…」或「<帳號>:鎖定已過期…」。
# 常見失敗:印「找不到帳號 xxx」(結束碼 1)→ CN 打錯或不在 ou=users 底下
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
POLICY="cn=default,ou=policies,dc=corp,dc=demo"
BASE="dc=corp,dc=demo"
LOCK_SECONDS=60
ldap_admin() { docker exec -i openldap "$@" -x -H ldap://localhost -D "cn=admin,$BASE" -w adminpw; }   # demo 的目錄管理員(正式環境 = AD 管理員)
user_dn() { docker exec openldap ldapsearch -x -LLL -H ldap://localhost -D "cn=admin,$BASE" -w adminpw -b "ou=users,$BASE" "(cn=$1)" dn 2>/dev/null | sed -n 's/^dn: //p' | head -1; }
case "${1:-}" in
on)  printf 'dn: %s\nchangetype: modify\nreplace: pwdLockout\npwdLockout: TRUE\n' "$POLICY" | ldap_admin ldapmodify >/dev/null && echo "[ad-lockout] 已打開:連續 5 次失敗鎖 $LOCK_SECONDS 秒(pwdMaxFailure=5、pwdLockoutDuration=$LOCK_SECONDS)";;
off) printf 'dn: %s\nchangetype: modify\nreplace: pwdLockout\npwdLockout: FALSE\n' "$POLICY" | ldap_admin ldapmodify >/dev/null && echo "[ad-lockout] 已關閉";;
status)
  dn=$(user_dn "$2"); [ -n "$dn" ] || { echo "找不到帳號 $2"; exit 1; }
  out=$(docker exec openldap ldapsearch -x -LLL -H ldap://localhost -D "cn=admin,$BASE" -w adminpw -b "$dn" -s base "(objectClass=*)" pwdAccountLockedTime pwdFailureTime 2>/dev/null)
  n=$(printf '%s\n' "$out" | grep -c '^pwdFailureTime' || true); lk=$(printf '%s\n' "$out" | sed -n 's/^pwdAccountLockedTime: //p')
  if [ -z "$lk" ]; then echo "$2:未鎖定;最近失敗 $n 次"
  else t=$(date -u -d "${lk:0:4}-${lk:4:2}-${lk:6:2} ${lk:8:2}:${lk:10:2}:${lk:12:2}" +%s); age=$(( $(date -u +%s) - t ))
    if [ "$age" -lt "$LOCK_SECONDS" ]; then echo "$2:已鎖定(${age} 秒前鎖定,$((LOCK_SECONDS-age)) 秒後自動解除;或由管理員解鎖)"; else echo "$2:鎖定已過期(${age} 秒前鎖定,鎖 $LOCK_SECONDS 秒),下次登入成功即清除"; fi; fi;;
unlock)
  dn=$(user_dn "$2"); [ -n "$dn" ] || { echo "找不到帳號 $2"; exit 1; }
  for a in pwdAccountLockedTime pwdFailureTime; do printf 'dn: %s\nchangetype: modify\ndelete: %s\n' "$dn" "$a" | ldap_admin ldapmodify >/dev/null 2>&1 || true; done
  echo "[ad-lockout] 已解鎖 $2(清除 pwdAccountLockedTime / pwdFailureTime)";;
*) sed -nE '2,/^# ={20,}$/p' "$0" | sed -E '1d;$d; s/^# ?//'; exit 1;;
esac
