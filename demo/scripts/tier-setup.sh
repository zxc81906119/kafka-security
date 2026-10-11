#!/usr/bin/env bash
# ============================================================================
# tier-setup.sh — 啟用或關閉 Tiered Storage 的測試環境(第 32 章的前置):物件儲存 MinIO + broker 設定
# ----------------------------------------------------------------------------
# 白話:Tiered Storage 把 broker 上「比較舊、不會再寫」的 log segment 搬到物件儲存(S3 相容),broker 本機只留熱資料。
#   好處:本機磁碟不必照保留期買、新增 broker 要搬的資料變少。這支腳本:
#   ① 產生 MinIO 的帳密與 TLS 檔(根帳號只給管理用;Kafka 用專用帳號,權限只限這個 bucket)
#   ② 啟動 MinIO(HTTPS)、建立 bucket 與專用帳號
#   ③ 把 docker-compose.tier.yml 加進 .env 的 COMPOSE_FILE,依序重建 broker(一次一台)
#   MinIO 只是測試用的 S3 相容儲存;正式環境換成客戶行內的物件儲存(官方有認證清單),設定的形狀相同。
# 前置條件:叢集已啟動(scripts/ha.sh on)
# 用法:
#   scripts/tier-setup.sh on       備妥並啟用(可重複執行)
#   scripts/tier-setup.sh off      還原 broker 設定(依序重建),停掉 MinIO(資料卷保留)
#   scripts/tier-setup.sh status   顯示狀態
# 會改動什麼:config/tier/ 產生密碼與憑證副本(不進版本庫);.env 的 COMPOSE_FILE 多一個檔;broker 依序重建;啟動 minio 容器。
# 怎麼判斷成功:最後印 [tier] 完成;broker 日誌有 TierObjectStore 或 tier 相關啟動訊息。
# 常見失敗:broker 起不來 → docker logs broker1(常見:憑證檔不存在、bucket 不存在、endpoint 不通);
#   寫入物件 403 → 看專用帳號的 policy(mc admin policy info)
# ============================================================================
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/kafka.sh"
[ "${1:-}" = "--help" ] && { usage_from_header "$0"; exit 0; }
cd "$DEMO_DIR" || exit 1
need_ha_mode

TIER_DIR=config/tier
BUCKET=kafka-tier
KAFKA_USER=kafka-tier
MC_IMAGE=quay.io/minio/mc:latest
WIN_DIR="$(pwd -W 2>/dev/null || pwd)"        # docker 掛載用的路徑(Windows 要 C:/…)

# 產生一個隨機密碼檔(已存在就不動)。
make_secret() { [ -s "$1" ] || { head -c 24 /dev/urandom | base64 | tr -d '\n=+/' > "$1"; note "產生 $1"; }; }

# 備妥 MinIO 要用的檔案:根帳密、Kafka 專用帳密、TLS(用共用 server 憑證)、broker 用的憑證檔(accessKey=、secretKey=)。
prepare_files() {
  mkdir -p "$TIER_DIR/certs" "$TIER_DIR/secrets"
  printf 'minio-root' > "$TIER_DIR/secrets/root-user"
  make_secret "$TIER_DIR/secrets/root-password"
  make_secret "$TIER_DIR/secrets/kafka-secret"
  # MinIO 的伺服器端加密需要 KMS;Kafka 預設要求 AES256(confluent.tier.s3.sse.algorithm),沒有 KMS 時 MinIO 回 501 NotImplemented(實測)
  [ -s "$TIER_DIR/secrets/kms-key" ] || { printf 'kafka-tier-key:%s\n' "$(head -c 32 /dev/urandom | base64)" > "$TIER_DIR/secrets/kms-key"; note "產生 $TIER_DIR/secrets/kms-key"; }
  bash scripts/make-certs.sh >/dev/null                      # 補 server 憑證的 SAN(minio)
  cp certs/server.pem "$TIER_DIR/certs/public.crt"
  cp certs/server.key "$TIER_DIR/certs/private.key"
  # confluent.tier.s3.cred.file.path 要的是 properties 檔:accessKey=、secretKey=(實測:用 AWS CLI 的 [default] 格式 broker 起不來:
  #   「doesn't contain the expected properties 'accessKey' and 'secretKey'」)
  printf 'accessKey=%s\nsecretKey=%s\n' "$KAFKA_USER" "$(cat "$TIER_DIR/secrets/kafka-secret")" > "$TIER_DIR/aws-credentials"
  chmod 644 "$TIER_DIR"/certs/* "$TIER_DIR"/secrets/* "$TIER_DIR/aws-credentials"
}

# 在 demo 網路裡執行 mc(MinIO 的管理 CLI):mc_run <mc 參數…>;帶根帳號與行內 CA。
mc_run() {
  docker run --rm --network cpsec_default --entrypoint mc \
    -v "$WIN_DIR/certs/ca.pem:/root/.mc/certs/CAs/ca.crt:ro" \
    -e "MC_HOST_local=https://minio-root:$(cat "$TIER_DIR/secrets/root-password")@minio:9000" \
    "$MC_IMAGE" "$@" 2>&1
}

# 建立 bucket 與 Kafka 專用帳號:policy 只含官方文件列的四項(DeleteObject、GetObject、PutObject、GetBucketLocation),只限這個 bucket。
create_bucket_and_user() {
  cat > "$TIER_DIR/policy.json" <<EOF
{"Version":"2012-10-17","Statement":[
 {"Effect":"Allow","Action":["s3:GetBucketLocation"],"Resource":["arn:aws:s3:::$BUCKET"]},
 {"Effect":"Allow","Action":["s3:PutObject","s3:GetObject","s3:DeleteObject"],"Resource":["arn:aws:s3:::$BUCKET/*"]}]}
EOF
  mc_run mb --ignore-existing "local/$BUCKET" | tail -1
  docker run --rm --network cpsec_default --entrypoint sh \
    -v "$WIN_DIR/certs/ca.pem:/root/.mc/certs/CAs/ca.crt:ro" -v "$WIN_DIR/$TIER_DIR/policy.json:/policy.json:ro" \
    -e "MC_HOST_local=https://minio-root:$(cat "$TIER_DIR/secrets/root-password")@minio:9000" \
    -e "KUSER=$KAFKA_USER" -e "KSECRET=$(cat "$TIER_DIR/secrets/kafka-secret")" "$MC_IMAGE" \
    -c 'mc admin policy create local kafka-tier-rw /policy.json && mc admin user add local "$KUSER" "$KSECRET" && mc admin policy attach local kafka-tier-rw --user "$KUSER"' 2>&1 | tail -3
}

# .env 的 COMPOSE_FILE 是否含 tier 檔。
tier_in_env() { grep -q '^COMPOSE_FILE=.*docker-compose.tier.yml' .env; }

# 依序重建 broker(一次一台,等 healthy)。若第 4 台 broker 在跑也一併處理。
roll_brokers() {
  local n list="broker1 broker2 broker3 broker4"
  docker ps --format '{{.Names}}' | grep -qx broker5 && list="$list broker5"
  for n in $list; do
    say "重建 $n"
    docker compose --profile tier --profile sbc up -d --no-deps --force-recreate "$n" >/dev/null 2>&1
    wait_healthy "$n" >/dev/null || die "$n 重建後沒有 healthy:docker logs $n"
    note "$n 已 healthy"
  done
}

case "${1:-status}" in
  on)
    say "備妥帳密、TLS 檔與 broker 用的憑證檔(accessKey= / secretKey=)(密碼隨機產生,不進版本庫)"
    prepare_files
    say "啟動 MinIO(HTTPS,使用共用 server 憑證)"
    docker compose --profile tier up -d minio >/dev/null 2>&1
    wait_healthy minio >/dev/null || die "minio 沒有 healthy:docker logs minio"
    say "建立 bucket $BUCKET 與專用帳號 $KAFKA_USER(權限只限這個 bucket)"
    create_bucket_and_user
    if ! tier_in_env; then
      sed -i '/^COMPOSE_PATH_SEPARATOR=/d;/^COMPOSE_FILE=/d' .env
      printf 'COMPOSE_PATH_SEPARATOR=,\nCOMPOSE_FILE=docker-compose.yml,docker-compose.tier.yml\n' >> .env
    fi
    say "broker 依序重建,讀入 Tiered Storage 設定"
    roll_brokers
    note "[tier] 完成:bucket=$BUCKET,endpoint=https://minio:9000,控制台 https://localhost:9001(未對外開放埠;需要時 docker exec)" ;;
  off)
    say "還原 .env,broker 依序重建(不再載入 Tiered Storage 設定),停掉 MinIO"
    sed -i '/^COMPOSE_PATH_SEPARATOR=/d;/^COMPOSE_FILE=/d' .env
    roll_brokers
    docker compose --profile tier stop minio >/dev/null 2>&1; docker compose --profile tier rm -f minio >/dev/null 2>&1
    note "[tier] 已關閉(MinIO 資料卷 minio-data 保留;ha.sh 重建時會一併清除)" ;;
  status)
    echo "COMPOSE_FILE 含 tier:$(tier_in_env && echo 是 || echo 否)"
    docker ps --format '{{.Names}} {{.Status}}' | grep -E '^minio ' || echo "minio 沒有在跑" ;;
  *) usage_from_header "$0"; exit 1 ;;
esac
