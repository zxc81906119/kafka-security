#!/usr/bin/env bash
# 第 20 章(進階):Schema Registry 納入同一套身分與授權;KEK 管理權限;欄位級加密(CSFLE)的授權前提
# 實測結果摘要:SR 的 REST 要認證,授權跟 AD 群組走(subject 與 KEK 都是);KEK 只有 security 群組能建;
#   但 CSFLE 本身(ENCRYPT 規則)需要「企業版 + CSFLE 加購授權」,demo 的試用授權註冊會回 402,所以加密與解密沒有在這個環境驗證。
source "$(dirname "$0")/../scripts/lib-ev.sh"
ch_begin ch20 "Schema Registry 與欄位級加密(CSFLE)的授權"
DC="$DEMO_ROOT/scripts/dcurl.sh"
SR=https://schema-registry:8081
J='Content-Type: application/vnd.schemaregistry.v1+json'
# schema 本體(Avro):card_no 欄位標上 PII;一般版本不帶 ruleSet
ORDER='{"type":"record","name":"Order","namespace":"demo","fields":[{"name":"id","type":"string"},{"name":"amount","type":"int"},{"name":"card_no","type":"string","confluent:tags":["PII"]}]}'
ORDER_BODY='{"schemaType":"AVRO","schema":"{\"type\":\"record\",\"name\":\"Order\",\"namespace\":\"demo\",\"fields\":[{\"name\":\"id\",\"type\":\"string\"},{\"name\":\"amount\",\"type\":\"int\"},{\"name\":\"card_no\",\"type\":\"string\",\"confluent:tags\":[\"PII\"]}]}"}'
# 同一份 schema 加上 ENCRYPT 規則(資料合約的 domain rule):PII 標籤的欄位用 KEK orders-kek 加密
ORDER_ENC_BODY='{"schemaType":"AVRO","schema":"{\"type\":\"record\",\"name\":\"Order\",\"namespace\":\"demo\",\"fields\":[{\"name\":\"id\",\"type\":\"string\"},{\"name\":\"amount\",\"type\":\"int\"},{\"name\":\"card_no\",\"type\":\"string\",\"confluent:tags\":[\"PII\"]}]}","ruleSet":{"domainRules":[{"name":"encryptPII","kind":"TRANSFORM","type":"ENCRYPT","mode":"WRITEREAD","tags":["PII"],"params":{"encrypt.kek.name":"orders-kek"},"onFailure":"ERROR,ERROR"}]}}'
KEK_BODY='{"name":"orders-kek","kmsType":"local-kms","kmsKeyId":"demo-local-key","shared":false,"doc":"CSFLE demo (local-kms:僅測試用,正式環境接 KMS / HSM)"}'

step sr-setup "【建置】啟動 Schema Registry(profile sr):SR 用 client 憑證(CN=schema-registry)向 MDS 換 token 連 Kafka,人用 AD 帳密;授權依 AD 群組" \
  "scripts/sr-setup.sh   # 補 SR 自己的 role、SR 叢集範圍的群組 role,啟動並等授權生效" \
  'bash "$DEMO_ROOT/scripts/sr-setup.sh" 2>&1 | tail -4' '就緒'

step sr-auth "【認證】SR 的 REST 要帳密:不帶 401、密碼錯 401、AD 帳密正確 200;授權另外看 role" \
  "curl https://schema-registry:8081/subjects   # 對照:不帶帳密 / 錯密碼 / 正確" \
  'a=$(bash "$DC" $SR/subjects | tail -1); b=$(bash "$DC" -u gary:bad $SR/subjects | tail -1); c=$(bash "$DC" -u gary:gary-pw $SR/subjects | tail -1); echo "不帶帳密 → $a"; echo "密碼錯誤 → $b"; echo "gary 正確 → $c"; [ "$a$b$c" = "[HTTP 401][HTTP 401][HTTP 200]" ] && echo "判定:不帶帳密與密碼錯誤都是 401,正確帳密 200" || echo "判定:不符合"' '判定:不帶帳密與密碼錯誤都是 401'

step sr-subject "【subject 授權】授權跟 AD 群組走:orders-write(yujie)只能寫 orders. 開頭的 subject;payments 的被拒;yujie 列 subject 只看得到自己有權限的" \
  "POST /subjects/<subject>/versions   # gary(topic-admin)/ yujie(orders-write)" \
  'echo "gary 註冊 payments.events-value → $(bash "$DC" -u gary:gary-pw -X POST -H "$J" -d "$ORDER_BODY" $SR/subjects/payments.events-value/versions | tail -1)"; echo "yujie 註冊 orders.events-value → $(bash "$DC" -u yujie:yujie-pw -X POST -H "$J" -d "$ORDER_BODY" $SR/subjects/orders.events-value/versions | tail -1)"; echo "yujie 註冊 payments.events-value(新版本)→ $(bash "$DC" -u yujie:yujie-pw -X POST -H "$J" -d "$ORDER_BODY" $SR/subjects/payments.events-value/versions | tail -1)"; echo "gary 列 subject:$(bash "$DC" -u gary:gary-pw $SR/subjects | head -1)"; echo "yujie 列 subject:$(bash "$DC" -u yujie:yujie-pw $SR/subjects | head -1)"; echo "ming(沒有群組)列 subject:$(bash "$DC" -u ming:ming-pw $SR/subjects | head -1)"; y=$(bash "$DC" -u yujie:yujie-pw $SR/subjects | head -1); p=$(bash "$DC" -u yujie:yujie-pw -X POST -H "$J" -d "$ORDER_BODY" $SR/subjects/payments.events-value/versions | tail -1); [ "$p" = "[HTTP 403]" ] && [ "$y" = "[\"orders.events-value\"]" ] && echo "判定:yujie 只能碰 orders. 開頭的 subject" || echo "判定:不符合"' '判定:yujie 只能碰 orders'

step sr-kek "【KEK 授權】KEK 只有 security 群組(gary)能建;yujie(orders-write)只被授權「讀」orders-kek;ming 沒有任何 role" \
  "POST /dek-registry/v1/keks   # gary / yujie;GET /dek-registry/v1/keks/orders-kek   # yujie / ming" \
  'c=$(bash "$DC" -u gary:gary-pw -X POST -H "$J" -d "$KEK_BODY" $SR/dek-registry/v1/keks | tail -1); echo "gary 建立 KEK orders-kek → $c(200 = 新建,409 = 已存在)"; echo "yujie 建立 KEK x-kek → $(bash "$DC" -u yujie:yujie-pw -X POST -H "$J" -d "{\"name\":\"x-kek\",\"kmsType\":\"local-kms\",\"kmsKeyId\":\"k\",\"shared\":false}" $SR/dek-registry/v1/keks | tail -3 | tr "\n" " ")"; echo "yujie 讀 KEK orders-kek → $(bash "$DC" -u yujie:yujie-pw $SR/dek-registry/v1/keks/orders-kek | tail -1)"; echo "ming 讀 KEK orders-kek → $(bash "$DC" -u ming:ming-pw $SR/dek-registry/v1/keks/orders-kek | tail -2 | tr "\n" " ")"; a=$(bash "$DC" -u yujie:yujie-pw -X POST -H "$J" -d "{\"name\":\"x-kek\",\"kmsType\":\"local-kms\",\"kmsKeyId\":\"k\",\"shared\":false}" $SR/dek-registry/v1/keks | tail -1); b=$(bash "$DC" -u yujie:yujie-pw $SR/dek-registry/v1/keks/orders-kek | tail -1); m=$(bash "$DC" -u ming:ming-pw $SR/dek-registry/v1/keks/orders-kek | tail -1); [ "$a$b$m" = "[HTTP 403][HTTP 200][HTTP 403]" ] && echo "判定:只有被授權的人能建或讀 KEK" || echo "判定:不符合"' '判定:只有被授權的人能建或讀 KEK'

step sr-csfle "【CSFLE】註冊帶 ENCRYPT 規則的 schema:試用授權回 402「Both enterprise and add-on CSFLE licenses are required」——欄位級加密需要加購授權,這個環境無法驗證加密與解密" \
  "POST /subjects/orders.events-value/versions   # body 帶 ruleSet(ENCRYPT)" \
  'bash "$DC" -u gary:gary-pw -X POST -H "$J" -d "$ORDER_ENC_BODY" $SR/subjects/orders.events-value/versions' 'add-on CSFLE licenses are required'

step sr-raw "【上線前的檢查習慣】欄位到底有沒有被加密?不看 producer 有沒有報錯,直接讀 topic 的原始位元組:yujie 用 Avro 寫一筆含卡號的訂單,再以一般 consumer 讀原始位元組——這個環境會看到明文(沒有 CSFLE 授權、規則不存在);正式環境看到明文就代表加密規則沒生效" \
  "scripts/sr-raw-check.sh   # ① kafka-avro-console-producer 寫入 ② kafka-console-consumer 讀原始位元組" \
  'bash "$DEMO_ROOT/scripts/sr-raw-check.sh" 2>&1' '判定:topic 裡的卡號是明文'

ch_end
