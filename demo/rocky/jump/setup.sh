#!/bin/sh
# 容器啟動時把 certificate 放到位(正式環境由部署流程做):
#   /etc/kafka/secrets  truststore、CA、各 .pem(公開,大家可讀;17 certificate 到期日掃這裡)
#   /etc/opmenu/bootstrap  bootstrap 的 keystore 與連線設定,只有 opbootstrap 讀得到
set -e
S=/mnt/certs
cp "$S/truststore.p12" "$S/truststore_creds" "$S/ca.pem" "$S/server.pem" "$S/client-bootstrap.pem" "$S/client-c3.pem" "$S/client-restproxy.pem" /etc/kafka/secrets/
chmod 644 /etc/kafka/secrets/*
B=/etc/opmenu/bootstrap
cp "$S/client-bootstrap.keystore.p12" "$S/client-bootstrap.pem" "$S/client-bootstrap.key" "$B/"
cat > "$B/token-bootstrap.properties" <<EOF
security.protocol=SASL_SSL
sasl.mechanism=OAUTHBEARER
sasl.login.callback.handler.class=io.confluent.kafka.clients.plugins.auth.token.TokenCertificateLoginCallbackHandler
sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required metadataServerUrls="$(. /etc/opmenu/opmenu.conf; echo "$OPMENU_MDS_URL")";
ssl.keystore.location=$B/client-bootstrap.keystore.p12
ssl.keystore.type=PKCS12
ssl.keystore.password=$(cat "$S/keystore_creds" 2>/dev/null || echo changeit)
ssl.key.password=$(cat "$S/sslkey_creds" 2>/dev/null || echo changeit)
ssl.truststore.location=/etc/kafka/secrets/truststore.p12
ssl.truststore.type=PKCS12
ssl.truststore.password=$(cat "$S/truststore_creds")
EOF
chown -R opbootstrap:opbootstrap "$B"; chmod 700 "$B"; chmod 600 "$B"/*
echo "[setup] certificate 就位;gary 讀不到 $B:"; su -s /bin/sh gary -c "ls $B" 2>&1 | head -1 || true
/usr/sbin/sshd && echo "[setup] sshd 已啟動"
