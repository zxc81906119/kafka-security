# LB 實驗結果(2026-10-06,nginx 1.27 模擬 F5)

目的:客戶用 F5。legacy app 的 mTLS 身分(client 憑證 CN)經過 LB 後,REST Proxy 還認不認得。
環境:demo 的 REST Proxy(`ssl.client.authentication=REQUESTED`,多協定處理器)、legacy-orders 綁 `orders.` 的 DeveloperWrite、legacy-other 沒有任何 role。
腳本:`run.sh`(legacy app → REST Proxy)、`run-mds.sh`(REST Proxy → MDS);原始輸出 `run.log`、`run-mds.log`。

## 結果

| 情境(nginx 設定) | 對應的 F5 做法 | legacy-orders | legacy-other | 不帶憑證 |
|---|---|---|---|---|
| 直連(基線) | — | 200 | 403 | 401 |
| L4 TCP 透傳(`stream`) | Performance (Layer 4) / FastL4 | **200** | **403** | 401;自簽偽造憑證 TLS 被拒 |
| L7 終止 TLS,連後端不帶憑證 | Client SSL profile + 預設 Server SSL profile | **401** | — | 401 |
| L7 終止 TLS,憑證資訊放 header 轉給後端 | iRule 插入 header | **401**(REST Proxy 不認 header) | — | — |
| L7 終止 TLS,LB 用固定一張 client 憑證連後端 | Server SSL profile 設 client 憑證 | 200 | **200(應該是 403)** | **200(應該是 401)** |

REST Proxy → MDS(restproxy 憑證換 token,`/security/1.0/authenticate`):直連 200、L4 透傳 200、L7 終止 TLS **401**。

## 結論
1. **要保留 legacy app 的 mTLS 身分,LB 必須是 L4 透傳。** L4 下 403、401、偽造憑證被拒都和直連一致。
2. **L7 終止 TLS 會讓這個設計失效**:REST Proxy 看不到 app 的憑證;放 header 不行(實測不認;未找到官方支援)。
3. **「LB 用一張固定憑證連後端」是危險的修法**:所有呼叫者都變成那張憑證的身分,沒權限的 app 也能寫入,連不帶憑證的人都通過;audit 只會看到那個身分。
4. **REST Proxy → MDS 這段同樣不能放 L7 終止 TLS**(`/authenticate`、`/impersonate` 認的是憑證身分)。
5. **L4 透傳時 server 憑證的 SAN 必須包含 LB 的主機名**(實測:用 LB 名稱連,TLS 主機名驗證失敗)。共用 server 憑證要加 LB 名稱。

## 方法上的陷阱(實驗中踩到)
- nginx 預設 `proxy_ssl_session_reuse on`,不同 server 區塊對同一個 `proxy_pass https://restproxy:8086` 共用 upstream,**TLS session 被復用,後端沿用最先建立連線的憑證身分**,結果會隨測試順序變(第一次跑 L7-C 全 401、第二次 L7-A 不帶憑證卻 200)。關掉(`proxy_ssl_session_reuse off`)後結果穩定。這是依結果推測的原因,沒有直接抓封包證明。**F5 的 Server SSL profile 有沒有類似的 session 復用行為未驗證,要問客戶的 F5 管理者。**

## 還沒做
- 兩台 REST Proxy + sticky session 的 v2 consumer 行為(官方文件說需要 sticky,未實測)。
- REST Proxy 的 `metadataServerUrls` 設多台 MDS 時的實際切換行為(demo 設了兩台但沒停 MDS 測過)。
- F5 本身的行為(以上都是 nginx 的邏輯驗證):虛擬伺服器類型、persistence、TCP idle timeout、SNAT 對來源 IP 的影響、iRule 能否轉送憑證。

## 收掉
`docker compose -f spike/lb-nginx/docker-compose.yml down`(在 demo/ 目錄)
