// 產生「官方 JMX exporter 設定 + HTTPS + Basic 帳密」的設定檔(<元件>_tls.yml:broker、controller、Schema Registry、Connect、REST Proxy)。
// 用法:node jmx-tls-config.mjs <密碼檔> <設定目錄>   例:node jmx-tls-config.mjs config/c3/jmx_exporter.pw config/jmx
// 做法:在官方 yml 前面加一段 httpServer(HTTPS 用 server keystore,帳號 Prometheus,密碼存成 PBKDF2 雜湊)。
// 雜湊與官方 utils/jmxexporter_hash_password_PBKDF2WithHmacSHA512.py 相同:PBKDF2-HMAC-SHA512、210000 次、輸出 128 位元組(hex)。
// salt 由密碼推導(同一個密碼每次產生相同設定,方便重現)。
import fs from 'node:fs';
import crypto from 'node:crypto';

const [pwFile, dir] = process.argv.slice(2);
const password = fs.readFileSync(pwFile, 'utf8').trim();
const salt = crypto.createHash('sha256').update(password).digest('hex').slice(0, 10);
const hash = crypto.pbkdf2Sync(password, salt, 210000, 128, 'sha512').toString('hex');

const httpServer = [
  'httpServer:',
  '  ssl:',
  '    keyStore:',
  '      type: PKCS12',
  '      filename: /etc/kafka/secrets/server.keystore.p12',
  '      password: changeit',          // 測試值;正式環境由 CyberArk 提供
  '    certificate:',
  '      alias: server',
  '  authentication:',
  '    basic:',
  '      username: Prometheus',
  `      passwordHash: ${hash}`,
  '      algorithm: PBKDF2WithHmacSHA512',
  `      salt: ${salt}`,
  '',
].join('\n');

for (const name of ['kafka_broker', 'kafka_controller', 'confluent_schemaregistry', 'kafka_connect', 'confluent_rest']) {
  const official = fs.readFileSync(`${dir}/${name}.yml`, 'utf8').replace(/^---\r?\n/, '');
  fs.writeFileSync(`${dir}/${name}_tls.yml`, '---\n' + httpServer + official);
}
