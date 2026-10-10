# ============================================================================
# rbac-lib.sh — 共用函式庫:透過 MDS REST 建立/移除 role binding(由 scripts/*.sh 以 source 載入,不要直接執行)
# ----------------------------------------------------------------------------
# 白話:要替某個帳號或群組綁定/解除 RBAC 角色,每次都得組一大段 MDS REST 的 JSON。這個函式庫把它包成兩個函式,
#   讓其他腳本一行就能授權或收回權限。
# 用法(在別的腳本裡):
#   source scripts/rbac-lib.sh
#   rbac_bind   <mode> <who> <principal> <role> [資源類型 資源名稱 [LITERAL|PREFIXED]]
#   rbac_unbind <mode> <who> <principal> <role> [資源類型 資源名稱 [LITERAL|PREFIXED]]
#     mode + who = 以誰的身分呼叫 MDS(傳給 scripts/mds.sh):cert bootstrap(client 憑證)或 basic gary:gary-pw(AD 帳密)
#     principal  = User:xxx 或 Group:xxx
#     有給資源類型 = 資源型角色(DeveloperRead/Write 等),綁在特定資源,patternType 預設 LITERAL;
#     沒給 = 叢集型角色(SystemAdmin 等),綁在整個 Kafka 叢集
#   環境變數 KAFKA_CLUSTER_ID 可覆蓋 Kafka 叢集 ID(預設 XyZBQ3-GTvKH2qNfP7X33A)。
# 會改動什麼:呼叫 MDS 新增或刪除 role binding(source 本身什麼都不做)。
# 怎麼判斷成功:每次呼叫印一行「  bind|unbind <principal> <role> <資源> -> <MDS 回應最後兩行,含 [HTTP 狀態碼]>」,
#   2xx 為成功。注意函式本身永遠回傳成功,要判斷結果得看這行輸出。
# ============================================================================
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
