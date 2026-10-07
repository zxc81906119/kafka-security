#!/usr/bin/env bash
# 第 8 章(選修):為什麼「全元件共用一張憑證」不能拿來做 mTLS 身分 —— 同一個 DN 只有一個 principal
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
