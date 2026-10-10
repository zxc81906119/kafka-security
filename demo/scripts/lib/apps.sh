#!/usr/bin/env bash
# ============================================================================
# lib/apps.sh — 執行 apps/ 底下的 Java 單檔程式(第 25 章起的應用開發 Lab)
# ----------------------------------------------------------------------------
# 前置:先 source lib/common.sh。
# 為什麼要這樣做:cp-server 映像裡的 Java 是精簡版,沒有編譯器,不能 `java Foo.java`。
#   所以用 JDK 映像(eclipse-temurin:21-jdk,官方映像)執行,Kafka 的 jar 從 cp-server 映像複製到一個 Docker volume(只做一次)。
#   這樣讀者不必在自己的電腦安裝 Java,程式碼也是「一個檔案一個 main」,從頭讀到尾就看得懂。
# 認證:程式讀 /clients/token-bootstrap.properties(super user 的憑證換 token),重點是可靠性行為,不是授權;
#   應用程式正式上線時應使用自己的身分與最小權限(見第 5 到 14 章)。
# ============================================================================
APP_IMAGE="${APP_IMAGE:-eclipse-temurin:21-jdk}"
APP_JARS_VOLUME="${APP_JARS_VOLUME:-cpsec-kafka-jars}"
APP_NETWORK=cpsec_default
APP_HOST_DIR="$(cd "$DEMO_DIR" && pwd -W 2>/dev/null || pwd)"      # 給 docker -v 用的主機路徑

# apps_prepare:確認 JDK 映像與 Kafka jar 的 volume 都在;沒有就建立(第一次約 1 到 2 分鐘,需要網路下載 JDK 映像)。
apps_prepare() {
  if ! docker image inspect "$APP_IMAGE" >/dev/null 2>&1; then
    say "第一次使用:下載 JDK 映像 $APP_IMAGE(官方映像,約 740 MB),之後不會再下載"
    docker pull "$APP_IMAGE" >/dev/null || die "下載 $APP_IMAGE 失敗"
  fi
  if ! docker run --rm -v "$APP_JARS_VOLUME:/jars:ro" --entrypoint sh "$APP_IMAGE" -c 'ls /jars/kafka/*.jar >/dev/null 2>&1'; then
    say "第一次使用:把 Kafka 的 jar 從 cp-server 映像複製到 Docker volume $APP_JARS_VOLUME(約 400 MB)"
    docker volume create "$APP_JARS_VOLUME" >/dev/null
    docker run --rm --user 0 -v "$APP_JARS_VOLUME:/dst" --entrypoint bash confluentinc/cp-server:8.3.2 \
      -c 'rm -rf /dst/kafka; cp -rL /usr/share/java/kafka /dst/' || die "複製 Kafka jar 失敗"
  fi
}

# run_app <名稱> <程式> [參數...]:在前景執行 apps/<程式>.java,容器取名 <名稱>(之後可以用 docker kill <名稱> 強制中止)。
#   環境變數 APP_ENV_ARGS 可以放額外的 docker 參數(例如 "-e BOOTSTRAP=…"),APP_JAVA_OPTS 放額外的 JVM 參數(例如 -javaagent:…,第 27 章用來掛 OpenTelemetry agent)。
run_app() {
  local name="$1" prog="$2"; shift 2
  docker rm -f "$name" >/dev/null 2>&1
  docker run --rm --name "$name" --network "$APP_NETWORK" \
    -v "$APP_HOST_DIR/certs:/etc/kafka/secrets:ro" -v "$APP_HOST_DIR/config/clients:/clients:ro" \
    -v "$APP_HOST_DIR/apps:/apps:ro" -v "$APP_JARS_VOLUME:/jars:ro" -v "$APP_HOST_DIR/config/observability:/otel:ro" \
    -e CLASSPATH="/jars/kafka/*" ${APP_ENV_ARGS:-} \
    --entrypoint java "$APP_IMAGE" ${APP_JAVA_OPTS:-} "/apps/$prog.java" "$@" 2>&1 | grep -v -E '^SLF4J|^WARNING|^Note:'
}
