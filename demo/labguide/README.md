# Lab 手冊產生與驗證

- `labs.mjs`:手冊內容(資料驅動)。每個步驟有 `manual`(純手動指令)、`auto`(專案包好的指令)、`ui`/`uiEq`(介面操作與等效指令)、`ev`(取哪個實跑輸出)。
- `build.mjs`:產生 `../../Confluent-Security-Lab-Guide.docx`(輸出文字取自 `demo/evidence/*/NN-*.log`,圖取自 `demo/evidence/**.png`)。
- `verify.mjs`:依序實際執行 Lab 1~11 的手動指令並判定(結果 `verify.log`)。**執行期間不要同時跑其他腳本,會互相干擾。**
- `verify0.mjs`:驗證 Lab 0(憑證在暫存資料夾,其餘為可重複執行步驟)。

```bash
cd demo/labguide
node verify0.mjs    # Lab 0
node verify.mjs     # Lab 1~11(含重置;約 25 分鐘)
node build.mjs      # 產生 Word
```
