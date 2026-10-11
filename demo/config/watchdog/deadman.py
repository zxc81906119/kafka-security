#!/usr/bin/env python3
# ============================================================================
# deadman.py — 外部看門狗(dead man's switch):收 Alertmanager 的 Watchdog 心跳,太久沒收到就判定「監控鏈路失效」
# ----------------------------------------------------------------------------
# 白話:Prometheus 有一條永遠在觸發的告警 Watchdog,Alertmanager 每分鐘把它送來這裡。只要 Prometheus、Alertmanager、
#   兩者之間的設定與網路任何一處壞掉,心跳就會停;這支程式發現「超過 TIMEOUT_SEC 秒沒收到」就把狀態改成 FAILED。
#   在 demo 裡它代表行內既有的企業監控平台(正式環境由那個平台負責通知值班人員,這支程式不需要部署)。
# 端點(HTTPS,Basic 認證):
#   POST /heartbeat   Alertmanager 的 webhook(只接受帳密正確、而且內容含 Watchdog 告警的請求)
#   GET  /status      目前狀態 JSON:state(WAITING / OK / FAILED)、上次心跳距今秒數、狀態變化紀錄
# 環境變數:TIMEOUT_SEC(預設 180)、USER_FILE(帳號:密碼,一行)、TLS_CERT、TLS_KEY、PORT(預設 9443)
# 只用 Python 標準函式庫。
# ============================================================================
import base64, json, os, ssl, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TIMEOUT = int(os.environ.get('TIMEOUT_SEC', '180'))
PORT = int(os.environ.get('PORT', '9443'))
with open(os.environ['USER_FILE']) as f:
    EXPECTED = 'Basic ' + base64.b64encode(f.read().strip().encode()).decode()

lock = threading.Lock()
state = {'state': 'WAITING', 'last_heartbeat': None, 'started': time.time(), 'events': []}


def log(msg):
    line = time.strftime('%Y-%m-%dT%H:%M:%S') + ' ' + msg
    print(line, flush=True)
    state['events'] = (state['events'] + [line])[-20:]


def set_state(new, why):
    if state['state'] != new:
        state['state'] = new
        if new == 'FAILED':
            log('ALERT 監控鏈路失效:' + why)       # 正式環境:企業監控平台在這裡通知值班人員
        else:
            log('RECOVERED 監控鏈路恢復:' + why)


def checker():
    while True:
        time.sleep(5)
        with lock:
            last = state['last_heartbeat']
            ref = last if last is not None else state['started']
            if time.time() - ref > TIMEOUT:
                set_state('FAILED', f'超過 {TIMEOUT} 秒沒有收到 Watchdog 心跳')


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, obj):
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _authorized(self):
        if self.headers.get('Authorization') == EXPECTED:
            return True
        self._send(401, {'error': 'unauthorized'})
        return False

    def do_POST(self):
        if self.path != '/heartbeat':
            return self._send(404, {'error': 'not found'})
        if not self._authorized():
            return
        try:
            data = json.loads(self.rfile.read(int(self.headers.get('Content-Length', '0'))) or b'{}')
        except ValueError:
            return self._send(400, {'error': 'bad json'})
        names = {a.get('labels', {}).get('alertname') for a in data.get('alerts', [])}
        if 'Watchdog' not in names:
            return self._send(400, {'error': 'not a Watchdog notification'})
        with lock:
            state['last_heartbeat'] = time.time()
            set_state('OK', '收到 Watchdog 心跳')
        self._send(200, {'ok': True})

    def do_GET(self):
        if self.path != '/status':
            return self._send(404, {'error': 'not found'})
        if not self._authorized():
            return
        with lock:
            last = state['last_heartbeat']
            self._send(200, {'state': state['state'], 'timeout_sec': TIMEOUT,
                             'seconds_since_heartbeat': None if last is None else int(time.time() - last),
                             'events': state['events']})


ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.minimum_version = ssl.TLSVersion.TLSv1_2
ctx.load_cert_chain(os.environ['TLS_CERT'], os.environ['TLS_KEY'])
srv = ThreadingHTTPServer(('0.0.0.0', PORT), Handler)
srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
threading.Thread(target=checker, daemon=True).start()
log(f'deadman 啟動:port {PORT},逾時 {TIMEOUT} 秒')
srv.serve_forever()
