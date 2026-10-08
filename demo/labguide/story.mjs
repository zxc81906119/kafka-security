// 故事版 Lab 手冊的故事內容(build-story.mjs 使用)。
// 原則:故事只負責「為什麼要做這件事」;指令、輸出、截圖仍來自 labs.mjs 與 evidence/(實跑結果)。
// 用詞:繁體中文為主、英文為輔;不出現 SSO、Kerberos、IdP 等客戶不採用的方案。

export const TITLE = 'Ming 的前三週';
export const SUBTITLE = '新進維運工程師的 Confluent Kafka 安全 Lab 手冊';
export const TAGLINE = 'AD 只放 user / group 時:人與服務如何串接 Kafka、REST Proxy、Control Center;每個 Lab 都附可直接貼上的指令與實際執行的輸出';

export const SETTING = [
  '某銀行資訊部成立了「Kafka 平台組」,要把 Confluent Platform 當成全行的事件串流平台。上線之前,資安與稽核提了幾條規矩,整份手冊的每一個 Lab,都是在回答其中一條:',
];

export const RULES = [
  ['預設全部拒絕', '沒有身分、或有身分但沒被授權,什麼都看不到、做不到。'],
  ['人用 AD', '人員一律用 AD 帳號登入,不另外建 Kafka 帳號;AD 裡只有 user 與 group。'],
  ['授權跟著群組走', 'role 綁在 AD 群組上,人員異動只改 AD,Kafka 端不用動。'],
  ['機器不放 AD', '應用系統是機器,不佔用 AD;改用 Kafka 自己的服務身分,權限一樣走 RBAC,而且最小權限。'],
  ['每個動作都查得到', '誰、什麼時候、對什麼做了什麼,事後都要能還原(audit log)。'],
  ['憑證要少', '客戶希望共用一張 server 憑證,只做傳輸加密,不拿它當身分。'],
];

// 角色:名稱、在故事裡的身分、demo 帳號
export const CAST = [
  ['Ming', '新進維運工程師(本手冊的主角,每個 Lab 都是他的一個任務)', 'ming / ming-pw;到職第一天不在任何 AD 群組'],
  ['Gary', '平台組組長,Ming 的師傅', 'gary / gary-pw;AD 群組 cluster-admin、topic-admin、rbac-admin、security(沒有 SystemAdmin)'],
  ['Yujie', '訂單系統(orders)的開發同事', 'yujie / yujie-pw;AD 群組 orders-write(demo 示範用)'],
  ['svc-orders', '訂單系統的應用程式(機器,不在 AD)', 'svc-orders / orders-secret-v1;Kafka SCRAM 服務帳號'],
  ['legacy-orders', '一套只能用 HTTP 的舊系統', 'client 憑證(CN = legacy-orders)'],
  ['資安顧問', '第四天來訪,專挑設計的毛病', '(Lab 8、9)'],
];

// 幕:每一幕包含哪些 Lab、開場白
export const ACTS = [
  { id: 'prologue', title: '序幕:開工前', when: '週一 早上', labs: [0],
    scene: ['Ming 到職的第一個早上,Gary 丟給他一句話:「環境你先自己建一次。建完,你就知道每個零件在哪、為什麼這樣接。」',
      '桌上已經有一份驗收標準:用 AD 帳號登入、依群組授權、機器另有身分、全程留下紀錄。Ming 的任務是先把這套環境立起來。'] },
  { id: 'week1-mon', title: '第一週 週一:進不去,是對的', when: '週一', labs: [1, 2],
    scene: ['環境好了,Ming 想先確認一件事:資安說的「預設全部拒絕」是真的嗎?他決定自己試一遍,把每一種「進不去」的情況都親眼看過。'] },
  { id: 'week1-tue', title: '第一週 週二:授權跟著群組走', when: '週二', labs: [3, 4],
    scene: ['Yujie 要開始寫訂單系統,需要寫入 orders.* 的 topic。Ming 正要幫他的帳號加權限,Gary 阻止了他:「別綁人,綁群組。今天你就知道為什麼。」'] },
  { id: 'week1-wed', title: '第一週 週三:工具、腳本與應用系統', when: '週三', labs: [5, 6, 7],
    scene: ['QA 同事習慣用 Postman,維運組有一堆共用的腳本,訂單系統的應用程式也排定要上線。三件事其實是同一個問題:每一個「呼叫者」是誰,Kafka 認不認得、授不授權。'] },
  { id: 'week1-thu', title: '第一週 週四:資安顧問來訪(選修)', when: '週四', labs: [8, 9],
    scene: ['外聘的資安顧問來做設計審查,他的問題一個比一個刁:「共用一張憑證真的安全嗎?」「密碼多久換一次?AD 掛了怎麼辦?」Gary 說:「別辯,做給他看。」'] },
  { id: 'week1-fri', title: '第一週 週五:週報', when: '週五', labs: [10],
    scene: ['一週結束,主管要週報:這一週誰被拒絕、誰被允許、誰動過授權。Ming 不想憑記憶寫,他要從 audit log 把事實撈出來。'] },
  { id: 'week2', title: '第二週:現實的麻煩', when: '第二週', labs: [11, 12, 13, 14],
    scene: ['基本功過關了,但現實不會照教科書走:半夜要有人能建 topic、舊系統不會說 Kafka 的語言、稽核要盤點每條連線、還有一個你不知道的 REST 入口。'] },
  { id: 'week3', title: '第三週:異動、日常維運、傳輸加密與 CyberArk', when: '第三週', labs: [15, 16, 17, 18],
    scene: ['人會調動、會離職;而日常維運不能每次都靠指令記憶。第三週,Ming 處理人員異動,並第一次用平台組自己做的維運選單(OP menu)值班。接著把「線上傳輸」補完整:連 AD 的線路、監控元件、使用者連 C3 的入口。最後,資安要求所有密碼不能再放在檔案裡——行裡的 CyberArk 登場。'] },
];

// 每個 Lab 的故事:scene 情境、mission 任務、recap 小結(學到的事 + 對應的規矩)
export const LAB_STORY = {
  0: { scene: ['Ming 依序把零件立起來:先是憑證,再是模擬 AD 的 OpenLDAP,然後是 controller 與兩台 broker(MDS 內建在 broker 裡),最後是 REST Proxy 與 Control Center。每個零件都在回答一個問題:誰負責認人、誰負責授權、誰負責記錄。'],
    mission: ['啟動環境並通過自檢。', '搞清楚四個身分平面:人(AD)、機器(服務帳號)、平台元件(憑證)、內部通道。'],
    recap: ['AD 只放 user 與 group;role 與服務帳號都在 Kafka 這一側。', '平台元件(C3、REST Proxy、bootstrap)各用一張 client 憑證向 MDS 認證,不需要 AD 服務帳號。'] },
  1: { scene: ['Ming 先不帶任何帳密打 REST Proxy,被擋。接著帳號對、密碼錯,被擋。最後用 AD 帳號直連 broker 但密碼錯,也被擋。他才相信預設真的是「全部拒絕」。',
      '最有意思的是最後一種:帳密正確、AD 登入成功,但還沒被授權,結果一樣什麼都做不了。Gary 在旁邊說:「這就是認證和授權是兩關。」'],
    mission: ['依序試出三種失敗:沒有身分、密碼錯誤、認證成功但沒授權。', '分清楚每一種對應的回應(401 或授權失敗)。'],
    recap: ['認證回答「你是誰」,授權回答「你能做什麼」,兩關都過才有動作。', '對應規矩一:預設全部拒絕。'] },
  2: { scene: ['Ming 第一次登入 Control Center(C3),用的是自己的 AD 帳號。隔壁的 Gary 與 Yujie 也同時登入。三個人看同一個 C3,畫面卻不一樣:Gary 什麼都看得到,Yujie 只看得到自己被授權的,Ming 則幾乎是空的。'],
    mission: ['分別以 gary、yujie、ming 登入 C3,記錄三個人看到的差異。'],
    recap: ['C3 沒有「管理員版」與「一般版」之分,畫面完全由登入者在 RBAC 的權限決定。', '對應規矩二:人用 AD。'] },
  3: { scene: ['Yujie 的帳號已經在 AD 的 orders-write 群組,但他寫入 orders.events 還是被拒:群組在,role 還沒綁。Gary 讓 Ming 在 C3 上把 orders.* 的讀寫權限指派給「AD 群組」orders-write,不是指派給 Yujie 個人。',
      'Yujie 立刻能寫,Ming 因為還不在群組,仍被拒。接著重頭戲:Gary 要 Ming 去 AD 把自己加進 orders-write,「Kafka 這邊一個設定都不要動」。幾秒後,同一個指令,Ming 成功了。'],
    mission: ['授權前確認 Yujie 被拒;在 C3 把 role 指派給 AD 群組;', '驗證 Yujie 成功、Ming 被拒;', '在 AD 把 Ming 加進群組,不碰 Kafka,等幾秒後驗證明也成功。'],
    recap: ['★ 整個方案的核心:role 綁群組,人員異動只改 AD,Kafka 端零變更。', '群組異動不是即時:demo 設 5 秒,官方預設 60 秒,實機請預留約 1 分鐘。', '對應規矩三:授權跟著群組走。'] },
  4: { scene: ['營運主管有一條硬規定:正式環境的人只能「看」,不能「改」。Ming 於是建立唯讀群組 orders-read,把自己從 orders-write 移過去。',
      '之後他試了三件事:讀資料(可以)、寫資料(被拒)、建 topic(被拒)。而 Yujie 完全沒有受影響。連他的 C3 畫面也只剩檢視,沒有任何管理按鈕。'],
    mission: ['建立唯讀授權(DeveloperRead)並把 Ming 移進去。', '驗證讀可以、寫與建 topic 被拒,且不影響 Yujie。'],
    recap: ['換身分只是換 AD 群組,不是改一堆 ACL。', '「人只能唯讀」是預設姿態;需要改動時走 Lab 11 的臨時提權。'] },
  5: { scene: ['QA 同事用 Postman 測 API,問 Ming:「我要用誰的帳號?」Ming 匯入 Postman collection,三個人各跑一遍,結果與 CLI、C3 完全一致。'],
    mission: ['匯入 collection 與環境,信任 demo CA。', '用不同身分呼叫 REST Proxy 與 MDS API,對照結果。'],
    recap: ['CLI、C3、Postman 看到的是同一份身分與授權,不是三套規則。', '帳密不寫進 collection,放在 environment 的 secret 變數。'] },
  6: { scene: ['維運組有一批共用腳本。Gary 要求「腳本共用,憑證各人各自」:同一支腳本,每個人登入跳板機後用自己的身分執行。',
      'Ming 也看了一個反面教材:全組共用一個帳號 shared-ops。腳本照跑,但稽核日誌裡從頭到尾只有 shared-ops,看不出是誰做的。'],
    mission: ['用 asuser 模擬各人執行同一支腳本,比較結果。', '做出反例,到 audit 看「誰做了什麼」,最後清掉反例。'],
    recap: ['共用腳本沒問題,共用帳號才有問題。', '對應規矩五:每個動作都查得到。'] },
  7: { scene: ['訂單系統要上線,應用程式不是人,不該進 AD。Gary 的做法:在 Kafka 建一個 SCRAM 服務帳號 svc-orders,授權同樣走 RBAC。',
      '剛建好的 svc-orders 能認證,卻什麼都做不了,Ming 先確認了這一點。授權給它寫 orders.* 之後,寫 orders 成功,碰 payments 就被拒:最小權限。他還特地試了用 AD 的方式(PLAIN)驗證 svc-orders,結果失敗,證明它真的不在 AD。'],
    mission: ['建立 svc-orders 並確認授權前被拒。', '在 C3 指派 orders.* 寫入;驗證最小權限、密碼錯誤、與「不在 AD」。'],
    recap: ['對應規矩四:機器不放 AD,權限仍由 RBAC 控管。', '服務帳號的密碼存在 Kafka 裡,不在目錄服務。'] },
  8: { scene: ['顧問第一個問題:「你們打算共用一張 server 憑證,那 Kafka 怎麼分辨 C3 和 REST Proxy?」Ming 沒有爭辯,拿憑證去 MDS 換 token,給顧問看 Kafka 眼中的 principal。',
      '共用憑證時,兩個元件拿到的是同一個身分;每個元件各一張憑證(不同 DN),才分得出來。Gary 補了一句:「所以共用憑證只做加密,身分另外處理。」'],
    mission: ['定義 tokensub 函式,看 Kafka 認得的 principal。', '對照:共用憑證 vs 每個元件各一張憑證。'],
    recap: ['共用憑證不能當身分,否則無法分權、稽核也分不出來。', '對應規矩六:憑證要少,但身分不能共用。'] },
  9: { scene: ['顧問第二組問題:密碼多久換?換的時候會不會中斷?AD 掛了怎麼辦?Ming 在 demo 環境一項一項演練:先建新帳號、讓新舊並行、全部切換後停用舊帳號,舊密碼立刻失效而新帳號照常。',
      '最後是 AD 故障演練:把 openldap 停掉,看誰受影響,誰不受影響。'],
    mission: ['完成不中斷的密碼輪替(四步)。', '觀察內部通道的行為,並演練 AD 故障。'],
    recap: ['服務密碼可以不中斷輪替(新舊並行)。', 'AD 掛掉時,依賴 AD 登入的人受影響;已發出的 token 與服務帳號、平台元件不受影響(到期前)。'] },
  10: { scene: ['Ming 從 audit log 把這一週的事實撈出來:誰被拒絕、誰被允許、誰動過授權。每一條都有時間、主體、操作與結果。主管看完只問了一句:「這些都是自動留下的?」「是。」'],
    mission: ['彙整被拒絕的事件、被允許的事件,以及權限變更紀錄。'],
    recap: ['第一週結束:認證、授權、機器身分、稽核都走完一遍。', '對應規矩五:每個動作都查得到。'] },
  11: { scene: ['正式環境人只能唯讀,但半夜總有人要看叢集、建 topic、調整授權。Gary 的做法是用 AD 群組拆成三種維運角色:ops(看叢集)、topic-admin(管 topic)、rbac-admin(管授權);三組的 role 早就綁好,平常群組是空的,需要時經核准臨時加入,做完立刻收回。',
      'Ming 這次不是照著做,而是親手試出每個角色「到底能做什麼」。Yujie 先被唯讀擋下;加進 ops 後他能看,卻建不了 topic、讀不到資料、改不了授權;改加進 topic-admin 後他能建 topic、讀得到資料,甚至能在自己的範圍內改授權,這才發現 topic-admin 是強角色;最後 Ming 加進 rbac-admin,能改授權,卻建不了 topic。兩人都收回之後,再試一次,全部被拒。'],
    mission: ['確認三個維運群組的 role 平常就綁好,而且群組是空的。', '依序臨時提權 ops、topic-admin、rbac-admin,記下每個角色實際能做與不能做的事。', '收回後確認回到唯讀。'],
    recap: ['ops 看得到卻改不了;rbac-admin 只管授權;topic-admin 是強角色(能建刪 topic、讀資料、在自己範圍內改授權),所以一定要臨時、事後收回。', '提權與收回都只發生在 AD,Kafka 端零變更,每次都有 audit 紀錄。', '實測陷阱:同一個 consumer group 讀過的 topic 會提交 offset,再讀要換新的 group 名稱。'] },
  12: { scene: ['有一套核心舊系統只能用 HTTP,沒辦法用 Kafka client,更不可能用 SCRAM。方案是讓它經 REST Proxy 進來:機器出示 client 憑證(CN 就是它的名稱),人仍然用 AD 帳密,兩種身分並存。',
      'Ming 替它發了一張憑證:授權前通過認證卻被拒(403);授權後可以寫 orders,碰 payments 被拒;沒有憑證也沒有帳密是 401;偽造的憑證在 TLS 握手就被擋下。broker 看到的主體是 User:legacy-orders,不是 restproxy。'],
    mission: ['設定 REST Proxy 讓人與機器並存。', '發憑證、授權、驗證最小權限與各種失敗。'],
    recap: ['legacy app 以憑證身分進來,身分一路傳到 broker,audit 看得到是誰。', '客戶若在 REST Proxy 前面放負載平衡器,必須是 TCP 透傳(L4);在 LB 終止 TLS 會讓憑證身分失效(nginx 實測,見附錄)。'] },
  13: { scene: ['稽核要求盤點 C3:誰連到誰、人與機器各用什麼身分、哪些連線沒有認證、哪些身分權力過大。Ming 逐項用日誌、audit 與實際呼叫驗證,而不是憑文件猜。',
      '他發現兩件事:c3 這張憑證等同管理員,必須嚴格保管;監控元件(Prometheus、Alertmanager)必須要有認證,否則任何連得到的人都能讀指標,Alertmanager 甚至能被寫入、靜音告警。這個 demo 已經替它們加上 HTTPS 與 Basic 帳密,Ming 逐一驗證:不帶帳密一律 401。'],
    mission: ['盤點人與機器各走哪一條路。', '用日誌與 audit 驗證主體;找出風險點。'],
    recap: ['人:瀏覽器登入後一路以使用者本人的 token 運作;機器:C3 自己是 User:c3(SystemAdmin)。', '監控元件走 HTTPS + Basic,不帶帳密一律 401;Basic 沒有細部授權,有帳密就能寫,所以帳號要分開、日誌要保護(C3 的日誌會印出 Authorization 標頭)。'] },
  14: { scene: ['盤點到最後,Ming 發現 broker 的 8091 埠除了 MDS,還有一組內建的 Admin REST(/kafka/v3),不設定安全擴充時完全沒有認證。他依官方設定套上保護之後,匿名呼叫被擋;錯誤密碼被擋;gary 能列 topic;沒有 role 的 Ming 看到的清單是空的。'],
    mission: ['確認匿名呼叫被擋、依使用者授權。', '驗證各種身分的結果(含一個容易誤會的:HTTP 200 但內容是 40301)。'],
    recap: ['每一個 HTTP 入口都要盤點,不只是你知道的那幾個。', '回應碼可能是 200,但內容裡的 error_code 才是真的結果。'] },
  15: { scene: ['Yujie 調到別的部門,AD 把他移出 orders-write。這時他手上還有一個還沒到期的 MDS token。Ming 很好奇:token 不是還有效嗎?',
      '他先確認收回前他能寫入,再讓 AD 移出群組。同一個 token(還沒到期)再寫一次,這次是 403:授權依「現在的群組」判斷,不是依發 token 當下。他的 AD 帳號沒被停用,仍能登入,只是什麼都看不到。'],
    mission: ['發 token、收回前寫入成功;AD 移出群組;', '同一個 token 再寫入應被拒;他仍能登入但看不到業務 topic。'],
    recap: ['人員異動只改 AD,Kafka 端與已發出的 token 都不用處理,權限當下就依群組現況判斷。', '離職時務必同時停用 AD 帳號;停用之前,已發出的 token 在到期前仍可通過認證(但沒有權限)。'] },
  16: { scene: ['第三週,Gary 交給 Ming 一個東西:平台組自己寫的維運選單。「以後日常維運都從這裡進,別直接敲指令。」',
      '選單就是登入殼層,用 Ming 自己的 AD 身分,Kafka 的動作由 RBAC 判斷,主機的動作由 sudo 規則判斷,選單本身不判斷權限。Ming 依序用它做了日常的事:看健康、看生效設定、替要維護的 node 靜音告警、匯出權限清單給覆核、查 audit,最後看了變更時窗與並行鎖如何擋住不該發生的操作。'],
    mission: ['登入選單,列出項目,執行健康檢查與生效設定。', '開始與結束維護模式;匯出權限清單;查詢 audit。', '體驗變更時窗與並行鎖。'],
    recap: ['選單把「做什麼」標準化,而「能不能做」仍由 Kafka RBAC 與 sudo 決定。', '選單不用額外憑證;每個動作都以操作者本人的 AD 身分執行並留紀錄。'] },
  17: { scene: ['資安來信:「授權做得很好,但你們的 AD 密碼是怎麼從 broker 走到 AD 的?監控的 Prometheus 與 Alertmanager 有加密嗎?使用者連 C3 是 HTTP 還是 HTTPS?」Gary 把這三個問題交給 Ming:每一個都要用證據回答,不能只說「有設定」。',
      'Ming 先看 AD 那一段:openldap 日誌顯示 broker 的連線全部落在 636(LDAPS),389 沒有 broker;換一個不信任 demo CA 的用戶端,連線就失敗,這才解釋了為什麼 broker 需要信任庫。接著是監控:Prometheus 與 Alertmanager 不帶帳密一律 401,明文 HTTP 也被拒;broker 推指標與 C3 的連線仍然正常,證明帳密與信任庫都設對了。最後是 C3:憑證驗證通過,不信任簽發 CA 時被擋,他也記下:正式環境要把內部 CA 發給每一台使用者電腦。'],
    mission: ['證明 broker 連 AD 走 LDAPS,而且信任 CA 才連得上。', '證明 Prometheus、Alertmanager 要 HTTPS 加 Basic,而 broker 的指標推送與 C3 的連線仍正常。', '證明使用者連 C3 走 HTTPS,並理解不信任 CA 時的結果。'],
    recap: ['AD 連線:ldaps:// 加信任庫;只有連 AD 的 JVM 需要信任庫。', '監控:web-config 設 TLS 與 Basic;Prometheus 連 Alertmanager 那一段也要改設定(官方頁沒寫、實測必要)。', 'C3:只開 HTTPS;共用 server 憑證要把所有元件的名稱放進 SAN,並規劃 CA 發放給使用者電腦。', '共用 server 憑證只是補了名稱,用同一把 key、同一個 CA 重簽,不用重發任何 client 憑證。'] },
  18: { scene: ['行裡有 CyberArk。資安問 Gary:「你們的密碼放哪?」Gary 老實說:應用程式的 SCRAM 密碼在設定檔、OP menu 的帳密在跳板機的檔案、broker 連 AD 的密碼在 properties 裡。資安的要求很簡單:「以後這些都不能放在檔案裡。」',
      'Ming 用 CyberArk 的開源版(Conjur)在環境裡接了一遍:policy 寫清楚哪個機器身分能拿哪個秘密;應用啟動時先用自己的 API key 換 token、取密碼、在記憶體組連線設定;另一個沒被授權的應用拿不到,錯的 API key 連門都進不了。密碼輪替後,應用重新啟動就自己跟上,舊密碼立刻失效。接著他把 OP menu 的帳密、broker 設定檔的密碼也都搬進去:broker 啟動前向 Conjur 取主金鑰,設定檔裡只剩密文。',
      '做完他也清楚哪些本機做不到:代登入錄影、自動輪替主機帳號、依單借出私鑰,那些是 CyberArk 的 PAM,只能到客戶環境才驗。'],
    mission: ['讓應用以自己的機器身分取密碼,並確認沒被授權的拿不到。', '走一次輪替,確認應用跟上、舊密碼失效。', '把 OP menu 與 broker 設定檔的密碼從檔案搬進 Conjur。'],
    recap: ['CyberArk 不改變身分與授權的設計,它接管的是「密碼與私鑰放哪、誰能拿、怎麼輪替」。', '每個應用一個機器身分,policy 只給它自己的秘密;稽核紀錄的主體就是這個身分。', 'Kafka 的 SCRAM 輪替沒有現成的 CyberArk 平台,靠腳本;誰來觸發(CPM 或排程)是客戶的決定。', '秘密不落地的代價:Conjur 不可用時依賴它的服務起不來,可用性要一併規劃。'] },
};

export const EPILOGUE = {
  title: '終章:一個月後',
  scene: ['一個月後,Ming 已經能獨立值班。回頭看,他做的每一件事都在回答最初那六條規矩:預設全部拒絕、人用 AD、授權跟著群組、機器不放 AD、每個動作查得到、憑證要少。',
    'Gary 問他:「如果客戶明天要你上到真正的 RHEL 9 VM,你還缺什麼?」Ming 列了一張清單,這份清單也是這個 demo 誠實承認還沒驗證的部分。'],
  todo: [
    ['真實 AD', '巢狀群組、帳號大小寫(RBAC 區分大小寫)、群組異動的實際延遲;客戶 AD 的使用者名稱是 CN。'],
    ['部署環境', '以 docker demo 為準,不另外在真實 CP 節點(RPM、systemd)驗證;多 controller(demo 只有 1 個)與 SELinux 同樣不在驗證範圍。'],
    ['傳輸加密的剩餘題目', 'demo 已做 LDAPS、監控 HTTPS + Basic、C3 HTTPS(Lab 17);未驗證:真實 AD 的 LDAPS 憑證鏈(中繼 CA 要放進信任庫)、Alertmanager 的 mTLS、由 F5 終止 C3 的 TLS 時的行為。'],
    ['負載平衡器', '客戶使用 F5:legacy app 前面的 LB 必須是 L4 透傳;sticky session 與 F5 的 TLS session 行為待客戶確認。'],
    ['憑證設計', '以客戶前提為準:共用一張 server 憑證,只做傳輸加密;身分另外處理(平台元件與 legacy app 各用 client 憑證)。Kafka 專家建議每台一張,僅供參考,不採用。'],
    ['變更核准', 'OP menu 的 ticket 檢查是可開關、可抽換的,等客戶決定核准方式。'],
    ['CyberArk 的 PAM 側', '秘密管理那條路已用 Conjur 驗過(Lab 18);代登入與錄影(PSM)、主機帳號自動輪替(CPM)、依單借出(PVWA)要在客戶環境 PoC;跳板機與主機是否加入 AD、人連主機是否一律經 PSM,待客戶回答。'],
  ],
};
