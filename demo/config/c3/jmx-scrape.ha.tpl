# HA 模式(scripts/ha.sh on)會複製成 jmx_scrape.yml,由 prometheus-generated.yml 的 scrape_config_files 載入。
scrape_configs:
  - job_name: kafka-jmx
    scrape_interval: 15s
    static_configs:
      - targets: ['broker1:7778', 'broker2:7778', 'broker3:7778']
        labels: { role: broker }
      - targets: ['controller1:7778', 'controller2:7778', 'controller3:7778']
        labels: { role: controller }
  # 第 23 章:用 blackbox exporter 探測各 TLS 端點「實際送出的憑證」的到期時間
  - job_name: tls-expiry
    metrics_path: /probe
    params: { module: [tls_connect] }
    scrape_interval: 30s
    static_configs:
      - targets: ['broker1:9094', 'broker2:9094', 'broker3:9094', 'broker1:8091', 'broker2:8092', 'broker3:8093']
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: blackbox-exporter:9115
