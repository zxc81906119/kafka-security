#!/usr/bin/env bash
# bind.sh add|del <User:xxx> <Role>  — 在 rocky-jump 內以 gary 的 MDS token 暫時綁定/解除 role(測試用)
CA=/etc/kafka/secrets/ca.pem; M=https://broker1:8091; CID=XyZBQ3-GTvKH2qNfP7X33A
T=$(curl -s --cacert $CA -u gary:gary-pw -H 'Accept: application/json' $M/security/1.0/authenticate | grep -o '"auth_token":"[^"]*' | cut -d'"' -f4)
B="{\"clusters\":{\"kafka-cluster\":\"$CID\"}}"
case "$1" in
  add) curl -s -o /dev/null -w 'add HTTP %{http_code}\n' --cacert $CA -H "Authorization: Bearer $T" -H 'Content-Type: application/json' -X POST -d "$B" "$M/security/1.0/principals/$2/roles/$3";;
  del) curl -s -o /dev/null -w 'del HTTP %{http_code}\n' --cacert $CA -H "Authorization: Bearer $T" -H 'Content-Type: application/json' -X DELETE -d "$B" "$M/security/1.0/principals/$2/roles/$3";;
esac
