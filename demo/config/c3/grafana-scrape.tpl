# scripts/grafana.sh on 會複製成 grafana_scrape.yml,由 prometheus-generated.yml 的 scrape_config_files 載入。
# 監控端點的保護和第 22 章一致:能 mTLS 就 mTLS(node_exporter、kafka_exporter),其餘 HTTPS + Basic(Grafana 的 /metrics)。
scrape_configs:
  - job_name: node
    scrape_interval: 15s
    scheme: https
    tls_config: { ca_file: /etc/tls/ca.pem, cert_file: /etc/tls/client-monitor.pem, key_file: /etc/tls/client-monitor.key }
    static_configs:
      - targets: ['node-exporter:9100']
        labels: { env: demo }
  - job_name: kafka-exporter
    scrape_interval: 30s
    scheme: https
    tls_config: { ca_file: /etc/tls/ca.pem, cert_file: /etc/tls/client-monitor.pem, key_file: /etc/tls/client-monitor.key }
    static_configs:
      - targets: ['kafka-exporter:9308']
        labels: { env: demo }
  - job_name: grafana
    scrape_interval: 30s
    scheme: https
    basic_auth: { username: Prometheus, password_file: /mnt/config/grafana_metrics.pw }
    tls_config: { ca_file: /etc/tls/ca.pem }
    static_configs:
      - targets: ['grafana:3000']
