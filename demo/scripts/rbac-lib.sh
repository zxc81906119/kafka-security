# 共用函式:透過 MDS REST 建立/移除 role binding(由 scripts/*.sh source)
KAFKA_CLUSTER_ID="${KAFKA_CLUSTER_ID:-XyZBQ3-GTvKH2qNfP7X33A}"
DIR_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_rbac_call() { # <bind|unbind> mode who principal role [rtype rname ptype]
  local act="$1" mode="$2" who="$3" principal="$4" role="$5" rtype="${6:-}" rname="${7:-}" ptype="${8:-LITERAL}"
  local enc="${principal/:/%3A}" method path body
  if [ "$act" = bind ]; then method=POST; else method=DELETE; fi
  if [ -n "$rtype" ]; then   # 資源型 role(DeveloperRead/Write 等):綁定在特定資源
    path="/security/1.0/principals/$enc/roles/$role/bindings"
    body="{\"scope\":{\"clusters\":{\"kafka-cluster\":\"$KAFKA_CLUSTER_ID\"}},\"resourcePatterns\":[{\"resourceType\":\"$rtype\",\"name\":\"$rname\",\"patternType\":\"$ptype\"}]}"
  else                        # 叢集型 role(SystemAdmin 等)
    path="/security/1.0/principals/$enc/roles/$role"
    body="{\"clusters\":{\"kafka-cluster\":\"$KAFKA_CLUSTER_ID\"}}"
  fi
  local out; out=$("$DIR_LIB/mds.sh" "$mode" "$who" "$method" "$path" "$body" 2>&1 | tr -d '\r' | tail -2 | tr '\n' ' ')
  echo "  $act $principal $role ${rtype:+$rtype:$rname($ptype)} -> $out"
}
rbac_bind()   { _rbac_call bind   "$@"; }
rbac_unbind() { _rbac_call unbind "$@"; }
