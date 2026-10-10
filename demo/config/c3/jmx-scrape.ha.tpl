# HA 模式(scripts/ha.sh on)會複製成 jmx_scrape.yml,由 prometheus-generated.yml 的 scrape_config_files 載入。
# 監控端點的保護(對照一般企業做法:TLS + 驗證、能 mTLS 就 mTLS、密碼不寫在設定裡、網路層只開給 Prometheus):
#   - JMX exporter:HTTPS + Basic 帳密(exporter 不支援 mTLS);密碼用 password_file;用行內 CA 驗證 exporter 的憑證(不跳過驗證)
#   - blackbox exporter:HTTPS + mTLS(Prometheus 帶 monitor client 憑證)
scrape_configs:
  # job 名稱與 env 標籤照 Confluent 官方 jmx-monitoring-stacks 的慣例(kafka-broker、kafka-controller、env),
  # 官方 Grafana 儀表板的查詢直接用這些標籤,這樣儀表板可以原封不動匯入(第 26 章)
  - job_name: kafka-broker
    scrape_interval: 15s
    scheme: https
    basic_auth: { username: Prometheus, password_file: /mnt/config/jmx_exporter.pw }
    tls_config: { ca_file: /etc/tls/ca.pem }
    static_configs:
      - targets: ['broker1:7778', 'broker2:7778', 'broker3:7778']
        labels: { role: broker, env: demo }
  - job_name: kafka-controller
    scrape_interval: 15s
    scheme: https
    basic_auth: { username: Prometheus, password_file: /mnt/config/jmx_exporter.pw }
    tls_config: { ca_file: /etc/tls/ca.pem }
    static_configs:
      - targets: ['controller1:7778', 'controller2:7778', 'controller3:7778']
        labels: { role: controller, env: demo }
  # 憑證到期:用 blackbox exporter 探測各 TLS 端點「實際送出的憑證」;Prometheus 以 mTLS 呼叫 blackbox
  - job_name: tls-expiry
    metrics_path: /probe
    params: { module: [tls_connect] }
    scrape_interval: 30s
    scheme: https
    tls_config: { ca_file: /etc/tls/ca.pem, cert_file: /etc/tls/client-monitor.pem, key_file: /etc/tls/client-monitor.key }
    static_configs:
      - targets: ['broker1:9094', 'broker2:9094', 'broker3:9094', 'broker1:8091', 'broker2:8092', 'broker3:8093']
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: blackbox-exporter:9115
  # 內部 mTLS 埠(INTERNAL 9092、CONTROLLER 9093):要 client 憑證才能握手,探測用無權限的 client 憑證
  - job_name: tls-expiry-mtls
    metrics_path: /probe
    params: { module: [tls_mtls] }
    scrape_interval: 30s
    scheme: https
    tls_config: { ca_file: /etc/tls/ca.pem, cert_file: /etc/tls/client-monitor.pem, key_file: /etc/tls/client-monitor.key }
    static_configs:
      - targets: ['broker1:9092', 'broker2:9092', 'broker3:9092', 'controller1:9093', 'controller2:9093', 'controller3:9093']
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: blackbox-exporter:9115
