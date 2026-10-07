#!/usr/bin/env bash
# REST Proxy → MDS 這段經過 LB:用 restproxy 的 client 憑證向 MDS 換 token(GET /security/1.0/authenticate)。在 demo/ 目錄執行。只印狀態碼,不印 token。
export MSYS_NO_PATHCONV=1; cd "$(dirname "$0")/../.."; D="$(pwd -W 2>/dev/null || pwd)"
m() { local label="$1" port="$2" who="$3"; local a=(-s --cacert /certs/ca.pem -o /dev/null -w "[HTTP %{http_code}]" -H "Accept: application/json"); [ "$who" != none ] && a+=(--cert "/certs/client-$who.pem" --key "/certs/client-$who.key")
  [ "$port" != direct ] && a+=(--connect-to "broker1:8091:lb-nginx:$port")
  printf '%-40s' "$label"; docker run --rm --network cpsec_default -v "$D/certs:/certs:ro" --entrypoint curl curlimages/curl:latest "${a[@]}" https://broker1:8091/security/1.0/authenticate; echo; }
m "[0] 直連 MDS,restproxy 憑證" direct restproxy
m "[0] 直連 MDS,不帶憑證" direct none
m "[1] L4 透傳,restproxy 憑證" 9091 restproxy
m "[2] L7 終止 TLS,restproxy 憑證" 9092 restproxy
