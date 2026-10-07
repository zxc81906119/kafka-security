#!/usr/bin/env bash
# Rocky Linux 9 jump host 的功能測試:在 rocky-jump 容器裡以作業系統使用者 gary 執行選單(vm 後端)。
# 事前:docker compose -f rocky/compose.yml up -d --build(在 demo/ 目錄);demo cluster 在跑。
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1   # Git Bash 會把 /bin/bash 之類的參數轉成 Windows 路徑
J=rocky-jump
# 以 gary 執行一個指令(保留環境變數;gary 的登入殼層是選單,所以測試時指定 bash)
asg() { docker exec -e OPMENU_PASS=gary-pw -e OPMENU_YES=1 -e OPMENU_TICKET=CHG-2026-0050 -e OPMENU_REASON=test "$@" "$J" su -s /bin/bash -p gary -c "cd /tmp && /opt/opmenu/opmenu.sh $RUN" </dev/null 2>&1 | grep -v '^$'; }
run() { local n="$1"; shift; RUN="--run $*"; echo; echo "===== $*"; asg | tail -"$n"; }

echo "===== 環境:jump host 能 ssh 到 node、node 的假服務在跑"
docker exec "$J" su - gary -s /bin/bash -c 'ssh node1 "hostname; systemctl is-active confluent-server confluent-control-center"' 2>&1 | tail -3
echo "===== 作業系統層:gary 讀不到 bootstrap certificate;sudo 只開放包裝腳本"
docker exec "$J" su -s /bin/bash gary -c 'ls /etc/opmenu/bootstrap; sudo -n -l' 2>&1 | tail -4
echo "===== 登入殼層:su - gary 直接進選單(送 0 離開)"
echo 0 | docker exec -i -e OPMENU_PASS=gary-pw "$J" su - gary 2>&1 | grep -E "操作者|=== Kafka|離開" | head -3

run 4 11
run 3 12
run 3 13 demo-
run 3 14 orders.events
run 2 16
run 4 17
run 1 18
run 2 21 node1:confluent-server
run 1 22 node1:confluent-control-center
run 3 23 node1:confluent-server 10
run 1 24 node1 14
run 1 24 node1 3
run 1 31 rk.events 1
run 1 32 rk.events 3600000
run 2 34 svc-rktest rk.
run 4 41 User:svc-rktest
run 1 35 svc-rktest
run 2 36 rk-nogroup earliest
run 1 42 add orders-read DeveloperRead Topic rk.
run 1 42 remove orders-read DeveloperRead Topic rk.
run 1 43 20
run 1 33 rk.events
run 3 91 kafka-topics --list
run 1 91 kafka-delete-records --help
echo; echo "===== 收尾:刪測試帳號(用 bootstrap)"; RUN="--run 91 kafka-configs --alter --delete-config SCRAM-SHA-512 --entity-type users --entity-name svc-rktest"; asg | tail -1
echo; echo "===== 冒用測試:環境變數給 OPMENU_USER=ming + ming 的密碼;設定檔 OPMENU_USER_FROM_OS=1 蓋過環境變數,身分仍是 gary → 應 登入失敗"
docker exec -e OPMENU_USER_FROM_OS=0 -e OPMENU_USER=ming -e OPMENU_PASS=ming-pw -e OPMENU_YES=1 -e OPMENU_TICKET=CHG-2026-0050 "$J" su -s /bin/bash -p gary -c "cd /tmp && /opt/opmenu/opmenu.sh --run 31 rk.deny 1" </dev/null 2>&1 | grep -v '^$' | tail -1
echo; echo "===== sshd 旁路:ssh gary@jump id(應:進選單、不執行 id;紀錄 BYPASS_ATTEMPT)"
docker exec "$J" su -s /bin/bash gary -c 'ssh -o BatchMode=yes gary@localhost id' </dev/null 2>&1 | grep -v '^$' | tail -2
echo "===== sshd 旁路:scp 與 sftp(應:失敗)"
docker exec "$J" su -s /bin/bash gary -c 'scp -o BatchMode=yes /etc/hostname gary@localhost:/tmp/x; echo "scp rc=$?"; sftp -o BatchMode=yes gary@localhost </dev/null; echo "sftp rc=$?"' 2>&1 | grep -E "rc=|denied|closed|refused|選單" | tail -4
echo "===== sshd 旁路:轉埠(開通道後真的連一次;應:administratively prohibited,連線失敗)"
docker exec "$J" su -s /bin/bash gary -c 'ssh -o BatchMode=yes -L 19999:broker1:9094 -N gary@localhost 2>/tmp/fwd.err & p=$!; sleep 2; curl -sk --max-time 5 -o /dev/null -w "經通道連 broker:HTTP %{http_code}\n" https://localhost:19999/; kill $p; sleep 1; grep -o "administratively prohibited" /tmp/fwd.err | head -1' </dev/null 2>&1 | tail -2

echo; echo "===== ssh 認證開關:password 模式(用登入選單的 AD 密碼 ssh 到 node,金鑰停用)"
docker exec "$J" sh -c "sed 's#^OPMENU_SSH_AUTH=.*##' /etc/opmenu/opmenu.conf > /tmp/pw.conf; echo OPMENU_SSH_AUTH=password >> /tmp/pw.conf"
docker exec -e OPMENU_CONF=/tmp/pw.conf -e OPMENU_PASS=gary-pw -e OPMENU_YES=1 -e OPMENU_TICKET=CHG-2026-0051 "$J" su -s /bin/bash -p gary -c "cd /tmp && /opt/opmenu/opmenu.sh --run 22 node1:confluent-control-center" </dev/null 2>&1 | grep -v '^$' | tail -1
echo "===== ssh 認證開關:password 模式但 node 密碼不同(node 沒接 AD)→ 應 失敗;測完還原"
docker exec rocky-node1 sh -c "echo 'gary:other-pw' | chpasswd"
docker exec -e OPMENU_CONF=/tmp/pw.conf -e OPMENU_PASS=gary-pw -e OPMENU_YES=1 "$J" su -s /bin/bash -p gary -c "cd /tmp && /opt/opmenu/opmenu.sh --run 16" </dev/null 2>&1 | grep -v '^$' | tail -2
docker exec rocky-node1 sh -c "echo 'gary:gary-pw' | chpasswd"
echo "===== ControlMaster:同一 session 內連兩次 node,第二次重用連線(看 ssh -O check)"
docker exec "$J" su -s /bin/bash gary -c 'rm -rf /tmp/cm; mkdir -m 700 /tmp/cm; o="-o ControlMaster=auto -o ControlPath=/tmp/cm/%C -o ControlPersist=60"; ssh $o -o BatchMode=yes node1 true; ssh $o -O check node1 2>&1 | head -1; ssh $o -O exit node1 2>&1 | head -1'

echo; echo "===== MDS 失效轉移:第一台填不存在的主機(broker9),應自動用第二台"
docker exec "$J" sh -c "sed 's#^OPMENU_MDS_URL=.*#OPMENU_MDS_URL=\"https://broker9:8091,https://broker1:8091\"#' /etc/opmenu/opmenu.conf > /tmp/failover.conf"
docker exec -e OPMENU_CONF=/tmp/failover.conf -e OPMENU_PASS=gary-pw "$J" su -s /bin/bash -p gary -c "cd /tmp && /opt/opmenu/opmenu.sh --run 41 User:svc-orders" </dev/null 2>&1 | grep -v '^$' | tail -2
echo "===== MDS 失效轉移:bootstrap 包裝腳本(暫改設定檔,測完還原)"
sed -i 's#^OPMENU_MDS_URL=.*#OPMENU_MDS_URL='"'"'https://broker9:8091,https://broker1:8091'"'"'#' rocky/opmenu.conf
docker exec "$J" su -s /bin/bash gary -c 'sudo -n -u opbootstrap /usr/local/sbin/opmenu-bootstrap mds POST /security/1.0/lookup/principals/User%3Agary/roleNames "{\"clusters\":{\"kafka-cluster\":\"XyZBQ3-GTvKH2qNfP7X33A\"}}"' 2>&1 | tail -2
sed -i 's#^OPMENU_MDS_URL=.*#OPMENU_MDS_URL='"'"'https://broker1:8091,https://broker2:8092'"'"'#' rocky/opmenu.conf
echo "===== MDS 全部連不上(應:登入失敗,不是當掉)"
docker exec "$J" sh -c "sed 's#^OPMENU_MDS_URL=.*#OPMENU_MDS_URL=\"https://broker9:8091\"#' /etc/opmenu/opmenu.conf > /tmp/dead.conf"
docker exec -e OPMENU_CONF=/tmp/dead.conf -e OPMENU_PASS=gary-pw "$J" su -s /bin/bash -p gary -c "cd /tmp && /opt/opmenu/opmenu.sh --run 11" </dev/null 2>&1 | grep -v '^$' | tail -2

echo; echo "===== 紀錄(容器內 /var/log/opmenu/opmenu.log)"; docker exec "$J" tail -34 /var/log/opmenu/opmenu.log
