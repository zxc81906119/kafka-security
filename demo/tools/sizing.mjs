#!/usr/bin/env node
// ============================================================================
// sizing.mjs — Kafka 叢集容量估算(粗估用;實際要靠壓測與你的流量數字校正)
// ----------------------------------------------------------------------------
// 白話:給「每秒幾筆、每筆多大、留幾天、副本幾份」,算出大概要幾台 broker、多少磁碟、網路頻寬,
//   並分別列出「由哪個資源決定台數」(磁碟、網路、分區數、最少台數)。
// 用法:
//   node tools/sizing.mjs                         用內建範例數字跑一次,看輸出長什麼樣
//   node tools/sizing.mjs --file my.json          讀自己的輸入(欄位見下方 DEFAULTS)
//   node tools/sizing.mjs --msgs 20000 --size 1500 --retention 7 --rf 3 --consumers 3
// 輸入欄位(皆可用 --名稱 值 覆蓋;名稱同 JSON 欄位):
//   msgs          平均每秒訊息數
//   peakFactor    尖峰是平均的幾倍(影響網路與台數,不影響磁碟)
//   size          每筆平均大小(bytes,壓縮前)
//   compression   壓縮比(壓縮後/壓縮前,例如 lz4 約 0.5;未壓縮填 1)
//   rf            副本數
//   retention     保留天數(整體,含物件儲存)
//   hotsetHours   啟用 Tiered Storage 時本機只留幾小時;0 = 沒用 Tiered Storage
//   consumers     「每筆資料被幾個 consumer group 完整讀一次」(扇出)
//   headroom      成長與突發的預留比例(0.3 = 預留 30%)
//   diskPerBrokerTB  每台 broker 可用的資料磁碟(TB)
//   targetDiskUtil   磁碟用量上限(官方 Self-Balancing 預設 disk.max.load 0.85;規劃建議 0.6 到 0.7,留給搬家與暫時性成長)
//   brokerNetMBps    每台 broker 網路(MB/s,單向,實際可用;1 Gbps 約 110、10 Gbps 約 1100)
//   brokerMaxIngestMBps  壓測得到的單台寫入上限(MB/s;未壓測前請用保守值,例如 30 到 60)
//   maxReplicasPerBroker 單台副本數上限(官方 Self-Balancing 文件建議 4000)
//   partitionMBps  單一分區能撐的寫入(MB/s;壓測得到,未測用 5 到 10)
// 公式與假設見 DESIGN-BASIS.md「容量規劃」;這是估算,不是保證。
// ============================================================================
import fs from 'node:fs';

const DEFAULTS = {
  msgs: 10000, peakFactor: 3, size: 1000, compression: 1, rf: 3, retention: 7, hotsetHours: 0,
  consumers: 2, headroom: 0.3, diskPerBrokerTB: 4, targetDiskUtil: 0.65,
  brokerNetMBps: 110, brokerMaxIngestMBps: 40, maxReplicasPerBroker: 4000, partitionMBps: 5,
};

// ---- 參數解析 ----
const args = process.argv.slice(2);
const cfg = { ...DEFAULTS };
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--file') Object.assign(cfg, JSON.parse(fs.readFileSync(args[++i], 'utf8')));
  else if (args[i].startsWith('--')) {
    const k = args[i].slice(2);
    if (!(k in DEFAULTS)) { console.error(`不認識的參數 --${k}`); process.exit(1); }
    cfg[k] = Number(args[++i]);
  }
}

const MB = 1024 * 1024, TB = 1024 * MB * 1024;
const f = (n, d = 1) => Number(n).toLocaleString('en-US', { maximumFractionDigits: d });

// ---- 計算 ----
const wireBytes = cfg.size * cfg.compression;                       // 實際在網路與磁碟上的大小
const avgInMBps = cfg.msgs * wireBytes / MB;                        // 平均寫入(叢集總量,MB/s)
const peakInMBps = avgInMBps * cfg.peakFactor;                      // 尖峰寫入
const replMBps = peakInMBps * (cfg.rf - 1);                         // 尖峰副本複寫流量(叢集內部)
const outMBps = peakInMBps * cfg.consumers + replMBps;              // 尖峰對外讀取 + 副本複寫的送出

// 儲存:整體保留 vs 本機保留
const dayBytes = avgInMBps * MB * 86400;                            // 一天的資料量(單一副本)
const totalBytes = dayBytes * cfg.retention * cfg.rf;               // 全部副本、整個保留期
const localDays = cfg.hotsetHours > 0 ? cfg.hotsetHours / 24 : cfg.retention;
const localBytes = dayBytes * localDays * cfg.rf;                   // 本機磁碟(啟用 Tiered Storage 時只有 hotset)
const objectBytes = cfg.hotsetHours > 0 ? dayBytes * cfg.retention : 0;   // 物件儲存只放一份(物件儲存自己處理耐久性)
const localWithHeadroom = localBytes * (1 + cfg.headroom);

// 台數:由哪個資源決定
const byDisk = Math.ceil(localWithHeadroom / (cfg.diskPerBrokerTB * TB * cfg.targetDiskUtil));
// 每台 broker 的網路:進來 = 寫入份額 + 複寫接收份額;出去 = 讀取份額 + 複寫送出份額。粗估用叢集總量除以台數,取較大的方向
const netPerBrokerNeed = Math.max(peakInMBps + replMBps, outMBps) * (1 + cfg.headroom);
const byNet = Math.ceil(netPerBrokerNeed / cfg.brokerNetMBps);
const byIngest = Math.ceil(peakInMBps * (1 + cfg.headroom) / cfg.brokerMaxIngestMBps);
const partitionsForThroughput = Math.ceil(peakInMBps * (1 + cfg.headroom) / cfg.partitionMBps);
const replicasTotal = partitionsForThroughput * cfg.rf;
const byReplicas = Math.ceil(replicasTotal / cfg.maxReplicasPerBroker);
const minBrokers = Math.max(cfg.rf, 3);
const drivers = [
  ['最少台數(副本數與 min.insync.replicas)', minBrokers],
  ['磁碟(本機資料量 ÷ 每台可用)', byDisk],
  ['網路(尖峰進出流量 ÷ 每台頻寬)', byNet],
  ['寫入能力(尖峰寫入 ÷ 壓測單台上限)', byIngest],
  ['副本數上限(分區數 × RF ÷ 每台上限)', byReplicas],
];
const need = Math.max(...drivers.map(d => d[1]));
const withSpare = need + 1;                                          // N+1:壞一台時剩下的還要撐得住

// ---- 輸出 ----
console.log('輸入');
console.log(`  ${f(cfg.msgs, 0)} 筆/秒(尖峰 ×${cfg.peakFactor}),每筆 ${f(cfg.size, 0)} bytes,壓縮比 ${cfg.compression},RF=${cfg.rf},保留 ${cfg.retention} 天,扇出 ${cfg.consumers}`);
console.log(`  每台磁碟 ${cfg.diskPerBrokerTB} TB(用量上限 ${cfg.targetDiskUtil * 100}%),每台網路 ${cfg.brokerNetMBps} MB/s,壓測單台寫入 ${cfg.brokerMaxIngestMBps} MB/s,預留 ${cfg.headroom * 100}%`);
console.log(`  Tiered Storage:${cfg.hotsetHours > 0 ? `是,本機只留 ${cfg.hotsetHours} 小時` : '否'}`);
console.log('\n流量');
console.log(`  平均寫入 ${f(avgInMBps)} MB/s,尖峰 ${f(peakInMBps)} MB/s`);
console.log(`  尖峰副本複寫 ${f(replMBps)} MB/s,尖峰對外送出(讀取 + 複寫)${f(outMBps)} MB/s`);
console.log('\n儲存');
console.log(`  每天(單一副本)${f(dayBytes / TB, 3)} TB;整個保留期含 ${cfg.rf} 副本 ${f(totalBytes / TB, 2)} TB`);
console.log(`  本機磁碟需求(含預留)${f(localWithHeadroom / TB, 2)} TB${cfg.hotsetHours > 0 ? `;物件儲存 ${f(objectBytes / TB, 2)} TB(一份)` : ''}`);
console.log('\n台數(各資源各自算出的最少台數)');
for (const [name, n] of drivers) console.log(`  ${String(n).padStart(3)} 台  ${name}${n === need ? '  ← 決定台數' : ''}`);
console.log(`\n建議:${need} 台 + 1 台備援(N+1)= ${withSpare} 台 broker;至少 ${partitionsForThroughput} 個分區(依吞吐)`);
console.log('\n注意:');
console.log('  · 這是估算。單台寫入上限、單分區吞吐請用 scripts/perf-lab.sh 在「真實硬體與網路」上實測後回填。');
console.log('  · 只看磁碟與網路;CPU(TLS、壓縮、RBAC 授權)、頁面快取大小、分區數對 controller 的影響要靠壓測。');
console.log('  · controller 另算:正式環境至少 3 台,與 broker 分開,規格小(中小規模 4 核 8 GB 級即可,依分區總數調整)。');
