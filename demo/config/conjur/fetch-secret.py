#!/usr/bin/env python3
# broker 啟動前向 CyberArk(Conjur)取秘密(例如 Secret Protection 的主金鑰),印到 stdout 給呼叫端放進環境變數。
# 正式環境對應 systemd 的 ExecStartPre:取完才啟動服務;秘密不寫入磁碟。
# 環境變數:CONJUR_URL(https://conjur)、CONJUR_ACCOUNT、CONJUR_HOST(例 kafka/broker)、CONJUR_API_KEY_FILE、CONJUR_VARIABLE(例 kafka/broker/master-key)、CONJUR_CA(CA 憑證檔)
import base64, os, ssl, sys, urllib.parse, urllib.request

url = os.environ.get('CONJUR_URL', 'https://conjur')
acc = os.environ.get('CONJUR_ACCOUNT', 'demo')
host = os.environ['CONJUR_HOST']
var = os.environ['CONJUR_VARIABLE']
ca = os.environ.get('CONJUR_CA', '/etc/kafka/secrets/ca.pem')
with open(os.environ['CONJUR_API_KEY_FILE']) as f:
    api_key = f.read().strip()

ctx = ssl.create_default_context(cafile=ca)
def call(method, path, data=None, headers=None):
    req = urllib.request.Request(url + path, data=data, method=method, headers=headers or {})
    with urllib.request.urlopen(req, context=ctx, timeout=15) as r:
        return r.read()

try:
    token = call('POST', f'/authn/{acc}/{urllib.parse.quote("host/" + host, safe="")}/authenticate', api_key.encode())
    tok = base64.b64encode(token).decode()
    secret = call('GET', f'/secrets/{acc}/variable/{urllib.parse.quote(var, safe="")}', headers={'Authorization': f'Token token="{tok}"'})
except urllib.error.HTTPError as e:
    print(f'conjur: {e.code} {e.reason}(host={host}, variable={var})', file=sys.stderr); sys.exit(1)
sys.stdout.write(secret.decode())
