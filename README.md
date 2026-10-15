# Hyday Talk

Hyday Talk 是一款原生 macOS 語音輸入工具，使用者在任何 App 中按下 fn 即可開始說話，再按一次 fn 完成，辨識並整理後的文字會插入原本的游標位置

Hyday Talk 為原生 macOS App，語音辨識可在本機完成，錄音不需上傳

![Hyday Talk 總覽畫面](docs/images/screenshot.png)

## 主要功能

- **聽寫**：將語音轉為文字並插入目前的輸入框；找不到輸入框或輸入位置已變更時，自動複製文字
- **翻譯**：說話後直接輸出指定語言的譯文
- **文字提問**：以語音對選取文字下達指示，結果顯示於浮動面板供複製
- **文字整理**：補上標點、刪除口語贅字、依前後文修正同音錯字，並自動將列舉事項排成編號列表
- **個人辭典**：記錄常說的人名、產品與術語，提供給語音辨識與文字 AI 作為提示，並可從使用者對插入文字的修正中自動學習
- **洞察**：統計口述字數、節省時間、口述速度、使用時段與常用 App
- **與 [Hyday](https://hyday.tw) 整合**：以語音記錄 Hyday 日誌，提問時參考 Hyday 筆記，並以筆記中的名稱與標籤提升辨識準確度

## 系統需求

| 項目 | 需求 |
| --- | --- |
| 作業系統 | macOS 14 以上 |
| 處理器 | Apple Silicon |
| 本機文字 AI（選用） | Ollama 與已下載的文字模型 |

## 安裝

1. 至 [Releases](https://github.com/mukiwu/hyday-talk/releases) 下載最新版本的 `Hyday-Talk-<版本>.dmg`
2. 開啟 DMG，將 Hyday Talk 拖曳至應用程式資料夾
3. 從應用程式資料夾開啟 Hyday Talk

## 初次設定

首次開啟時，App 會顯示權限指引，請依序允許下列權限：

| 權限 | 用途 | 是否必要 |
| --- | --- | --- |
| 麥克風 | 錄製語音 | 必要 |
| 輔助使用 | 偵測輸入框並插入文字 | 必要 |
| 語音辨識 | 使用 macOS 系統辨識 | 僅限選用系統辨識時 |

之後可從側欄底部的權限指引重新開啟

若輔助使用開關已開啟，App 仍顯示未授權，通常是系統保留了舊版本的簽章授權，請至系統設定的隱私權與安全性，於輔助使用清單移除舊的 Hyday Talk，重新加入應用程式資料夾中的 Hyday Talk 並開啟，再返回 App 按下重新檢查，詳細說明請參閱 [Apple TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)

## 快捷鍵

| 操作 | 快捷鍵 |
| --- | --- |
| 開始或完成聽寫 | fn |
| 開始翻譯 | fn ＋ 左 Shift |
| 文字提問 | fn ＋ Control |
| 記到 Hyday | fn ＋ Space |
| 取消錄音或處理 | esc |

若按下 fn 會同時開啟表情符號或 macOS 聽寫，請至系統設定的鍵盤，將按下 🌐 鍵來設為不執行動作

## 語音辨識來源

| 來源 | 設定方式 | 資料處理 |
| --- | --- | --- |
| 系統辨識 | 允許語音辨識權限並選擇語言 | 由 Apple Speech 處理，部分語言可能使用 Apple 伺服器；可設定僅使用離線辨識 |
| 本機模型 | 於 App 內下載模型 | 以內建的 whisper.cpp 或 transcribe.cpp 在本機辨識，錄音不會上傳 |
| API | 設定服務網址、模型名稱與 API Key | 音訊傳送至指定的 OpenAI 相容服務 |

系統辨識單次錄音上限為 55 秒，其他來源為 180 秒

### 推薦組合

| 用途 | 推薦模型 | 取得方式 |
| --- | --- | --- |
| 語音辨識 | TEA-ASR 1.1 或 Qwen3-ASR 0.6B | 在語音辨識頁選擇本機模型後下載 |
| 文字整理 | qwen3.5:9b | 先安裝 [Ollama](https://ollama.com/download)，再於文字整理頁按安裝模型 |

這個組合對中文口語與中英夾雜較準確，全部在本機執行，也可以在 App 內改用其他模型；TEA-ASR 1.1 針對台灣口語調校，直接輸出繁體與台灣用詞，檔案約 1.69 GB，Qwen3-ASR 0.6B 較小也較快

本機辨識引擎 whisper.cpp 與 transcribe.cpp 已內建於 App，不需另行安裝；Qwen3-ASR 模型採 Apache 2.0 授權，TEA-ASR 1.1 採 MIT 授權，App 下載的是轉換給 transcribe.cpp 使用的 [GGUF 版本](https://huggingface.co/mukiwu/TEA-ASR-1.1-transcribe-gguf)，個人辭典與 Hyday 詞彙會作為辨識詞彙提示

API 來源需支援 `POST /audio/transcriptions` 並回傳含 `text` 欄位的 JSON，遠端服務僅接受 HTTPS；本機服務可使用 HTTP 並免填 API Key

## 與 Hyday 整合

[Hyday](https://hyday.tw) 是一款本地優先的 AI 個人知識庫秘書，將筆記、網頁、文件、日誌與行事曆連結在同一套工作流裡

筆記保存在使用者自己的資料夾，提供 macOS 與 Windows 桌面版

Hyday Talk 直接讀寫 Hyday 的筆記資料夾，不需要開啟 Hyday，也不需要另外安裝其他工具

相關設定集中於側欄的 Hyday 頁，資料夾預設沿用 Hyday 的設定，也可以自行選擇

### 記到 Hyday

按 fn 加 Space 說話，內容會加在 Hyday 資料夾當天日誌的最後面，一般聽寫不會寫入 Hyday

設定文字 AI 後，說的話會依 Hyday 的 Life Log 規則整理成 Markdown：

| 說的內容 | 寫入的格式 |
| --- | --- |
| 開始做某件事 | `>(時間) 內容` |
| 結束某件事 | `<(時間) 內容` |
| 目前的狀態 | `-(時間) 內容` |
| 想法 | `%(內容)` |
| 重要事項 | `!(內容)` |
| 提醒與待辦 | `- [ ] 內容` |
| 較長的回顧 | 小標題加上列點 |

一次說的話可以同時產生多行，例如一筆待辦加上一則想法

每筆記錄的第一行都會標上說話當下的時間，時間由 App 填入，不由 AI 決定；AI 輸出格式不符時，該行會改為一般列點，內容不會遺失

沒有設定文字 AI 時，整理後的原文會寫成一個列點

寫入時只會加在日誌最後面，並保留原本的 frontmatter，即使 Hyday 正在編輯同一份日誌，新內容也會接在草稿後面，不會覆蓋尚未儲存的內容；當天日誌不存在時，會依 Hyday 的日誌範本建立

### 問筆記

開啟後，文字提問會先搜尋 Hyday 筆記，以找到的內容作為參考回答，並在最後附上相關筆記的連結

已安裝 Hyday 時使用 Hyday 內建的搜尋，否則使用 Hyday Talk 的關鍵字搜尋，搜尋不包含 Hyday 自行管理的資料夾與 AI 衍生內容

### Hyday 詞彙

Hyday Talk 會讀取筆記中的 `@(名稱)` 與 `#標籤`，作為語音辨識的提示，讓人名、專案與主題更容易辨識正確，這些詞彙不會加入個人辭典

## 文字整理

| 方式 | 說明 |
| --- | --- |
| 基礎整理 | 轉換字形、將既有標點轉為全形並套用個人辭典，不補上新標點 |
| 本機 AI | 透過本機 Ollama 模型整理文字，逐字稿不會上傳 |
| Claude | 透過這台 Mac 上已登入的 Claude Code 整理文字，可選 Haiku、Sonnet 或 Opus，使用自己的 Claude 訂閱額度 |
| API | 透過 OpenAI 相容的 `POST /chat/completions` 服務整理文字 |

聽寫風格分為保留原話、自然與正式，預設為自然；保留原話會略過 AI 整理，僅套用字形、既有標點與個人辭典；自然只刪掉沒有意思的贅詞，保留使用者的用詞與帶情緒的語氣；正式會刪除所有贅詞並改成書面用語

使用 AI 整理時，App 會：

- 補上標點與斷句，刪除口語贅字與冗長的轉折詞
- 依前後文修正同音或近音錯字，不改變說話者的原意
- 一般敘述保留為段落；連續列舉的事項改為編號列表，同一段輸出可同時包含段落與列表
- 保留所有事項、數字、英文與專有名詞的原寫法

回應檢查會拒絕未完成的結果、過長的分析文字，以及遺失原始數字或英文的內容，AI 整理失敗時保留原始辨識結果

繁體中文模式會將中文句子的半形標點轉為全形，並保留英文句子、數字、時間、版本、網址、電子郵件與程式碼

## 自動學習詞彙

你修改插入的文字後，App 會比對修改前後的內容，把改正的人名、產品、術語或英文縮寫加入個人辭典，下次辨識時作為提示

- 只學聽寫結果，翻譯與提問不學
- 只把改錯字當成修正，刪字、改標點或整段重寫都不算
- 有文字 AI 時由 AI 判斷詞彙是否值得記住，沒有時只學英文、數字與縮寫
- 自動加入的詞彙只當提示，不會直接替換文字；想強制替換時，可在個人辭典手動填寫常聽錯成的寫法
- 你刪掉的自動詞彙不會再學回來

此功能可於一般設定關閉，預設為開啟

## 使用統計

使用統計另行儲存每日的字數、錄音秒數、筆數、使用時段、目標 App 與功能類型，不保存任何文字內容，清除或停用聽寫紀錄不會影響統計

節省時間的估算方式為口述字數除以使用者的打字速度，再扣除實際口述時間，打字速度預設為每分鐘 40 字，可於一般設定調整

## 隱私與資料儲存

- 設定、聽寫紀錄（最多 200 筆）與使用統計存放於 `~/Library/Application Support/HydayTalk/`，不使用雲端同步
- API Key 存放於 macOS 鑰匙圈，不寫入設定檔
- 系統辨識不寫入音訊檔；其他來源的暫存音訊於完成或取消後刪除，下次啟動時亦會清理殘留檔案
- 插入文字時透過剪貼簿送出貼上指令，並於 0.8 秒後還原原本的剪貼簿內容
- App 不讀取整份文件、瀏覽器頁面或剪貼簿歷史，並拒絕在密碼欄位開始錄音
- 使用 API 時，音訊、逐字稿、辭典與選取文字會依功能傳送至使用者指定的服務
- 使用 Claude 時，逐字稿會送至 Anthropic 處理；開始錄音時會先在背景啟動 Claude Code，講完約 1 秒內整理完成；Hyday Talk 不經手登入資料

## 參考資料

- [Apple Speech](https://developer.apple.com/documentation/speech/sfspeechrecognizer)
- [OpenAI 語音辨識](https://developers.openai.com/api/docs/guides/speech-to-text)
- [whisper.cpp](https://github.com/ggml-org/whisper.cpp)
- [transcribe.cpp](https://github.com/handy-computer/transcribe.cpp)
- [Qwen3-ASR](https://github.com/QwenLM/Qwen3-ASR)
- [TEA-ASR 1.1](https://huggingface.co/JacobLinCool/TEA-ASR-1.1)
- [Claude Code](https://docs.claude.com/en/docs/claude-code/overview)

## 贊助

如果這個專案對你有幫助，歡迎贊助支持我持續開發

<a href="https://sponsor.muki.tw"><img src="https://sponsor.muki.tw/badge/sponsor-button.png" alt="贊助 MUKI" width="240"></a>
