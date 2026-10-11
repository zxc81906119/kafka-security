// 組出 FileStreamSink 連接器的建立請求(JSON),給第 29 章的實驗用。
// 用法:node connector-json.mjs <連接器名稱> <topic> [選項…]
//   --principal=provider  連接器用自己的 AD 服務帳號,帳密用 ${file:…} 引用密碼檔(建議)
//   --principal=inline    連接器用自己的 AD 服務帳號,帳密直接寫在設定裡(對照用,不要這樣做)
//   --principal=none      不覆寫身分,用 worker 的身分(對照用)
//   --dlq                 錯誤容忍(errors.tolerance=all)並把壞資料送到 <topic>.dlq(附錯誤標頭)
// 輸出到標準輸出;inline 的密碼從環境變數 CONNECTOR_PASSWORD 取。
const [name, topic, ...opts] = process.argv.slice(2);
const principal = (opts.find(o => o.startsWith('--principal=')) || '--principal=provider').split('=')[1];
const dlq = opts.includes('--dlq');

const handler = 'io.confluent.kafka.clients.plugins.auth.token.TokenUserLoginCallbackHandler';
const secretFile = '/etc/connect-secrets/orders-sink.properties';
const mds = 'https://broker1:8091,https://broker2:8092,https://broker3:8093,https://broker4:8094';
const jaas = principal === 'inline'
  ? `org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username="SVC-ORDERS-SINK" password="${process.env.CONNECTOR_PASSWORD}" metadataServerUrls="${mds}";`
  : `org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username="\${file:${secretFile}:username}" password="\${file:${secretFile}:password}" metadataServerUrls="${mds}";`;

const config = {
  'connector.class': 'org.apache.kafka.connect.file.FileStreamSinkConnector',
  'tasks.max': '1',
  topics: topic,
  file: `/tmp/${name}.out`,
};
if (principal !== 'none') {
  // 每種客戶端(讀 topic 的 consumer、寫 DLQ 的 producer、DLQ 的 admin)都要覆寫成連接器自己的身分
  for (const kind of ['consumer', 'producer', 'admin']) {
    config[`${kind}.override.sasl.login.callback.handler.class`] = handler;
    config[`${kind}.override.sasl.jaas.config`] = jaas;
  }
}
if (dlq) {
  Object.assign(config, {
    'errors.tolerance': 'all',
    'errors.deadletterqueue.topic.name': `${topic}.dlq`,
    'errors.deadletterqueue.topic.replication.factor': '3',
    'errors.deadletterqueue.context.headers.enable': 'true',
    'errors.log.enable': 'true',
  });
}
console.log(JSON.stringify({ name, config }));
