// 每個 Lab 的「從這裡開始時先執行」:指令一律是 scripts/chapter-start.sh chNN(冪等:已正確的不動),這裡寫它會確保什麼。
// 內容要與 scripts/chapter-start.sh 各章的 case 一致;沒列的 Lab 用 DEFAULT。
export const START = {
  1: '回到「還沒有任何授權」的起點(執行 scripts/reset.sh)。',
  2: '回到「還沒有任何授權」的起點(執行 scripts/reset.sh)。',
  3: 'orders-write 群組還沒有 orders. 的授權;yujie 在 orders-write;ming 不在任何群組;orders.events 存在。',
  4: '等同 Lab 3 結束時:orders-write 可讀寫 orders.;ming 在 orders-write、不在 orders-read;orders-read 還沒有唯讀授權;orders.events 有資料。',
  5: '等同 Lab 4 結束時:orders-write 可讀寫、orders-read 唯讀;ming 只在 orders-read;orders.events 與 payments.events 存在。',
  6: '同 Lab 5 的起點,另外清掉上次留下的反面教材帳號 shared-ops。',
  7: 'svc-orders 還沒有任何示範綁定(要示範授權前被拒、在 C3 授權後成功)。',
  9: 'svc-orders(密碼 v1)與寫入授權存在;orders-write 可寫;清掉上次輪替留下的 svc-orders-v2;AD 在線。',
  10: 'yujie 可寫、ming 唯讀;本 Lab 第二步會自己製造要彙整的稽核事件,不依賴前面跑過哪些 Lab。',
  11: 'ming 只在 orders-read、yujie 只在 orders-write、三個維運群組都沒有人;清掉上次的 infra 示範;orders.events 有資料。',
  12: 'legacy-orders 與 orders-write 都還沒有 orders. 的寫入權(本 Lab 在 C3 指派後才可寫)。',
  14: 'ming 沒有任何 role;yujie 在 orders-write。',
  15: 'yujie 在 orders-write,群組可讀寫 orders.。',
  16: '清掉 OP menu 殘留的鎖與上次維護模式的輸出。',
  18: '啟動 Conjur;svc-orders 與寫入授權存在;Conjur 裡「現在該用的帳號密碼」設為 svc-orders / 原密碼。',
  33: '不需要額外準備:本 Lab 第一步 scripts/quorum-lab.sh reset 會把 voter 名單收斂成 {1,2,3}(上次汰換留下的 controller4 移除、controller3 重新加入),最後一步再還原一次。',
};
export const DEFAULT = '不需要額外準備:直接從第一步開始(需要的元件由本 Lab 第一步啟動,結束時還原)。';
