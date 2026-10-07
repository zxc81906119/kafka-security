#!/usr/bin/env bash
# 測 ticket 模式(OPMENU_TICKET_MODE)與檢查方式(OPMENU_TICKET_CHECK):
#  required+format 格式錯被擋;optional 空 ticket 可過;none 不問 ticket;http 向假的開單系統查(approved / open / 不存在)。
cd "$(dirname "$0")"
G=(OPMENU_USER=gary OPMENU_PASS=gary-pw OPMENU_YES=1)
run(){ local n="$1"; shift; echo; echo "===== $*"; env "${G[@]}" "$@" timeout 180 ./opmenu.sh --run "${RUN[@]}" </dev/null 2>&1 | grep -v "^$" | tail -"$n"; }

RUN=(31 opm.tk 1); run 1 OPMENU_TICKET=CHG-2026-0020
echo; echo "== required:格式錯(應:ticket 不接受)"; RUN=(31 opm.tk2 1); run 1 OPMENU_TICKET=bad OPMENU_TICKET_MODE=required
echo; echo "== optional:空 ticket(應:OK,ticket=-)"; RUN=(32 opm.tk 60000); run 1 OPMENU_TICKET= OPMENU_TICKET_MODE=optional
echo; echo "== none:不問 ticket(應:OK,ticket=-)"; RUN=(32 opm.tk 70000); run 1 OPMENU_TICKET_MODE=none

# http:用容器起一個假的開單系統(主機的 python 可能是 Windows 的空殼,所以用容器)
T="$PWD/.tkfake"; rm -rf "$T"; mkdir -p "$T/changes"; echo '{"id":"CHG-2026-0001","status":"approved"}' > "$T/changes/CHG-2026-0001"; echo '{"id":"CHG-2026-0002","status":"open"}' > "$T/changes/CHG-2026-0002"
TW="$(cd "$T" && { pwd -W 2>/dev/null || pwd; })"
MSYS_NO_PATHCONV=1 docker run -d --rm --name opmenu-tkfake -p 8099:8000 -v "$TW:/srv:ro" python:3-alpine python -m http.server -d /srv 8000 >/dev/null; sleep 3
curl -s -o /dev/null -w "假開單系統回應:HTTP %{http_code}\n" http://localhost:8099/changes/CHG-2026-0001
H=(OPMENU_TICKET_CHECK=http OPMENU_TICKET_URL=http://localhost:8099/changes)
echo; echo "== http:已核准(應:OK)"; RUN=(32 opm.tk 80000); run 1 "${H[@]}" OPMENU_TICKET=CHG-2026-0001
echo; echo "== http:未核准(應:尚未核准)"; run 2 "${H[@]}" OPMENU_TICKET=CHG-2026-0002
echo; echo "== http:不存在(應:查不到)"; run 2 "${H[@]}" OPMENU_TICKET=CHG-2026-0003
docker rm -f opmenu-tkfake >/dev/null 2>&1; rm -rf "$T"

RUN=(33 opm.tk); run 1 OPMENU_TICKET=CHG-2026-0020
echo; echo "===== 紀錄"; tail -9 log/opmenu.log
