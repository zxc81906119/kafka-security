# REST Proxy 設多台 MDS 的實際行為(2026-10-06,demo)

設定(docker-compose.yml):`confluent.metadata.bootstrap.server.urls=https://broker1:8091,https://broker2:8092`(REST Proxy 轉送身分、換 token),Kafka client 登入的 `metadataServerUrls` 同樣兩台。
腳本:`run.sh`(階段 0–2;被我設的 timeout 截斷)與 `run-part2.sh`(階段 3–4);輸出合併在 `run.log`。
方法:legacy-orders(client 憑證,走 `/impersonate`)與 gary(Basic)交錯送 POST /topics/orders.events,記錄狀態碼與耗時,並統計各 broker 的 MDS 收到 restproxy 的請求數。

## 結果

| 階段 | 結果 |
|---|---|
| 兩台都在 | 全 200,幾十毫秒;`/impersonate` 分散在兩台(broker1 3 次、broker2 1 次),**不是固定打列表第一台** |
| 停 broker1(設定的第一台) | 全 200;**第一個受影響的請求 ≈ 8 秒**,之後恢復幾十毫秒;之後的 `/impersonate` 全落在 broker2 |
| broker1 仍停著時重啟 REST Proxy | 正常啟動、healthy;啟動後全 200(含一次 ≈ 8 秒的 Basic 請求);Kafka client 登入也走得通 |
| 停 broker2 | 全 200;同樣第一個請求 ≈ 8 秒,之後 `/impersonate` 全落在 broker1 |
| 全部恢復 | 全 200,兩台都再收到請求 |

## 結論
1. **REST Proxy 設多台 MDS 時,會自動換台,不需要在 MDS 前面放 LB。** 這也代表 REST Proxy → MDS 這段可以不經 LB,避開「L7 終止 TLS 會讓 `/impersonate` 的憑證身分失效」的問題(見 `../lb-nginx/FINDINGS.md`)。
2. 切換的代價是第一個請求約 8 秒(原因沒有查,可能是連線逾時或重試設定;未驗證)。
3. 人(Basic)與機器(憑證)兩條路徑都有效。

## 限制(沒驗證)
- 這裡的「停掉」是 docker stop(連線被拒絕或重設)。MDS 若是 hung、或防火牆直接丟封包(沒有拒絕回應),切換可能遠比 8 秒久。
- REST Proxy 自己的 Kafka client token 約 1 小時到期、需要重新換取;MDS 其中一台掛著時的更新沒有等到那個時間點驗證。
- 8 秒延遲有沒有可調的設定,沒查。
