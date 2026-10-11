#!/usr/bin/env bash
# ============================================================================
# mail-setup.sh — 啟動或關閉第 30 章的告警郵件(測試用郵件伺服器 + Alertmanager 的郵件通知)
# ----------------------------------------------------------------------------
# 白話:告警只在 Prometheus 與 Alertmanager 裡亮燈,值班的人不會知道。這支腳本讓 Alertmanager 把告警寄成信,
#   寄到郵件伺服器。demo 用 Mailpit(輕量的測試用郵件伺服器,有網頁可看收到的信)代替行內自架的郵件伺服器;
#   設定的形狀(位址、埠、STARTTLS、帳密、寄件人與收件人)和接到行內伺服器時相同。
# 前置條件:Prometheus 與 Alertmanager 已啟動(docker compose --profile c3 up -d prometheus alertmanager)
# 用法:
#   scripts/mail-setup.sh on       備妥並啟動(可重複執行)
#   scripts/mail-setup.sh off      停掉郵件伺服器,Alertmanager 的設定還原成原本的
#   scripts/mail-setup.sh status   顯示狀態
# 會改動什麼:config/mail/ 產生兩個密碼檔(SMTP 與網頁,不進版本庫)、config/c3/smtp.pw(不進版本庫);
#   config/c3/alertmanager-generated.yml 換成郵件版(原檔備份成 .orig);重啟 alertmanager 容器;啟動 mailpit 容器。
#   注意:Control Center 的畫面若也改告警設定,會寫同一個檔案;要改設定請走這支腳本。
# 怎麼判斷成功:最後印 [mail] 完成;Alertmanager 重啟後 healthy。
# 常見失敗:Alertmanager 起不來 → docker logs alertmanager(常見:設定檔語法、smtp.pw 不存在)
# ============================================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
[ "${1:-}" = "--help" ] && { usage_from_header "$0"; exit 0; }
cd "$DEMO_DIR"

MAIL_DIR=config/mail
AM_CONF=config/c3/alertmanager-generated.yml

# 密碼雜湊用 bcrypt(Mailpit 的密碼檔支援);用 httpd 映像裡的 htpasswd 產生,不必在本機安裝。
bcrypt() { docker run --rm --entrypoint htpasswd httpd:2-alpine -nbBC 10 "$1" "$2" | tr -d '\r\n'; }

make_secret() { [ -s "$1" ] || { head -c 18 /dev/urandom | base64 | tr -d '\n=+/' > "$1"; note "產生 $1"; }; }

prepare_secrets() {
  mkdir -p "$MAIL_DIR"
  make_secret "$MAIL_DIR/smtp.pw"
  make_secret "$MAIL_DIR/ui.pw"
  # 郵件伺服器的密碼檔:每行 帳號:bcrypt 雜湊(正式環境由行內郵件伺服器管理帳號)
  bcrypt alertmanager "$(cat "$MAIL_DIR/smtp.pw")" > "$MAIL_DIR/smtp-auth"; echo >> "$MAIL_DIR/smtp-auth"
  bcrypt ops "$(cat "$MAIL_DIR/ui.pw")" > "$MAIL_DIR/ui-auth"; echo >> "$MAIL_DIR/ui-auth"
  cp "$MAIL_DIR/smtp.pw" config/c3/smtp.pw        # Alertmanager 用 smtp_auth_password_file 讀
  chmod 644 "$MAIL_DIR"/* config/c3/smtp.pw
}

turn_on() {
  need_container alertmanager "先執行:docker compose --profile c3 up -d prometheus alertmanager"
  bash scripts/make-certs.sh >/dev/null           # 補 server 憑證的 SAN(mailpit)
  say "備妥郵件伺服器的帳密檔(寄信帳號 alertmanager、網頁帳號 ops;密碼隨機產生,不進版本庫)"
  prepare_secrets
  say "啟動郵件伺服器 mailpit(SMTP 強制 STARTTLS 並要帳密;網頁 HTTPS + Basic)"
  docker compose --profile mail up -d mailpit >/dev/null 2>&1
  wait_until "mailpit 在跑" 60 docker inspect -f '{{.State.Running}}' mailpit >/dev/null || die "mailpit 沒有起來:docker logs mailpit"
  say "把 Alertmanager 的設定換成郵件版(原檔備份成 $AM_CONF.orig),重啟 alertmanager"
  [ -f "$AM_CONF.orig" ] || cp "$AM_CONF" "$AM_CONF.orig"
  cp "$MAIL_DIR/alertmanager-mail.yml" "$AM_CONF"
  docker restart alertmanager >/dev/null
  wait_healthy alertmanager >/dev/null || die "alertmanager 沒有 healthy:docker logs alertmanager"
  note "[mail] 完成:收件匣網頁 https://localhost:8025(帳號 ops,密碼在 $MAIL_DIR/ui.pw)"
}

turn_off() {
  say "停掉 mailpit,把 Alertmanager 的設定還原"
  docker compose --profile mail stop mailpit >/dev/null 2>&1 || true
  docker compose --profile mail rm -f mailpit >/dev/null 2>&1 || true
  if [ -f "$AM_CONF.orig" ]; then mv -f "$AM_CONF.orig" "$AM_CONF"; fi
  if docker ps --format '{{.Names}}' | grep -qx alertmanager; then docker restart alertmanager >/dev/null; fi
  note "[mail] 已關閉"
}

case "${1:-status}" in
  on)     turn_on ;;
  off)    turn_off ;;
  status) docker ps -a --format '{{.Names}} {{.Status}}' | grep -E '^(mailpit|alertmanager) ' || echo "沒有執行中的郵件相關容器" ;;
  *)      usage_from_header "$0"; exit 1 ;;
esac
