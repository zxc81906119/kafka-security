#!/usr/bin/env bash
# ============================================================================
# ch08-shared-cert.sh — 第 8 章(選修):為什麼「全元件共用一張憑證」不能拿來做 mTLS 身分 —— 同一個 DN 只有一個 principal
# ----------------------------------------------------------------------------
# 白話:若 Control Center 與 REST Proxy 共用同一張憑證,Kafka 眼中它們是同一個 principal,
#       無法分開授權、audit log 分不出是誰、一台被入侵就全部淪陷。對照之下,每個元件各用一張不同 DN 的 client 憑證就能分別授權。
# 前置條件:環境已建好(MDS 在 broker1:8091);Docker 可用(用 alpine/openssl 容器看憑證);certs/ 底下有 server.pem 與各元件 client 憑證
# 用法:
#   ./demo.sh 8                       經由講解控制台跑這一章
#   ./scenarios/ch08-shared-cert.sh   直接跑(DEMO_PAUSE=0 不暫停)
# 會改動什麼:看不出有改動(只讀取憑證、向 MDS 查詢 principal)
# 怎麼判斷成功:每一步印『✔ 符合預期』,最後一行『第 08 章完成(失敗 0 項)』
# 實測結果摘要:
#   共用憑證:C3 與 REST Proxy 用 server.pem 向 MDS 認證,得到同一個身分(含 kafka.demo.local)
#   各自憑證:C3 憑證得到 principal = "c3"、REST Proxy 憑證得到 principal = "restproxy"
#   結論:共用 server 憑證只做加密;服務身分用 SCRAM(帳號密碼,免憑證);平台元件(C3、REST Proxy)需要各自的 client 憑證
# ============================================================================
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch08 "為什麼不用共用憑證做 mTLS 身分"

step shared-dn "【客戶的做法】Control Center 與 REST Proxy 共用同一張憑證(同一個 DN、同一把 private key)" \
  "openssl x509 -in shared-server.pem -noout -subject -ext subjectAltName" \
  'docker run --rm -v "$(cd $DEMO_ROOT && pwd -W)/certs:/certs:ro" --entrypoint sh alpine/openssl -c "openssl x509 -in /certs/server.pem -noout -subject; openssl x509 -in /certs/server.pem -noout -ext subjectAltName | tr \",\" \"\n\" | head -5"' 'subject'

step shared-c3 "【以共用憑證當身分(1)】C3 出示「共用憑證」向 MDS 認證" \
  "curl --cert shared-server.pem https://broker1:8091/security/1.0/authenticate   # 身分 = 憑證 DN" \
  'bash "$DEMO_ROOT/scripts/mds-token-sub.sh" server' 'kafka.demo.local'
step shared-rp "【以共用憑證當身分(2)】REST Proxy 也出示「同一張共用憑證」" \
  "curl --cert shared-server.pem https://broker1:8091/security/1.0/authenticate" \
  'bash "$DEMO_ROOT/scripts/mds-token-sub.sh" server' 'kafka.demo.local'
echo "    ⇒ 兩個元件在 Kafka 眼中是「同一個人」:無法分別授權(最小權限做不到)、audit log 分不出是誰、一台被入侵 = 全部淪陷"

step sep-c3 "【對照:每元件各一張(不同 DN)】C3 的憑證 CN=c3" \
  "curl --cert client-c3.pem https://broker1:8091/security/1.0/authenticate" \
  'bash "$DEMO_ROOT/scripts/mds-token-sub.sh" client-c3' 'principal = "c3"'
step sep-rp "【對照】REST Proxy 的憑證 CN=restproxy → 不同 principal,可分別授權" \
  "curl --cert client-restproxy.pem https://broker1:8091/security/1.0/authenticate" \
  'bash "$DEMO_ROOT/scripts/mds-token-sub.sh" client-restproxy' 'principal = "restproxy"'
echo "    ⇒ 結論:共用 server 憑證「只做加密」;服務身分用 SCRAM(帳號密碼,免憑證);平台元件(C3、REST Proxy)需要各自的 client 憑證"
ch_end
